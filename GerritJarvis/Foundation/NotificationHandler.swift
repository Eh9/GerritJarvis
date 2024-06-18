//
//  NotificationHandler.swift
//  GerritJarvis
//
//  Created by hudi on 2024/5/20.
//  Copyright © 2024 Chuanren Shang. All rights reserved.
//

import Foundation
import UserNotifications
import AppKit

class UserNotificationHandler: NSObject {
    static let shared: UserNotificationHandler = .init()

    private var notificationHandlers: [String: () -> Void] = [:]

    override private init() {
        super.init()
        center.delegate = self
    }

    let center: UNUserNotificationCenter = .current()

    func setup() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("requestAuthorization granted: \(granted)")
            } else {
                print("requestAuthorization granted: \(granted)")
            }
            if let error = error {
                print("requestAuthorization error: \(error)")
            }
        }
        let silentAction = UNNotificationAction(identifier: "Silent", title: "SilentThisMR", options: .destructive)
        let category = UNNotificationCategory(
            identifier: "Review",
            actions: [silentAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func sendNotification(
        title: String,
        body: String,
        iconUrl: String? = nil,
        url: String? = nil,
        onNotificationConfirmed: (() -> Void)? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "Review"
        content.userInfo = ["jumpUrl": url ?? ""]
        // add image
        if let iconUrl = iconUrl, let imageUrl = URL(string: iconUrl) {
            do {
                let attachment = try UNNotificationAttachment(
                    identifier: UUID().uuidString,
                    url: imageUrl,
                    options: nil
                )
                content.attachments = [attachment]
            } catch {
                print("sendNotification error: \(error)")
            }
        }

        let uuid = UUID().uuidString
        notificationHandlers[uuid] = onNotificationConfirmed
        let request = UNNotificationRequest(identifier: uuid, content: content, trigger: nil)
        center.add(request) { error in
            if let error = error {
                print("sendNotification error: \(error)")
            }
        }
    }
}

extension UserNotificationHandler: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        if request.content.categoryIdentifier == "Review" {
            switch response.actionIdentifier {
            case "Silent":
                print("Silent")
            default:
                break
            }
        }
        if let url = request.content.userInfo["jumpUrl"] as? String,
           let jumpUrl = URL(string: url)
        {
            NSWorkspace.shared.open(jumpUrl)
        }
        if let handler = notificationHandlers[request.identifier] {
            handler()
            NotificationCenter.default.post(
                name: ReviewListNewEvents.notificationName,
                object: nil,
                userInfo: nil
            )
        }
        completionHandler()
    }
}
