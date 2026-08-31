import AppKit
import Foundation
import SwiftUI

enum TextSyncSizeLimit: String, CaseIterable, Identifiable {
    case unlimited = "unlimited"
    case tenMegabytes = "10mb"
    case oneMegabyte = "1mb"
    case quarterMegabyte = "256kb"

    nonisolated static let defaultsKey = "text_sync_size_limit"

    var id: String { rawValue }

    /// 完整文本超过该字节数时,仅同步截断后的前缀;nil = 无限制。
    nonisolated var limitBytes: Int? {
        switch self {
        case .unlimited: return nil
        case .tenMegabytes: return 10 * 1024 * 1024
        case .oneMegabyte: return 1024 * 1024
        case .quarterMegabyte: return 256 * 1024
        }
    }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .unlimited: return LocalizedStringResource("No Limit")
        case .tenMegabytes: return "10 MB"
        case .oneMegabyte: return "1 MB"
        case .quarterMegabyte: return "256 KB"
        }
    }
}

enum PasteTextFormat: String, CaseIterable, Identifiable {
    case original  = "original"
    case plainText = "plainText"

    var id: String { self.rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .original: return LocalizedStringResource("Keep Original Formatting")
        case .plainText: return LocalizedStringResource("Always Plain Text")
        }
    }
}

enum ClipboardLinkDisplayMode: String, CaseIterable, Identifiable {
    case rich
    case plain

    nonisolated static let defaultsKey = "linkDisplayMode"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .rich: return LocalizedStringResource("Rich Mode")
        case .plain: return LocalizedStringResource("Default Mode")
        }
    }

    nonisolated static func shouldFetchMetadata(defaults: UserDefaults = .standard) -> Bool {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let mode = Self(rawValue: rawValue) else {
            return true
        }

        return mode == .rich
    }
}
