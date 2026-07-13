import AppKit
import Foundation
import SwiftUI

enum ModifierKey: String, CaseIterable, Identifiable {
    enum ShortcutRole {
        case quickPaste
        case plainText
    }

    case command
    case option
    case control
    case shift

    static let quickPasteDefaultsKey = "modifier_quick_paste"
    static let plainTextDefaultsKey = "modifier_plain_text"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    func localizedDisplayName(locale: Locale?) -> String {
        let resolved = locale ?? .current
        switch self {
        case .command: return String(localized: "Command", locale: resolved)
        case .option: return String(localized: "Option", locale: resolved)
        case .control: return String(localized: "Control", locale: resolved)
        case .shift: return String(localized: "Shift", locale: resolved)
        }
    }

    func pickerLabel(locale: Locale?) -> String {
        "\(symbol) \(localizedDisplayName(locale: locale))"
    }

    var eventFlags: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }

    var eventModifiers: EventModifiers {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }

    static func migrateStoredPreferences(in defaults: UserDefaults = .standard) {
        migrate(defaultsKey: quickPasteDefaultsKey, fallback: .command, in: defaults)
        migrate(defaultsKey: plainTextDefaultsKey, fallback: .shift, in: defaults)
    }

    static func quickPastePreference(in defaults: UserDefaults = .standard) -> ModifierKey {
        resolvedValue(forKey: quickPasteDefaultsKey, fallback: .command, in: defaults)
    }

    static func plainTextPreference(in defaults: UserDefaults = .standard) -> ModifierKey {
        resolvedValue(forKey: plainTextDefaultsKey, fallback: .shift, in: defaults)
    }

    static func normalizedExclusiveShortcutPair(
        quickPaste: ModifierKey,
        plainText: ModifierKey,
        changedRole: ShortcutRole,
        previousQuickPaste: ModifierKey? = nil,
        previousPlainText: ModifierKey? = nil
    ) -> (quickPaste: ModifierKey, plainText: ModifierKey) {
        guard quickPaste == plainText else {
            return (quickPaste, plainText)
        }

        switch changedRole {
        case .quickPaste:
            return (
                quickPaste,
                replacementExcluding(
                    quickPaste,
                    preferred: previousPlainText
                )
            )
        case .plainText:
            return (
                replacementExcluding(
                    plainText,
                    preferred: previousQuickPaste
                ),
                plainText
            )
        }
    }

    private static func migrate(defaultsKey: String, fallback: ModifierKey, in defaults: UserDefaults) {
        let resolved = resolvedValue(forKey: defaultsKey, fallback: fallback, in: defaults)
        defaults.set(resolved.rawValue, forKey: defaultsKey)
    }

    private static func resolvedValue(
        forKey defaultsKey: String,
        fallback: ModifierKey,
        in defaults: UserDefaults
    ) -> ModifierKey {
        guard let storedValue = defaults.string(forKey: defaultsKey) else {
            return fallback
        }

        return Self(legacyRawValue: storedValue) ?? fallback
    }

    private init?(legacyRawValue: String) {
        switch legacyRawValue {
        case Self.command.rawValue, "⌘ Command":
            self = .command
        case Self.option.rawValue, "⌥ Option":
            self = .option
        case Self.control.rawValue, "⌃ Control":
            self = .control
        case Self.shift.rawValue, "⇧ Shift":
            self = .shift
        default:
            return nil
        }
    }

    private static func replacementExcluding(
        _ excluded: ModifierKey,
        preferred: ModifierKey?
    ) -> ModifierKey {
        if let preferred, preferred != excluded {
            return preferred
        }

        return allCases.first(where: { $0 != excluded }) ?? excluded
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    case de = "de"
    case fr = "fr"

    var id: String { self.rawValue }

    /// 语言选择器中展示的原生文案（非本地化键）。
    var nativeDisplayName: String {
        switch self {
        case .auto:   return ""
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en:     return "English"
        case .ja:     return "日本語"
        case .ko:     return "한국어"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
        }
    }

    var localizedDisplayName: LocalizedStringResource {
        switch self {
        case .auto: return LocalizedStringResource("Follow System")
        case .zhHans: return LocalizedStringResource("Simplified Chinese")
        case .zhHant: return LocalizedStringResource("Traditional Chinese")
        case .en: return LocalizedStringResource("English")
        case .ja: return LocalizedStringResource("Japanese")
        case .ko: return LocalizedStringResource("Korean")
        case .de: return LocalizedStringResource("German")
        case .fr: return LocalizedStringResource("French")
        }
    }

    var locale: Locale? {
        switch self {
        case .auto:   return nil
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .zhHant: return Locale(identifier: "zh-Hant")
        case .en:     return Locale(identifier: "en")
        case .ja:     return Locale(identifier: "ja")
        case .ko:     return Locale(identifier: "ko")
        case .de:     return Locale(identifier: "de")
        case .fr:     return Locale(identifier: "fr")
        }
    }

    var resolvedLocale: Locale {
        locale ?? Self.systemLocale
    }

    static var systemLocale: Locale {
        let globalDefaults = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        if let preferredLanguages = globalDefaults?["AppleLanguages"] as? [String],
           let languageIdentifier = preferredLanguages.first,
           languageIdentifier.isEmpty == false {
            return Locale(identifier: languageIdentifier)
        }
        return .current
    }
}

