import SwiftUI
import DevHavenCore

struct WorkspaceSplitView<Leading: View, Trailing: View>: View {
    let direction: WorkspaceSplitAxis
    let ratio: Double
    let onRatioChange: (Double) -> Void
    let leading: Leading
    let trailing: Trailing

    @State private var dragStartRatio: Double?

    init(
        direction: WorkspaceSplitAxis,
        ratio: Double,
        onRatioChange: @escaping (Double) -> Void,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.direction = direction
        self.ratio = ratio
        self.onRatioChange = onRatioChange
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { geometry in
            if direction == .horizontal {
                let total = max(geometry.size.width, 1)
                let divider = dividerThickness
                let primary = max(0, (total * ratio) - (divider / 2))
                let secondary = max(0, total - primary - divider)
                HStack(spacing: 0) {
                    leading
                        .frame(width: primary)
                    dividerHandle(totalLength: total, horizontal: true)
                    trailing
                        .frame(width: secondary)
                }
            } else {
                let total = max(geometry.size.height, 1)
                let divider = dividerThickness
                let primary = max(0, (total * ratio) - (divider / 2))
                let secondary = max(0, total - primary - divider)
                VStack(spacing: 0) {
                    leading
                        .frame(height: primary)
                    dividerHandle(totalLength: total, horizontal: false)
                    trailing
                        .frame(height: secondary)
                }
            }
        }
    }

    private var dividerThickness: CGFloat {
        8
    }

    private func dividerHandle(totalLength: CGFloat, horizontal: Bool) -> some View {
        Rectangle()
            .fill(NativeTheme.border.opacity(0.9))
            .frame(width: horizontal ? dividerThickness : nil, height: horizontal ? nil : dividerThickness)
            .overlay(
                Capsule(style: .continuous)
                    .fill(NativeTheme.textSecondary.opacity(0.55))
                    .frame(width: horizontal ? 3 : 28, height: horizontal ? 28 : 3)
            )
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let base = dragStartRatio ?? ratio
                        if dragStartRatio == nil {
                            dragStartRatio = ratio
                        }
                        let offset = horizontal ? value.translation.width : value.translation.height
                        let updated = min(max(base + (offset / totalLength), 0.1), 0.9)
                        onRatioChange(updated)
                    }
                    .onEnded { _ in
                        dragStartRatio = nil
                    }
            )
    }
}
