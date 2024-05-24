//
//  GerritAccountPreferenceView.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/23.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import SwiftUI
import ComposableArchitecture

@Reducer
struct GerritAccountPreference {
    @ObservableState
    struct State {
        var user = ConfigManager.shared.user ?? ""
        var token = ConfigManager.shared.password ?? ""
        var baseUrl = ConfigManager.shared.baseUrl ?? ""
        @Presents var alert: AlertState<Action.Alert>?
    }

    enum Action {
        case setUser(String)
        case setToken(String)
        case setBaseUrl(String)
        case save
        case alert(PresentationAction<Alert>)
        case showErrorAlert(LocalizedStringKey)
        case showLoginSuccessAlert(String?)

        @CasePathable
        enum Alert {
            case cancle
            case comfirm
        }
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setUser(value):
                state.user = value
                return .none
            case let .setToken(value):
                state.token = value
                return .none
            case let .setBaseUrl(value):
                state.baseUrl = value
                return .none
            case .save:
                if let message = validateGerritAccountStateHint(state) {
                    state.alert = .init { TextState(LocalizedStringKey("SaveFailed")) }
                    actions: { ButtonState(role: .cancel) { TextState(LocalizedStringKey("OK")) } }
                    message: { TextState(message) }
                    return .none
                } else {
                    return .run(priority: .userInitiated) { [state] send in
                        let (account, statusCode) = try await GerritService(
                            user: state.user,
                            password: state.token,
                            baseUrl: state.baseUrl
                        ).verifyAccount()
                        guard let account = account, let accountId = account.accountId else {
                            await send(.showErrorAlert(LocalizedStringKey(
                                statusCode == 401 ? "Unauthorized" :
                                    "NetworkError"
                            )))
                            return
                        }
                        guard account.username == state.user else {
                            await send(.showErrorAlert(LocalizedStringKey("InvalidUser")))
                            return
                        }
                        ConfigManager.shared.update(
                            baseUrl: state.baseUrl,
                            user: state.user,
                            password: state.token,
                            accountId: accountId
                        )
                        await send(.showLoginSuccessAlert(account.displayName))
                    } catch: { error, send in
                        assertionFailure(error.localizedDescription)
                    }
                }
            case .alert:
                return .none
            case let .showErrorAlert(message):
                state.alert = .init { TextState(LocalizedStringKey("SaveFailed")) }
                actions: { ButtonState(role: .cancel) { TextState(LocalizedStringKey("OK")) } }
                message: { TextState(message) }
                return .none
            case let .showLoginSuccessAlert(name):
                state.alert = .init { TextState(LocalizedStringKey("SaveSuccess")) }
                actions: { ButtonState(role: .cancel) { TextState(LocalizedStringKey("OK")) } }
                message: { [state] in
                    TextState("\(name ?? state.user)," + NSLocalizedString("JarvisService", comment: ""))
                }
                return .none
            }
        }.ifLet(\.$alert, action: \.alert)
    }

    private func validateGerritAccountStateHint(_ state: State) -> LocalizedStringKey? {
        return if state.baseUrl.isEmpty {
            LocalizedStringKey("EmptyUrl")
        } else if URL(string: state.baseUrl) == nil {
            LocalizedStringKey("InvalidUrl")
        } else if state.user.isEmpty {
            LocalizedStringKey("EmptyUser")
        } else if state.token.isEmpty {
            LocalizedStringKey("EmptyPassword")
        } else {
            nil
        }
    }
}

struct GerritAccountPreferenceView: View {
    enum Metric {
        static let textFieldWidth = 226.0
    }

    @State var store: StoreOf<GerritAccountPreference>

    var body: some View {
        VStack {
            HStack(alignment: .center) {
                Text("Gerrit Base URL")
                Spacer()
                TextField("baseUrl", text: $store.baseUrl.sending(\.setBaseUrl))
                    .frame(width: Metric.textFieldWidth)
            }
            HStack(alignment: .center) {
                Text("User")
                Spacer()
                TextField("name", text: $store.user.sending(\.setUser))
                    .frame(width: Metric.textFieldWidth)
            }
            HStack(alignment: .center) {
                Text("HTTP Password")
                Spacer()
                SecureField("token", text: $store.token.sending(\.setToken))
                    .frame(width: Metric.textFieldWidth)
            }
            HStack(alignment: .top) {
                Spacer()
                Text("Gerrit -> Settings -> HTTP Credentials, Click \"Generate New Password\"")
                    .font(.caption).foregroundStyle(.gray)
                    .frame(width: Metric.textFieldWidth, height: 40, alignment: .topLeading)
            }
            HStack {
                Spacer()
                Button(action: { store.send(.save) }, label: { Text("Save").frame(width: 80) })
                    .keyboardShortcut(.return)
            }
        }
        .padding(.all).frame(width: 370)
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}

#Preview {
    GerritAccountPreferenceView(store: .init(initialState: GerritAccountPreference.State()) {
        GerritAccountPreference()
    })
}
