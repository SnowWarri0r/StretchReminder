// ReminderManager.swift
import Foundation
import AppKit
import SwiftUI

enum ReminderType {
    case stretch
    case drink
}

extension ReminderType {
    var rawValue: String {
        switch self {
        case .stretch: return "stretch"
        case .drink: return "drink"
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
    let interval: TimeInterval
    let endDelay: TimeInterval
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
    private var dispatchTimers: [ReminderType: DispatchSourceTimer] = [:]
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
        dispatchTimers.values.forEach { $0.cancel() }
        revertTimers.values.forEach { $0.cancel() }
    }
    
    func addReminder(_ config: ReminderConfig) {
        configs[config.type] = config
        schedule(config)
    }
    
    func pause() {
        isPaused = true
        dispatchTimers.values.forEach { $0.cancel() }
        dispatchTimers.removeAll()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        for config in configs.values {
            schedule(config)
        }
    }
    
    @objc private func handleWake() {
        dispatchTimers.values.forEach { $0.cancel() }
        configs.values.forEach { schedule($0) }
    }
    
    private func schedule(_ config: ReminderConfig) {
        guard !isPaused else { return }
        dispatchTimers[config.type]?.cancel()
        
        let next = Date().addingTimeInterval(config.interval)
        nextFireDateMap[config.type] = next
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + config.interval,
            repeating: .never,
            leeway: .seconds(1)
        )
        timer.setEventHandler { [weak self] in
            self?.showFloatingReminder(config)
            self?.schedule(config)
        }
        timer.resume()
        dispatchTimers[config.type] = timer
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

        dispatchTimers[type]?.cancel()  // 取消原定时器
        showFloatingReminder(config)   // 立即显示
        schedule(config)               // 重置下一轮调度
    }
    
    private func buildCombinedMessage() -> String {
        var lines: [String] = []
        if pendingTypes.contains(.stretch) {
            lines.append(configs[.stretch]!.message)
        }
        if pendingTypes.contains(.drink) {
            lines.append(configs[.drink]!.message)
        }
        return lines.joined(separator: "\n")
    }
    
    private func updateFloatingContent() {
        floatingOverlayModel?.message = buildCombinedMessage()
    }
    
    /// 核心：创建带动画的半透明浮窗
    private func showFloatingReminder(_ config: ReminderConfig) {
        pendingTypes.insert(config.type)
        guard floatingWindows.isEmpty else {
            updateFloatingContent()
            return
        }
        for type in pendingTypes {
            delegate?.reminderDidStart(type)
        }
        let model = ReminderOverlayModel(message: buildCombinedMessage())
        self.floatingOverlayModel = model
        let overlay = FloatingReminderView(model: model)
        
        // 2. 托管到 NSHostingController
        let host = NSHostingController(rootView: overlay)
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = CGColor.clear
        host.view.layer?.isOpaque = false
        let size = CGSize(width: 300, height: 100)
        
        // 3. 居中计算
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let rect = NSRect(
            x: screen.midX - size.width/2,
            y: screen.midY - size.height/2,
            width: size.width,
            height: size.height
        )
        
        // 4. 创建 borderless 窗口
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
        
        // 5. 强引用并显示
        floatingWindows.append(window)
        window.makeKeyAndOrderFront(nil)
        
        // 6. 动画：淡入 → 停留 → 淡出
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 1
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                    // 移除强引用
                    self.floatingWindows.removeAll { $0 === window }
                    self.pendingTypes.removeAll()
                })
            }
        })
        for type in pendingTypes {
            revertTimers[type]?.cancel()
            let rt = DispatchSource.makeTimerSource(queue: .main)
            rt.schedule(
                wallDeadline: .now() + config.endDelay,
                repeating: .never,
                leeway: .seconds(1)
            )
            rt.setEventHandler { [weak self] in
                self?.delegate?.reminderDidEnd(type)
            }
            rt.resume()
            revertTimers[type] = rt
        }
    }
}