enum VerticalFollowMode: String, CaseIterable, Identifiable {
    case statusBar = "statusBar"
    case mouse = "mouse"
    case lastPosition = "lastPosition"

    var id: String { self.rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .statusBar: return LocalizedStringResource("Near Status Bar Icon")
        case .mouse: return LocalizedStringResource("Near Mouse Cursor")
        case .lastPosition: return LocalizedStringResource("Last Position")
        }
    }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    case oneDay = "1d"
    case threeDays = "3d"
    case oneWeek = "1w"
    case oneMonth = "1m"
    case sixMonths = "6m"
    case oneYear = "1y"
    case unlimited = "unlimited"
    var id: String { self.rawValue }
    
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .oneDay: return LocalizedStringResource("1 Day")
        case .threeDays: return LocalizedStringResource("3 Days")
        case .oneWeek: return LocalizedStringResource("1 Week")
        case .oneMonth: return LocalizedStringResource("1 Month")
        case .sixMonths: return LocalizedStringResource("6 Months")
        case .oneYear: return LocalizedStringResource("1 Year")
        case .unlimited: return LocalizedStringResource("Forever")
        }
    }
}

extension HistoryRetention {
    /// Returns a threshold date; records created before this date should be deleted.
    /// Returns nil for `.unlimited` (keep forever).
    nonisolated var expirationDate: Date? {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        switch self {
        case .oneDay:    return now.addingTimeInterval(-24 * 3600)
        case .threeDays:  return now.addingTimeInterval(-3 * 24 * 3600)
        case .oneWeek:    return now.addingTimeInterval(-7 * 24 * 3600)
        case .oneMonth:   return cal.date(byAdding: .month, value: -1, to: now)
        case .sixMonths:  return cal.date(byAdding: .month, value: -6, to: now)
        case .oneYear:    return cal.date(byAdding: .year,  value: -1, to: now)
        case .unlimited:  return nil
        }
    }
}

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

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .rich: return LocalizedStringResource("Rich Mode")
        case .plain: return LocalizedStringResource("Default Mode")
        }
    }
}

enum PreviewPanelMode: String, CaseIterable, Identifiable {
    case disabled
    case enabled

    static let defaultsKey = "previewPanelMode"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .disabled: return LocalizedStringResource("Disabled")
        case .enabled: return LocalizedStringResource("Enabled")
        }
    }

    static func registerDefault(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [defaultsKey: Self.disabled.rawValue])
    }

    static func migrateStoredPreference(in defaults: UserDefaults = .standard) {
        guard let storedValue = defaults.object(forKey: defaultsKey) else { return }

        guard let canonicalMode = canonicalMode(from: storedValue) else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }

        if defaults.string(forKey: defaultsKey) != canonicalMode.rawValue {
            defaults.set(canonicalMode.rawValue, forKey: defaultsKey)
        }
    }

    static func resolved(in defaults: UserDefaults = .standard) -> PreviewPanelMode {
        registerDefault(in: defaults)
        migrateStoredPreference(in: defaults)

        guard let rawValue = defaults.string(forKey: defaultsKey),
              let mode = Self(rawValue: rawValue) else {
            return .disabled
        }

        return mode
    }

    private static func canonicalMode(from storedValue: Any) -> PreviewPanelMode? {
        if let rawValue = storedValue as? String {
            switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case Self.disabled.rawValue, "false", "0", "off", "no":
                return .disabled
            case Self.enabled.rawValue, "true", "1", "on", "yes":
                return .enabled
            default:
                return nil
            }
        }

        if let boolValue = storedValue as? Bool {
            return boolValue ? .enabled : .disabled
        }

        if let numberValue = storedValue as? NSNumber {
            return numberValue.boolValue ? .enabled : .disabled
        }

        return nil
    }
}
