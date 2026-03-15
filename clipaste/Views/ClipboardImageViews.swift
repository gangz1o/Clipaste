import AppKit
import SwiftUI

struct ClipboardThumbnailView<Placeholder: View>: View {
    let itemID: UUID
    let maxPixelSize: Int
    @ViewBuilder let placeholder: Placeholder

    @State private var image: NSImage?

    init(
        itemID: UUID,
        maxPixelSize: Int,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.itemID = itemID
        self.maxPixelSize = maxPixelSize
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder
            }
        }
        .task(id: cacheIdentity) {
            image = await ClipboardImagePipeline.shared.thumbnail(
                for: itemID,
                maxPixelSize: maxPixelSize
            )
        }
    }

    private var cacheIdentity: String {
        "\(itemID.uuidString)-\(maxPixelSize)"
    }
}

struct ClipboardQuickLookImageView: View {
    let itemID: UUID

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 600)
                    .padding(16)
            } else {
                ProgressView()
                    .frame(width: 220, height: 220)
                    .padding(16)
            }
        }
        .task(id: itemID) {
            image = await ClipboardImagePipeline.shared.fullImage(
                for: itemID,
                maxPixelSize: 2400
            )
        }
    }
}
