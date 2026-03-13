import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Auto-Paste to Active App on Double-Click", isOn: $viewModel.autoPasteToActiveApp)
                    .toggleStyle(.switch)

                if viewModel.autoPasteToActiveApp {
                    Button("Open Accessibility Settings…") {
                        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
                            return
                        }

                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                }
            } header: {
                Text("Paste")
            } footer: {
                Text("When disabled, double-clicking an item only copies it to the clipboard without sending the paste shortcut.")
            }

            Section {
                Toggle("Move Item to Top After Pasting", isOn: $viewModel.moveToTopAfterPaste)
                    .toggleStyle(.switch)
            } header: {
                Text("Sort & Behavior")
            } footer: {
                Text("Useful when you repeatedly paste the same content.")
            }

            Section {
                Picker("Default Text Format", selection: $viewModel.pasteTextFormat) {
                    ForEach(PasteTextFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Text Format")
            } footer: {
                Text("Hold Option and double-click to temporarily reverse the current text format setting.")
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, minHeight: 320, alignment: .top)
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(SettingsViewModel())
}
