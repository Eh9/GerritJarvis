//
//  GerritReviewCell.swift
//  GerritJarvis
//
//  Created by hudi on 2024/6/4.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import SwiftUI
import ComposableArchitecture

@Reducer
struct GerritReviewDisplay {
    @ObservableState
    struct State: Identifiable {
        var id: String = ""
        var baseCell: ReviewDisplay.State
        var gerritScore: ReviewScore = .Zero
    }

    enum Action {
        case baseCell(ReviewDisplay.Action)
        case pressTrigger
    }

    @Dependency(\.openURL) var openURL
    @Dependency(\.gerritClient) var gerritClient

    var body: some Reducer<State, Action> {
        Scope(state: \.baseCell, action: \.baseCell) {
            ReviewDisplay()
        }
        Reduce { state, action in
            switch action {
            case let .baseCell(baseCellAction):
                let id = state.id
                switch baseCellAction {
                case .didPressAuthor: return .run { _ in
                        guard let url = gerritClient.authorURL(id: id) else { return }
                        await openURL(url)
                    }
                case .didPressBranch: return .run { _ in
                        guard let url = gerritClient.branchURL(id: id) else { return }
                        await openURL(url)
                    }
                case .didPressProject: return .run { _ in
                        guard let url = gerritClient.projectURL(id: id) else { return }
                        await openURL(url)
                    }
                default: return .none
                }
            default: return .none
            }
        }
    }
}

struct GerritReviewCell: View {
    @State var store: StoreOf<GerritReviewDisplay>

    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 0) {
                ReviewCell(store: store.scope(state: \.baseCell, action: \.baseCell))
                Divider()
                Spacer()
                VStack {
                    switch store.gerritScore {
                    case .PlusTwo:
                        Image(.reviewPlus2).resizable().frame(width: 40, height: 40)
                    case .PlusOne:
                        Image(.reviewPlus1).resizable().frame(width: 40, height: 40)
                    case .MinusOne:
                        Image(.reviewMinus1).resizable().frame(width: 40, height: 40)
                    case .MinusTwo:
                        Image(.reviewMinus2).resizable().frame(width: 40, height: 40)
                    default: Text("")
                    }
                    Spacer()
                    Button { store.send(.pressTrigger) } label: {
                        Text("Trigger")
                            .font(.system(size: 10))
                            .offset(y: -1)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 5)
        }
    }
}

#Preview {
    GerritReviewCell(store: .init(initialState: GerritReviewDisplay.State(
        baseCell: ReviewDisplay.State(
            project: "tutor-ios-embedded",
            branch: "feature/test",
            name: "Walter White",
            commitMessage: "ADD: new feature very long long messages, say my name",
            avatarUrl: "https://www.gravatar.com/avatar/205e460b479e2e5b48aec07710c08d50",
            hasNewEvent: false,
            isMergeConflict: true
        ),
        gerritScore: .PlusOne
    )) {
        GerritReviewDisplay()
    })
}
