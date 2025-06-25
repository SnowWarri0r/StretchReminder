// ReminderManager.swift
import Foundation
import AppKit
import SwiftUI

protocol ReminderManagerDelegate: AnyObject {
    /// 伸展开始时调用
    func reminderDidStartStretch()
    
    /// 伸展结束后调用
    func reminderDidEndStretch()
}

class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class ReminderManager: ObservableObject {
    weak var delegate: ReminderManagerDelegate?
    
    @Published var nextFireDate: Date?
    
    private var floatingWindows: [NSWindow] = []
    private var revertTimer: DispatchSourceTimer?
    private var dispatchTimer: DispatchSourceTimer?
    
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
        dispatchTimer?.cancel()
        revertTimer?.cancel()
    }
    
    func start() {
        scheduleNextCycle()
    }
    
    /// 手动触发一次浮窗提醒
    func triggerNow() {
        dispatchTimer?.cancel()
        showFloatingReminder()
        scheduleNextCycle()
    }
    
    @objc private func handleWake() {
        dispatchTimer?.cancel()
        scheduleNextCycle()
    }
    
    private func scheduleNextCycle() {
        // 1. 取消旧定时
        dispatchTimer?.cancel()
        
        // 2. 计算下次触发时间：以「现在」为基准
        let next = Date().addingTimeInterval(45 * 60)
        nextFireDate = next
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            wallDeadline: .now() + 45 * 60,
            repeating: .never,
            leeway: .seconds(1)
        )
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.showFloatingReminder()
            self.scheduleNextCycle()
        }
        timer.resume()
        dispatchTimer = timer
    }
    
    /// 核心：创建带动画的半透明浮窗
    private func showFloatingReminder() {
        delegate?.reminderDidStartStretch()
        // 1. SwiftUI 视图
        let overlay = FloatingReminderView(message: "🕒 该起来活动啦！")
        
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
                })
            }
        })
        revertTimer?.cancel()
        let rt = DispatchSource.makeTimerSource(queue: .main)
        rt.schedule(
            wallDeadline: .now() + 120,
            repeating: .never,
            leeway: .seconds(1)
        )
        rt.setEventHandler { [weak self] in
            self?.delegate?.reminderDidEndStretch()
        }
        rt.resume()
        revertTimer = rt
    }
}
