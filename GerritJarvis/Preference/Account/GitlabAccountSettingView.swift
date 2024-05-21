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
    @State private var loginErrorAlert: Bool = false

    @EnvironmentObject var groupInfo: ObservedGroupsInfo

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
                Text("Access Token")
                Spacer()
                SecureField("token", text: $token).frame(width: Metric.textFieldWidth)
            }
            HStack(alignment: .center) {
                Spacer()
                Text("GitLab -> Edit Profile -> Access Tokens -> Create Personal access token(read_api)")
                    .font(.caption).foregroundStyle(.gray)
                    .frame(width: Metric.textFieldWidth, alignment: .leading)
                    .lineLimit(nil)
            }.padding(.bottom, 10)
            if groupInfo.hasLogin {
                HStack {
                    Text("Subscribed Groups")
                    Spacer()
                }
                List {
                    HStack {
                        Text("GroupName").font(.headline)
                        Spacer()
                        Text("subscribe").font(.headline)
                    }
                    ForEach(groupInfo.groups) { group in
                        HStack {
                            Text(group.fullName ?? String(group.id))
                            Spacer()
                            Toggle("", isOn: .init(get: {
                                groupInfo.observedGroups.contains(group.id)
                            }, set: {
                                if $0 { groupInfo.observedGroups.insert(group.id) }
                                else { groupInfo.observedGroups.remove(group.id) }
                            })).toggleStyle(.switch)
                        }
                    }
                }.frame(height: 130)
                HStack {
                    Spacer()
                    Button(action: { clear() }, label: { Text("clear account info") }).foregroundStyle(.red)
                }
            } else {
                Button(action: { login() }, label: { Text("Login") }).keyboardShortcut(.return)
            }
        }
        .padding(.all, 18).frame(width: 370)
        .alert("?", isPresented: $wrongInputAlert) {
            Button("确认", role: .cancel) {}
        }
        .alert("认证失败", isPresented: $loginErrorAlert) {
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
        Task {
            await GitlabService.shared.setup()
            if GitLabConfigs.userInfo == nil { loginErrorAlert = true } else {
                NotificationCenter.default.post(
                    name: ConfigManager.AccountUpdatedNotification,
                    object: nil,
                    userInfo: nil
                )
            }
        }
    }

    private func clear() {
        baseUrl = ""
        email = ""
        token = ""
        GitlabService.shared.clear()
    }
}

#Preview {
    GitLabAccountSettingView().environmentObject(GitLabConfigs.groupInfo)
}
