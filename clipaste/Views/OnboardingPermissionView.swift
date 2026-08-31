import AppKit
import KeyboardShortcuts
import SwiftUI


struct PermissionView: View {
    let hasAccessibilityPermission: Bool
    let openSystemSettings: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: hasAccessibilityPermission ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(hasAccessibilityPermission ? Color.green : Color.red)

                VStack(spacing: 8) {
                    Text("Grant Paste Superpower")
                        .font(.system(size: 28, weight: .bold))

                    Text("Clipaste needs Accessibility permission to securely simulate paste in any app.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                Label(
                    title: {
                        if hasAccessibilityPermission {
                            Text("Authorized — Continue")
                        } else {
                            Text("Authorization Required — Enable in System Settings")
                        }
                    },
                    icon: {
                        Image(systemName: hasAccessibilityPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                    }
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 72)

                Text("Return to Clipaste after authorizing; status refreshes automatically.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Spacer()
        }
    }
}

// MARK: - Step 3: Preferences
