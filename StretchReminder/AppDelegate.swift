import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let reminderManager = ReminderManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(reminderManager: reminderManager)
        reminderManager.start()
    }
}
