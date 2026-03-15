import SwiftData
import Foundation

// MARK: - SwiftData 持久化实体
@Model
final class ClipboardGroupModel {
    var id: String = UUID().uuidString
    var name: String = ""
    var createdAt: Date = Date()
    var systemIconName: String = "folder"
    var sortOrder: Int = 0

    init(id: String = UUID().uuidString, name: String, systemIconName: String = "folder", sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.systemIconName = systemIconName
        self.sortOrder = sortOrder
    }
}

// MARK: - UI 传输对象（防卡顿，Sendable）
struct ClipboardGroupItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let systemIconName: String
    let sortOrder: Int
}
