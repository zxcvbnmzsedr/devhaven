import SwiftUI
import DevHavenCore

struct WorkspaceGitCommitGraphView: View {
    static let rowHeight: CGFloat = 28

    let row: WorkspaceGitCommitGraphVisibleRow
    let width: Double

    private let strokeWidth: CGFloat = 1.2
    private let nodeRadius: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let metrics = GraphMetrics(size: size, rowHeight: Self.rowHeight)
            drawEdges(in: &context, metrics: metrics)
            drawNode(in: &context, metrics: metrics)
        }
        .frame(
            width: width,
            height: Self.rowHeight + GraphVisualMetrics.verticalOverflow * 2,
            alignment: .leading
        )
        .offset(y: -GraphVisualMetrics.verticalOverflow)
        .frame(width: width, height: Self.rowHeight, alignment: .leading)
        .clipped()
        .accessibilityHidden(true)
    }

    private func drawEdges(in context: inout GraphicsContext, metrics: GraphMetrics) {
        for edge in row.edgeElements {
            let start = CGPoint(
                x: metrics.x(for: edge.positionInCurrentRow),
                y: metrics.currentRowCenterY
            )
            let adjacentCenter = CGPoint(
                x: metrics.x(for: edge.positionInOtherRow),
                y: metrics.adjacentRowCenterY(for: edge.direction)
            )
            drawLine(
                in: &context,
                from: start,
                to: metrics.visibleEndpoint(from: start, toward: adjacentCenter, direction: edge.direction),
                color: branchColor(for: edge.colorIndex)
            )
        }
    }

    private func drawNode(in context: inout GraphicsContext, metrics: GraphMetrics) {
        guard let node = row.node else {
            return
        }
        let center = CGPoint(x: metrics.x(for: node.positionInCurrentRow), y: metrics.currentRowCenterY)
        let nodeRect = CGRect(
            x: center.x - nodeRadius,
            y: center.y - nodeRadius,
            width: nodeRadius * 2,
            height: nodeRadius * 2
        )
        let color = branchColor(for: node.colorIndex)
        context.fill(Path(ellipseIn: nodeRect), with: .color(color))
    }

    private func drawLine(in context: inout GraphicsContext, from start: CGPoint, to end: CGPoint, color: Color) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func branchColor(for colorIndex: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.24, green: 0.78, blue: 0.82),
            Color(red: 0.55, green: 0.36, blue: 0.87),
            Color(red: 0.31, green: 0.57, blue: 0.96),
            Color(red: 0.48, green: 0.78, blue: 0.30),
            Color(red: 0.88, green: 0.62, blue: 0.26),
            Color(red: 0.86, green: 0.42, blue: 0.68),
            Color(red: 0.90, green: 0.74, blue: 0.28)
        ]
        return palette[abs(colorIndex) % palette.count].opacity(0.98)
    }
}

private extension WorkspaceGitCommitGraphView {
    enum GraphVisualMetrics {
        static let verticalOverflow: CGFloat = 3
    }

    struct GraphMetrics {
        let size: CGSize
        let rowHeight: CGFloat

        var step: CGFloat {
            CGFloat(WorkspaceGitCommitGraphBuilder.columnSpacing)
        }

        var padding: CGFloat {
            CGFloat(WorkspaceGitCommitGraphBuilder.horizontalPadding)
        }

        var currentRowCenterY: CGFloat {
            pixelAligned(rowHeight / 2 + GraphVisualMetrics.verticalOverflow)
        }

        var canvasHeight: CGFloat {
            rowHeight + GraphVisualMetrics.verticalOverflow * 2
        }

        func x(for column: Int) -> CGFloat {
            pixelAligned(padding + CGFloat(max(column, 0)) * step)
        }

        func adjacentRowCenterY(for direction: WorkspaceGitCommitGraphEdgeDirection) -> CGFloat {
            currentRowCenterY + (direction == .down ? rowHeight : -rowHeight)
        }

        func visibleEndpoint(
            from start: CGPoint,
            toward adjacentCenter: CGPoint,
            direction: WorkspaceGitCommitGraphEdgeDirection
        ) -> CGPoint {
            let targetY: CGFloat = direction == .up ? 0 : canvasHeight
            let deltaY = adjacentCenter.y - start.y
            guard abs(deltaY) > 0.001 else {
                return CGPoint(x: start.x, y: targetY)
            }

            let progress = (targetY - start.y) / deltaY
            let targetX = start.x + (adjacentCenter.x - start.x) * progress
            return CGPoint(x: targetX, y: targetY)
        }

        private func pixelAligned(_ value: CGFloat) -> CGFloat {
            floor(value) + 0.5
        }
    }
}
