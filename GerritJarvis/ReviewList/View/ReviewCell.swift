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
        var targetBranch: String?
        var name: String
        var commitMessage: String
        var avatarName: String?
        var avatarUrl: String?
        var hasNewEvent: Bool = false
        var isMergeConflict: Bool = false

        var projectHover: Bool = false
        var branchHover: Bool = false

        var branchDescription: String {
            if let targetBranch = targetBranch {
                return "\(branch) -> \(targetBranch)"
            } else {
                return branch
            }
        }
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
        WithPerceptionTracking {
            HStack {
                VStack {
                    WebImage(url: URL(string: store.avatarUrl ?? "")) { result in
                        WithPerceptionTracking {
                            result.image ?? Image(nsImage: NSImage(named: .init(store.avatarName ?? "")) ?? .init())
                                .resizable()
                        }
                    }.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 35, height: 35)
                        .clipShape(Circle())
                        .overlay(alignment: .topLeading) {
                            if store.hasNewEvent { Circle().foregroundStyle(.red).frame(width: 6, height: 6) }
                        }
                    Text(store.name).frame(maxWidth: 40).lineLimit(2)
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.7)
                        .multilineTextAlignment(.center)
                }.padding(.leading).onTapGesture {
                    store.send(.didPressAuthor)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Label {
                        Text(store.project)
                            .font(.system(size: 11, weight: .light))
                            .underline(store.projectHover)
                            .foregroundStyle(store.projectHover ? .blue : .gray)
                            .onHover { store.send(.onProjectHover($0)) }
                    } icon: {
                        Image(.folder)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(.gray)
                    }.onTapGesture {
                        store.send(.didPressProject)
                    }.padding(.bottom, 0)
                    Label {
                        Text(store.branchDescription)
                            .font(.system(size: 11, weight: .light))
                            .underline(store.branchHover)
                            .foregroundStyle(store.branchHover ? .blue : .gray)
                            .onHover { store.send(.onBranchHover($0)) }
                    } icon: {
                        Image(.branch)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(.gray)
                    }.onTapGesture {
                        store.send(.didPressBranch)
                    }.padding(.top, 0)
                    Spacer()
                    Text(store.commitMessage).font(.system(size: 12)).lineLimit(2)
                        .frame(height: 30)
                        .opacity(0.6)
                }
                .padding(.vertical)
            }
            .frame(width: 400, height: 70, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if store.isMergeConflict {
                    Image(.conflict).resizable().frame(width: 25, height: 25)
                }
            }
        }
    }
}

#Preview {
    ReviewCell(store: .init(initialState: ReviewDisplay.State(
        project: "tutor-ios-embedded",
        branch: "feature/test",
        name: "乔斯达",
        commitMessage: "ADD: new feature teststststs tststst stststststst line line line line",
        avatarUrl: "https://www.gravatar.com/avatar/205e460b479e2e5b48aec07710c08d50",
        hasNewEvent: true,
        isMergeConflict: true
    )) {
        ReviewDisplay()
    })
}
