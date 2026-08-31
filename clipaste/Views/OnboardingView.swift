import AppKit
import KeyboardShortcuts
import SwiftUI

struct OnboardingView: View {
    @StateObject var viewModel = OnboardingViewModel()
    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue

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
                // ── Page content ──
                
                // Step Indicator Dots in Content Area
                stepIndicatorDots
                
                Group {
                    switch viewModel.currentStep {
                    case .welcomeAndShortcut:
                        ShortcutView()
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity.combined(with: .move(edge: .leading))))
                    case .permissions:
                        PermissionView(
                            hasAccessibilityPermission: viewModel.hasAccessibilityPermission,
                            openSystemSettings: viewModel.openSystemSettingsForAccessibility
                        )
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity.combined(with: .move(edge: .leading))))
                    case .preferences:
                        PreferencesView(
                            launchAtLogin: $viewModel.launchAtLogin,
                            historyLimit: $viewModel.historyLimit
                        )
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity.combined(with: .move(edge: .leading))))
                    }
                }
                .id(viewModel.currentStep)
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

                // ── Bottom bar ──
                bottomNavigationBar
            }
            .padding(30)
        }
        .frame(width: 520, height: 460)
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

    // MARK: - Background

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

    // MARK: - Step Indicator
    
    private var stepIndicatorDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step == viewModel.currentStep ? appAccentColor.color : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.22), value: viewModel.currentStep)
            }
        }
        .padding(.bottom, 24)
        .padding(.top, 16)
    }

    // MARK: - Bottom Navigation Bar

    private var bottomNavigationBar: some View {
        HStack {
            Spacer()

            // Primary Action Button
            Button(action: viewModel.nextStep) {
                Text(isLastStep ? "Done" : "Next")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minWidth: 96)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(appAccentColor.color)
            .controlSize(.large)
            .disabled(!canContinue)
        }
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}
