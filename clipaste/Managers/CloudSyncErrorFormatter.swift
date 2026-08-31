import CloudKit
import CoreData
import Foundation
import os
import SwiftData

nonisolated enum CloudSyncErrorFormatter {
    static func message(for error: Error) -> String {
        // CKError.partialFailure 的顶层描述只有一句 "Failed to modify some records",
        // 真正的失败原因(记录过大、配额不足等)藏在 per-item 错误里,展开它。
        if let ckError = error as? CKError,
           ckError.code == .partialFailure,
           let partialErrors = ckError.partialErrorsByItemID,
           partialErrors.isEmpty == false {
            let distinctReasons = Set(partialErrors.values.map { ($0 as NSError).localizedDescription })
            let detail = distinctReasons.sorted().prefix(3).joined(separator: "；")
            return "CloudKit 部分记录同步失败（\(partialErrors.count) 条）：\(detail)"
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
}
