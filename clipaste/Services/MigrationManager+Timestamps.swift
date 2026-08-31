import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers

// MARK: - Timestamp Decoding

extension MigrationManager {
    nonisolated static var migrationTimestampLowerBound: Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? .distantPast
    }

    nonisolated static func migrationTimestampScore(
        for date: Date,
        now: Date = Date()
    ) -> TimeInterval {
        let calendar = Calendar(identifier: .gregorian)
        let futureBound = calendar.date(byAdding: .year, value: 1, to: now) ?? now

        if date >= migrationTimestampLowerBound, date <= futureBound {
            return abs(date.timeIntervalSince(now))
        }

        if date < migrationTimestampLowerBound {
            return 1_000_000_000_000 + migrationTimestampLowerBound.timeIntervalSince(date)
        }

        return 2_000_000_000_000 + date.timeIntervalSince(futureBound)
    }

    nonisolated static func resolveMostPlausibleMigrationDate(
        from candidates: [Date],
        now: Date = Date()
    ) -> Date? {
        let uniqueCandidates = candidates.reduce(into: [Date]()) { result, candidate in
            let isDuplicate = result.contains {
                abs($0.timeIntervalSinceReferenceDate - candidate.timeIntervalSinceReferenceDate) < 0.001
            }
            guard !isDuplicate else { return }
            result.append(candidate)
        }

        return uniqueCandidates.min {
            migrationTimestampScore(for: $0, now: now) < migrationTimestampScore(for: $1, now: now)
        }
    }

    nonisolated static func decodeUnixTimestamp(_ value: Any) -> Date? {
        switch value {
        case let number as NSNumber:
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return decodeUnixTimestamp(number.doubleValue)

        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            guard let numeric = Double(trimmed) else { return nil }
            return decodeUnixTimestamp(numeric)

        default:
            return nil
        }
    }

    nonisolated static func decodeUnixTimestamp(_ rawValue: Double) -> Date? {
        guard rawValue.isFinite else { return nil }

        let absoluteRawValue = abs(rawValue)
        let integerPortion = Int64(absoluteRawValue.rounded(.towardZero))
        let digitCount = String(integerPortion).count
        var candidates: [Date] = [
            Date(timeIntervalSince1970: rawValue),
            Date(timeIntervalSinceReferenceDate: rawValue),
        ]

        if (12...13).contains(digitCount) || absoluteRawValue >= 100_000_000_000 {
            candidates.append(Date(timeIntervalSince1970: rawValue / 1_000))
            candidates.append(Date(timeIntervalSinceReferenceDate: rawValue / 1_000))
        }

        if (15...16).contains(digitCount) {
            candidates.append(Date(timeIntervalSince1970: rawValue / 1_000_000))
            candidates.append(Date(timeIntervalSinceReferenceDate: rawValue / 1_000_000))
        }

        if digitCount >= 18 {
            candidates.append(Date(timeIntervalSince1970: rawValue / 1_000_000_000))
            candidates.append(Date(timeIntervalSinceReferenceDate: rawValue / 1_000_000_000))
        }

        return resolveMostPlausibleMigrationDate(from: candidates)
    }

    nonisolated static func decodeSQLiteUnixTimestamp(
        from statement: OpaquePointer,
        columnIndex: Int32
    ) -> Date? {
        guard sqlite3_column_type(statement, columnIndex) != SQLITE_NULL else {
            return nil
        }

        switch sqlite3_column_type(statement, columnIndex) {
        case SQLITE_INTEGER:
            return decodeUnixTimestamp(Double(sqlite3_column_int64(statement, columnIndex)))

        case SQLITE_FLOAT:
            return decodeUnixTimestamp(sqlite3_column_double(statement, columnIndex))

        case SQLITE_TEXT:
            guard let rawValue = sqlite3_column_text(statement, columnIndex) else { return nil }
            return decodeUnixTimestamp(String(cString: rawValue))

        default:
            return nil
        }
    }

    nonisolated static func decodeSQLiteCoreDataReferenceDate(
        from statement: OpaquePointer,
        columnIndex: Int32
    ) -> Date? {
        guard sqlite3_column_type(statement, columnIndex) != SQLITE_NULL else {
            return nil
        }

        let rawValue: Double
        switch sqlite3_column_type(statement, columnIndex) {
        case SQLITE_INTEGER:
            rawValue = Double(sqlite3_column_int64(statement, columnIndex))

        case SQLITE_FLOAT:
            rawValue = sqlite3_column_double(statement, columnIndex)

        case SQLITE_TEXT:
            guard let rawText = sqlite3_column_text(statement, columnIndex),
                  let parsedValue = Double(String(cString: rawText).trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            rawValue = parsedValue

        default:
            return nil
        }

        guard rawValue.isFinite else { return nil }
        return Date(timeIntervalSinceReferenceDate: rawValue)
    }
}
