import SwiftUI
import ServiceManagement
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let reminderManager = ReminderManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 请求通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    return
                }
                
                let alert = NSAlert()
                alert.messageText = "无法发送提醒通知"
                alert.informativeText = """
                请在“系统设置 → 通知”中为 StretchReminder 启用通知，以接收更新提醒。
                """
                alert.alertStyle = .informational
                alert.addButton(withTitle: "打开通知设置")
                alert.addButton(withTitle: "取消")
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
        
        statusBarController = StatusBarController(reminderManager: reminderManager)
        reminderManager.start()
    }
}
