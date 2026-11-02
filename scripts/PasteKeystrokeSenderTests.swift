import CoreGraphics
import Foundation

@main
enum PasteKeystrokeSenderTests {
    @MainActor
    static func main() async {
        await testRemoteAndLocalShortcuts()
        await testWaitsForFocusAndModifierRelease()
        await testReadinessTimeouts()
        await testCancellationReleasesKeys()
        await testFocusLossBeforeV()
        await testAlreadyCancelledTask()
        print("PasteKeystrokeSenderTests passed")
    }

    @MainActor
    private static func testRemoteAndLocalShortcuts() async {
        for bundleID in ["com.microsoft.rdc.macos", "com.apple.TextEdit", "com.microsoft.rdc.macos.unrelated", nil] {
            var events: [CGEvent] = []
            let sent = await PasteKeystrokeSender.send(
                bundleIdentifier: bundleID,
                isTargetActive: { true },
                currentModifiers: { [] },
                postEvent: { events.append($0) },
                sleep: { _ in }
            )
            precondition(sent)
            // Model a remote client that tracks modifiers only through flagsChanged events.
            // The old V-only implementation would arrive here with no modifier held.
            let expectedKey: Int64 = bundleID == "com.microsoft.rdc.macos" ? 0x3B : 0x37
            assertBalancedShortcut(events, expectedModifierKey: expectedKey)
        }
    }

    @MainActor
    private static func testWaitsForFocusAndModifierRelease() async {
        for heldModifier: CGEventFlags in [.maskCommand, .maskAlternate, .maskShift, .maskControl, .maskSecondaryFn] {
            var ticks = 0
            var events: [CGEvent] = []
            let sent = await PasteKeystrokeSender.send(
                bundleIdentifier: "com.microsoft.rdc.macos",
                isTargetActive: { ticks >= 2 },
                currentModifiers: { ticks >= 4 ? [] : heldModifier },
                postEvent: {
                    precondition(ticks >= 4, "Never send while the triggering shortcut is still held")
                    events.append($0)
                },
                sleep: { _ in ticks += 1 }
            )
            precondition(sent)
            assertBalancedShortcut(events, expectedModifierKey: 0x3B)
        }
        let sentWithCapsLock = await PasteKeystrokeSender.send(
            bundleIdentifier: nil,
            isTargetActive: { true },
            currentModifiers: { .maskAlphaShift },
            postEvent: { _ in },
            sleep: { _ in }
        )
        precondition(sentWithCapsLock, "Caps Lock must not prevent pasting")
    }

    @MainActor
    private static func testReadinessTimeouts() async {
        for targetActive in [false, true] {
            var sleeps = 0
            let sent = await PasteKeystrokeSender.send(
                bundleIdentifier: "com.microsoft.rdc.macos",
                isTargetActive: { targetActive },
                currentModifiers: { targetActive ? .maskCommand : [] },
                postEvent: { _ in preconditionFailure("An unready destination must receive no keys") },
                sleep: { _ in sleeps += 1 }
            )
            precondition(!sent)
            precondition(sleeps <= 101, "Focus/key-release waiting must be bounded")
        }
    }

    @MainActor
    private static func testCancellationReleasesKeys() async {
        // Cancel before any key, after modifier-down, and after V-down.
        for cancelAt in 1...3 {
            var sleeps = 0
            var events: [CGEvent] = []
            let sent = await PasteKeystrokeSender.send(
                bundleIdentifier: "com.microsoft.rdc.macos",
                isTargetActive: { true },
                currentModifiers: { [] },
                postEvent: { events.append($0) },
                sleep: { _ in
                    sleeps += 1
                    if sleeps == cancelAt { throw CancellationError() }
                }
            )
            precondition(!sent)
            switch cancelAt {
            case 1:
                precondition(events.isEmpty)
            case 2:
                precondition(events.count == 2)
                precondition(events.allSatisfy { $0.type == .flagsChanged })
                precondition(events.last?.flags.isEmpty == true, "Cancellation must release Control")
            default:
                assertBalancedShortcut(events, expectedModifierKey: 0x3B)
            }
        }
    }

    @MainActor
    private static func testFocusLossBeforeV() async {
        var active = true
        var events: [CGEvent] = []
        let sent = await PasteKeystrokeSender.send(
            bundleIdentifier: "com.microsoft.rdc.macos",
            isTargetActive: { active },
            currentModifiers: { [] },
            postEvent: {
                events.append($0)
                active = false
            },
            sleep: { _ in }
        )
        precondition(!sent)
        precondition(events.count == 2)
        precondition(events.allSatisfy { $0.type == .flagsChanged }, "Do not paste into the new foreground app")
        precondition(events.last?.flags.isEmpty == true)
    }

    @MainActor
    private static func testAlreadyCancelledTask() async {
        let task = Task { @MainActor in
            await PasteKeystrokeSender.send(
                bundleIdentifier: nil,
                isTargetActive: { true },
                currentModifiers: { [] },
                postEvent: { _ in preconditionFailure("Cancelled requests must not send keys") },
                sleep: { _ in }
            )
        }
        task.cancel()
        let sent = await task.value
        precondition(!sent)
    }

    private static func assertBalancedShortcut(_ events: [CGEvent], expectedModifierKey: Int64) {
        var heldModifier: Int64?
        var vIsDown = false
        var pasteCount = 0
        for event in events {
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            switch event.type {
            case .flagsChanged:
                precondition(key == expectedModifierKey)
                if event.flags.isEmpty {
                    precondition(!vIsDown, "Release V before releasing the modifier")
                    heldModifier = nil
                } else {
                    precondition(heldModifier == nil)
                    heldModifier = key
                }
            case .keyDown:
                precondition(key == 0x09 && !vIsDown)
                precondition(heldModifier == expectedModifierKey, "Remote client must see modifier-down before V")
                let expectedFlags = PasteKeystrokeSender.shortcutFlags(isWindowsApp: expectedModifierKey == 0x3B)
                precondition(event.flags == expectedFlags, "Do not leak the quick-paste shortcut's modifiers")
                // VMs/remote clients ignore modifiers without the left-key device bit.
                let deviceBit: UInt64 = expectedModifierKey == 0x3B ? 0x01 : 0x08
                precondition(event.flags.rawValue & deviceBit != 0, "Missing device-dependent modifier bit")
                vIsDown = true
                pasteCount += 1
            case .keyUp:
                precondition(key == 0x09 && vIsDown)
                precondition(heldModifier == expectedModifierKey)
                vIsDown = false
            default:
                preconditionFailure("Unexpected keyboard event")
            }
        }
        precondition(pasteCount == 1, "Each request must paste exactly once")
        precondition(heldModifier == nil && !vIsDown, "Never leave synthetic keys held")
    }
}
