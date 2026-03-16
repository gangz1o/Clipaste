import Combine
import Foundation
import SwiftUI

// MARK: - Model

enum IconType: String, Codable {
    case system  // SF Symbols — rendered with Image(systemName:)
    case custom  // Assets catalog — rendered with Image(_:) + .renderingMode(.template)
}

struct IconItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String         // e.g. "folder" or "python"
    let type: IconType       // determines rendering path
    let displayName: String  // friendly label used for search

    init(name: String, type: IconType = .system, displayName: String) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.displayName = displayName
    }
}

struct IconCategory: Identifiable {
    let id: UUID = UUID()
    let name: LocalizedStringKey
    let icons: [IconItem]
}

// MARK: - ViewModel

@MainActor
final class IconPickerViewModel: ObservableObject {
    @Published var searchQuery: String = ""

    // MARK: Static lookup – used by ClipboardGroupItem.iconType without a ViewModel instance
    nonisolated static let customIconNames: Set<String> = [
        "python", "java", "swift", "javascript", "typescript",
        "kotlin", "rust", "go", "cpp", "csharp",
        "git", "docker", "figma", "xcode", "vscode",
    ]

    // MARK: Catalogue
    let categories: [IconCategory] = [
        IconCategory(name: "Common", icons: [
            IconItem(name: "folder",                            type: .system, displayName: "Folder"),
            IconItem(name: "folder.fill",                      type: .system, displayName: "Folder Filled"),
            IconItem(name: "doc.text",                         type: .system, displayName: "Document"),
            IconItem(name: "terminal",                         type: .system, displayName: "Terminal"),
            IconItem(name: "chevron.left.forwardslash.chevron.right", type: .system, displayName: "Code"),
            IconItem(name: "paintpalette",                     type: .system, displayName: "Palette"),
            IconItem(name: "photo",                            type: .system, displayName: "Photo"),
            IconItem(name: "link",                             type: .system, displayName: "Link"),
            IconItem(name: "globe",                            type: .system, displayName: "Globe"),
            IconItem(name: "envelope",                         type: .system, displayName: "Email"),
        ]),
        IconCategory(name: "Work", icons: [
            IconItem(name: "cart",                             type: .system, displayName: "Cart"),
            IconItem(name: "creditcard",                       type: .system, displayName: "Credit Card"),
            IconItem(name: "briefcase",                        type: .system, displayName: "Briefcase"),
            IconItem(name: "lock.shield",                      type: .system, displayName: "Security"),
            IconItem(name: "key",                              type: .system, displayName: "Key"),
            IconItem(name: "star",                             type: .system, displayName: "Star"),
            IconItem(name: "heart",                            type: .system, displayName: "Heart"),
            IconItem(name: "bookmark",                         type: .system, displayName: "Bookmark"),
            IconItem(name: "flag",                             type: .system, displayName: "Flag"),
            IconItem(name: "bell",                             type: .system, displayName: "Bell"),
        ]),
        IconCategory(name: "Storage", icons: [
            IconItem(name: "tag",                              type: .system, displayName: "Tag"),
            IconItem(name: "tray",                             type: .system, displayName: "Tray"),
            IconItem(name: "archivebox",                       type: .system, displayName: "Archive"),
            IconItem(name: "shippingbox",                      type: .system, displayName: "Box"),
            IconItem(name: "books.vertical",                   type: .system, displayName: "Library"),
            IconItem(name: "externaldrive",                    type: .system, displayName: "Drive"),
            IconItem(name: "internaldrive",                    type: .system, displayName: "SSD"),
            IconItem(name: "icloud",                           type: .system, displayName: "iCloud"),
            IconItem(name: "server.rack",                      type: .system, displayName: "Server"),
            IconItem(name: "sdcard",                           type: .system, displayName: "SD Card"),
        ]),
        IconCategory(name: "Dev Languages", icons: [
            IconItem(name: "python",                           type: .custom, displayName: "Python"),
            IconItem(name: "java",                             type: .custom, displayName: "Java"),
            IconItem(name: "swift",                            type: .custom, displayName: "Swift"),
            IconItem(name: "javascript",                       type: .custom, displayName: "JavaScript"),
            IconItem(name: "typescript",                       type: .custom, displayName: "TypeScript"),
            IconItem(name: "kotlin",                           type: .custom, displayName: "Kotlin"),
            IconItem(name: "rust",                             type: .custom, displayName: "Rust"),
            IconItem(name: "go",                               type: .custom, displayName: "Go"),
            IconItem(name: "cpp",                              type: .custom, displayName: "C++"),
            IconItem(name: "csharp",                           type: .custom, displayName: "C#"),
        ]),
        IconCategory(name: "Dev Tools", icons: [
            IconItem(name: "git",                              type: .custom, displayName: "Git"),
            IconItem(name: "docker",                           type: .custom, displayName: "Docker"),
            IconItem(name: "figma",                            type: .custom, displayName: "Figma"),
            IconItem(name: "xcode",                            type: .custom, displayName: "Xcode"),
            IconItem(name: "vscode",                           type: .custom, displayName: "VS Code"),
        ]),
    ]

    // MARK: Search

    /// Flat list of matching icons when a search query is active.
    var searchResults: [IconItem] {
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return categories
            .flatMap(\.icons)
            .filter { $0.displayName.lowercased().contains(q) || $0.name.lowercased().contains(q) }
    }

    var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }
}
