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
        case clearNewEvent
        case refreshData
        case clickAbout
        case clickPreferences
        case clickQuit
        case updateGerritChanges
        case updateGitLabMRs
        case gerritReviews(IdentifiedActionOf<GerritReviewDisplay>)
        case gitlabReviews(IdentifiedActionOf<GitLabReviewDisplay>)
        case didPressGerrit(id: GerritReviewDisplay.State.ID)
        case didPressGitLab(id: GitLabReviewDisplay.State.ID)
    }

    @Dependency(\.gerritClient) var gerritClient
    @Dependency(\.gitlabService) var gitlabService
    @Dependency(\.openURL) var openURL

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .`init`:
                return updateDataSideEffect
            case .clickAbout:
                return .run { _ in
                    await NSApplication.shared.orderFrontStandardAboutPanel()
                }
            case .clickPreferences:
                return .run { _ in
                    if let delegate = await NSApplication.shared.delegate as? AppDelegate {
                        delegate.showPreference()
                    }
                }
            case .clickQuit:
                return .run { _ in
                    await NSApplication.shared.terminate(self)
                }
            case .updateGerritChanges:
                state.gerritReviews = .init(uniqueElements: gerritClient.showingChanges)
                return .none
            case .updateGitLabMRs:
                state.gitlabReviews = .init(uniqueElements: gitlabService.showingMRs)
                return .none
            case let .didPressGerrit(id):
                print("didPressGerrit", id)
                return .run { _ in
                    guard let url = gerritClient.changeURL(id: id) else { return }
                    await openURL(url)
                }
            case let .didPressGitLab(id):
                print("didPressGitLab", id)
                return .run { _ in
                    guard let url = gitlabService.mrURL(id: id) else { return }
                    await openURL(url)
                }
            default: return .none
            }
        }.forEach(\.gerritReviews, action: \.gerritReviews) {
            GerritReviewDisplay()
        }.forEach(\.gitlabReviews, action: \.gitlabReviews) {
            GitLabReviewDisplay()
        }
    }

    private var updateDataSideEffect: Effect<Action> {
        .run { send in
            await gerritClient.update()
            await send(.updateGerritChanges)
            await gitlabService.fetchMRs()
            await send(.updateGitLabMRs)
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
        headerView
        WithPerceptionTracking {
            List {
                ForEachStore(store.scope(state: \.gerritReviews, action: \.gerritReviews)) { s in
                    GerritReviewCell(store: s).contentShape(.rect).onTapGesture {
                        store.send(.didPressGerrit(id: s.id))
                    }
                }
                ForEachStore(store.scope(state: \.gitlabReviews, action: \.gitlabReviews)) { s in
                    GitLabReviewCell(store: s).contentShape(.rect).onTapGesture {
                        store.send(.didPressGitLab(id: s.id))
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer()
            Image(.clear)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.black.opacity(0.7))
                .padding(.top, 6)
                .onTapGesture {
                    store.send(.clearNewEvent)
                }
            Image(.sync)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.black.opacity(0.7))
                .padding(.top, 6)
                .onTapGesture {
                    store.send(.refreshData)
                }
            Menu {
                Button("About") { store.send(.clickAbout) }
                Button("Preference") { store.send(.clickPreferences) }
                Divider()
                Button("Quit") { store.send(.clickQuit) }
            } label: {
                Image(.setting)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.black.opacity(0.7))
            }.menuStyle(.borderlessButton)
                .padding(.top, 6)
                .padding(.trailing)
                .frame(width: 60)
        }
        .foregroundStyle(.background)
        .frame(height: 30)
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
