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

    /// 侧边栏等位置使用 `LocalizedStringResource`，确保随 `\.locale` 即时刷新。
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
    @EnvironmentObject private var storeManager: StoreManager
    @EnvironmentObject private var runtimeStore: ClipboardRuntimeStore
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto

    var body: some View {
        let resolvedLocale = appLanguage.locale ?? .current

        return HStack(spacing: 0) {
            // ── 左侧：极窄纵向侧边栏 ──
            VStack(spacing: 12) {
                // 顶部：App Icon
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // 导航按钮组
                ForEach(SettingsTab.allCases) { tab in
                    SettingsSidebarItem(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                }

                Spacer()
            }
            .frame(width: 86)
            .frame(maxHeight: .infinity)
            .background(Color.clear)

            // ── 右侧：内容区 ──
            Group {
                switch selectedTab {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        }
        .background(.ultraThinMaterial)
        .environment(\.locale, resolvedLocale)
        .frame(minWidth: 560, idealWidth: 620, maxWidth: .infinity,
               minHeight: 540, idealHeight: 580, maxHeight: .infinity)
        .background(SettingsWindowObserver())
        .background(WindowAppearanceObserver(theme: appTheme))
        .sheet(
            isPresented: Binding(
                get: {
                    storeManager.shouldShowPaywall && storeManager.paywallSource == .settings
                },
                set: { isPresented in
                    if !isPresented {
                        storeManager.dismissPaywall()
                    }
                }
            )
        ) {
            PaywallView()
                .environmentObject(storeManager)
                .environment(\.locale, resolvedLocale)
        }
    }
}

// MARK: - Sidebar Item

private struct SettingsSidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .frame(width: 22, height: 20)
                    .symbolRenderingMode(isSelected ? .hierarchical : .monochrome)

                Text(tab.localizedTitle)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .default))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.15)
                            : (isHovering ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}
