import Foundation

enum SearchMatchKind: String, Codable, Equatable {
    case ocr
    case visual
    case time
    case type
}

enum SearchResultConfidence: String, Codable, Equatable {
    case high
    case low

    var description: String {
        switch self {
        case .high:
            return "高置信"
        case .low:
            return "相近结果"
        }
    }
}

struct SearchMatchReason: Codable, Equatable {
    let kind: SearchMatchKind
    let text: String
    let scoreContribution: Double
}

struct SearchResult: Identifiable, Equatable {
    var id: String {
        assetLocalIdentifier
    }

    let assetLocalIdentifier: String
    let title: String
    let explanation: String
    let score: Double
    let confidence: SearchResultConfidence
    let reasons: [SearchMatchReason]
    let record: AssetIndexRecord

    var visualSimilarity: Double? {
        reasons.first(where: { $0.kind == .visual }).map {
            $0.scoreContribution / SearchScoring.visualContributionScale
        }
    }
}

enum SearchScoring {
    static let visualContributionScale = 100.0
    static let highConfidenceThreshold = 50.0
}

enum SearchAssetType: String, Codable, Equatable {
    case screenshot
    case photo
    case document

    var displayName: String {
        switch self {
        case .screenshot:
            return "截图"
        case .photo:
            return "照片"
        case .document:
            return "文档图"
        }
    }
}

struct SearchQueryPlan: Equatable {
    let originalQuery: String
    let normalizedQuery: String
    let ocrTerms: [String]
    let timeRange: DateInterval?
    let timeDescription: String?
    let assetTypes: [SearchAssetType]
    let visualUnavailableMessage: String?

    var isEmpty: Bool {
        normalizedQuery.isEmpty
    }

    var hasAnySignal: Bool {
        !ocrTerms.isEmpty || timeRange != nil || !assetTypes.isEmpty
    }
}

struct VisualSearchResult: Identifiable, Equatable {
    var id: String {
        assetLocalIdentifier
    }

    let assetLocalIdentifier: String
    let score: Double
    let explanation: String
    let record: AssetIndexRecord
}
