import SwiftUI


struct AISettingsToggleRow: View {
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Configuration Row

struct AIConfigurationRow: View {
    let config: AIConfiguration
    let isActive: Bool
    let onSetActive: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        HStack(spacing: 12) {
            // Active indicator
            Button(action: onSetActive) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? appAccentColor.color : Color.secondary)
                    .font(.system(size: 16))
                    .animation(.easeInOut(duration: 0.15), value: isActive)
            }
            .buttonStyle(.plain)
            .help(LocalizedStringKey("Set as Active"))

            AIProviderIconView(configuration: config, size: 18)
                .foregroundStyle(appAccentColor.color)
                .frame(width: 18)

            // Configuration info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.displayTitle)
                        .fontWeight(.medium)
                    if isActive {
                        Text(LocalizedStringKey("Active"))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appAccentColor.color.opacity(0.15))
                            .foregroundStyle(appAccentColor.color)
                            .clipShape(Capsule())
                    }
                }
                Text("\(config.providerType.localizedName) · \(config.model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appAccentColor.color)
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("Edit Configuration"))

            // Delete button
            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("Delete Configuration"))
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            LocalizedStringKey("Delete AI Configuration Confirmation Title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringKey("Delete Configuration"), role: .destructive, action: onDelete)
            Button(LocalizedStringKey("Cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("Delete AI Configuration Confirmation Message"))
        }
    }
}

// MARK: - Skill Row

struct AISkillRow: View {
    let skill: AISkill
    let configurationTitle: String
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @AppStorage("appAccentColor") private var appAccentColor: AppAccentColor = .defaultValue
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle(!skill.isEnabled)
            } label: {
                Image(systemName: skill.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(skill.isEnabled ? appAccentColor.color : Color.secondary)
                    .font(.system(size: 16))
                    .animation(.easeInOut(duration: 0.15), value: skill.isEnabled)
            }
            .buttonStyle(.plain)
            .help(LocalizedStringKey("Enable Skill"))

            Image(systemName: skill.outputMode.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(skill.isEnabled ? appAccentColor.color : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.displayTitle)
                    .fontWeight(.medium)
                    .foregroundStyle(skill.isEnabled ? .primary : .secondary)

                Text("\(contentSummary) · \(configurationTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appAccentColor.color)
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("Edit Skill"))

            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("Delete Skill"))
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            LocalizedStringKey("Delete AI Skill Confirmation Title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringKey("Delete Skill"), role: .destructive, action: onDelete)
            Button(LocalizedStringKey("Cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("Delete AI Skill Confirmation Message"))
        }
    }

    private var contentSummary: String {
        let orderedTypes: [ClipboardContentType] = [.text, .code, .link, .image, .fileURL, .color]
        let titles = orderedTypes
            .filter { skill.supportedContentTypes.contains($0) }
            .map { contentTypeTitle($0) }

        return titles.isEmpty ? String(localized: "No Supported Content") : titles.joined(separator: ", ")
    }

    private func contentTypeTitle(_ contentType: ClipboardContentType) -> String {
        switch contentType {
        case .text: return String(localized: "Text Content")
        case .code: return String(localized: "Code Content")
        case .link: return String(localized: "Link Content")
        case .image: return String(localized: "Image Content")
        case .fileURL: return String(localized: "File Content")
        case .color: return String(localized: "Color Content")
        }
    }
}

#Preview {
    AISettingsView()
}
