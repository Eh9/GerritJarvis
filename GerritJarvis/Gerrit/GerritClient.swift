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

    @AppStorage("UserKey") var user: String = ""
    @AppStorage("PasswordKey") var password: String = ""
    @AppStorage("BaseUrlKey") var baseUrl: String = ""

    static let shared = GerritClient()

    private var trackingChanges: [Change] = []

    var showingChanges: [GerritReviewDisplay.State] {
        trackingChanges.map {
            GerritReviewDisplay.State(
                id: $0.changeId!,
                baseCell: ReviewDisplay.State(
                    project: $0.project ?? "null_project",
                    branch: $0.branch ?? "null_branch",
                    name: $0.owner?.displayName ?? $0.owner?.name ?? "null_name",
                    commitMessage: $0.subject ?? "null_message",
                    avatarName: $0.owner?.avatarImageName(),
                    hasNewEvent: false,
                    isMergeConflict: !($0.mergeable ?? true)
                ),
                gerritScore: $0.calculateReviewScore().0
            )
        }
    }

    func update() async {
        if let gerritChanges = try? await fetchReviewList() {
            trackingChanges = gerritChanges
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
        guard let change = trackingChanges.first(where: { $0.changeId == id }),
              let number = change.number
        else {
            return nil
        }
        return URL(string: baseUrl + "/#/c/" + "\(number)")
    }

    func authorURL(id: String) -> URL? {
        guard let change = trackingChanges.first(where: { $0.changeId == id }),
              let emailEncoded = change.owner?.email?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            return nil
        }
        return URL(string: baseUrl + "/#/q/owner:" + emailEncoded)
    }

    func projectURL(id: String) -> URL? {
        guard let change = trackingChanges.first(where: { $0.changeId == id }),
              let project = change.project
        else {
            return nil
        }
        return URL(string: baseUrl + "/#/q/project:" + project)
    }

    func branchURL(id: String) -> URL? {
        guard let projectURLString = projectURL(id: id)?.absoluteString,
              let branch = trackingChanges.first(where: { $0.changeId == id })?.branch
        else {
            return nil
        }
        return URL(string: projectURLString + "+branch:" + branch)
    }
}
