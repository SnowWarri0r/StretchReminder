import SwiftUI
import ServiceManagement
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let manager = ReminderManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 请求通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    return
                }
                
                let alert = NSAlert()
                alert.messageText = String(localized: "alert_notification_denied_title")
                alert.informativeText = String(localized: "alert_notification_denied_detail")
                alert.alertStyle = .informational
                alert.addButton(withTitle: String(localized: "alert_notification_open_button"))
                alert.addButton(withTitle: String(localized: "alert_cancel"))
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                if let error = error {
                    NSLog("⚠️ 通知权限请求出错: \(error.localizedDescription)")
                }
            }
        }
        manager.addReminder(ReminderConfig(
            type: .stretch,
            message: String(localized: "reminder_message_stretch"),
            interval: 45 * 60,
            endDelay: 120,
            fireTimes: nil
        ))
        
        manager.addReminder(ReminderConfig(
            type: .drink,
            message: String(localized: "reminder_message_drink"),
            interval: 60 * 60,
            endDelay: 10,
            fireTimes: nil
        ))
        
        manager.addReminder(ReminderConfig(
            type: .analLift,
            message: String(localized: "reminder_message_analLift"),
            interval: 90 * 60, // 每90分钟提醒一次
            endDelay: 30, // 持续30秒
            fireTimes: nil
        ))
        
        manager.addReminder(ReminderConfig(
            type: .orderFood,
            message: String(localized: "reminder_message_orderFood"),
            interval: nil,
            endDelay: 60,
            fireTimes: [
                DateComponents(hour: 11, minute: 30),
                DateComponents(hour: 17, minute: 30)
            ]
        ))
        
        manager.addReminder(ReminderConfig(
            type: .eat,
            message: String(localized: "reminder_message_eat"),
            interval: nil,
            endDelay: 60,
            fireTimes: [
                DateComponents(hour: 12, minute: 0),
                DateComponents(hour: 18, minute: 0)
            ]
        ))
        
        statusBarController = StatusBarController(reminderManager: manager)
        manager.start()
    }
}
