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
    struct State {
        var baseCell: ReviewDisplay.State
        var gerritScore: ReviewScore = .Zero
    }

    enum Action {
        case baseCell(ReviewDisplay.Action)
        case pressTrigger
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.baseCell, action: \.baseCell) {
            ReviewDisplay()
        }
        Reduce { state, action in
            switch action {
            case .baseCell:
                return .none
            default: return .none
            }
        }
    }
}

struct GerritReviewCell: View {
    @State var store: StoreOf<GerritReviewDisplay>

    var body: some View {
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
        .frame(width: 420, height: 66)
        .padding(.vertical, 5)
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
