import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general = "general"
    case shortcuts = "shortcuts"
    case advanced = "advanced"
    case about = "about"

    var id: String { self.rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var navigationTitle: LocalizedStringKey { title }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some View {
        HStack(spacing: 0) {
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
            .frame(width: 76)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

            // ── 右侧：内容区 ──
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .shortcuts:
                    ShortcutsSettingsView()
                case .advanced:
                    AdvancedSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 560, idealWidth: 620, maxWidth: .infinity,
               minHeight: 420, idealHeight: 460, maxHeight: .infinity)
        .background(SettingsWindowObserver())
        .background(WindowAppearanceObserver(theme: appTheme))
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

                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : (isHovering ? Color.primary.opacity(0.04) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}
