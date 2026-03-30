import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceSplitView<Leading: View, Trailing: View>: View {
    let direction: WorkspaceSplitAxis
    let ratio: Double
    let onRatioChange: (Double) -> Void
    let onRatioChangeEnded: ((Double) -> Void)?
    let onEqualize: () -> Void
    let minLeadingSize: CGFloat
    let minTrailingSize: CGFloat
    let leading: Leading
    let trailing: Trailing

    private let splitterVisibleSize: CGFloat = 1
    private let splitterInvisibleSize: CGFloat = 6

    init(
        direction: WorkspaceSplitAxis,
        ratio: Double,
        onRatioChange: @escaping (Double) -> Void,
        onRatioChangeEnded: ((Double) -> Void)? = nil,
        minLeadingSize: CGFloat = 10,
        minTrailingSize: CGFloat = 10,
        onEqualize: @escaping () -> Void = {},
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.direction = direction
        self.ratio = ratio
        self.onRatioChange = onRatioChange
        self.onRatioChangeEnded = onRatioChangeEnded
        self.minLeadingSize = max(0, minLeadingSize)
        self.minTrailingSize = max(0, minTrailingSize)
        self.onEqualize = onEqualize
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { geometry in
            let leadingRect = leadingRect(for: geometry.size)
            let trailingRect = trailingRect(for: geometry.size, leadingRect: leadingRect)
            let splitterPoint = splitterPoint(for: geometry.size, leadingRect: leadingRect)

            ZStack(alignment: .topLeading) {
                leading
                    .frame(width: leadingRect.size.width, height: leadingRect.size.height)
                    .offset(x: leadingRect.origin.x, y: leadingRect.origin.y)
                trailing
                    .frame(width: trailingRect.size.width, height: trailingRect.size.height)
                    .offset(x: trailingRect.origin.x, y: trailingRect.origin.y)
                SplitDivider(
                    direction: direction,
                    visibleSize: splitterVisibleSize,
                    invisibleSize: splitterInvisibleSize
                )
                .position(splitterPoint)
                .gesture(dragGesture(geometry.size))
                .onTapGesture(count: 2) {
                    onEqualize()
                }
            }
        }
    }

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { gesture in
                onRatioChange(resolvedRatio(for: gesture.location, in: size))
            }
            .onEnded { gesture in
                let finalRatio = resolvedRatio(for: gesture.location, in: size)
                onRatioChange(finalRatio)
                onRatioChangeEnded?(finalRatio)
            }
    }

    private func resolvedRatio(for location: CGPoint, in size: CGSize) -> Double {
        let axisLength = axisLength(for: size)
        guard axisLength > 0 else {
            return ratio
        }

        let proposedLeadingSize: CGFloat
        switch direction {
        case .horizontal:
            proposedLeadingSize = location.x
        case .vertical:
            proposedLeadingSize = location.y
        }

        let clampedLeadingSize = WorkspaceSplitLayoutPolicy.clampedLeadingSize(
            proposedSize: proposedLeadingSize,
            axisLength: axisLength,
            minLeadingSize: minLeadingSize,
            minTrailingSize: minTrailingSize
        )
        return Double(clampedLeadingSize / axisLength)
    }

    private func leadingRect(for size: CGSize) -> CGRect {
        var result = CGRect(origin: .zero, size: size)
        let leadingLength = resolvedLeadingSize(for: size)
        switch direction {
        case .horizontal:
            result.size.width = max(0, leadingLength - splitterVisibleSize / 2)
        case .vertical:
            result.size.height = max(0, leadingLength - splitterVisibleSize / 2)
        }
        return result
    }

    private func trailingRect(for size: CGSize, leadingRect: CGRect) -> CGRect {
        var result = CGRect(origin: .zero, size: size)
        switch direction {
        case .horizontal:
            result.origin.x += leadingRect.size.width
            result.origin.x += splitterVisibleSize / 2
            result.size.width -= result.origin.x
        case .vertical:
            result.origin.y += leadingRect.size.height
            result.origin.y += splitterVisibleSize / 2
            result.size.height -= result.origin.y
        }
        return result
    }

    private func resolvedLeadingSize(for size: CGSize) -> CGFloat {
        let axisLength = axisLength(for: size)
        guard axisLength > 0 else {
            return 0
        }

        return WorkspaceSplitLayoutPolicy.clampedLeadingSize(
            proposedSize: CGFloat(ratio) * axisLength,
            axisLength: axisLength,
            minLeadingSize: minLeadingSize,
            minTrailingSize: minTrailingSize
        )
    }

    private func axisLength(for size: CGSize) -> CGFloat {
        switch direction {
        case .horizontal:
            size.width
        case .vertical:
            size.height
        }
    }

    private func splitterPoint(for size: CGSize, leadingRect: CGRect) -> CGPoint {
        switch direction {
        case .horizontal:
            return CGPoint(x: leadingRect.size.width, y: size.height / 2)
        case .vertical:
            return CGPoint(x: size.width / 2, y: leadingRect.size.height)
        }
    }

    private struct SplitDivider: View {
        let direction: WorkspaceSplitAxis
        let visibleSize: CGFloat
        let invisibleSize: CGFloat
        @State private var isHovered = false

        var body: some View {
            ZStack {
                Rectangle()
                    .fill(NativeTheme.border.opacity(0.9))
                    .frame(width: visibleWidth, height: visibleHeight)
            }
            .frame(width: hitboxWidth, height: hitboxHeight)
            .contentShape(.rect)
            .onHover { hovering in
                guard hovering != isHovered else { return }
                isHovered = hovering
                if hovering {
                    hoverCursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovered {
                    isHovered = false
                    NSCursor.pop()
                }
            }
        }

        private var hoverCursor: NSCursor {
            switch direction {
            case .horizontal:
                return .resizeLeftRight
            case .vertical:
                return .resizeUpDown
            }
        }

        private var visibleWidth: CGFloat? {
            direction == .horizontal ? visibleSize : nil
        }

        private var visibleHeight: CGFloat? {
            direction == .vertical ? visibleSize : nil
        }

        private var hitboxWidth: CGFloat? {
            direction == .horizontal ? visibleSize + invisibleSize : nil
        }

        private var hitboxHeight: CGFloat? {
            direction == .vertical ? visibleSize + invisibleSize : nil
        }
    }
}

enum WorkspaceSplitLayoutPolicy {
    static func clampedLeadingSize(
        proposedSize: CGFloat,
        axisLength: CGFloat,
        minLeadingSize: CGFloat,
        minTrailingSize: CGFloat
    ) -> CGFloat {
        guard axisLength > 0 else {
            return 0
        }

        let normalizedMinLeading = max(0, minLeadingSize)
        let normalizedMinTrailing = max(0, minTrailingSize)
        let maxLeading = max(0, axisLength - normalizedMinTrailing)
        let minLeading = min(normalizedMinLeading, maxLeading)
        return min(max(minLeading, proposedSize), maxLeading)
    }
}
