import Foundation

public enum UpdateChannel: String, Codable, Sendable, CaseIterable, Identifiable {
    case stable
    case nightly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .stable:
            return "稳定版"
        case .nightly:
            return "Nightly"
        }
    }
}
