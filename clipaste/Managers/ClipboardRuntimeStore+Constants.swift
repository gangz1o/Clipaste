import CloudKit
import CoreData
import Foundation
import os
import SwiftData

extension ClipboardRuntimeStore {
    enum Keys {
        static let syncEnabled = "enable_icloud_sync"
        static let lastSyncDate = "last_sync_date"
        static let textClassificationRepairVersion = "clipboard_text_classification_repair_version"
        static let appIconColorRepairVersion = "clipboard_app_icon_color_repair_version"
        static let appIconDataRepairVersion = "clipboard_app_icon_data_repair_version"
        static let duplicateRepairVersion = "clipboard_duplicate_repair_version"
        static let oversizedTextRepairVersion = "clipboard_oversized_text_repair_version"
        static let favoriteRecoveryVersion = "clipboard_favorite_cloud_recovery_version"
    }

    enum FavoriteRecovery {
        static let currentVersion = 1
    }

    enum DedupThrottle {
        // Dedup is O(n) over the full record table. Only run it occasionally
        // after CloudKit deliveries — most CloudKit events do not actually
        // introduce duplicates, and our inline upsert path already handles
        // ordinary capture-time duplicates.
        static let minimumInterval: TimeInterval = 10 * 60
        // Version bumps force a one-shot dedup on next startup.
        static let currentVersion = 1
    }
}
