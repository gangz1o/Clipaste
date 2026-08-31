import AppKit
import KeyboardShortcuts
import SwiftUI


struct ShortcutView: View {
    @StateObject private var shortcutRecorderViewModel = ShortcutRecorderRowViewModel(name: .toggleClipboardPanel)

    private var appIcon: NSImage {
        NSApplication.shared.applicationIconImage
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 20) {
                // App icon
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 10)

                // Title / Subtitle
                VStack(spacing: 8) {
                    Text("Welcome to Clipaste")
                        .font(.system(size: 28, weight: .bold))

                    Text("Set Up Your Activation Shortcut")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Shortcut recorder panel
                VStack(alignment: .leading, spacing: 12) {
                    Text("Global Shortcut")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Open Clipboard History")
                            .font(.system(size: 15, weight: .medium))

                        Spacer()

                        LocalizedShortcutRecorder(viewModel: shortcutRecorderViewModel)
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.4))
                )
                .padding(.horizontal, 36)

                Text("You can change this later in Settings.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }
}

// MARK: - Step 2: Permissions
