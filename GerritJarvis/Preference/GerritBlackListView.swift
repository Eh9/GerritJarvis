//
//  GerritBlackListView.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/24.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import SwiftUI
import ComposableArchitecture

@Reducer
struct GerritBlackList {
    @ObservableState
    struct State {
        var currentType: String = ConfigManager.BlacklistType.User
        var blacklist: [(String, String)] = ConfigManager.shared.blacklist
        var currentInput: String = ""

        var currentList: [String] {
            blacklist.filter { $0.0 == currentType }.map(\.1)
        }
    }

    enum Action {
        case setCurrentInput(String)
        case switchType(String)
        case addBlackListItem
        case deleteBlackListItem(String)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setCurrentInput(input):
                state.currentInput = input
                return .none
            case let .switchType(type):
                state.currentType = type
                return .none
            case .addBlackListItem:
                let value = state.currentInput.trimmingCharacters(in: .whitespaces)
                guard value.count > 0 else { return .none }
                ConfigManager.shared.appendBlacklist(type: state.currentType, value: state.currentInput)
                state.blacklist = ConfigManager.shared.blacklist
                state.currentInput = ""
                return .none
            case let .deleteBlackListItem(item):
                ConfigManager.shared.removeBlacklist(type: state.currentType, value: item)
                state.blacklist = ConfigManager.shared.blacklist
                return .none
            }
        }
    }
}

struct GerritBlackListView: View {
    @State var store: StoreOf<GerritBlackList>

    var body: some View {
        VStack {
            Picker(selection: $store.currentType.sending(\.switchType)) {
                Text("User BlackList").tag(ConfigManager.BlacklistType.User)
                Text("Project BlackList").tag(ConfigManager.BlacklistType.Project)
            } label: {}
                .pickerStyle(SegmentedPickerStyle())
            List {
                ForEach(store.currentList, id: \.self) { item in
                    Text(item).contextMenu {
                        Button("Delete") { store.send(.deleteBlackListItem(item)) }
                    }
                }
            }.frame(height: 100)
            HStack {
                TextField("New Blacklist item", text: $store.currentInput.sending(\.setCurrentInput))
                Button("Add") { store.send(.addBlackListItem) }
            }
        }
        .padding(.all).frame(width: 370)
    }
}

#Preview {
    GerritBlackListView(store: .init(initialState: GerritBlackList.State()) { GerritBlackList() })
}
