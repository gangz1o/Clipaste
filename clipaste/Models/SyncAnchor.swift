import Foundation
import SwiftData

@Model
final class SyncAnchor {
    var id: String = "global"
    var updatedAt: Date = Date()
    var platform: String = ClipboardSourceMetadata.currentPlatform
    var deviceName: String = ClipboardSourceMetadata.currentDeviceName ?? ""
    var generation: UUID = UUID()

    init(
        id: String = "global",
        updatedAt: Date = Date(),
        platform: String = ClipboardSourceMetadata.currentPlatform,
        deviceName: String = ClipboardSourceMetadata.currentDeviceName ?? "",
        generation: UUID = UUID()
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.platform = platform
        self.deviceName = deviceName
        self.generation = generation
    }
}
