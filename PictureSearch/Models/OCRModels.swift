import Foundation

enum OCRFailureType: String, CaseIterable, Codable, Equatable {
    case assetNotFound
    case imageUnavailable
    case imageDecodeFailed
    case recognitionFailed
    case cancelled
    case unknown

    var displayName: String {
        switch self {
        case .assetNotFound:
            return "Photos 资产不存在"
        case .imageUnavailable:
            return "图片不可用"
        case .imageDecodeFailed:
            return "图片解码失败"
        case .recognitionFailed:
            return "OCR 识别失败"
        case .cancelled:
            return "任务已取消"
        case .unknown:
            return "未知失败"
        }
    }
}

struct OCRRecognitionResult: Equatable {
    let text: String
    let durationSeconds: Double
}

struct OCRPerformanceSummary: Equatable {
    var averageDurationSeconds: Double?
    var failureCounts: [OCRFailureType: Int]

    static let empty = OCRPerformanceSummary(
        averageDurationSeconds: nil,
        failureCounts: [:]
    )

    var formattedAverageDuration: String {
        guard let averageDurationSeconds else {
            return "暂无"
        }

        return String(format: "%.2f 秒/张", averageDurationSeconds)
    }

    var formattedFailureTypes: String {
        guard !failureCounts.isEmpty else {
            return "暂无"
        }

        return failureCounts
            .sorted { first, second in
                if first.value == second.value {
                    return first.key.rawValue < second.key.rawValue
                }
                return first.value > second.value
            }
            .map { "\($0.key.displayName) \($0.value)" }
            .joined(separator: " · ")
    }
}

enum OCRTextNormalizer {
    static func normalize(_ lines: [String]) -> String {
        lines
            .map { line in
                line
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
