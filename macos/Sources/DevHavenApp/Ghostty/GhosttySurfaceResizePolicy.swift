import CoreGraphics

struct GhosttySurfaceResizeDecision: Equatable {
    let width: UInt32
    let height: UInt32
}

enum GhosttySurfaceResizePolicy {
    static func resizeDecision(
        lastBackingSize: CGSize,
        newBackingSize: CGSize,
        cellSizeInPixels: CGSize
    ) -> GhosttySurfaceResizeDecision? {
        guard newBackingSize != lastBackingSize else {
            return nil
        }

        let width = UInt32(max(1, Int(newBackingSize.width.rounded(.down))))
        let height = UInt32(max(1, Int(newBackingSize.height.rounded(.down))))

        guard cellSizeInPixels.width > 0, cellSizeInPixels.height > 0 else {
            return GhosttySurfaceResizeDecision(width: width, height: height)
        }

        let columns = Int(width) / max(1, Int(cellSizeInPixels.width.rounded(.down)))
        let rows = Int(height) / max(1, Int(cellSizeInPixels.height.rounded(.down)))
        guard columns >= 5, rows >= 2 else {
            return nil
        }

        return GhosttySurfaceResizeDecision(width: width, height: height)
    }
}
