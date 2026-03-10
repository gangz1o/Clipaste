import AppKit
import SwiftUI

/// ClipboardPanelManager is responsible for managing the floating clipboard history panel.
/// It uses a borderless, non-activating NSPanel that floats at the bottom of the screen.
class ClipboardPanelManager {
    static let shared = ClipboardPanelManager()
    
    private var panel: ClipboardPanel?
    private var eventMonitor: Any?
    
    /// Indicates whether the panel is currently visible to the user.
    private(set) var isVisible: Bool = false
    
    private init() {
        setupPanel()
    }
    
    private func setupPanel() {
        // Create an NSPanel with borderless and non-activating style masks.
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        
        let panel = ClipboardPanel(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        // Ensure the panel can display full-size content and has a clear background.
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.alphaValue = 0.0 // Start invisible
        
        // Float above other normal windows
        panel.level = .floating
        
        // Set the SwiftUI view as the content view controller
        let hostingController = NSHostingController(rootView: ClipboardMainView())
        panel.contentViewController = hostingController
        
        self.panel = panel
    }
    
    /// Toggles the visibility of the clipboard panel.
    func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    /// Shows the panel at the bottom of the screen covering 100% of the screen width and 250pt in height.
    func showPanel() {
        guard !isVisible, let panel = panel, let screen = NSScreen.main else { return }
        
        let visibleFrame = screen.visibleFrame
        let panelHeight: CGFloat = 300
        
        // Starting frame (slightly below the visible bottom)
        let hiddenFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY - 20,
            width: visibleFrame.width,
            height: panelHeight
        )
        
        // Target frame (exact bottom of the visible frame)
        let visibleFrameRect = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: panelHeight
        )
        
        // Set to initial hidden state before animation starts
        panel.setFrame(hiddenFrame, display: true)
        panel.alphaValue = 0.0
        panel.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            panel.animator().setFrame(visibleFrameRect, display: true)
            panel.animator().alphaValue = 1.0
        }) { [weak self] in
            self?.isVisible = true
            self?.setupEventMonitor()
        }
        
        // Activate the application as an accessory if needed, but DO NOT ignore other apps.
        NSApp.activate(ignoringOtherApps: false)
    }
    
    /// Hides the clipboard panel with an animation.
    func hidePanel() {
        guard isVisible, let panel = panel else { return }
        
        let currentFrame = panel.frame
        let hiddenFrame = NSRect(
            x: currentFrame.minX,
            y: currentFrame.minY - 20,
            width: currentFrame.width,
            height: currentFrame.height
        )
        
        removeEventMonitor()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            
            panel.animator().setFrame(hiddenFrame, display: true)
            panel.animator().alphaValue = 0.0
        }) { [weak self] in
            panel.orderOut(nil)
            self?.isVisible = false
            NSApp.hide(nil)
        }
    }
    
    // MARK: - Event Monitoring
    
    /// Sets up a global monitor to detect clicks outside the panel when it's visible.
    private func setupEventMonitor() {
        guard eventMonitor == nil else { return }
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.isVisible else { return }
            self.hidePanel()
        }
    }
    
    /// Removes the global event monitor.
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
