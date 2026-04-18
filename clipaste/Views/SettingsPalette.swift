import SwiftUI

enum SettingsPalette {
    static func updateAccent(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(.sRGB, red: 0.50, green: 0.64, blue: 0.80, opacity: 1.0)
        default:
            Color(.sRGB, red: 0.36, green: 0.50, blue: 0.65, opacity: 1.0)
        }
    }

    static func updateAccentEmphasis(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(.sRGB, red: 0.61, green: 0.72, blue: 0.83, opacity: 1.0)
        default:
            Color(.sRGB, red: 0.31, green: 0.45, blue: 0.59, opacity: 1.0)
        }
    }

    static func updateSurface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(.sRGB, red: 0.13, green: 0.18, blue: 0.22, opacity: 1.0)
        default:
            Color(.sRGB, red: 0.93, green: 0.96, blue: 0.97, opacity: 1.0)
        }
    }

    static func updateSurfaceBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(.sRGB, red: 0.24, green: 0.30, blue: 0.36, opacity: 1.0)
        default:
            Color(.sRGB, red: 0.84, green: 0.89, blue: 0.93, opacity: 1.0)
        }
    }

    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(.sRGB, red: 0.10, green: 0.12, blue: 0.15, opacity: 1.0)
        default:
            Color(.sRGB, red: 0.98, green: 0.98, blue: 0.98, opacity: 1.0)
        }
    }

    static func sidebarSelectionFill(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(.sRGB, red: 0.16, green: 0.21, blue: 0.26, opacity: 1.0)
        default:
            Color(.sRGB, red: 0.92, green: 0.95, blue: 0.97, opacity: 1.0)
        }
    }

    static func sidebarSelectionBorder(for colorScheme: ColorScheme) -> Color {
        updateSurfaceBorder(for: colorScheme)
    }
}
