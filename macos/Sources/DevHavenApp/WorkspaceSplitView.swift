import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceSplitView<Leading: View, Trailing: View>: View {
    let direction: WorkspaceSplitAxis
    let ratio: Double
    let onRatioChange: (Double) -> Void
    let onEqualize: () -> Void
    let leading: Leading
    let trailing: Trailing

    private let minSize: CGFloat = 10
    private let splitterVisibleSize: CGFloat = 1
    private let splitterInvisibleSize: CGFloat = 6

    init(
        direction: WorkspaceSplitAxis,
        ratio: Double,
        onRatioChange: @escaping (Double) -> Void,
        onEqualize: @escaping () -> Void = {},
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.direction = direction
        self.ratio = ratio
        self.onRatioChange = onRatioChange
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
                switch direction {
                case .horizontal:
                    let new = min(max(minSize, gesture.location.x), size.width - minSize)
                    onRatioChange(Double(new / size.width))
                case .vertical:
                    let new = min(max(minSize, gesture.location.y), size.height - minSize)
                    onRatioChange(Double(new / size.height))
                }
            }
    }

    private func leadingRect(for size: CGSize) -> CGRect {
        var result = CGRect(origin: .zero, size: size)
        switch direction {
        case .horizontal:
            result.size.width *= ratio
            result.size.width -= splitterVisibleSize / 2
        case .vertical:
            result.size.height *= ratio
            result.size.height -= splitterVisibleSize / 2
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
