import AppKit
import Foundation
import SwiftUI

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
