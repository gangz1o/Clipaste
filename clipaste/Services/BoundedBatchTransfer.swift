import Foundation

enum BoundedBatchTransferError: Error, Equatable {
    case batchLimitExceeded(limit: Int, actual: Int)
}

enum BoundedBatchTransfer {
    nonisolated static func run<Element: Sendable>(
        batchSize: Int,
        loadBatch: @Sendable (Int, Int) async throws -> [Element],
        consumeBatch: @Sendable ([Element]) async throws -> Void
    ) async throws -> Int {
        guard batchSize > 0 else { return 0 }

        var offset = 0
        var transferredCount = 0
        while true {
            try Task.checkCancellation()
            let batch = try await loadBatch(offset, batchSize)
            guard batch.isEmpty == false else { break }
            guard batch.count <= batchSize else {
                throw BoundedBatchTransferError.batchLimitExceeded(
                    limit: batchSize,
                    actual: batch.count
                )
            }

            try await consumeBatch(batch)
            transferredCount += batch.count
            offset += batch.count
            await Task.yield()
        }
        return transferredCount
    }
}
