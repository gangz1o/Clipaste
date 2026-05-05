import Foundation

enum AISkillOutputMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case copyToClipboard
    case createClipboardItem
    case replaceCurrentItem
    case pasteToActiveApp
    case openConversation

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .copyToClipboard: return "doc.on.clipboard"
        case .createClipboardItem: return "plus.square.on.square"
        case .replaceCurrentItem: return "arrow.triangle.2.circlepath.doc.on.clipboard"
        case .pasteToActiveApp: return "arrow.turn.down.right"
        case .openConversation: return "bubble.left.and.bubble.right"
        }
    }
}

struct AISkill: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var promptTemplate: String
    var supportedContentTypes: Set<ClipboardContentType>
    var configurationID: UUID?
    var outputMode: AISkillOutputMode
    var opensConversation: Bool
    var sortOrder: Int
    var presetIdentifier: String?

    init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        promptTemplate: String = "",
        supportedContentTypes: Set<ClipboardContentType> = [.text, .link, .code],
        configurationID: UUID? = nil,
        outputMode: AISkillOutputMode = .copyToClipboard,
        opensConversation: Bool = false,
        sortOrder: Int = 0,
        presetIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.promptTemplate = promptTemplate
        self.supportedContentTypes = supportedContentTypes
        self.configurationID = configurationID
        self.outputMode = outputMode
        self.opensConversation = opensConversation
        self.sortOrder = sortOrder
        self.presetIdentifier = presetIdentifier
    }

    var displayTitle: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func supports(_ item: ClipboardItem) -> Bool {
        isEnabled && supportedContentTypes.contains(item.contentType)
    }
}
