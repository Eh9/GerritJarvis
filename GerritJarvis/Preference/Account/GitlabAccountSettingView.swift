//
//  GitlabAccountSettingView.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/11.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import SwiftUI
import Settings
import UniformTypeIdentifiers

struct GitLabAccountSettingView: View {
    enum Metric {
        static let textFieldWidth = 226.0
    }

    @State private var email: String = GitLabConfigs.user
    @State private var token: String = GitLabConfigs.token
    @State private var baseUrl: String = GitLabConfigs.baseUrl

    @State private var wrongInputAlert: Bool = false

    @Environment(ObservedGroupsInfo.self) var groupInfo

    var body: some View {
        VStack {
            HStack(alignment: .center) {
                Text("GitLab BaseURL")
                Spacer()
                TextField("baseUrl", text: $baseUrl).frame(width: Metric.textFieldWidth)
            }
            HStack(alignment: .center) {
                Text("User")
                Spacer()
                TextField("email", text: $email).frame(width: Metric.textFieldWidth)
            }
            HStack(alignment: .center) {
                Text("Token")
                Spacer()
                SecureField("token", text: $token).frame(width: Metric.textFieldWidth)
            }
            if groupInfo.hasLogin {
                HStack {
                    Text("notify groups")
                    Spacer()
                }
                List {
                    ForEach(groupInfo.groups) { group in
                        HStack {
                            Text(group.full_name!)
                            Spacer()
                            Toggle("", isOn: .init(get: {
                                groupInfo.observedGroups.contains(group.id)
                            }, set: {
                                if $0 { groupInfo.observedGroups.insert(group.id) }
                                else { groupInfo.observedGroups.remove(group.id) }
                            })).toggleStyle(.switch)
                        }
                    }
                }.frame(height: 100)
            } else {
                Button(action: { login() }, label: { Text("Login") }).keyboardShortcut(.return)
            }
        }
        .padding(.all, 18).frame(width: 370)
        .alert("?", isPresented: $wrongInputAlert) {
            Button("确认", role: .cancel) {}
        }
    }

    private func login() {
        guard !wrongInputAlert else { return }
        guard !baseUrl.isEmpty, !email.isEmpty, !token.isEmpty else {
            wrongInputAlert = true
            return
        }
        GitLabConfigs.baseUrl = baseUrl
        GitLabConfigs.user = email
        GitLabConfigs.token = token
        GitlabService.shared.setup()
    }
}

#Preview {
    GitLabAccountSettingView().environment(GitLabConfigs.groupInfo)
}
