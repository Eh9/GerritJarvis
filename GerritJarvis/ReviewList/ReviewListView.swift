//
//  ReviewListView.swift
//  GerritJarvis
//
//  Created by hudi on 2024/6/4.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import SwiftUI
import ComposableArchitecture

@Reducer
struct ReviewList {
    @ObservableState
    struct State {
        var gerritReviews: IdentifiedArrayOf<GerritReviewDisplay.State> = []
        var gitlabReviews: IdentifiedArrayOf<GitLabReviewDisplay.State> = []
    }

    enum Action {
        case `init`
        case updateGerritChanges([Change])
        case gerritReviews(IdentifiedActionOf<GerritReviewDisplay>)
        case gitlabReviews(IdentifiedActionOf<GitLabReviewDisplay>)
        case didPressGerrit(id: GerritReviewDisplay.State.ID)
        case didPressGitLab(id: GitLabReviewDisplay.State.ID)
    }

    @Dependency(\.gerritClient) var gerritClient: GerritClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .`init`:
                return .run { action in
                    guard let changes = try? await gerritClient.fetchReviewList() else {
                        return
                    }
                    await action(.updateGerritChanges(changes))
                }
            case let .updateGerritChanges(changes):
                state.gerritReviews = IdentifiedArrayOf(uniqueElements: changes.map {
                    GerritReviewDisplay.State(
                        id: $0.changeId!,
                        baseCell: ReviewDisplay.State(
                            project: $0.project ?? "null_project",
                            branch: $0.branch ?? "null_branch",
                            name: $0.owner?.displayName ?? $0.owner?.name ?? "null_name",
                            commitMessage: $0.subject ?? "null_message",
                            avatar: $0.owner?.avatarImage(),
                            hasNewEvent: false, // TODO: implement this
                            isMergeConflict: false // TODO: implement this
                        ),
                        gerritScore: $0.calculateReviewScore().0
                    )
                })
                return .none
            case let .didPressGerrit(id):
                print(id)
                return .none
            case let .didPressGitLab(id):
                print(id)
                return .none
            default: return .none
            }
        }.forEach(\.gerritReviews, action: \.gerritReviews) {
            GerritReviewDisplay()
        }.forEach(\.gitlabReviews, action: \.gitlabReviews) {
            GitLabReviewDisplay()
        }
    }
}

struct ReviewListView: View {
    var store: StoreOf<ReviewList>

    init(store: StoreOf<ReviewList>) {
        self.store = store
        store.send(.`init`)
    }

    var body: some View {
        WithPerceptionTracking {
            List {
                ForEachStore(store.scope(state: \.gerritReviews, action: \.gerritReviews)) { s in
                    GerritReviewCell(store: s).onTapGesture {
                        store.send(.didPressGerrit(id: s.id))
                    }
                }
                ForEachStore(store.scope(state: \.gitlabReviews, action: \.gitlabReviews)) { s in
                    GitLabReviewCell(store: s).onTapGesture {
                        store.send(.didPressGitLab(id: s.id))
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(width: 420)
        .frame(maxHeight: 600)
    }

    static var vc: NSViewController {
        NSHostingController(
            rootView: ReviewListView(store: .init(initialState: ReviewList.State()) { ReviewList() })
        )
    }
}

#Preview {
    ReviewListView(
        store: .init(initialState: ReviewList.State(
            gerritReviews: [
                .init(
                    id: "1",
                    baseCell: ReviewDisplay.State(
                        project: "tutor-ios-embedded",
                        branch: "feature/test1",
                        name: "Walter White",
                        commitMessage: "ADD: new feature very long long messages, say my name",
                        avatarUrl: "https://www.gravatar.com/avatar/205e460b479e2e5b48aec07710c08d50",
                        hasNewEvent: false,
                        isMergeConflict: true
                    ),
                    gerritScore: .PlusOne
                ),
                .init(
                    id: "2",
                    baseCell: ReviewDisplay.State(
                        project: "tutor-ios-embedded",
                        branch: "feature/test2",
                        name: "Walter White",
                        commitMessage: "ADD: new feature very long long messages, say my name",
                        avatarUrl: "https://www.gravatar.com/avatar/205e460b479e2e5b48aec07710c08d50",
                        hasNewEvent: false,
                        isMergeConflict: true
                    ),
                    gerritScore: .PlusOne
                )
            ],
            gitlabReviews: [
                .init(
                    id: 1,
                    baseCell: ReviewDisplay.State(
                        project: "tutor-ios-embedded",
                        branch: "feature/test3",
                        name: "Walter White",
                        commitMessage: "ADD: new feature very long long messages, now say my name",
                        avatarUrl: "https://www.gravatar.com/avatar/205e460b479e2e5b48aec07710c08d50",
                        hasNewEvent: false,
                        isMergeConflict: true
                    ),
                    threadCount: 99,
                    approved: true
                ),
                .init(
                    id: 2,
                    baseCell: ReviewDisplay.State(
                        project: "tutor-ios-embedded",
                        branch: "feature/test4",
                        name: "Walter White",
                        commitMessage: "ADD: new feature very long long messages, now say my name",
                        avatarUrl: "https://www.gravatar.com/avatar/205e460b479e2e5b48aec07710c08d50",
                        hasNewEvent: false,
                        isMergeConflict: true
                    ),
                    threadCount: 99,
                    approved: true
                )
            ]
        )) {
            ReviewList()
        }
    )
}
