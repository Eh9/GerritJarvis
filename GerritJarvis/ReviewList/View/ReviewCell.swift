//
//  ReviewCell.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/29.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI
import ComposableArchitecture

@Reducer
struct ReviewDisplay {
    @ObservableState
    struct State {
        var project: String
        var branch: String
        var name: String
        var commitMessage: String
        var avatar: NSImage?
        var avatarUrl: String?
        var hasNewEvent: Bool = false
        var isMergeConflict: Bool = false

        var projectHover: Bool = false
        var branchHover: Bool = false
    }

    enum Action {
        case onProjectHover(Bool)
        case onBranchHover(Bool)
        case didPressAuthor
        case didPressProject
        case didPressBranch
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            // TODO: action
            case let .onBranchHover(value):
                state.branchHover = value
                return .none
            case let .onProjectHover(value):
                state.projectHover = value
                return .none
            default: return .none
            }
        }
    }
}

struct ReviewCell: View {
    @State var store: StoreOf<ReviewDisplay>

    var body: some View {
        HStack {
            VStack {
                WebImage(url: URL(string: store.avatarUrl ?? "")) { $0.image ?? Image(nsImage: store.avatar ?? .init())
                }.resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                Text(store.name).frame(maxWidth: 40).lineLimit(2)
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .overlay(alignment: .topLeading) {
                        if store.hasNewEvent { Circle().foregroundStyle(.red).frame(width: 4, height: 4) }
                    }
            }.padding(.leading)
            VStack(alignment: .leading, spacing: 0) {
                Label {
                    Text(store.project)
                        .font(.system(size: 10, weight: .light))
                        .underline(store.projectHover)
                        .foregroundStyle(store.projectHover ? .blue : .gray)
                        .onHover { store.send(.onProjectHover($0)) }
                } icon: {
                    Image(.folder)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.gray)
                }.onTapGesture {
                    store.send(.didPressProject)
                }.padding(.bottom, 0)
                Label {
                    Text(store.branch)
                        .font(.system(size: 10, weight: .light))
                        .underline(store.branchHover)
                        .foregroundStyle(store.branchHover ? .blue : .gray)
                        .onHover { store.send(.onBranchHover($0)) }
                } icon: {
                    Image(.branch)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.gray)
                }.onTapGesture {
                    store.send(.didPressBranch)
                }.padding(.top, 0)
                Spacer()
                Text(store.commitMessage).font(.system(size: 12)).lineLimit(2)
                    .frame(height: 30)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical)
            .overlay(alignment: .topTrailing) {
                if store.isMergeConflict {
                    Image(.conflict).resizable().frame(width: 20, height: 20).offset(y: 20)
                }
            }
        }
        .frame(width: 340, height: 66, alignment: .leading)
    }
}

#Preview {
    ReviewCell(store: .init(initialState: ReviewDisplay.State(
        project: "tutor-ios-embedded",
        branch: "feature/test",
        name: "jessy pinkman",
        commitMessage: "ADD: new feature teststststs tststst stststststst",
        avatarUrl: "https://www.gravatar.com/avatar/205e460b479e2e5b48aec07710c08d50",
        hasNewEvent: true,
        isMergeConflict: true
    )) {
        ReviewDisplay()
    })
}
