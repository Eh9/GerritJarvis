//
//  GitLabService.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/11.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import Foundation
import GitLabSwift
import OSLog

class GitlabService {
    static let shared = GitlabService()
    private init() {}

    private var user: String!
    private var gitlab: GLApi!
    private let logger = Logger()

    private(set) var trackingMRs: [GLModel.MergeRequest] = []
    private(set) var projectInfos: [Int: GLModel.Project] = [:] // projectID: project
    private(set) var discussionInfos: [Int: [GLModel.Discussion.Note]] = [:] // mr.id: notes
    private(set) var approvalInfos: [Int: GLModel.MergeRequestApprovals] = [:] // mr.id: approvalInfo
    private(set) var mrsUpdated: [GLModel.MergeRequest] = []

    private var mrsNotTracking: [GLModel.MergeRequest] = []
    private var mrUpdateTime: [Int: Date?] = [:] // mr.id: updateDate

    func setup() async {
//        // reset DEBUG Code
//        let appDomain = Bundle.main.bundleIdentifier
//        UserDefaults.standard.removePersistentDomain(forName: appDomain!)
//        UserDefaults.standard.synchronize()
        self.user = GitLabConfigs.user
        guard let url = URL(string: GitLabConfigs.baseUrl.appending("/api/v4")) else {
            return
        }
        gitlab = GLApi(config: .init(baseURL: url) { $0.token = GitLabConfigs.token })
        await setupUserInfo()
    }

    func fetchMRs() async {
        await setupUserInfo()
        let groups = GitLabConfigs.groupInfo.groups.filter {
            GitLabConfigs.groupInfo.observedGroups.contains($0.id)
        }
        var searchTexts = groups.compactMap(\.fullName)
        if let userName = GitLabConfigs.user.split(separator: "@").first { searchTexts.append(String(userName)) }

        var mrs: [GLModel.MergeRequest] = []
        for text in searchTexts {
            // TODO: fetch MRs in parallel
            if let groupMRs = await fetchMRList(searchText: text) {
                mrs.append(contentsOf: groupMRs)
            }
        }
        if let ownedMRs = await fetchOwnedMRs() {
            mrs.append(contentsOf: ownedMRs)
        }
        if let reviewedMRs = await fetchReviewedMRs() {
            mrs.append(contentsOf: reviewedMRs)
        }
        mrs = mrs.reduce(into: []) { result, mr in
            if !result.contains(where: { $0.id == mr.id }) {
                result.append(mr)
            }
        }
        mrsNotTracking = trackingMRs.filter { mr in !mrs.contains(where: { $0.id == mr.id }) }
        mrsUpdated = mrs.compactMap { if let t = mrUpdateTime[$0.id], t != $0.updated_at { $0 } else { nil } }
        notifyVotes(newMrs: mrs)
        trackingMRs = mrs
        mrUpdateTime = .init(uniqueKeysWithValues: mrs.map { ($0.id, $0.updated_at) })
        for mr in mrs {
            if projectInfos[mr.project_id] == nil, let project = await fetchProject(id: mr.project_id) {
                projectInfos[mr.project_id] = project
            }
            if discussionInfos[mr.id] == nil,
               let discussions = await fetchMRDiscussions(id: mr.iid, projectId: mr.project_id)
            {
                discussionInfos[mr.id] = discussions.flatMap(\.notes).filter { $0.system == false }
            }
            if approvalInfos[mr.id] == nil,
               let approvals = await fetchMRApprovals(id: mr.iid, projectId: mr.project_id)
            {
                approvalInfos[mr.id] = approvals
            }
        }
        await notityNotTrackingMR()
        await notifyUpdatedMR()
    }

    func clear() {
        let appDomain = Bundle.main.bundleIdentifier
        UserDefaults.standard.removePersistentDomain(forName: appDomain!)
        UserDefaults.standard.synchronize()
        trackingMRs = []
        projectInfos = [:]
        discussionInfos = [:]
        approvalInfos = [:]
        mrsUpdated = []

        mrsNotTracking = []
        mrUpdateTime = [:]
        GitLabConfigs.groups = []
        GitLabConfigs.userInfo = nil
        GitLabConfigs.user = ""
        GitLabConfigs.hasSetup = GitLabConfigs.userInfo != nil
        GitLabConfigs.setupGroupInfo()
    }

    // TODO: how to filter votes action from the user
    private func notifyVotes(newMrs: [GLModel.MergeRequest]) {
        newMrs.forEach { newMr in
            if let oldMr = trackingMRs.first(where: { $0.id == newMr.id }),
               oldMr.downvotes != newMr.downvotes || oldMr.upvotes != newMr.upvotes
            {
                UserNotificationHandler.shared.sendNotification(
                    title: "\(newMr.title ?? "")",
                    body: "votes updated. 👍:\(newMr.upvotes)     👎:\(newMr.downvotes)",
                    url: newMr.web_url.absoluteString
                )
            }
        }
    }

