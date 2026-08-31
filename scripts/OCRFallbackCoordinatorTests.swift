import Foundation

private enum ProbeError: Error {
    case failed
}

private actor Probe {
    private(set) var primaryStarted = false
    private(set) var fallbackCount = 0

    func markPrimaryStarted() {
        primaryStarted = true
    }

    func markFallback() {
        fallbackCount += 1
    }
}

@main
enum OCRFallbackCoordinatorTests {
    static func main() async {
        await testOrdinaryFailureUsesFallback()
        await testCancellationSkipsFallback()
        print("OCRFallbackCoordinatorTests passed")
    }

    @MainActor
    private static func testOrdinaryFailureUsesFallback() async {
        let probe = Probe()
        let result: String? = await OCRFallbackCoordinator.run(
            primary: { throw ProbeError.failed },
            fallback: { _ in
                await probe.markFallback()
                return "fallback"
            }
        )

        let fallbackCount = await probe.fallbackCount
        precondition(result == "fallback")
        precondition(fallbackCount == 1)
    }

    @MainActor
    private static func testCancellationSkipsFallback() async {
        let probe = Probe()
        let task = Task { @MainActor in
            await OCRFallbackCoordinator.run(
                primary: {
                    await probe.markPrimaryStarted()
                    while Task.isCancelled == false {
                        await Task.yield()
                    }
                    throw ProbeError.failed
                },
                fallback: { _ in
                    await probe.markFallback()
                    return "unexpected"
                }
            ) as String?
        }

        while await probe.primaryStarted == false {
            await Task.yield()
        }
        task.cancel()

        let result = await task.value
        let fallbackCount = await probe.fallbackCount
        precondition(result == nil)
        precondition(fallbackCount == 0)
    }
}
