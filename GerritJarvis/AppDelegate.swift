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
    static let account = Self("gerrit")
    static let gitlabAccount = Self("gitlab")
    static let blacklist = Self("blacklist")
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    lazy var popover: NSPopover = {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = ReviewListViewController
            .freshController(dataController: self.reviewListDataController)
        return pop
    }()

    lazy var preferencesWindowController = SettingsWindowController(
        panes: [
            GeneralPreferenceViewController(),
            AccountPreferenceViewController(),
            Settings.Pane(
                identifier: .gitlabAccount,
                title: "GitLabAccount",
                toolbarIcon: NSImage(named: NSImage.advancedName)!
            ) {
                GitLabAccountSettingView().environmentObject(GitLabConfigs.groupInfo)
            },
            BlackListPreferenceViewController(),
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
            preferencesWindowController.show(pane: .account)
        }
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
