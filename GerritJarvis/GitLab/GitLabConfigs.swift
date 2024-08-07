//
//  GitLabConfigs.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/11.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import Foundation
import GitLabSwift

@propertyWrapper
struct UserDefaultsValue<T: Codable> {
    let key: String
    let defaultValue: T
    var cacheValue: T?

    init(key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
        self.cacheValue = wrappedValue
    }

    var wrappedValue: T {
        get {
            if let cacheValue = cacheValue {
                return cacheValue
            } else {
                guard let jsonString = UserDefaults.standard.object(forKey: key) as? String,
                      let data = jsonString.data(using: .utf8),
                      let value = try? JSONDecoder().decode(T.self, from: data)
                else {
                    return defaultValue
                }
                return value
            }
        }
        set {
            cacheValue = newValue
            guard let jsonString = (try? JSONEncoder().encode(newValue))?.asString(encoding: .utf8) else {
                assertionFailure()
                return
            }
            UserDefaults.standard.set(jsonString, forKey: key)
        }
    }
}

// TODO: 使用 MainActor 重构，避免 Data Race
enum GitLabConfigs {
    static var userInfo: GLModel.User?
    static var groups: [GLModel.Group] = []

    @UserDefaultsValue(key: "gitlab_token", defaultValue: "")
    static var token: String
    @UserDefaultsValue(key: "gitlab_base_url", defaultValue: "")
    static var baseUrl: String
    @UserDefaultsValue(key: "gitlab_user", defaultValue: "")
    static var user: String
    @UserDefaultsValue(key: "gitlab_has_setup", defaultValue: false)
    static var hasSetup: Bool
    @UserDefaultsValue(key: "gitlab_observed_groups", defaultValue: [])
    static var observedGroups: Set<Int>

    // ui observable
    static var groupInfo: ObservedGroupsInfo = .init()

    @MainActor
    static func setupGroupInfo() {
        groupInfo.groups = groups
        groupInfo.observedGroups = observedGroups
        groupInfo.hasLogin = hasSetup
    }
}

import SwiftUI

class ObservedGroupsInfo: ObservableObject {
    @Published var groups: [GLModel.Group] = GitLabConfigs.groups {
        didSet {
            GitLabConfigs.groups = groups
        }
    }

    @Published var observedGroups: Set<Int> = GitLabConfigs.observedGroups {
        didSet {
            GitLabConfigs.observedGroups = observedGroups
        }
    }

    @Published var hasLogin: Bool = GitLabConfigs.hasSetup {
        didSet {
            GitLabConfigs.hasSetup = hasLogin
        }
    }
}

extension GLModel.Group: Identifiable {
    var fullName: String? {
        full_name?.replacingOccurrences(of: " ", with: "")
    }
}
