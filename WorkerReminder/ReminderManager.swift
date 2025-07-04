import Foundation
import AppKit
import SwiftUI

enum ReminderType: CaseIterable {
    case stretch
    case drink
    case analLift
    case orderFood
    case eat
}

extension ReminderType {
    var localizedMessage: String {
        switch self {
        case .stretch: return String(localized: "reminder_message_stretch")
        case .drink: return String(localized: "reminder_message_drink")
        case .analLift: return String(localized: "reminder_message_analLift")
        case .orderFood: return String(localized: "reminder_message_orderFood")
        case .eat: return String(localized: "reminder_message_eat")
        }
    }
}

protocol ReminderManagerDelegate: AnyObject {
    func reminderDidStart(_ type: ReminderType)
    func reminderDidEnd(_ type: ReminderType)
}

struct ReminderConfig {
    let type: ReminderType
    let message: String
    var interval: TimeInterval?
    let endDelay: TimeInterval
    let fireTimes: [DateComponents]?
}

class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class ReminderOverlayModel: ObservableObject {
    @Published var message: String
    
    init(message: String) {
        self.message = message
    }
}

class ReminderManager: ObservableObject {
    weak var delegate: ReminderManagerDelegate?
    
    @Published var nextFireDateMap: [ReminderType: Date] = [:]
    @Published var isPaused: Bool = false
    
    private var pendingTypes: Set<ReminderType> = []
    private var floatingOverlayModel: ReminderOverlayModel?
    private var floatingWindows: [NSWindow] = []
    private var dispatchTimers: [ReminderType: [DispatchSourceTimer]] = [:]
    private var revertTimers: [ReminderType: DispatchSourceTimer] = [:]
    
    private var configs: [ReminderType: ReminderConfig] = [:]
    
    init() {
        // 监听系统唤醒，重置倒计时
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        dispatchTimers.values
            .flatMap { $0 }
            .forEach { $0.cancel() }
        revertTimers.values.forEach { $0.cancel() }
    }
    
    func addReminder(_ config: ReminderConfig) {
        configs[config.type] = config
        schedule(config)
    }
    
    func pause() {
        isPaused = true
        dispatchTimers.values
            .flatMap { $0 }
            .forEach { $0.cancel() }
        dispatchTimers.removeAll()
    }
    
    func resume() {
        guard isPaused else { return }
        isPaused = false
        for config in configs.values {
            schedule(config)
        }
    }
    
