import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .system:
            return nil
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }

    var nsAppearance: NSAppearance? {
        guard let nsAppearanceName else { return nil }
        return Self.appearanceCache[nsAppearanceName]
    }

    private static let appearanceCache: [NSAppearance.Name: NSAppearance] = {
        var cache: [NSAppearance.Name: NSAppearance] = [:]

        if let aquaAppearance = NSAppearance(named: .aqua) {
            cache[.aqua] = aquaAppearance
        }

        if let darkAquaAppearance = NSAppearance(named: .darkAqua) {
            cache[.darkAqua] = darkAquaAppearance
        }

        return cache
    }()
}
