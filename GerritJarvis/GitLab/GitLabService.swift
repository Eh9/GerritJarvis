//
//  GitLabService.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/11.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import Foundation
import GitLabSwift

class GitlabService {
    static let shared = GitlabService()
    private init() {}

    private var user: String!
    private var gitlab: GLApi!

    func setup() {
        self.user = GitLabConfigs.user
        // TODO: URL error, append /api/v4
        gitlab = GLApi(config: .init(baseURL: URL(string: GitLabConfigs.baseUrl)!) {
            $0.token = GitLabConfigs.token
        })
        Task { await setupUserInfo() }
    }

    func fetchMRs() async -> [GLModel.MergeRequest] {
        await setupUserInfo()
        let groups = GitLabConfigs.groupInfo.groups.filter {
            GitLabConfigs.groupInfo.observedGroups.contains($0.id)
        }
        var searchTexts = groups.compactMap(\.full_name)
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
        return mrs
    }

    private func fetchUserInfo() async -> GLModel.User? {
        let response = try? await gitlab.users.me()
        return try? response?.decode()
    }

    private func fetchGroupInfo() async -> [GLModel.Group] {
        let response: GLResponse<[GLModel.Group]>? = try? await gitlab.execute(.init(endpoint: CustomURLs.groups))
        return (try? response?.decode()) ?? []
    }

    private func setupUserInfo() async {
        GitLabConfigs.groupInfo.groups = await fetchGroupInfo()
        GitLabConfigs.userInfo = await fetchUserInfo()
        if let email = GitLabConfigs.userInfo?.email { GitLabConfigs.user = email }
        GitLabConfigs.hasSetup = GitLabConfigs.userInfo != nil
        GitLabConfigs.setupGroupInfo()
    }

    private func fetchMRList(searchText: String) async -> [GLModel.MergeRequest]? {
        let text = searchText.replacingOccurrences(of: " ", with: "")
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
        let response: GLResponse<[GLModel.MergeRequest]>? =
            try? await gitlab.execute(.init(endpoint: CustomURLs.mergeRequest(searchText: text)))
        return try? response?.decode()
    }

    private func fetchOwnedMRs() async -> [GLModel.MergeRequest]? {
        let response = try? await gitlab.mergeRequest.list(options: {
            $0.authorId = GitLabConfigs.userInfo?.id
            $0.state = .opened
            $0.perPage = 100
        })
        return try? response?.decode()
    }

    private func fetchReviewedMRs() async -> [GLModel.MergeRequest]? {
        let response = try? await gitlab.mergeRequest.list(options: {
            $0.reviewerId = GitLabConfigs.userInfo?.id
            $0.state = .opened
            $0.perPage = 100
        })
        return try? response?.decode()
    }

    private func fetchMRStatus(id: Int, projectId: Int) async -> GLModel.MergeRequest? {
        let response = try? await gitlab.mergeRequest.get(id, project: .id(projectId))
        return try? response?.decode()
    }
}

// MARK: - Extra Gitlab Apis

// ref: https://docs.gitlab.com/ee/api/merge_requests.html#merge-status
public enum DetailMergeStatus: String {
    case blockedStatus = "blocked_status"
    case checking
    case unchecked
    case ciMustPass = "ci_must_pass"
    case ciStillRunning = "ci_still_running"
    case discussionsNotResolved = "discussions_not_resolved"
    case draftStatus = "draft_status"
    case externalStatusChecks = "external_status_checks"
    case mergeable
    case notApproved = "not_approved"
    case notOpen = "not_open"
    case jiraAssociationMissing = "jira_association_missing"
    case needRebase = "need_rebase"
    case conflict
    case requestedChanges = "requested_changes"
}

public enum MRState: String {
    case opened
    case closed
    case locked
    case merged
}

private enum CustomURLs: GLEndpoint {
    case groups
    case mergeRequest(searchText: String)

    public var value: String {
        switch self {
        case .groups: "/groups"
        case let .mergeRequest(searchText):
            "/merge_requests?state=opened&scope=all&per_page=100&search=\(searchText)"
        }
    }
}
