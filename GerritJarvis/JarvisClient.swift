//
//  JarvisClient.swift
//  GerritJarvis
//
//  Created by hudi on 2024/6/7.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import Foundation
import ComposableArchitecture

private enum JarvisClientKey: DependencyKey {
    static let liveValue: JarvisClient = .shared
}

extension DependencyValues {
    var jarvisClient: JarvisClient {
        get { self[JarvisClientKey.self] }
        set { self[JarvisClientKey.self] = newValue }
    }
}

// TODO: 直接用  ReviewList() Reducer 来实现
class JarvisClient {
    static let shared = JarvisClient()

    @Shared(.refreshFrequencyKey) var refreshFrequency = 3

    @Dependency(\.gerritClient) var gerritClient
    @Dependency(\.gitlabService) var gitlabService

    private var timer: Timer?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .RefreshFrequencyUpdatedNotification,
            object: nil,
            queue: nil
        ) { [self] _ in
            Task { await refreshData() }
        }
        NotificationCenter.default.addObserver(
            forName: .AccountUpdatedNotification,
            object: nil,
            queue: nil
        ) { [self] _ in
            Task { await refreshData() }
        }
    }

    private(set) var isFetchingData: Bool = false

    var hasAccount: Bool {
        ConfigManager.shared.hasUser()
    }

    var newEventCount: Int { gerritClient.newEventCount + gitlabService.newEventCount }

    func setupAccount() async {
        stopTimer()
        isFetchingData = true
        async let gitlabAccount: ()? = ConfigManager.shared.hasGitLabUser ? gitlabService.setup() : nil
        async let gerritAccount = ConfigManager.shared.hasGerritUser ? gerritClient.verifyAccount() : nil
        do {
            _ = try await gerritAccount
        } catch {
            print("setupAccount error: \(error)")
        }
        await gitlabAccount
        isFetchingData = false
        await refreshData()
    }

    func refreshData() async {
        stopTimer()
        isFetchingData = true
        async let gerrit: ()? = ConfigManager.shared.hasGerritUser ? gerritClient.update() : nil
        async let gitlab: ()? = ConfigManager.shared.hasGitLabUser ? gitlabService.fetchMRs() : nil
        _ = await(gerrit, gitlab)
        DispatchQueue.main.async { [self] in
            isFetchingData = false
            NotificationCenter.default.post(
                name: .ReviewListUpdatedNotification,
                object: nil,
                userInfo: nil
            )
            NotificationCenter.default.post(
                name: ReviewListNewEvents.notificationName,
                object: nil,
                userInfo: nil
            )
            startTimer()
        }
    }

    func clearNewEvent() {
        gerritClient.clearNewEvent()
        gitlabService.clearNewEvent()
        NotificationCenter.default.post(
            name: ReviewListNewEvents.notificationName,
            object: nil,
            userInfo: nil
        )
    }

    private func startTimer() {
        if timer != nil {
            return
        }
        let interval: TimeInterval = refreshFrequency * 60
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshData() }
        })
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
