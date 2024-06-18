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
            case .pressTrigger:
                let id = state.id
                return .run { _ in
                    if let delegate = await NSApplication.shared.delegate as? AppDelegate,
                       let change = gerritClient.trackingChanges.first(where: { $0.changeId == id })
                    {
                        DispatchQueue.main.async { delegate.showGerritTrigger(change: change) }
                    }
                }
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
                    if let reviewScoreImage = store.gerritScore.imageIcon {
                        Image(reviewScoreImage).resizable().frame(width: 40, height: 40)
                    } else {
                        Text("")
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
