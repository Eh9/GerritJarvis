//
//  GitLabReviewCell.swift
//  GerritJarvis
//
//  Created by hudi on 2024/6/4.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import SwiftUI
import ComposableArchitecture

@Reducer
struct GitLabReviewDisplay {
    @ObservableState
    struct State: Identifiable {
        var id: Int = 0
        var baseCell: ReviewDisplay.State
        var upvotes: Int = 0
        var downvotes: Int = 0
        var threadCount: Int = 0
        var approved: Bool = false
        // TODO: add target branch
    }

    enum Action {
        case baseCell(ReviewDisplay.Action)
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

struct GitLabReviewCell: View {
    @State var store: StoreOf<GitLabReviewDisplay>

    var body: some View {
        HStack(spacing: 0) {
            WithPerceptionTracking {
                ReviewCell(store: store.scope(state: \.baseCell, action: \.baseCell))
            }
            Divider()
            Spacer()
            VStack {
                Text("👍:\(store.upvotes)   👎:\(store.downvotes)")
                    .lineLimit(1)
                    .font(.system(size: 10))
                Spacer()
                if store.approved {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                }
                Spacer()
                if store.threadCount > 0 {
                    Text("\(store.threadCount) unresolved threads")
                        .font(.system(size: 8))
                }
            }
            Spacer()
        }
        .frame(width: 420, height: 66)
        .padding(.vertical, 5)
    }
}

#Preview {
    GitLabReviewCell(store: .init(initialState: GitLabReviewDisplay.State(
        baseCell: ReviewDisplay.State(
            project: "tutor-ios-embedded",
            branch: "feature/test",
            name: "Walter White",
            commitMessage: "ADD: new feature very long long messages, now say my name",
            avatarUrl: "https://www.gravatar.com/avatar/205e460b479e2e5b48aec07710c08d50",
            hasNewEvent: false,
            isMergeConflict: true
        ),
        threadCount: 99,
        approved: true
    )) {
        GitLabReviewDisplay()
    })
}
