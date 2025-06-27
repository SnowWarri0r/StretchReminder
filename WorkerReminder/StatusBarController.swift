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
    private var iconCycleTimer: Timer?
    private var currentIconIndex: Int = 0
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
        
        let orderFoodItem = NSMenuItem(title: String(localized: "menu_orderFood_placeholder"), action: nil, keyEquivalent: "")
        orderFoodItem.isEnabled = false
        menu.addItem(orderFoodItem)
        countdownItems[.orderFood] = orderFoodItem
        
        let eatItem = NSMenuItem(title: String(localized: "menu_eat_placeholder"), action: nil, keyEquivalent: "")
        eatItem.isEnabled = false
        menu.addItem(eatItem)
        countdownItems[.eat] = eatItem
        
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
        
        let triggerOrderFood = NSMenuItem(title: String(localized: "menu_trigger_orderFood"), action: #selector(triggerOrderFood), keyEquivalent: "")
        triggerOrderFood.target = self
        triggerSubmenu.addItem(triggerOrderFood)
        
        let triggerEat = NSMenuItem(title: String(localized: "menu_trigger_eat"), action: #selector(triggerEat), keyEquivalent: "")
        triggerEat.target = self
        triggerSubmenu.addItem(triggerEat)
        
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
                case .orderFood:
                    item.title = String(localized: "menu_paused_orderFood")
                case .eat:
                    item.title = String(localized: "menu_paused_eat")
                }
            } else if let next = reminderManager.nextFireDateMap[type] {
                let mins = max(0, Int(ceil(next.timeIntervalSinceNow / 60)))
                let format: String
                switch type {
                case .stretch:
                    format = String(localized: "menu_next_stretch")
                case .drink:
                    format = String(localized: "menu_next_drink")
                case .orderFood:
                    format = String(localized: "menu_next_orderFood")
                case .eat:
                    format = String(localized: "menu_next_eat")
                }
                item.title = String.localizedStringWithFormat(format, mins)
            } else {
                switch type {
                case .stretch:
                    item.title = String(localized: "menu_not_set_stretch")
                case .drink:
                    item.title = String(localized: "menu_not_set_drink")
                case .orderFood:
                    item.title = String(localized: "menu_not_set_orderFood")
                case .eat:
                    item.title = String(localized: "menu_not_set_eat")
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
    
    private func symbolName(for type: ReminderType) -> String {
        switch type {
        case .stretch:    return "figure.cooldown"
        case .drink:      return "drop.fill"
        case .orderFood:  return "takeoutbag.and.cup.and.straw.fill"
        case .eat:        return "fork.knife.circle.fill"
        }
    }
    
    private func updateStatusBarIcon() {
        iconCycleTimer?.invalidate()
        iconCycleTimer = nil
        currentIconIndex = 0
        if activeStates.count > 1 {
            // 直接用最新的 activeStates 重启
            startIconCycle()
        } else {
            // 单一或无状态，显示唯一图标
            let name = activeStates.first.map(symbolName) ?? "figure.walk"
            applyIcon(named: name)
        }
    }
    
    private func applyIcon(named name: String) {
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        statusItem.button?.image?.isTemplate = true
    }
    
    private func startIconCycle() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let types = ReminderType.allCases.filter { self.activeStates.contains($0) }
            let names = types.map(symbolName)
            guard !names.isEmpty else { return }
            let name = names[self.currentIconIndex % names.count]
            self.applyIcon(named: name)
            self.currentIconIndex += 1
        }
        RunLoop.main.add(timer, forMode: .common)
        iconCycleTimer = timer
    }
    
    private func stopIconCycle() {
        iconCycleTimer?.invalidate()
        iconCycleTimer = nil
        currentIconIndex = 0
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
    
    @objc private func triggerOrderFood() {
        reminderManager.triggerNow(for: .orderFood)
    }
    
    @objc private func triggerEat() {
        reminderManager.triggerNow(for: .eat)
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
