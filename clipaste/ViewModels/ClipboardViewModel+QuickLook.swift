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

        let shouldAnimatePresentation = quickLookItem == nil
        if shouldAnimatePresentation {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                quickLookItem = item
            }
        } else {
            quickLookItem = item
        }

        if item.contentType == .image {
            primeQuickLookImageState(for: item)
            loadQuickLookImagePreview(for: item)
            return
        }

        resetQuickLookImageState()
        quickLookRequestedItemID = nil
    }
}

extension ClipboardViewModel {
    var quickLookPreviewCandidate: ClipboardItem? {
        if let lastSelectedID,
           selectedItemIDs.contains(lastSelectedID),
           let item = displayedItemsForInteraction.first(where: { $0.id == lastSelectedID }) {
            return item
        }

        return displayedItemsForInteraction.first { selectedItemIDs.contains($0.id) }
    }

    func loadQuickLookImagePreview(for item: ClipboardItem) {
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

            guard let initialImage = await ClipboardQuickLookImageService.shared.loadInitialImage(
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

            self.applyQuickLookImageState(from: initialImage, preserveTargetSize: true)
            guard !Task.isCancelled, self.quickLookLoadGeneration == loadGeneration else { return }
            self.quickLookRequestedItemID = nil

            guard ClipboardQuickLookImageService.shared.shouldUpgradeInitialImage(
                initialImage,
                targetDisplaySize: self.previewTargetSize
            ) else {
                return
            }

            guard let upgradedImage = await ClipboardQuickLookImageService.shared.loadUpgradedImage(
                for: itemID,
                maxPixelSize: maxPixelSize
            ),
                  !Task.isCancelled,
                  self.quickLookLoadGeneration == loadGeneration else {
                return
            }

            self.applyQuickLookImageState(from: upgradedImage, preserveTargetSize: true)
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

    func primeQuickLookImageState(for item: ClipboardItem) {
        highResImage = nil
        if let imagePixelSize = item.imagePixelSize {
            previewTargetSize = safeQuickLookPreviewSize(for: imagePixelSize)
        } else {
            previewTargetSize = .zero
        }
    }

    func applyQuickLookImageState(from image: NSImage, preserveTargetSize: Bool) {
        let previewState = makeQuickLookImagePreviewState(from: image)
        if preserveTargetSize == false || previewTargetSize == .zero {
            previewTargetSize = previewState.targetSize
        }
        highResImage = previewState.image
    }

    func quickLookPreviewMaxPixelSize() -> Int {
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
        let scaleFactor = NSScreen.main?.backingScaleFactor
            ?? NSScreen.screens.first?.backingScaleFactor
            ?? 2

        return ClipboardImagePreviewPolicy.quickLookDisplayMaxPixelSize(
            visibleFrame: visibleFrame,
            scaleFactor: scaleFactor
        )
    }

    func prewarmQuickLookPreviewIfNeeded() {
        guard let item = quickLookPreviewCandidate, item.contentType == .image else {
            return
        }

        let maxPixelSize = quickLookPreviewMaxPixelSize()
        ClipboardQuickLookImageService.shared.prewarmInitialImage(
            for: item.id,
            maxPixelSize: maxPixelSize
        )
    }
}
