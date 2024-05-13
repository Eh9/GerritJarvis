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
    private var user: String!

    private var gitlab: GLApi!

    static let shared = GitlabService()

    private init() {}

    func setup() {
        self.user = GitLabConfigs.user
        // TODO: URL error, append /api/v4
        gitlab = GLApi(config: .init(baseURL: URL(string: GitLabConfigs.baseUrl)!) {
            $0.token = GitLabConfigs.token
        })
        Task {
            GitLabConfigs.groupInfo.groups = await fetchGroupInfo()
            GitLabConfigs.userInfo = await fetchUserInfo()
            GitLabConfigs.hasSetup = GitLabConfigs.userInfo != nil
            GitLabConfigs.setupGroupInfo()
        }
    }

    func fetchUserInfo() async -> GLModel.User? {
        let response = try? await gitlab.users.me()
        return try? response?.decode()
    }

    func fetchGroupInfo() async -> [GLModel.Group] {
        let response: GLResponse<[GLModel.Group]>? = try? await gitlab.execute(.init(endpoint: CustomURLs.groups))
        return (try? response?.decode()) ?? []
    }

    func fetchMRList() async -> [GLModel.MergeRequest]? {
        let response = try? await gitlab.mergeRequest.list()
        return try? response?.decode()
    }
}

private enum CustomURLs: String, GLEndpoint {
    case groups = "/groups"

    public var value: String { rawValue }
}
