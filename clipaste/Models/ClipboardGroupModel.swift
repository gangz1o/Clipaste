import SwiftData
import Foundation

enum ClipboardGroupIconName {
    nonisolated static func normalize(_ iconName: String?) -> String? {
        guard let trimmed = iconName?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    nonisolated static func storageValue(from iconName: String?) -> String {
        normalize(iconName) ?? ""
    }
}

// MARK: - SwiftData 持久化实体
@Model
final class ClipboardGroupModel {
    var id: String = UUID().uuidString
    var name: String = ""
    var createdAt: Date = Date()
    var systemIconName: String = ""
    var sortOrder: Int = 0

    var resolvedSystemIconName: String? {
        ClipboardGroupIconName.normalize(systemIconName)
    }

    init(id: String = UUID().uuidString, name: String, systemIconName: String? = nil, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.systemIconName = ClipboardGroupIconName.storageValue(from: systemIconName)
        self.sortOrder = sortOrder
    }
}

// MARK: - UI 传输对象（防卡顿，Sendable）
struct ClipboardGroupItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let systemIconName: String?   // icon identifier (SF Symbol name OR Assets name)
    let sortOrder: Int

    nonisolated init(id: String, name: String, systemIconName: String?, sortOrder: Int) {
        self.id = id
        self.name = name
        self.systemIconName = ClipboardGroupIconName.normalize(systemIconName)
        self.sortOrder = sortOrder
    }

    /// Resolved icon type — drives the rendering path in View layer.
    /// Custom icons are those registered in IconPickerModels' custom categories.
    @MainActor
    var iconType: IconType? {
        guard let systemIconName else { return nil }
        return IconPickerViewModel.customIconNames.contains(systemIconName) ? .custom : .system
    }
}

