//
//  GeneralPreferenceView.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/22.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import SwiftUI
import ComposableArchitecture

@Reducer
struct GeneralPreference {
    @ObservableState
    struct State {
        @Shared(.launchAtLogin) var launchAtLogin = false
        @Shared(.shouldNotifyMergeConflict) var shouldNotifyMergeConflict = false
        @Shared(.shouldNotifyNewIncomingReview) var shouldNotifyNewIncomingReview = false
        @Shared(.showOurNotReadyReview) var showOurNotReadyReview = false
        @Shared(.refreshFrequencyKey) var refreshFrequency = 3

        let options: [Double] = [1, 3, 5, 10, 30]
    }

    enum Action {
        case setLaunchAtLogin(Bool)
        case setShouldNotifyMergeConflict(Bool)
        case setShouldNotifyNewIncomingReview(Bool)
        case setShowOurNotReadyReview(Bool)
        case setRefreshFrequency(Double)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setLaunchAtLogin(value):
                state.launchAtLogin = value
                return .none
            case let .setShouldNotifyMergeConflict(value):
                state.shouldNotifyMergeConflict = value
                return .none
            case let .setShouldNotifyNewIncomingReview(value):
                state.shouldNotifyNewIncomingReview = value
                return .none
            case let .setShowOurNotReadyReview(value):
                state.showOurNotReadyReview = value
                return .none
            case let .setRefreshFrequency(value):
                state.refreshFrequency = value
                return .none // TODO: Add Side Effect
            }
        }
    }
}

extension PersistenceReaderKey where Self == AppStorageKey<Bool> {
    static var launchAtLogin: Self { appStorage("LaunchAtLoginKey") }
    static var shouldNotifyMergeConflict: Self { appStorage("ShouldNotifyMergeConflict") }
    static var shouldNotifyNewIncomingReview: Self { appStorage("ShouldNotifyNewIncomingReviewKey") }
    static var showOurNotReadyReview: Self { appStorage("ShowOurNotReadyReviewKey") }
}

extension PersistenceReaderKey where Self == AppStorageKey<Double> {
    static var refreshFrequencyKey: Self { appStorage("RefreshFrequencyKey") }
}

struct GeneralPreferenceView: View {
    @State var store: StoreOf<GeneralPreference>
    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Launch At Login", isOn: $store.launchAtLogin.sending(\.setLaunchAtLogin))
            Toggle(
                "Notify Merge Conflict",
                isOn: $store.shouldNotifyMergeConflict.sending(\.setShouldNotifyMergeConflict)
            )
            Toggle(
                "Notify New Incoming Review",
                isOn: $store.shouldNotifyNewIncomingReview.sending(\.setShouldNotifyNewIncomingReview)
            )
            Toggle(
                "Display My Review Which Score -2 By Myself",
                isOn: $store.showOurNotReadyReview.sending(\.setShowOurNotReadyReview)
            )
            Divider()
            HStack {
                Picker("Refresh Frequency", selection: $store.refreshFrequency.sending(\.setRefreshFrequency)) {
                    ForEach(store.options, id: \.self) { option in
                        Text(String(Int(option))).tag(option)
                    }
                }.frame(width: 170)
                Text("Minites")
            }
        }.padding(.all).frame(width: 370)
    }
}

#Preview {
    GeneralPreferenceView(store: .init(initialState: GeneralPreference.State()) {
        GeneralPreference()
    })
}
