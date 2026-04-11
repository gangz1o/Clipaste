import Foundation

enum AppMetadata {
    nonisolated
    static var displayName: String {
        if let displayName = trimmedValue(for: "CFBundleDisplayName") {
            return displayName 
        }

        if let bundleName = trimmedValue(for: "CFBundleName") {
            return bundleName
        }

        return "Clipaste"
    }

    nonisolated
    static var displayVersion: String {
        normalizedVersion(from: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    nonisolated
    static func normalizedVersion(from rawValue: String?) -> String {
        guard let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty else {
            return "-"
        }

        let sanitizedValue: String
        if let firstCharacter = trimmedValue.first,
           firstCharacter == "v" || firstCharacter == "V" {
            sanitizedValue = String(trimmedValue.dropFirst())
        } else {
            sanitizedValue = trimmedValue
        }

        let versionComponents = sanitizedValue.split(separator: ".", omittingEmptySubsequences: false)
        guard !versionComponents.isEmpty,
              versionComponents.allSatisfy({ component in
                  !component.isEmpty && component.allSatisfy(\.isNumber)
              }) else {
            return sanitizedValue
        }

        if versionComponents.count >= 3 {
            return versionComponents.map(String.init).joined(separator: ".")
        }

        let paddedComponents = versionComponents.map(String.init) + Array(
            repeating: "0",
            count: 3 - versionComponents.count
        )
        return paddedComponents.joined(separator: ".")
    }

    nonisolated
    private static func trimmedValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
