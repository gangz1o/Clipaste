import SwiftUI


extension GeneralSettingsView {
    var generalSection: some View {
        Section {
            Toggle(isOn: launchAtLoginBinding) {
                Text("Launch at Login")
            }

            Toggle(isOn: $hideMenuBarIcon) {
                Text("Hide Menu Bar Icon")
            }

            Picker("Language", selection: $viewModel.appLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.localizedDisplayName).tag(lang)
                }
            }

            Toggle(isOn: $viewModel.isCopySoundEnabled) {
                Text("Copy Notification Sound")
            }

            Toggle(isOn: $singleClickPaste) {
                Text("Single-click Paste")
            }

            Toggle(isOn: $autoPreview) {
                Text("Auto Preview")
            }
        } header: {
            SettingsSectionHeader(title: "Basic")
        }
    }
}

// MARK: - Section 2: Appearance

extension GeneralSettingsView {
    var appearanceSection: some View {
        Section {

            AppearanceThemePicker(
                selection: $appTheme,
                accentColor: appAccentColor.color
            )

            ThemeColorPicker(selection: $appAccentColor)
        } header: {
            SettingsSectionHeader(title: "Appearance")
        }
    }
}

// MARK: - Section 3: Window

extension GeneralSettingsView {
    var windowSection: some View {
        Section {
            Picker("Layout Mode", selection: $clipboardLayout) {
                ForEach(AppLayoutMode.allCases) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }

            PreviewPanelToggle()
        } header: {
            SettingsSectionHeader(title: "Window")
        }
    }
}
