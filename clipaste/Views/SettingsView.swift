import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general = "general"
    case shortcuts = "shortcuts"
    case ignoredApps = "ignoredApps"
    case advanced = "advanced"
    case about = "about"

    var id: String { self.rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .ignoredApps: return "Ignored Apps"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .general: return LocalizedStringResource("General")
        case .shortcuts: return LocalizedStringResource("Shortcuts")
        case .ignoredApps: return LocalizedStringResource("Ignored Apps")
        case .advanced: return LocalizedStringResource("Advanced")
        case .about: return LocalizedStringResource("About")
        }
    }

    var navigationTitle: LocalizedStringKey { title }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .ignoredApps: return "nosign"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }

}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var isSidebarVisible = true
    @Environment(AppUpdateViewModel.self) private var appUpdateViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some View {
        let resolvedLocale = appLanguage.locale ?? .current

        HStack(spacing: 0) {
            if isSidebarVisible {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(SettingsTab.allCases) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                SidebarLabel(
                                    tab: tab,
                                    isSelected: selectedTab == tab,
                                    showsUpdateBadge: tab == .about && appUpdateViewModel.shouldShowUpdateBadge
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
                .settingsScrollChromeHidden()
                .frame(width: 198)
                .frame(maxHeight: .infinity, alignment: .top)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05), lineWidth: 1)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 18, y: 8)
                .padding(.leading, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .padding(.trailing, 18)
            }

            settingsDetailView(for: selectedTab)
                .background(Color(nsColor: .windowBackgroundColor))
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .environment(\.locale, resolvedLocale)
        .animation(nil, value: appLanguage)
        .frame(minWidth: 820, idealWidth: 900, maxWidth: .infinity,
               minHeight: 620, idealHeight: 700, maxHeight: .infinity)
        .background(SettingsWindowObserver())
        .background(WindowAppearanceObserver(theme: appTheme))
        .onReceive(NotificationCenter.default.publisher(for: .toggleSettingsSidebarIntent)) { _ in
            if accessibilityReduceMotion {
                isSidebarVisible.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSidebarVisible.toggle()
                }
            }
        }
    }
}

// MARK: - Sidebar Label

private struct SidebarLabel: View {
    let tab: SettingsTab
    let isSelected: Bool
    let showsUpdateBadge: Bool

    var body: some View {
        Label {
            Text(tab.localizedTitle)
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : .primary)
        } icon: {
            Image(systemName: tab.iconName)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 16)
                .overlay(alignment: .topTrailing) {
                    if showsUpdateBadge {
                        Circle()
                            .fill(isSelected ? .white.opacity(0.9) : .red)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -1)
                    }
                }
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        }
    }
}

private extension SettingsView {
    @ViewBuilder
    func settingsDetailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView()
        case .shortcuts:
            ShortcutsSettingsView()
        case .ignoredApps:
            IgnoredAppsSettingsView()
        case .advanced:
            AdvancedSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}
