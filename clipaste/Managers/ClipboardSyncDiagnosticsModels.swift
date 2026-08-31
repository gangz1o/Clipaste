import CloudKit
import CoreData
import Foundation
import os
import SwiftData

enum ClipboardSyncDiagnosticLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct ClipboardSyncDiagnosticMessage: Sendable {
    enum Argument: Sendable {
        case string(String)
        case route(String)
        case syncState(Bool)
        case bool(Bool)
        case count(Int)

        func localized(locale: Locale) -> String {
            switch self {
            case .string(let value):
                return value
            case .route(let route):
                let key = route == "cloud" ? "iCloud" : "Local"
                return Self.localized(key, locale: locale)
            case .syncState(let isEnabled):
                let key = isEnabled ? "On" : "Off"
                return Self.localized(key, locale: locale)
            case .bool(let value):
                let key = value ? "Yes" : "No"
                return Self.localized(key, locale: locale)
            case .count(let value):
                let formatter = NumberFormatter()
                formatter.locale = locale
                formatter.numberStyle = .decimal
                return formatter.string(from: NSNumber(value: value)) ?? String(value)
            }
        }

        private static func localized(_ key: String, locale: Locale) -> String {
            let resource = LocalizedStringResource(String.LocalizationValue(key), locale: locale, bundle: .main)
            return String(localized: resource)
        }
    }

    let key: String
    let arguments: [Argument]

    init(_ key: String, arguments: [Argument] = []) {
        self.key = key
        self.arguments = arguments
    }

    func localized(locale: Locale) -> String {
        let resource = LocalizedStringResource(String.LocalizationValue(key), locale: locale, bundle: .main)
        let template = String(localized: resource)
        guard arguments.isEmpty == false else { return template }

        let localizedArguments = arguments.map { $0.localized(locale: locale) }
        return String(format: template, locale: locale, arguments: localizedArguments)
    }
}

struct ClipboardSyncDiagnosticEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: ClipboardSyncDiagnosticLevel
    let message: ClipboardSyncDiagnosticMessage

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: ClipboardSyncDiagnosticLevel,
        message: ClipboardSyncDiagnosticMessage
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }

    func localizedMessage(locale: Locale) -> String {
        message.localized(locale: locale)
    }
}

struct ClipboardSyncDiagnosticsSnapshot: Sendable {
    let activeRoute: String
    let preferredSyncEnabled: Bool
    let currentSyncEnabled: Bool
    let pendingSyncEnabled: Bool?
    let isSyncing: Bool
    let cloudKitContainerIdentifier: String
    let cloudKitEnvironment: String
    let cloudKitAccountRecordName: String?
    let cloudStoreRecordCount: Int?
    let cloudStoreGroupCount: Int?
    let cloudServerRecordCount: Int?
    let cloudServerGroupCount: Int?
    let cloudServerError: String?
    let latestRecordFingerprints: [String]
    let localRuntimeReady: Bool
    let cloudRuntimeReady: Bool
    let localStorePath: String
    let cloudStorePath: String
    let runtimeGeneration: String
    let lastSyncDate: Date?
    let lastError: String?
}
