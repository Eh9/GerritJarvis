//
//  GitLabConfigs.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/11.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import Foundation
import SwiftUI
import GitLabSwift

@propertyWrapper
struct UserDefaultsValue<T> {
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
                cacheValue
            } else {
                UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
            }
        }
        set {
            cacheValue = newValue
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}

class GitLabConfigs {
    @UserDefaultsValue(key: "gitlab_token", defaultValue: "")
    static var token: String
    @UserDefaultsValue(key: "gitlab_base_url", defaultValue: "")
    static var baseUrl: String
    @UserDefaultsValue(key: "gitlab_user", defaultValue: "")
    static var user: String

    static let shared: GitLabConfigs = .init(groups: [])

    private init(groups: [GLModel.Group]) {
        self.groups = groups
    }

    @State var groups: [GLModel.Group]
}
