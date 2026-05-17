import SwiftUI

struct ClipboardQuickPasteVisibleFrame: Equatable {
    let id: UUID
    let sourceIndex: Int
    let frame: CGRect
}

struct ClipboardQuickPasteVisibleFramePreferenceKey: PreferenceKey {
    static var defaultValue: [ClipboardQuickPasteVisibleFrame] = []

    static func reduce(
        value: inout [ClipboardQuickPasteVisibleFrame],
        nextValue: () -> [ClipboardQuickPasteVisibleFrame]
    ) {
        value.append(contentsOf: nextValue())
    }
}

enum ClipboardQuickPasteVisibleIndexResolver {
    enum Axis {
        case horizontal
        case vertical
    }

    static func resolve(
        frames: [ClipboardQuickPasteVisibleFrame],
        viewportSize: CGSize,
        axis: Axis
    ) -> [UUID: Int] {
        let viewport = CGRect(origin: .zero, size: viewportSize)
        guard viewport.width > 0, viewport.height > 0 else { return [:] }

        let visibleFrames = frames
            .filter { isVisibleEnough(frame: $0.frame, in: viewport) }
            .sorted { lhs, rhs in
                switch axis {
                case .horizontal:
                    if lhs.frame.minX == rhs.frame.minX {
                        return lhs.sourceIndex < rhs.sourceIndex
                    }
                    return lhs.frame.minX < rhs.frame.minX
                case .vertical:
                    if lhs.frame.minY == rhs.frame.minY {
                        return lhs.sourceIndex < rhs.sourceIndex
                    }
                    return lhs.frame.minY < rhs.frame.minY
                }
            }
            .prefix(9)

        return Dictionary(
            uniqueKeysWithValues: visibleFrames.enumerated().map { offset, visibleFrame in
                (visibleFrame.id, offset)
            }
        )
    }

    private static func isVisibleEnough(frame: CGRect, in viewport: CGRect) -> Bool {
        guard !frame.isEmpty else { return false }

        let intersection = frame.intersection(viewport)
        guard !intersection.isNull, !intersection.isEmpty else { return false }

        let visibleArea = intersection.width * intersection.height
        let frameArea = frame.width * frame.height
        guard frameArea > 0 else { return false }

        return visibleArea / frameArea >= 0.45
    }
}

extension View {
    func clipboardQuickPasteVisibleFrame(
        id: UUID,
        sourceIndex: Int,
        coordinateSpaceName: String
    ) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ClipboardQuickPasteVisibleFramePreferenceKey.self,
                    value: [
                        ClipboardQuickPasteVisibleFrame(
                            id: id,
                            sourceIndex: sourceIndex,
                            frame: proxy.frame(in: .named(coordinateSpaceName))
                        )
                    ]
                )
            }
        }
    }
}
