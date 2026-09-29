import AppKit
import SwiftUI
import SwiftData

// MARK: - Notification name

extension Notification.Name {
    static let clipboardLayoutModeChanged = Notification.Name("clipboardLayoutModeChanged")
    static let clipboardPreviewPanelChanged = Notification.Name("clipboardPreviewPanelChanged")
    /// showPanel 在面板排到前台之前于主线程同步发出，订阅方需同步处理才能赶在首帧之前。
    static let clipboardPanelWillPresent = Notification.Name("clipboardPanelWillPresent")
}
