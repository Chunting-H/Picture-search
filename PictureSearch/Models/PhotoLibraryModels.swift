import AppKit
import Foundation
import Photos

enum PhotoLibraryAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted
    case unknown

    init(status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .authorized
        case .limited:
            self = .limited
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .unknown
        }
    }

    var canRequestAccess: Bool {
        self == .notDetermined
    }

    var canReadLibrary: Bool {
        self == .authorized || self == .limited
    }

    var primaryActionTitle: String {
        switch self {
        case .notDetermined, .denied, .restricted, .unknown:
            return "申请权限"
        case .limited:
            return "调整授权范围"
        case .authorized:
            return "重新检查权限"
        }
    }

    var shouldOpenSettingsForAccessRequest: Bool {
        switch self {
        case .denied, .restricted, .limited, .unknown:
            return true
        case .notDetermined, .authorized:
            return false
        }
    }

    var title: String {
        switch self {
        case .notDetermined:
            return "需要 Photos 权限"
        case .authorized:
            return "已获得 Photos 权限"
        case .limited:
            return "已获得受限 Photos 权限"
        case .denied:
            return "Photos 权限已被拒绝"
        case .restricted:
            return "Photos 权限受系统限制"
        case .unknown:
            return "Photos 权限状态未知"
        }
    }

    var message: String {
        switch self {
        case .notDetermined:
            return "PictureSearch 需要读取 Photos 图库中的图片缩略图和创建时间，用于在本机验证图片搜索能力。当前阶段只读所选时间范围内的图片，不会修改、删除或整理照片。"
        case .authorized:
            return "可以读取 Photos 图库中的图片资产。"
        case .limited:
            return "当前只能读取你允许访问的部分照片。可以在系统设置中调整授权范围。"
        case .denied:
            return "请在系统设置中为 PictureSearch 开启 Photos 访问权限，然后回到应用重试。"
        case .restricted:
            return "当前设备或系统策略限制了 Photos 访问权限，请检查系统设置或管理配置。"
        case .unknown:
            return "系统返回了暂不支持的 Photos 权限状态，请稍后重试或检查系统设置。"
        }
    }
}

enum PhotoLibraryTimeScope: String, CaseIterable, Identifiable {
    case lastWeek
    case lastMonth
    case lastYear
    case all

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .lastWeek:
            return "近一周"
        case .lastMonth:
            return "近一个月"
        case .lastYear:
            return "近一年"
        case .all:
            return "全部"
        }
    }

    var emptyDescription: String {
        switch self {
        case .lastWeek:
            return "所选范围内没有读取到近一周的 Photos 图片。"
        case .lastMonth:
            return "所选范围内没有读取到近一个月的 Photos 图片。"
        case .lastYear:
            return "所选范围内没有读取到近一年的 Photos 图片。"
        case .all:
            return "没有读取到 Photos 图片。"
        }
    }

    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .lastYear:
            return calendar.date(byAdding: .year, value: -1, to: now)
        case .all:
            return nil
        }
    }
}

struct PhotoAssetSummary: Identifiable, Equatable {
    let id: String
    let creationDate: Date?
    let mediaTypeDescription: String
    let mediaSubtypeDescription: String
    let pixelWidth: Int
    let pixelHeight: Int

    var formattedCreationDate: String {
        guard let creationDate else {
            return "未知时间"
        }

        return Self.creationDateFormatter.string(from: creationDate)
    }

    private static let creationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

extension PhotoAssetSummary {
    init(indexRecord: AssetIndexRecord) {
        self.init(
            id: indexRecord.assetLocalIdentifier,
            creationDate: indexRecord.creationDate,
            mediaTypeDescription: indexRecord.mediaType,
            mediaSubtypeDescription: indexRecord.mediaSubtype,
            pixelWidth: indexRecord.pixelWidth,
            pixelHeight: indexRecord.pixelHeight
        )
    }
}

struct PhotoThumbnail: Identifiable {
    let id: String
    let image: NSImage?
    let failureReason: String?

    var didLoadSuccessfully: Bool {
        image != nil
    }
}

struct PhotoLibraryLoadSummary: Equatable {
    var totalAssets: Int
    var successfulThumbnails: Int
    var failedThumbnails: Int

    static let empty = PhotoLibraryLoadSummary(
        totalAssets: 0,
        successfulThumbnails: 0,
        failedThumbnails: 0
    )
}