    private func notityNotTrackingMR() async {
        for mr in mrsNotTracking {
            if let updatedMR = await fetchMRStatus(id: mr.iid, projectId: mr.project_id) {
                var message: String = ""
                if let mergedBy = updatedMR.merged_by, let mergedAt = updatedMR.merged_at {
                    message = "merged by \(mergedBy.name) at \(mergedAt)"
                }
                if let closedBy = updatedMR.closed_by, let closedAt = updatedMR.closed_at {
                    message = "closed by \(closedBy.name) at \(closedAt)"
                }
                UserNotificationHandler.shared.sendNotification(
                    title: "\(mr.title ?? "")",
                    body: message,
                    url: updatedMR.web_url.absoluteString
                )
            }
        }
        mrsNotTracking.removeAll()
    }

    private func notifyUpdatedMR() async {
        // discusstion updated
        for mr in mrsUpdated {
            guard let discussions = await fetchMRDiscussions(id: mr.iid, projectId: mr.project_id) else { continue }
            let notes = discussions.flatMap(\.notes).filter { $0.system == false }
            defer { discussionInfos[mr.id] = notes }
            guard let oldNotes = discussionInfos[mr.id] else { continue }
            let updateNotes: [GLModel.Discussion.Note] = notes.compactMap { note in
                if let oldNote = oldNotes.first(where: { $0.id == note.id }),
                   oldNote.updated_at == note.updated_at
                {
                    return nil
                }
                return note
            }.sorted { $0.updated_at! < $1.updated_at! }
            if !updateNotes.isEmpty {
                UserNotificationHandler.shared.sendNotification(
                    title: "\(mr.title ?? "")",
                    body: "New comments",
                    url: mr.web_url.absoluteString + "#note_\(updateNotes.first!.id)"
                )
            }
        }
        // approval updated
        for mr in mrsUpdated {
            guard let approval = await fetchMRApprovals(id: mr.iid, projectId: mr.project_id) else { continue }
            defer { approvalInfos[mr.id] = approval }
            guard let oldApproval = approvalInfos[mr.id] else { continue }
            if let newUsers = approval.approved_by?.compactMap({ approvalBy in
                if (oldApproval.approved_by ?? []).contains(where: { $0.user.id == approvalBy.user.id }) == false
                { return approvalBy.user } else { return nil }
            }), !newUsers.isEmpty {
                UserNotificationHandler.shared.sendNotification(
                    title: "\(mr.title ?? "")",
                    body: "approved by \(newUsers.map(\.name).joined(separator: "、"))",
                    url: mr.web_url.absoluteString
                )
            }
        }
    }

    private func fetchUserInfo() async -> GLModel.User? {
        do { return try await gitlab.users.me().decode() }
        catch {
            print(error)
            return nil
        }
    }

    private func fetchGroupInfo() async -> [GLModel.Group] {
        do {
            let response: GLResponse<[GLModel.Group]> = try await gitlab.execute(.init(endpoint: CustomURLs.groups))
            let result = try response.decode() ?? []
            logger.log(level: .info, "gitlabGroupInfo \(result, privacy: .public)")
            return result
        } catch {
            logger.error("\(error, privacy: .public)")
            return []
        }
    }

    private func setupUserInfo() async {
        GitLabConfigs.groups = await fetchGroupInfo()
        GitLabConfigs.userInfo = await fetchUserInfo()
        if let email = GitLabConfigs.userInfo?.email { GitLabConfigs.user = email }
        GitLabConfigs.hasSetup = GitLabConfigs.userInfo != nil
        GitLabConfigs.setupGroupInfo()
    }

    private func fetchMRList(searchText: String) async -> [GLModel.MergeRequest]? {
        guard let text = searchText.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return nil }
        do {
            let response: GLResponse<[GLModel.MergeRequest]>? =
                try await gitlab.execute(.init(endpoint: CustomURLs.mergeRequest(searchText: text)))
            return try response?.decode()
        } catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchOwnedMRs() async -> [GLModel.MergeRequest]? {
        do {
            return try await gitlab.mergeRequest.list(options: {
                $0.authorId = GitLabConfigs.userInfo?.id
                $0.state = .opened
                $0.perPage = 100
            }).decode()
        } catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchReviewedMRs() async -> [GLModel.MergeRequest]? {
        do {
            return try await gitlab.mergeRequest.list(options: {
                $0.reviewerId = GitLabConfigs.userInfo?.id
                $0.state = .opened
                $0.perPage = 100
            }).decode()
        } catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchMRStatus(id: Int, projectId: Int) async -> GLModel.MergeRequest? {
        do { return try await gitlab.mergeRequest.get(id, project: .id(projectId)).decode() }
        catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchProject(id: Int) async -> GLModel.Project? {
        do { return try await gitlab.projects.get(project: .id(id)).decode() }
        catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchMRDiscussions(id: Int, projectId: Int) async -> [GLModel.Discussion]? {
        do { return try await gitlab.mergeRequest.discussions(id, project: .id(projectId)).decode() }
        catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }

    private func fetchMRApprovals(id: Int, projectId: Int) async -> GLModel.MergeRequestApprovals? {
        do { return try await gitlab.mergeRequest.approvals(id, project: .id(projectId)).decode() }
        catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Extra Gitlab Apis

private enum CustomURLs: GLEndpoint {
    case groups
    case mergeRequest(searchText: String)

    public var value: String {
        switch self {
        case .groups: "/groups"
        case let .mergeRequest(searchText): "/merge_requests?state=opened&scope=all&per_page=100&search=\(searchText)"
        }
    }
}
