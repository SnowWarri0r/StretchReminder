import AppKit
import ServiceManagement
import UserNotifications
import Sparkle

extension StatusBarController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        // 在后台检测到有更新时提醒用户
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification_update_title")
        content.body = String(localized: "notification_update_body")
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "UpdateReminder", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

class StatusBarController: NSObject, NSMenuItemValidation, ReminderManagerDelegate {
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var reminderManager: ReminderManager
    private var countdownItems: [ReminderType: NSMenuItem] = [:]
    private var activeStates: Set<ReminderType> = []
    private lazy var updater: SPUStandardUpdaterController = {
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()
    
    init(reminderManager: ReminderManager) {
        self.reminderManager = reminderManager
        super.init()
        reminderManager.delegate = self
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: nil)
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        let stretchItem = NSMenuItem(title: String(localized: "menu_stretch_placeholder"), action: nil, keyEquivalent: "")
        stretchItem.isEnabled = false
        menu.addItem(stretchItem)
        countdownItems[.stretch] = stretchItem
        
        let drinkItem = NSMenuItem(title: String(localized: "menu_drink_placeholder"), action: nil, keyEquivalent: "")
        drinkItem.isEnabled = false
        menu.addItem(drinkItem)
        countdownItems[.drink] = drinkItem
        
        pauseItem = NSMenuItem(title: String(localized: "menu_pause"), action: #selector(togglePause), keyEquivalent: "P")
        pauseItem.target = self
        menu.addItem(pauseItem)
        
        let triggerSubmenu = NSMenu()
        let triggerMainItem = NSMenuItem(title: String(localized: "menu_trigger_main"), action: nil, keyEquivalent: "")
        triggerMainItem.submenu = triggerSubmenu
        
        let triggerStretch = NSMenuItem(title: String(localized: "menu_trigger_stretch"), action: #selector(triggerStretch), keyEquivalent: "")
        triggerStretch.target = self
        triggerSubmenu.addItem(triggerStretch)
        
        let triggerDrink = NSMenuItem(title: String(localized: "menu_trigger_drink")
                                      , action: #selector(triggerDrink), keyEquivalent: "")
        triggerDrink.target = self
        triggerSubmenu.addItem(triggerDrink)
        
        menu.addItem(triggerMainItem)
        // 开机自启开关
        let launchItem = NSMenuItem(
            title: String(localized: "menu_launch_on_startup"),
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        // 根据当前状态打勾
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchItem)
        let checkItem = NSMenuItem(
            title: String(localized: "menu_check_update"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkItem.target = self
        menu.addItem(checkItem)
        
        menu.addItem(.separator())
        
        let quitItem = NSMenuItem(title: String(localized: "menu_quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        for (type, item) in countdownItems {
            if reminderManager.isPaused {
                switch type {
                case .stretch:
                    item.title = String(localized: "menu_paused_stretch")
                case .drink:
                    item.title = String(localized: "menu_paused_drink")
                }
            } else if let next = reminderManager.nextFireDateMap[type] {
                let mins = max(0, Int(ceil(next.timeIntervalSinceNow / 60)))
                let format: String
                switch type {
                case .stretch:
                    format = String(localized: "menu_next_stretch")
                case .drink:
                    format = String(localized: "menu_next_drink")
                }
                item.title = String.localizedStringWithFormat(format, mins)
            } else {
                switch type {
                case .stretch:
                    item.title = String(localized: "menu_not_set_stretch")
                case .drink:
                    item.title = String(localized: "menu_not_set_drink")
                }
            }
        }
        
        if menuItem.action == #selector(toggleLaunchAtLogin(_:)) {
            menuItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        }
        return true
    }
    
    func reminderDidStart(_ type: ReminderType) {
        DispatchQueue.main.async {
            self.activeStates.insert(type)
            self.updateStatusBarIcon()
        }
    }
    
    func reminderDidEnd(_ type: ReminderType) {
        DispatchQueue.main.async {
            self.activeStates.remove(type)
            self.updateStatusBarIcon()
        }
    }
    
    private func updateStatusBarIcon() {
        let symbolName: String
        if activeStates.contains(.stretch) {
            symbolName = "figure.cooldown"
        } else if activeStates.contains(.drink) {
            symbolName = "drop.fill"
        } else {
            symbolName = "figure.walk"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        statusItem.button?.image?.isTemplate = true
    }
    
    @objc private func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
    
    @objc private func triggerStretch() {
        reminderManager.triggerNow(for: .stretch)
    }
    
    @objc private func triggerDrink() {
        reminderManager.triggerNow(for: .drink)
    }
    
    @objc private func togglePause() {
        if reminderManager.isPaused {
            reminderManager.resume()
            pauseItem.title = String(localized: "menu_pause")
        } else {
            reminderManager.pause()
            pauseItem.title = String(localized: "menu_resume")
        }
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
            alert.messageText = String(localized: "alert_autostart_failed_title")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: String(localized: "alert_button_ok"))
            alert.runModal()
        }
    }
    
    @objc func quit() {
        NSApp.terminate(nil)
    }
}
