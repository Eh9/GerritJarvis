//
//  GerritClient.swift
//  GerritJarvis
//
//  Created by hudi on 2024/6/5.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import Alamofire
import Foundation
import ComposableArchitecture
import SwiftUI
import ObjectMapper

private enum GerritClientKey: DependencyKey {
    static let liveValue: GerritClient = .shared
}

extension DependencyValues {
    var gerritClient: GerritClient {
        get { self[GerritClientKey.self] }
        set { self[GerritClientKey.self] = newValue }
    }
}

class GerritClient {
    enum GerritError: Error {
        case decodeError
    }

    // TODO: optimize UserDefault
    private let ReviewNewEventStatusKey = "ReviewNewEventStatusKey"
    private var newEventStates: [String: Bool] {
        get {
            guard let status = UserDefaults.standard.object(forKey: ReviewNewEventStatusKey) as? [String: Bool] else {
                return [String: Bool]()
            }
            return status
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ReviewNewEventStatusKey)
        }
    }

    private let ReviewLastestMessageIdKey = "ReviewLastestMessageIdKey"
    private var latestMessageIds: [String: String] {
        get {
            guard let messageIds = UserDefaults.standard.object(forKey: ReviewLastestMessageIdKey) as? [String: String]
            else {
                return [String: String]()
            }
            return messageIds
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ReviewLastestMessageIdKey)
        }
    }

    @AppStorage("UserKey") var user: String = ""
    @AppStorage("PasswordKey") var password: String = ""
    @AppStorage("BaseUrlKey") var baseUrl: String = ""

    @Shared(.shouldNotifyMergeConflict) var shouldNotifyMergeConflict = false
    @Shared(.shouldNotifyNewIncomingReview) var shouldNotifyNewIncomingReview = false
    @Shared(.showOurNotReadyReview) var showOurNotReadyReview = false

    static let shared = GerritClient()

    private(set) var trackingChanges: [Change] = []
    private var hasFinishedFirstFetch = false

    var showingChanges: [GerritReviewDisplay.State] {
        trackingChanges.map {
            GerritReviewDisplay.State(
                id: $0.id!,
                baseCell: ReviewDisplay.State(
                    project: $0.project ?? "null_project",
                    branch: $0.branch ?? "null_branch",
                    name: $0.owner?.displayName ?? $0.owner?.name ?? "null_name",
                    commitMessage: $0.subject ?? "null_message",
                    avatarName: $0.owner?.avatarImageName(),
                    hasNewEvent: newEventStates[$0.newEventKey()] ?? false,
                    isMergeConflict: !($0.mergeable ?? true)
                ),
                gerritScore: $0.calculateReviewScore().0
            )
        }
    }

    var newEventCount: Int {
        trackingChanges.reduce(0) { result, change in
            return result + (newEventStates[change.newEventKey()] ?? false ? 1 : 0)
        }
    }

    func update() async {
        guard let gerritChanges = try? await fetchReviewList() else {
            return
        }
        gerritChanges.forEach { change in
            guard let id = change.id else { return }
            if let oldChange = trackingChanges.first(where: { $0.id == id }) {
                updateCommentCount(change: change, oldChange: oldChange)
                updateNewEventState(change: change, oldChange: oldChange)
            } else {
                if hasFinishedFirstFetch, !change.isOurs() {
                    notifyNewChange(change)
                }
            }
        }
        trackingChanges = gerritChanges
        hasFinishedFirstFetch = true
        updateAllNewEventsCount()
    }

    func resetNewStateOfChange(id: String) {
        guard let change = trackingChanges.first(where: { $0.id == id }) else { return }
        newEventStates[change.newEventKey()] = false
    }

    private func updateCommentCount(change: Change, oldChange: Change) {
        // TODO: 感觉这个作用不大，写起来逻辑比较复杂，可以后面再加上
    }

    private func updateNewEventState(change: Change, oldChange: Change) {
        var raiseMergeConflict = false
        if change.isOurs() {
            raiseMergeConflict = change.isRaiseMergeConflict(with: oldChange)
            if raiseMergeConflict {
                newEventStates[change.newEventKey()] = true
            }
        }
        if change.shouldListenReviewEvent() {
            var messageId = oldChange.messages?.last?.id
            if let originMessageId = latestMessageIds[change.changeNumberKey()] {
                messageId = originMessageId
            }
            let messages = change.newMessages(baseOn: messageId)
            let originRevision = oldChange.messages?.last?.revisionNumber ?? 1
            let comments = GerritUtils.parseNewCommentCounts(messages, originRevision: originRevision)
            let scores = GerritUtils.parseReviewScores(messages, originRevision: originRevision)
            let filterComments = GerritUtils.filterComments(comments, authorFilter: { author in
                return change.shouldListen(author: author)
            })
            notifyReviewEvents(
                scores: scores,
                comments: filterComments,
                change: change
            )
        }
    }

    private func updateAllNewEventsCount() {
        latestMessageIds = trackingChanges.reduce(into: [String: String]()) { result, change in
            result[change.changeNumberKey()] = change.messages?.last?.id
        }
    }

    private func notifyNewChange(_ change: Change) {
        if shouldNotifyNewIncomingReview {
            let name = change.owner?.displayName ?? change.owner?.name ?? "null_name"
            let content = "New incoming review request from \(name)"
            let title = change.subject ?? "null_message"
            UserNotificationHandler.shared.sendNotification(
                title: title,
                body: content,
                url: changeURL(number: change.number)?.absoluteString
            ) { [weak self] in
                self?.resetNewStateOfChange(id: change.id!)
            }
        }
    }

    private func notifyReviewEvents(
        scores: [(Author, ReviewScore)],
        comments: [(Author, Int)],
        change: Change
    ) {
        let reviewEvents = GerritUtils.combineReviewEvents(scores: scores, comments: comments)
        for (author, score, comments) in reviewEvents {
            if author.isMe() || author.isInBlackList() || (score == .Zero && comments == 0) {
                continue
            }

            var title = author.name ?? ""
            var imageResource: URL?
            if score != .Zero {
                title += " Code-Review\(score.rawValue)"
                imageResource = score.imageFilePath
            }
            if comments != 0 {
                title += " (\(comments) "
                if comments == 1 {
                    title += "Comment)"
                } else {
                    title += "Comments)"
                }
            }
            let changeURL = changeURL(number: change.number)
            UserNotificationHandler.shared.sendNotification(
                title: title,
                body: change.subject ?? "null_message",
                iconUrl: imageResource?.absoluteString,
                url: changeURL?.absoluteString
            )
        }
    }

    func verifyAccount() async throws -> Author {
        let url = baseUrl + "/a/accounts/self/detail"
        let data = try await AF.request(url)
            .authenticate(username: user, password: password, persistence: .none)
            .validate(statusCode: 200..<300)
            .serializingData()
            .value
        guard let jsonString = GerritResponseUtils.filterResponse(data),
              let model = Mapper<Author>().map(JSONString: jsonString)
        else {
            throw GerritError.decodeError
        }
        return model
    }

    func fetchReviewList() async throws -> [Change] {
        // 具体见 https://gerrit-review.googlesource.com/Documentation/user-search.html#_search_operators
        let query =
            "?q=(status:open+is:owner)OR(status:open+is:reviewer)&o=MESSAGES&o=DETAILED_ACCOUNTS&o=DETAILED_LABELS"
        let url = baseUrl + "/a/changes/" + query
        let data = try await AF.request(url)
            .authenticate(username: user, password: password)
            .validate(statusCode: 200..<300)
            .serializingData()
            .value
        guard let jsonString = GerritResponseUtils.filterResponse(data),
              let model = Mapper<Change>().mapArray(JSONString: jsonString)
        else {
            throw GerritError.decodeError
        }
        return model
    }

    func fetchChangeDetail(changeId: String) async throws -> Change {
        let url = baseUrl + "/a/changes/" + "\(changeId)/detail"
        let data = try await AF.request(url)
            .authenticate(username: user, password: password)
            .validate(statusCode: 200..<300)
            .serializingData()
            .value
        guard let jsonString = GerritResponseUtils.filterResponse(data),
              let model = Mapper<Change>().map(JSONString: jsonString)
        else {
            throw GerritError.decodeError
        }
        return model
    }
}

// MARK: - Jump URL getter

extension GerritClient {
    func changeURL(id: String) -> URL? {
        guard let change = trackingChanges.first(where: { $0.id == id }),
              let number = change.number
        else {
            return nil
        }
        return changeURL(number: number)
    }

    private func changeURL(number: Int?) -> URL? {
        guard let number else { return nil }
        return URL(string: baseUrl + "/#/c/" + "\(number)")
    }

    func authorURL(id: String) -> URL? {
        guard let change = trackingChanges.first(where: { $0.id == id }),
              let emailEncoded = change.owner?.email?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            return nil
        }
        return URL(string: baseUrl + "/#/q/owner:" + emailEncoded)
    }

    func projectURL(id: String) -> URL? {
        guard let change = trackingChanges.first(where: { $0.id == id }),
              let project = change.project
        else {
            return nil
        }
        return URL(string: baseUrl + "/#/q/project:" + project)
    }

    func branchURL(id: String) -> URL? {
        guard let projectURLString = projectURL(id: id)?.absoluteString,
              let branch = trackingChanges.first(where: { $0.id == id })?.branch
        else {
            return nil
        }
        return URL(string: projectURLString + "+branch:" + branch)
    }
}
