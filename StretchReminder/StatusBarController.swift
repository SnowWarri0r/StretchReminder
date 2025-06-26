import AppKit
import ServiceManagement
import Sparkle

class StatusBarController: NSObject, NSMenuItemValidation, ReminderManagerDelegate {
    private var statusItem: NSStatusItem!
    private var reminderManager: ReminderManager
    private var countdownItem: NSMenuItem!
    private let updater = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    
    init(reminderManager: ReminderManager) {
        self.reminderManager = reminderManager
        super.init()
        reminderManager.delegate = self
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "站立走动")
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        countdownItem = NSMenuItem(title: "下次伸展还剩 -- 分钟", action: nil, keyEquivalent: "")
        countdownItem.isEnabled = false
        menu.addItem(countdownItem)
        
        let triggerItem = NSMenuItem(title: "立即提醒", action: #selector(triggerNow), keyEquivalent: "R")
        triggerItem.target = self
        menu.addItem(triggerItem)
        // 开机自启开关
        let launchItem = NSMenuItem(
            title: "开机自启",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        // 根据当前状态打勾
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchItem)
        let checkItem = NSMenuItem(
            title: "检查更新",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkItem.target = self
        menu.addItem(checkItem)
        
        menu.addItem(.separator())
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let next = reminderManager.nextFireDate {
            let interval = next.timeIntervalSinceNow
            let mins = max(0, Int(ceil(interval / 60)))
            countdownItem.title = "下次伸展还剩 \(mins) 分钟"
        } else {
            countdownItem.title = "下次伸展时间未设置"
        }
        if menuItem.action == #selector(toggleLaunchAtLogin(_:)) {
            menuItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        }
        return true
    }
    
    func reminderDidStartStretch() {
        DispatchQueue.main.async {
            self.statusItem.button?.image = NSImage(systemSymbolName: "figure.cooldown", accessibilityDescription: "伸展")
            self.statusItem.button?.image?.isTemplate = true
        }
    }
    
    func reminderDidEndStretch() {
        DispatchQueue.main.async {
            self.statusItem.button?.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "站立走动")
            self.statusItem.button?.image?.isTemplate = true
        }
    }
    
    @objc private func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
    
    @objc func triggerNow() {
        reminderManager.triggerNow()
    }
    
    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            default:
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "开机自启操作失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好的")
            alert.runModal()
        }
    }
    
    @objc func quit() {
        NSApp.terminate(nil)
    }
}