    private func schedule(_ config: ReminderConfig) {
        guard !isPaused else { return }
        dispatchTimers[config.type]?
            .forEach { $0.cancel() }
        dispatchTimers[config.type] = []
        
        if let fireTimes = config.fireTimes {
            // 取最小时间作为下次触发事件，避免错误
            refreshNextFireDate(for: config.type)

            var timers: [DispatchSourceTimer] = []
            for (_, timeComp) in fireTimes.enumerated() {
                let t = makeFixedTimer(
                    type: config.type,
                    at: timeComp,
                    config: config
                )
                if let t = t {
                    timers.append(t)
                }
            }
            dispatchTimers[config.type] = timers
        } else if let interval = config.interval {
            let next = Date().addingTimeInterval(interval)
            nextFireDateMap[config.type] = next
            
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + interval, repeating: .never)
            t.setEventHandler { [weak self] in
                self?.showFloatingReminder(config)
                self?.schedule(config)
            }
            t.resume()
            dispatchTimers[config.type] = [t]
        }
    }
    
    func start() {
        for config in configs.values {
            schedule(config)
        }
    }
    /// 手动触发一次浮窗提醒
    func triggerNow(for type: ReminderType) {
        guard !isPaused else { return }
        guard let config = configs[type] else { return }

        // 先取消并清空所有旧的定时器
        if let timers = dispatchTimers[type] {
            timers.forEach { $0.cancel() }
        }
        dispatchTimers[type] = []

        // 立即弹窗
        showFloatingReminder(config)
        // 重置下一轮调度
        schedule(config)
    }
    
    private func refreshNextFireDate(for type: ReminderType) {
        guard let times = configs[type]?.fireTimes else { return }
        let earliest = times.compactMap(nextDate).min()
        nextFireDateMap[type] = earliest
    }
    
    private func makeFixedTimer(type: ReminderType,
                                at time: DateComponents,
                                config: ReminderConfig) -> DispatchSourceTimer? {
        guard let next = nextDate(for: time) else { return nil }
        let interval = next.timeIntervalSinceNow
        
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: .never)
        t.setEventHandler { [weak self, weak t] in
            guard let self = self, let timer = t, !self.isPaused else { return }
            self.showFloatingReminder(config)
            // 当自己触发则可以清除
            timer.cancel()
            self.dispatchTimers[type]?.removeAll { $0 === timer }
            // 递归创建并跟踪
            if let nextTimer = self.makeFixedTimer(type: type, at: time, config: config) {
                self.dispatchTimers[type, default: []].append(nextTimer)
            }
            self.refreshNextFireDate(for: type)
        }
        t.resume()
        return t
    }
    
    private func nextDate(for time: DateComponents) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let now = Date()
        
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        
        if let candidate = calendar.date(from: components), candidate > now {
            return candidate
        } else {
            // 明天
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                var tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
                tomorrowComponents.hour = time.hour
                tomorrowComponents.minute = time.minute
                tomorrowComponents.second = 0
                return calendar.date(from: tomorrowComponents)
            }
        }
        return nil
    }
    
    private func buildCombinedMessage() -> String {
        var lines: [String] = []
        for type in pendingTypes {
            if let msg = configs[type]?.message {
                lines.append(msg)
            }
        }
        return lines.joined(separator: "\n")
    }
    
    private func updateFloatingContent() {
        floatingOverlayModel?.message = buildCombinedMessage()
    }
    
    /// 核心：创建带动画的半透明浮窗
    private func showFloatingReminder(_ config: ReminderConfig) {
        let isNew = !pendingTypes.contains(config.type)
        pendingTypes.insert(config.type)

        if isNew {
            delegate?.reminderDidStart(config.type)
        }
        
        revertTimers[config.type]?.cancel()
        let rt = DispatchSource.makeTimerSource(queue: .main)
        rt.schedule(wallDeadline: .now() + config.endDelay,
                    repeating: .never,
                    leeway: .seconds(1))
        rt.setEventHandler { [weak self, weak rt] in
            guard let self = self, let timer = rt else { return }
            DispatchQueue.main.async {
                timer.cancel()
                self.revertTimers[config.type] = nil
                self.delegate?.reminderDidEnd(config.type)
                self.pendingTypes.remove(config.type)
                
                if self.pendingTypes.isEmpty {
                    self.floatingWindows.forEach { $0.orderOut(nil) }
                    self.floatingWindows.removeAll()
                } else {
                    self.updateFloatingContent()
                }
            }
            
        }
        rt.resume()
        revertTimers[config.type] = rt
        
        if !floatingWindows.isEmpty {
            updateFloatingContent()
            return
        }
        
        let model = ReminderOverlayModel(message: buildCombinedMessage())
        self.floatingOverlayModel = model
        let overlay = FloatingReminderView(model: model)
        
        let host = NSHostingController(rootView: overlay)
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = CGColor.clear
        host.view.layer?.isOpaque = false
        host.view.translatesAutoresizingMaskIntoConstraints = false

        let minW = overlay.minWidth
        let maxW = overlay.maxWidth
        host.view.widthAnchor.constraint(greaterThanOrEqualToConstant: minW).isActive = true
        host.view.widthAnchor.constraint(lessThanOrEqualToConstant: maxW).isActive = true
        
        host.view.layoutSubtreeIfNeeded()

        let fitting = host.view.fittingSize
        let w = fitting.width
        let h = min(fitting.height, overlay.maxHeight)

        let screen = NSScreen.main!.visibleFrame
        let rect = NSRect(
            x: screen.midX - w/2,
            y: screen.midY - h/2,
            width: w, height: h
        )
        
        let window = FloatingWindow(
            contentRect: rect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        
        window.contentView = host.view
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = CGColor.clear
        
        window.alphaValue = 0  // 初始全透明
        
        floatingWindows.append(window)
        window.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 1
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                    // 移除强引用
                    self.floatingWindows.removeAll { $0 === window }
                })
            }
        })
    }
    
    @objc private func handleWake() {
        dispatchTimers.values
            .flatMap { $0 }
            .forEach { $0.cancel() }
        dispatchTimers.removeAll()

        configs.values.forEach { schedule($0) }
    }
}
