//
//  GitlabAccountSettingView.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/11.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import SwiftUI
import Settings

struct GitLabAccountSettingView: View {
    @State private var email: String = ""
    @State private var token: String = ""
    @State private var baseUrl: String = ""

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
                TextField("token", text: $token)
            }
            Button(action: { login() }, label: { Text("Login") })
        }.padding(.all, 20).frame(width: 370)
    }

    private func login() {}
}

#Preview {
    GitLabAccountSettingView()
}
