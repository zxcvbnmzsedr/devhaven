import AppKit

struct GhosttySurfaceAttachmentState: Equatable {
    var lastOcclusion: Bool?
    var lastSurfaceFocus: Bool?
    var lastBackingSize: NSSize
    var lastContentScale: CGFloat?

    init(
        lastOcclusion: Bool? = nil,
        lastSurfaceFocus: Bool? = nil,
        lastBackingSize: NSSize = .zero,
        lastContentScale: CGFloat? = nil
    ) {
        self.lastOcclusion = lastOcclusion
        self.lastSurfaceFocus = lastSurfaceFocus
        self.lastBackingSize = lastBackingSize
        self.lastContentScale = lastContentScale
    }

    mutating func prepareForContainerReuse() {
        lastOcclusion = nil
        lastSurfaceFocus = nil
        lastBackingSize = .zero
        lastContentScale = nil
    }
}
