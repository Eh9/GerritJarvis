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
        var hasAccount: Bool
        var loading: Bool = false
        var gerritReviews: IdentifiedArrayOf<GerritReviewDisplay.State> = []
        var gitlabReviews: IdentifiedArrayOf<GitLabReviewDisplay.State> = []
    }

    enum Action {
        case onAppear
        case clearNewEvent
        case refreshData
        case clickAbout
        case clickPreferences
        case clickQuit
        case updateList
        case gerritReviews(IdentifiedActionOf<GerritReviewDisplay>)
        case gitlabReviews(IdentifiedActionOf<GitLabReviewDisplay>)
        case didPressGerrit(id: GerritReviewDisplay.State.ID)
        case didPressGitLab(id: GitLabReviewDisplay.State.ID)
    }

    @Dependency(\.jarvisClient) var jarvisClient
    @Dependency(\.gerritClient) var gerritClient
    @Dependency(\.gitlabService) var gitlabService
    @Dependency(\.openURL) var openURL

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.hasAccount = jarvisClient.hasAccount
                return .none
            case .clearNewEvent:
                return .run { send in
                    jarvisClient.clearNewEvent()
                    await send(.updateList)
                }
            case .refreshData:
                state.loading = true
                return .run { send in
                    await jarvisClient.refreshData()
                }
            case .clickAbout:
                return .run { _ in
                    await NSApplication.shared.orderFrontStandardAboutPanel()
                }
            case .clickPreferences:
                return .run { _ in
                    if let delegate = await NSApplication.shared.delegate as? AppDelegate {
                        DispatchQueue.main.async { delegate.showPreference() }
                    }
                }
            case .clickQuit:
                return .run { _ in
                    await NSApplication.shared.terminate(self)
                }
            case .updateList:
                state.loading = jarvisClient.isFetchingData
                state.gerritReviews = .init(uniqueElements: gerritClient.showingChanges)
                state.gitlabReviews = .init(uniqueElements: gitlabService.showingMRs)
                return .none
            case let .didPressGerrit(id):
                state.gerritReviews[id: id]?.baseCell.hasNewEvent = false
                return .run { _ in
                    gerritClient.resetNewStateOfChange(id: id)
                    guard let url = gerritClient.changeURL(id: id) else { return }
                    await openURL(url)
                }
            case let .didPressGitLab(id):
                state.gitlabReviews[id: id]?.baseCell.hasNewEvent = false
                return .run { _ in
                    gitlabService.resetNewStateOfMR(id: id)
                    guard let url = gitlabService.mrURL(id: id) else { return }
                    await openURL(url)
                }
            case .gerritReviews:
                return .none
            case .gitlabReviews:
                return .none
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
        store.send(.updateList)
        NotificationCenter.default.addObserver(
            forName: .ReviewListUpdatedNotification,
            object: nil,
            queue: nil
        ) { [store] _ in
            store.send(.updateList)
        }
    }

    var body: some View {
        WithPerceptionTracking {
            headerView
            if store.hasAccount {
                if #available(macOS 13.0, *) {
                    listView.scrollIndicators(.never)
                } else {
                    listView
                }
            } else {
                emptyAccountView.frame(minHeight: 400)
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    private var listView: some View {
        List {
            gitlabReviewsView
            gerritReviewsView
        }
        .listStyle(.plain)
    }

    private var gerritReviewsView: some View {
        ForEachStore(store.scope(state: \.gerritReviews, action: \.gerritReviews)) { s in
            GerritReviewCell(store: s).contentShape(.rect).onTapGesture {
                store.send(.didPressGerrit(id: s.id))
            }
        }
    }

    private var gitlabReviewsView: some View {
        ForEachStore(store.scope(state: \.gitlabReviews, action: \.gitlabReviews)) { s in
            GitLabReviewCell(store: s).contentShape(.rect).onTapGesture {
                store.send(.didPressGitLab(id: s.id))
            }
        }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer()
            Image(.clear)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.primary)
                .padding(.top, 6)
                .onTapGesture {
                    store.send(.clearNewEvent)
                }
            Image(.sync)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.primary)
                .padding(.top, 6)
                .onTapGesture {
                    store.send(.refreshData)
                }
                .disabled(store.loading)
            Menu {
                Button("About") { store.send(.clickAbout) }
                Button("Preference") { store.send(.clickPreferences) }
                Divider()
                Button("Quit") { store.send(.clickQuit) }
            } label: {
                Image(.setting)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }.menuStyle(.borderlessButton)
                .padding(.top, 6)
                .padding(.trailing)
                .frame(width: 60)
        }
        .foregroundStyle(.background)
        .frame(height: 30)
        .overlay(alignment: .center) {
            if store.loading {
                ProgressView().scaleEffect(0.5)
            }
        }
    }

    private var emptyAccountView: some View {
        VStack {
            Text("Go to Preference To Setup Account")
            Button("Go to Preference") {
                store.send(.clickPreferences)
            }
        }
    }

    static var vc: NSViewController {
        NSHostingController(
            rootView: ReviewListView(store: .init(
                initialState: ReviewList
                    .State(hasAccount: ConfigManager.shared.hasUser())
            ) { ReviewList() })
        )
    }
}

#Preview {
    ReviewListView(
        store: .init(initialState: ReviewList.State(hasAccount: false)) {
            ReviewList()
        }
    )
}
