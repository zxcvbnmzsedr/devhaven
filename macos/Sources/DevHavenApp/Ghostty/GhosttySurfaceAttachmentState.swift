import AppKit

struct GhosttySurfaceAttachmentState: Equatable {
    var lastOcclusion: Bool?
    var lastSurfaceFocus: Bool?
    var lastBackingSize: NSSize

    init(
        lastOcclusion: Bool? = nil,
        lastSurfaceFocus: Bool? = nil,
        lastBackingSize: NSSize = .zero
    ) {
        self.lastOcclusion = lastOcclusion
        self.lastSurfaceFocus = lastSurfaceFocus
        self.lastBackingSize = lastBackingSize
    }

    mutating func prepareForContainerReuse() {
        lastOcclusion = nil
        lastSurfaceFocus = nil
        lastBackingSize = .zero
    }
}
