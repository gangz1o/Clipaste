import CloudKit
import CoreData
import Foundation
import os
import SwiftData

nonisolated enum CloudSyncErrorFormatter {
    static func message(for error: Error) -> String {
        // CKError.partialFailure 的顶层描述只有一句 "Failed to modify some records",
        // 真正的失败原因(记录过大、配额不足、schema 缺字段等)藏在 per-item 错误里,展开它。
        // Core Data 可能把它包在 NSUnderlyingErrorKey / NSDetailedErrors 里,逐层往下找。
        if let partialErrors = partialFailureItemErrors(in: error as NSError, depth: 0) {
            let distinctReasons = Set(partialErrors.map { ($0 as NSError).localizedDescription })
            let detail = distinctReasons.sorted().prefix(3).joined(separator: "；")
            let hint = distinctReasons.contains { $0.localizedCaseInsensitiveContains("Cannot create or modify field") }
                ? "iCloud 服务端尚未部署新版本的数据字段，需开发者部署 CloudKit schema。"
                : ""
            return "\(hint)CloudKit 部分记录同步失败（\(partialErrors.count) 条）：\(detail)"
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           description.isEmpty == false {
            return description
        }

        let nsError = error as NSError
        var segments = [nsError.localizedDescription]

        if let failureReason = nsError.localizedFailureReason,
           failureReason.isEmpty == false,
           segments.contains(failureReason) == false {
            segments.append(failureReason)
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            let underlyingMessage = "底层错误：\(underlyingError.localizedDescription)"
            if segments.contains(underlyingMessage) == false {
                segments.append(underlyingMessage)
            }
        }

        if let detailedErrors = nsError.userInfo["NSDetailedErrors"] as? [NSError],
           detailedErrors.isEmpty == false {
            let detailMessage = detailedErrors
                .map { $0.localizedDescription }
                .filter { $0.isEmpty == false }
                .joined(separator: "；")

            if detailMessage.isEmpty == false {
                segments.append("详细信息：\(detailMessage)")
            }
        }

        return segments.joined(separator: " ")
    }

    private static func partialFailureItemErrors(in error: NSError, depth: Int) -> [Error]? {
        if error.domain == CKError.errorDomain,
           error.code == CKError.Code.partialFailure.rawValue,
           let partialErrors = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
           partialErrors.isEmpty == false {
            return Array(partialErrors.values)
        }

        guard depth < 4 else { return nil }
        var nestedErrors = (error.userInfo["NSDetailedErrors"] as? [NSError]) ?? []
        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            nestedErrors.insert(underlyingError, at: 0)
        }
        for nestedError in nestedErrors {
            if let partialErrors = partialFailureItemErrors(in: nestedError, depth: depth + 1) {
                return partialErrors
            }
        }
        return nil
    }
}
