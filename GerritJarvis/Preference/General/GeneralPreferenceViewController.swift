//
//  GeneralPreferenceViewController.swift
//  GerritJarvis
//
//  Created by Chuanren Shang on 2019/5/14.
//  Copyright © 2019 Chuanren Shang. All rights reserved.
//

import Cocoa
import Settings
import LaunchAtLogin

class GeneralPreferenceViewController: NSViewController, SettingsPane {
    let paneIdentifier = Settings.PaneIdentifier.general
    let paneTitle = "General"
    let toolbarItemIcon = NSImage(named: NSImage.preferencesGeneralName)!

    @IBOutlet var launchAtLoginButton: NSButton!
    @IBOutlet var mergeConflictButton: NSButton!
    @IBOutlet var notifyNewIncomingButton: NSButton!
    @IBOutlet var showOurNotReadyReviewButton: NSButton!
    @IBOutlet var frequencyButton: NSPopUpButton!

    @IBAction func launchAtLoginClicked(_ sender: NSButton) {
        ConfigManager.shared.launchAtLogin = (sender.state == .on)
        LaunchAtLogin.isEnabled = ConfigManager.shared.launchAtLogin
    }

    @IBAction func notifyMergeConflictClicked(_ sender: NSButton) {
        ConfigManager.shared.shouldNotifyMergeConflict = (sender.state == .on)
    }

    @IBAction func notifyNewIncomingClicked(_ sender: NSButton) {
        ConfigManager.shared.shouldNotifyNewIncomingReview = (sender.state == .on)
    }

    @IBAction func showOurNotReadyReviewClicked(_ sender: NSButton) {
        ConfigManager.shared.showOurNotReadyReview = (sender.state == .on)
    }

    @IBAction func popupItemSelected(_ sender: NSPopUpButton) {
        let items = sender.itemTitles
        let index = sender.indexOfSelectedItem
        guard let frequency = TimeInterval(items[index]) else {
            return
        }
        ConfigManager.shared.refreshFrequency = frequency
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        mergeConflictButton.state = ConfigManager.shared.shouldNotifyMergeConflict ? .on : .off
        notifyNewIncomingButton.state = ConfigManager.shared.shouldNotifyNewIncomingReview ? .on : .off
        showOurNotReadyReviewButton.state = ConfigManager.shared.showOurNotReadyReview ? .on : .off

        let values: [TimeInterval] = [1, 3, 5, 10, 30]
        let frequency = ConfigManager.shared.refreshFrequency
        var index: Int?
        for (i, value) in values.enumerated() {
            if frequency == value {
                index = i
                break
            }
        }
        if let index = index {
            frequencyButton.selectItem(at: index)
        }
    }
}
