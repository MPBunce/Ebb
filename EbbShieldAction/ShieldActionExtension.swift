//
//  ShieldActionExtension.swift
//  EbbShieldAction
//
//  Handles the block screen's buttons. "Take a breath" can't open Ebb directly
//  (shield extensions can't launch apps), so it sends a notification that does.
//

import ManagedSettings
import UserNotifications

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .secondaryButtonPressed:
            ShieldController.pendingUnlock = application
            Self.postBreatherNotification {
                // Keep the shield up; the notification takes the user to Ebb.
                completionHandler(.defer)
            }
        case .primaryButtonPressed:
            // Closed the block screen instead of unlocking: an app visit avoided.
            TimeSaved.recordBlockedClose()
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    static func postBreatherNotification(completion: @escaping () -> Void) {
        let content = UNMutableNotificationContent()
        content.title = "Take a breath"
        content.body = "Tap to pause for a moment, then choose how long you need."
        content.userInfo = [BreatherNotification.kindKey: BreatherNotification.kind]
        content.interruptionLevel = .active
        let request = UNNotificationRequest(
            identifier: BreatherNotification.kind,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in completion() }
    }
}
