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
    @State private var email: String = GitLabConfigs.user
    @State private var token: String = GitLabConfigs.token
    @State private var baseUrl: String = GitLabConfigs.baseUrl

    @State private var wrongInputAlert: Bool = false

    var body: some View {
        VStack {
            HStack(alignment: .center) {
                Text("GitLab BaseURL")
                TextField("baseUrl", text: $baseUrl)
            }
            HStack(alignment: .center) {
                Text("User")
                TextField("email", text: $email)
            }
            HStack(alignment: .center) {
                Text("Token")
                SecureField("token", text: $token)
            }
            Button(action: { login() }, label: { Text("Login") }).keyboardShortcut(.return)
            Text("notify groups")
            List(GitLabConfigs.shared.groups, id: \.id) { group in
                Text(group.name ?? "")
            }.frame(height: 100)
        }
        .padding(.all, 20).frame(width: 370)
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
    GitLabAccountSettingView()
}
