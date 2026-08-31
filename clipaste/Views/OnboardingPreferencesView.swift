import AppKit
import KeyboardShortcuts
import SwiftUI


struct PreferencesView: View {
    @Binding var launchAtLogin: Bool
    @Binding var historyLimit: HistoryLimit

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Set Preferences")
                        .font(.system(size: 28, weight: .bold))

                    Text("These options can be changed anytime in Settings.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $launchAtLogin) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Launch at Login")
                                    .font(.system(size: 15, weight: .semibold))

                                Text("Runs automatically after login and appears in the menu bar, without interrupting your workflow.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(18)

                    Divider()
                        .overlay(Color.white.opacity(0.4))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("History Capacity")
                            .font(.system(size: 15, weight: .semibold))

                        Picker("History Capacity", selection: $historyLimit) {
                            ForEach(HistoryLimit.allCases) { limit in
                                Text(limit.localizedTitle).tag(limit)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.4))
                )
                .padding(.horizontal, 36)
            }

            Spacer()
        }
    }
}

#Preview {
    OnboardingView()
}
