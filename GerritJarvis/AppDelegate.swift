//
//  AppDelegate.swift
//  GerritJarvis
//
//  Created by Chuanren Shang on 2018/10/24.
//  Copyright © 2018 Chuanren Shang. All rights reserved.
//

import Cocoa
import Settings

extension Settings.PaneIdentifier {
    static let general = Self("general")
    static let gerrit = Self("gerrit")
    static let gitlab = Self("gitlab")
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private var triggerController: MergedTriggerWindowController?

    lazy var popover: NSPopover = {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = .init(width: 511, height: 557)
        pop.contentViewController = ReviewListView.vc
        return pop
    }()

    lazy var preferencesWindowController = SettingsWindowController(
        panes: [
            Settings.Pane(
                identifier: .general,
                title: "General",
                toolbarIcon: NSImage(named: NSImage.preferencesGeneralName)!
            ) {
                GeneralPreferenceView(store: .init(initialState: GeneralPreference.State()) {
                    GeneralPreference()
                })
            },
            Settings.Pane(
                identifier: .gerrit,
                title: "Gerrit",
                toolbarIcon: NSImage(named: NSImage.advancedName)!
            ) {
                GerritAccountPreferenceView(store: .init(initialState: GerritAccountPreference.State()) {
                    GerritAccountPreference()
                })
            },
            Settings.Pane(
                identifier: .gitlab,
                title: "GitLab",
                toolbarIcon: NSImage(named: NSImage.advancedName)!
            ) {
                GitLabAccountSettingView().environmentObject(GitLabConfigs.groupInfo)
            },
        ]
    )

    var reviewListDataController = ReviewListDataController()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application

        initPopover()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reviewListUpdated(notification:)),
            name: ReviewListDataController.ReviewListNewEventsNotification,
            object: nil
        )

        if ConfigManager.shared.hasUser() {
            reviewListDataController.setupAccount()
        }
        UserNotificationHandler.shared.setup()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

// MARK: - Popover

extension AppDelegate {
    private func initPopover() {
        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("CodeReview"))
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover(_:))
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }

    func showPopover(sender: Any?) {
        if let button = statusItem.button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.maxY)
        }
    }

    func closePopover(sender: Any?) {
        popover.performClose(sender)
    }
}

// MARK: - Preference

extension AppDelegate {
    func showPreference() {
        if ConfigManager.shared.hasUser() {
            preferencesWindowController.show(pane: .general)
        } else {
            preferencesWindowController.show(pane: .gerrit)
        }
    }
}

// MARK: - GerritTrigger

extension AppDelegate {
    func showGerritTrigger(change: Change) {
        if triggerController != nil {
            triggerController?.close()
        }
        triggerController = MergedTriggerWindowController(windowNibName: "MergedTriggerWindowController")
        triggerController?.change = change
        triggerController?.showWindow(NSApplication.shared.delegate)
    }
}

// MARK: - Event Count

extension AppDelegate {
    @objc func reviewListUpdated(notification: Notification?) {
        guard let userInfo = notification?.userInfo,
              let newEvents = userInfo[ReviewListDataController.ReviewListNewEventsKey] as? Int
        else {
            updateEventCount(0)
            return
        }
        updateEventCount(newEvents)
    }

    private func updateEventCount(_ count: Int) {
        guard let button = statusItem.button else {
            return
        }

        if count == 0 {
            button.title = ""
        } else {
            button.title = String(count)
        }
    }
}
