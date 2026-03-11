import SwiftData
import Foundation

// MARK: - SwiftData 持久化实体
@Model
final class ClipboardGroupModel {
    @Attribute(.unique) var id: String
    var name: String
    var createdAt: Date
    var systemIconName: String

    init(id: String = UUID().uuidString, name: String, systemIconName: String = "folder") {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.systemIconName = systemIconName
    }
}

// MARK: - UI 传输对象（防卡顿，Sendable）
struct ClipboardGroupItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let systemIconName: String
}
