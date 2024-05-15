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

    private(set) var trackingMRs: [GLModel.MergeRequest] = []
    private(set) var projectInfos: [Int: GLModel.Project] = [:] // projectID: project
    private(set) var mrUpdateTime: [Int: Date?] = [:] // mr.iid: updateDate

    func setup() async {
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
            mrs.append(contentsOf: ownedMRs.filter { mr in mrs.contains(where: { $0.iid == mr.iid }) })
        }
        if let reviewedMRs = await fetchReviewedMRs() {
            mrs.append(contentsOf: reviewedMRs.filter { mr in mrs.contains(where: { $0.iid == mr.iid }) })
        }
        trackingMRs = mrs
        mrUpdateTime = .init(uniqueKeysWithValues: mrs.map { ($0.iid, $0.updated_at) })
        for mr in mrs {
            if let project = await fetchProject(id: mr.project_id) {
                projectInfos[mr.project_id] = project
            }
        }
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
        guard let text = searchText.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return nil }
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

    private func fetchProject(id: Int) async -> GLModel.Project? {
        try? await gitlab.projects.get(project: .id(id)).decode()
    }
}

// MARK: - Extra Gitlab Apis

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
