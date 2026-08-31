import SwiftUI
import AppKit

/// Preview panel that shows full content of a clipboard item when hovered/focused
/// in the vertical list layout.

// MARK: - Checkerboard Background

/// Classic gray-white checkerboard pattern for transparent image visualization
struct CheckerboardBackground: View {
    let cellSize: CGFloat = 10
    let lightColor = Color.white.opacity(0.9)
    let darkColor = Color.gray.opacity(0.2)

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let isEven = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(Path(rect), with: .color(isEven ? lightColor : darkColor))
                }
            }
        }
        .accessibilityLabel("Checkerboard pattern for transparent image background")
    }
}

#Preview {
    HStack(spacing: 20) {
        ClipboardItemPreviewView(
            item: ClipboardItem(
                contentType: .text,
                contentHash: "preview1",
                textPreview: "Sample text content for preview",
                appName: "Safari",
                appIconName: "safari",
                rawText: "This is a longer piece of text that would normally be truncated in the list view. Now we can see the full content in the preview panel.\n\nIt can span multiple lines and include paragraphs."
            )
        )

        ClipboardItemPreviewView(
            item: ClipboardItem(
                contentType: .code,
                contentHash: "preview2",
                textPreview: "let greeting = \"Hello, World!\"",
                appName: "Xcode",
                appIconName: "xcode",
                rawText: "func greet(name: String) -> String {\n    return \"Hello, \\(name)!\"\n}\n\ngreet(name: \"World\")"
            )
        )
    }
    .padding()
    .background(Color.black)
}
