import Foundation

struct ClipboardListScrollRequest: Equatable {
    let id: UUID
    let animated: Bool
    let generation: UInt
}
