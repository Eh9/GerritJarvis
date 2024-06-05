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

struct GerritClient {
    enum GerritError: Error {
        case decodeError
    }

    @AppStorage("UserKey") var user: String = ""
    @AppStorage("PasswordKey") var password: String = ""
    @AppStorage("BaseUrlKey") var baseUrl: String = ""

    static let shared = GerritClient()

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
