import SwiftUI

struct ClipboardAIActionMenu<MenuLabel: View>: View {
    let item: ClipboardItem
    var viewModel: ClipboardViewModel
    @ViewBuilder var label: () -> MenuLabel

    var body: some View {
        Menu {
            menuContent
        } label: {
            label()
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        let aiSettings = viewModel.aiSettingsViewModel

        if aiSettings.isAIEnabled == false {
            EmptyView()
        } else if aiSettings.configurations.isEmpty {
            Text("No AI Configurations")
                .foregroundStyle(.secondary)

            Button {
                NotificationCenter.default.post(name: .openSettingsIntent, object: nil)
            } label: {
                Label("Open AI Settings…", systemImage: "gearshape")
            }
        } else {
            let skills = aiSettings.availableSkills(for: item)

            if skills.isEmpty {
                Text("No AI Skills Available")
                    .foregroundStyle(.secondary)

                Button {
                    NotificationCenter.default.post(name: .openSettingsIntent, object: nil)
                } label: {
                    Label("Add AI Skill…", systemImage: "plus")
                }
            } else {
                let lastSkill = aiSettings.lastUsedAvailableSkill(for: item)

                if let lastSkill {
                    Button {
                        viewModel.runAISkill(lastSkill, for: item)
                    } label: {
                        Label("Use Again: \(lastSkill.displayTitle)", systemImage: "clock.arrow.circlepath")
                    }

                    Divider()
                }

                ForEach(skills) { skill in
                    Button {
                        viewModel.runAISkill(skill, for: item)
                    } label: {
                        Label(skill.displayTitle, systemImage: skill.outputMode.systemImage)
                    }
                }

                Divider()

                Button {
                    NotificationCenter.default.post(name: .openSettingsIntent, object: nil)
                } label: {
                    Label("Manage AI Skills…", systemImage: "slider.horizontal.3")
                }
            }
        }
    }
}
