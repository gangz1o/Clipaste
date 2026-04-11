import AppKit
import SwiftUI

extension ClipboardViewModel {
    func toggleQuickLook() {
        if isQuickLookActive {
            dismissQuickLook()
        } else if let item = quickLookPreviewCandidate {
            presentQuickLook(for: item)
        }
    }

    func dismissQuickLook() {
        quickLookLoadGeneration &+= 1
        quickLookLoadTask?.cancel()
        quickLookLoadTask = nil
        quickLookRequestedItemID = nil

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            quickLookItem = nil
        }

        resetQuickLookImageState()
    }

    var isQuickLookActive: Bool {
        quickLookItem != nil || quickLookRequestedItemID != nil
    }

    func presentQuickLook(for item: ClipboardItem) {
        quickLookLoadGeneration &+= 1
        quickLookLoadTask?.cancel()
        quickLookLoadTask = nil
        quickLookRequestedItemID = item.id

        if quickLookItem?.id != item.id {
            quickLookItem = nil
        }

        if item.contentType == .image {
            resetQuickLookImageState()
            loadHighResolutionQuickLookImage(for: item)
            return
        }

        resetQuickLookImageState()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            quickLookItem = item
        }
    }
}

private extension ClipboardViewModel {
    var quickLookPreviewCandidate: ClipboardItem? {
        if let lastSelectedID,
           selectedItemIDs.contains(lastSelectedID),
           let item = displayedItemsForInteraction.first(where: { $0.id == lastSelectedID }) {
            return item
        }

        return displayedItemsForInteraction.first { selectedItemIDs.contains($0.id) }
    }

    func loadHighResolutionQuickLookImage(for item: ClipboardItem) {
        let previewItem = item
        let itemID = item.id
        let loadGeneration = quickLookLoadGeneration
        let maxPixelSize = quickLookPreviewMaxPixelSize()

        quickLookLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.quickLookLoadGeneration == loadGeneration {
                    self.quickLookLoadTask = nil
                }
            }

            guard let image = await ClipboardImagePipeline.shared.previewImage(
                for: itemID,
                maxPixelSize: maxPixelSize
            ),
                  !Task.isCancelled,
                  self.quickLookLoadGeneration == loadGeneration else {
                if self.quickLookLoadGeneration == loadGeneration {
                    self.quickLookRequestedItemID = nil
                }
                return
            }

            let previewState = self.makeQuickLookImagePreviewState(from: image)
            guard !Task.isCancelled, self.quickLookLoadGeneration == loadGeneration else { return }

            self.previewTargetSize = previewState.targetSize
            self.highResImage = previewState.image

            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                self.quickLookItem = previewItem
            }
        }
    }

    func makeQuickLookImagePreviewState(from image: NSImage) -> QuickLookImagePreviewState {
        let rawSize = image.size
        let boundedSize = safeQuickLookPreviewSize(for: rawSize)

        return QuickLookImagePreviewState(image: image, targetSize: boundedSize)
    }

    func safeQuickLookPreviewSize(for proposedSize: CGSize) -> CGSize {
        guard proposedSize.width > 0, proposedSize.height > 0 else {
            return .zero
        }

        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero

        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return proposedSize
        }

        let maxWidth = visibleFrame.width * 0.8
        let maxHeight = visibleFrame.height * 0.8
        let widthScale = maxWidth / proposedSize.width
        let heightScale = maxHeight / proposedSize.height
        let scale = min(1, widthScale, heightScale)

        return CGSize(
            width: proposedSize.width * scale,
            height: proposedSize.height * scale
        )
    }

    func resetQuickLookImageState() {
        highResImage = nil
        previewTargetSize = .zero
    }

    func quickLookPreviewMaxPixelSize() -> Int {
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
        let scaleFactor = NSScreen.main?.backingScaleFactor
            ?? NSScreen.screens.first?.backingScaleFactor
            ?? 2

        let longestEdge = max(visibleFrame.width, visibleFrame.height)
        guard longestEdge > 0 else {
            return 2048
        }

        let boundedEdge = longestEdge * 0.8 * scaleFactor
        return max(1600, Int(boundedEdge.rounded(.up)))
    }
}
