import Foundation
import DevHavenCore

struct DevHavenUpdateDiagnostics: Equatable {
    var currentChannel: UpdateChannel = .stable
    var currentFeedURL: String?
    var currentDownloadsPageURL: String?
    var lastCheckedAt: Date?
    var lastAvailableVersion: String?
    var lastAvailableBuildVersion: String?
    var lastResolvedDownloadURL: String?
    var lastStatusMessage: String?
    var lastErrorMessage: String?

    func exportText(metadata: DevHavenBuildMetadata) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "DevHaven 升级诊断",
            "版本：\(metadata.shortVersion) (build \(metadata.buildVersion))",
            "Bundle ID：\(metadata.bundleIdentifier)",
            "通道：\(currentChannel.rawValue)",
            "运行于 .app：\(metadata.isAppBundle ? "是" : "否")",
            "更新模式：\(metadata.updateDeliveryMode.title)",
            "支持检查更新：\(metadata.supportsUpdateChecks ? "是" : "否")",
            "支持自动升级：\(metadata.supportsAutomaticUpdates ? "是" : "否")",
            "当前 feed：\(currentFeedURL ?? "<none>")",
            "当前下载页：\(currentDownloadsPageURL ?? "<none>")",
        ]

        if let lastCheckedAt {
            lines.append("最近检查时间：\(formatter.string(from: lastCheckedAt))")
        }
        if let lastAvailableVersion {
            let buildSuffix = lastAvailableBuildVersion.map { " (build \($0))" } ?? ""
            lines.append("最近发现版本：\(lastAvailableVersion)\(buildSuffix)")
        }
        if let lastResolvedDownloadURL {
            lines.append("最近解析下载地址：\(lastResolvedDownloadURL)")
        }
        if let lastStatusMessage {
            lines.append("状态：\(lastStatusMessage)")
        }
        if let lastErrorMessage {
            lines.append("错误：\(lastErrorMessage)")
        }

        return lines.joined(separator: "\n")
    }
}
