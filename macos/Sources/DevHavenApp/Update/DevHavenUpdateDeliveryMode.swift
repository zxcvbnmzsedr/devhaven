import Foundation

enum DevHavenUpdateDeliveryMode: String, Equatable {
    case automatic
    case manualDownload

    var title: String {
        switch self {
        case .automatic:
            return "自动安装"
        case .manualDownload:
            return "手动下载"
        }
    }
}
