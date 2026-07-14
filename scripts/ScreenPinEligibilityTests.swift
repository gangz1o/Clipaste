import Foundation

@main
enum ScreenPinEligibilityTests {
    static func main() {
        precondition(makeItem(contentType: .image).isScreenPinEligible)
        precondition(makeItem(contentType: .fileURL, fileURL: "/tmp/example.png").isScreenPinEligible)
        precondition(makeItem(contentType: .fileURL, fileURL: "/tmp/example.txt").isScreenPinEligible == false)
        precondition(makeItem(contentType: .text).isScreenPinEligible == false)
        precondition(makeItem(contentType: .link).isScreenPinEligible == false)
        precondition(makeItem(contentType: .code).isScreenPinEligible == false)
        precondition(makeItem(contentType: .color).isScreenPinEligible == false)

        print("ScreenPinEligibilityTests passed")
    }

    private static func makeItem(
        contentType: ClipboardContentType,
        fileURL: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            contentType: contentType,
            contentHash: UUID().uuidString,
            textPreview: "",
            appName: "Tests",
            appIconName: "app",
            fileURL: fileURL
        )
    }
}
