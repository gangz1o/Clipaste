import Foundation

struct AIConfiguration: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var providerType: AIProviderType
    var apiKey: String
    var endpoint: String
    var model: String

    init(
        id: UUID = UUID(),
        name: String = "",
        providerType: AIProviderType = .openai,
        apiKey: String = "",
        endpoint: String = "",
        model: String = ""
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.apiKey = apiKey
        self.endpoint = endpoint.isEmpty ? providerType.defaultEndpoint : endpoint
        self.model = model.isEmpty ? (providerType.defaultModels.first ?? "") : model
    }

    /// A short display label shown in the clipboard panel picker.
    var displayTitle: String {
        name.isEmpty ? providerType.rawValue : name
    }
}
