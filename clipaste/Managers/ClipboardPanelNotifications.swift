import AppKit
import SwiftUI
import SwiftData

// MARK: - Notification name

extension Notification.Name {
    static let clipboardLayoutModeChanged = Notification.Name("clipboardLayoutModeChanged")
    static let clipboardPreviewPanelChanged = Notification.Name("clipboardPreviewPanelChanged")
}
