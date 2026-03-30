import Foundation

public enum WorkspaceEditorMarkupLane: String, Equatable, Sendable {
    case lineStatus
    case icons
    case annotations
    case folding
}

public enum WorkspaceEditorMarkupMarkerKind: String, Equatable, Sendable {
    case searchMatch
    case added
    case removed
    case changed
    case conflict
    case info
    case warning
    case error
    case breakpoint
    case bookmark
    case foldedRegion
}

public enum WorkspaceEditorMarkupIcon: String, Equatable, Sendable {
    case circle
    case bookmark
    case triangle
    case chevron
    case exclamation
}

public struct WorkspaceEditorMarkupMarker: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: WorkspaceEditorMarkupMarkerKind
    public var lineRange: WorkspaceDiffLineRange
    public var lane: WorkspaceEditorMarkupLane?
    public var priority: Int
    public var annotationText: String?
    public var icon: WorkspaceEditorMarkupIcon?
    public var showsInOverview: Bool
    public var showsInGutter: Bool
    public var tooltip: String?

    public init(
        id: String,
        kind: WorkspaceEditorMarkupMarkerKind,
        lineRange: WorkspaceDiffLineRange,
        lane: WorkspaceEditorMarkupLane? = nil,
        priority: Int = 0,
        annotationText: String? = nil,
        icon: WorkspaceEditorMarkupIcon? = nil,
        showsInOverview: Bool = true,
        showsInGutter: Bool = false,
        tooltip: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.lineRange = WorkspaceDiffLineRange(
            startLine: lineRange.startLine,
            lineCount: max(1, lineRange.lineCount)
        )
        self.lane = lane
        self.priority = priority
        let normalizedAnnotation = annotationText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.annotationText = normalizedAnnotation.isEmpty ? nil : normalizedAnnotation
        self.icon = icon
        self.showsInOverview = showsInOverview
        self.showsInGutter = showsInGutter
        let normalizedTooltip = tooltip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.tooltip = normalizedTooltip.isEmpty ? nil : normalizedTooltip
    }
}

public struct WorkspaceEditorMarkupModel: Equatable, Sendable {
    public var markers: [WorkspaceEditorMarkupMarker]

    public init(markers: [WorkspaceEditorMarkupMarker] = []) {
        self.markers = markers
    }

    public var overviewMarkers: [WorkspaceEditorMarkupMarker] {
        markers.filter(\.showsInOverview)
    }

    public var gutterMarkers: [WorkspaceEditorMarkupMarker] {
        markers.filter { $0.showsInGutter && $0.lane != nil }
    }
}
