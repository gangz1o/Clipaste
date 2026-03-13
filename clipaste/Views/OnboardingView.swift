import AppKit
import KeyboardShortcuts
import SwiftUI

struct OnboardingView: View {
    @StateObject var viewModel = OnboardingViewModel()

    private var isLastStep: Bool {
        viewModel.currentStep == .preferences
    }

    private var canContinue: Bool {
        viewModel.currentStep != .permissions || viewModel.hasAccessibilityPermission
    }

    var body: some View {
        ZStack {
            backgroundView

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                TabView(selection: $viewModel.currentStep) {
                    ShortcutView()
                        .tag(OnboardingStep.welcomeAndShortcut)

                    PermissionView(
                        hasAccessibilityPermission: viewModel.hasAccessibilityPermission,
                        openSystemSettings: viewModel.openSystemSettingsForAccessibility
                    )
                    .tag(OnboardingStep.permissions)

                    PreferencesView(
                        launchAtLogin: $viewModel.launchAtLogin,
                        historyLimit: $viewModel.historyLimit
                    )
                    .tag(OnboardingStep.preferences)
                }
                .animation(.easeInOut, value: viewModel.currentStep)

                Divider()
                    .overlay(Color.white.opacity(0.35))

                HStack {
                    Spacer()

                    Button(action: viewModel.nextStep) {
                        Text(isLastStep ? "Done" : "Continue")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(minWidth: 96)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canContinue)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(.ultraThinMaterial)
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            if viewModel.currentStep == .permissions {
                viewModel.checkPermission()
            }
        }
        .onChange(of: viewModel.currentStep) { _, newStep in
            if newStep == .permissions {
                viewModel.checkPermission()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.checkPermission()
        }
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.98, blue: 0.97),
                    Color(red: 0.92, green: 0.95, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.27, green: 0.68, blue: 0.59).opacity(0.22))
                .frame(width: 240, height: 240)
                .blur(radius: 18)
                .offset(x: 170, y: -150)

            Circle()
                .fill(Color(red: 0.99, green: 0.73, blue: 0.37).opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 24)
                .offset(x: -180, y: 155)
        }
        .overlay(.ultraThinMaterial.opacity(0.5))
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule(style: .continuous)
                    .fill(step == viewModel.currentStep ? Color.primary : Color.white.opacity(0.42))
                    .frame(width: step == viewModel.currentStep ? 28 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.22), value: viewModel.currentStep)
            }

            Spacer()

            Text(stepCaption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var stepCaption: String {
        let total = OnboardingStep.allCases.count
        let current = (OnboardingStep.allCases.firstIndex(of: viewModel.currentStep) ?? 0) + 1
        return String(format: String(localized: "Step %lld of %lld"), current, total)
    }
}

private struct ShortcutView: View {
    private var appIcon: NSImage {
        NSApplication.shared.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 10)

            VStack(spacing: 8) {
                Text("Welcome to Clipaste")
                    .font(.system(size: 28, weight: .bold))

                Text("Set your personal wake shortcut")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Global Shortcut")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Show Clipboard History")
                        .font(.system(size: 15, weight: .medium))

                    Spacer()

                    KeyboardShortcuts.Recorder(for: .toggleClipboardPanel)
                }
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4))
            )
            .padding(.horizontal, 36)

            Text("You can change this later in Settings.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.bottom, 8)
    }
}

private struct PermissionView: View {
    let hasAccessibilityPermission: Bool
    let openSystemSettings: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: hasAccessibilityPermission ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(hasAccessibilityPermission ? Color.green : Color.red)

            VStack(spacing: 8) {
                Text("Grant Paste Superpower")
                    .font(.system(size: 28, weight: .bold))

                Text("Clipaste needs Accessibility permission to safely simulate paste in any app.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Label(
                hasAccessibilityPermission
                    ? "Permission Granted — Continue"
                    : "Permission Required — Complete System Authorization",
                systemImage: hasAccessibilityPermission ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(hasAccessibilityPermission ? Color.green : Color.red)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))

            Button(action: openSystemSettings) {
                Text("Open System Settings to Authorize")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 72)

            Text("Return to Clipaste after granting permission; status refreshes automatically.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.bottom, 8)
    }
}

private struct PreferencesView: View {
    @Binding var launchAtLogin: Bool
    @Binding var historyLimit: HistoryLimit

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 8) {
                Text("Set Up Your Preferences")
                    .font(.system(size: 28, weight: .bold))

                Text("These options can be changed in Settings at any time.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $launchAtLogin) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Launch at Login")
                                .font(.system(size: 15, weight: .semibold))

                            Text("Starts in the menu bar after login, without interrupting your workflow.")
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
                            Text(limit.displayName).tag(limit)
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

            Spacer()
        }
        .padding(.bottom, 8)
    }
}

#Preview {
    OnboardingView()
}
