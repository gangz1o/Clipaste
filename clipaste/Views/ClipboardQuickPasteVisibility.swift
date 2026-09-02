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
        axis: Axis,
        itemIDsInDisplayOrder: [UUID]
    ) -> [UUID: Int] {
        let viewport = CGRect(origin: .zero, size: viewportSize)
        guard viewport.width > 0, viewport.height > 0 else { return [:] }

        var displayIndexByID: [UUID: Int] = [:]
        for (offset, id) in itemIDsInDisplayOrder.enumerated() {
            displayIndexByID[id] = displayIndexByID[id] ?? offset
        }

        var visibleFrameByID: [UUID: ClipboardQuickPasteVisibleFrame] = [:]
        for frame in frames {
            guard let expectedSourceIndex = displayIndexByID[frame.id] else { continue }
            guard frame.sourceIndex == expectedSourceIndex else { continue }
            guard isVisibleEnough(frame: frame.frame, in: viewport) else { continue }

            if let currentFrame = visibleFrameByID[frame.id],
               visibleRatio(frame: currentFrame.frame, in: viewport) >= visibleRatio(frame: frame.frame, in: viewport) {
                continue
            }

            visibleFrameByID[frame.id] = frame
        }

        let visibleFrames = visibleFrameByID.values
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

        var resolvedIndexes: [UUID: Int] = [:]
        for (offset, visibleFrame) in visibleFrames.enumerated() {
            resolvedIndexes[visibleFrame.id] = offset
        }
        return resolvedIndexes
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

    private static func visibleRatio(frame: CGRect, in viewport: CGRect) -> CGFloat {
        guard !frame.isEmpty else { return 0 }

        let intersection = frame.intersection(viewport)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }

        let visibleArea = intersection.width * intersection.height
        let frameArea = frame.width * frame.height
        guard frameArea > 0 else { return 0 }

        return visibleArea / frameArea
    }
}

extension View {
    func clipboardQuickPasteVisibleFrame(
        id: UUID,
        sourceIndex: Int,
        coordinateSpaceName: String,
        isEnabled: Bool
    ) -> some View {
        background {
            if isEnabled {
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
}
