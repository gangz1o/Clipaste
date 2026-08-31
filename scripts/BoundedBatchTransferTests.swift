import Foundation

private actor TransferProbe {
    private let source: [Int]
    private var consumed: [Int] = []
    private var maximumLoadedBatchSize = 0
    private var maximumConsumedBatchSize = 0

    init(source: [Int]) {
        self.source = source
    }

    func load(offset: Int, limit: Int) -> [Int] {
        guard offset < source.count else { return [] }
        // Simulate a byte-budgeted loader that may return a short, non-final
        // batch. The transfer must continue until the loader returns empty.
        let end = min(source.count, offset + min(limit, 37))
        let batch = Array(source[offset..<end])
        maximumLoadedBatchSize = max(maximumLoadedBatchSize, batch.count)
        return batch
    }

    func consume(_ batch: [Int]) {
        maximumConsumedBatchSize = max(maximumConsumedBatchSize, batch.count)
        consumed.append(contentsOf: batch)
    }

    func result() -> (items: [Int], maxLoaded: Int, maxConsumed: Int) {
        (consumed, maximumLoadedBatchSize, maximumConsumedBatchSize)
    }
}

@main
enum BoundedBatchTransferTests {
    static func main() async throws {
        let expected = Array(0..<10_003)
        let probe = TransferProbe(source: expected)
        let count = try await BoundedBatchTransfer.run(
            batchSize: 128,
            loadBatch: { offset, limit in
                await probe.load(offset: offset, limit: limit)
            },
            consumeBatch: { batch in
                await probe.consume(batch)
            }
        )

        let result = await probe.result()
        precondition(count == expected.count)
        precondition(result.items == expected)
        precondition(result.maxLoaded <= 128)
        precondition(result.maxConsumed <= 128)
        await testOversizedBatchFailsWithoutCrashing()
        print("BoundedBatchTransferTests passed")
    }

    private static func testOversizedBatchFailsWithoutCrashing() async {
        do {
            _ = try await BoundedBatchTransfer.run(
                batchSize: 1,
                loadBatch: { _, _ in [1, 2] },
                consumeBatch: { _ in }
            )
            preconditionFailure("Expected an oversized batch error")
        } catch let error as BoundedBatchTransferError {
            precondition(error == .batchLimitExceeded(limit: 1, actual: 2))
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }
}
