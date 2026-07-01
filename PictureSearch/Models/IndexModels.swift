import Foundation

enum IndexTaskStatus: String, CaseIterable, Codable, Equatable {
    case pending
    case processing
    case ready
    case failed
}

struct AssetIndexRecord: Identifiable, Codable, Equatable {
    var id: String {
        assetLocalIdentifier
    }

    let assetLocalIdentifier: String
    var creationDate: Date?
    var mediaType: String
    var mediaSubtype: String
    var pixelWidth: Int
    var pixelHeight: Int
    var ocrText: String?
    var ocrStatus: IndexTaskStatus
    var imageEmbedding: Data?
    var embeddingStatus: IndexTaskStatus
    var modelVersion: String?
    var lastIndexedAt: Date?
    var failureReason: String?
    var ocrDurationSeconds: Double?
    var ocrFailureType: OCRFailureType?
    var embeddingDurationSeconds: Double?
    var embeddingFailureType: EmbeddingFailureType?

    init(
        assetLocalIdentifier: String,
        creationDate: Date?,
        mediaType: String,
        mediaSubtype: String,
        pixelWidth: Int,
        pixelHeight: Int,
        ocrText: String? = nil,
        ocrStatus: IndexTaskStatus = .pending,
        imageEmbedding: Data? = nil,
        embeddingStatus: IndexTaskStatus = .pending,
        modelVersion: String? = nil,
        lastIndexedAt: Date? = nil,
        failureReason: String? = nil,
        ocrDurationSeconds: Double? = nil,
        ocrFailureType: OCRFailureType? = nil,
        embeddingDurationSeconds: Double? = nil,
        embeddingFailureType: EmbeddingFailureType? = nil
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.creationDate = creationDate
        self.mediaType = mediaType
        self.mediaSubtype = mediaSubtype
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.ocrText = ocrText
        self.ocrStatus = ocrStatus
        self.imageEmbedding = imageEmbedding
        self.embeddingStatus = embeddingStatus
        self.modelVersion = modelVersion
        self.lastIndexedAt = lastIndexedAt
        self.failureReason = failureReason
        self.ocrDurationSeconds = ocrDurationSeconds
        self.ocrFailureType = ocrFailureType
        self.embeddingDurationSeconds = embeddingDurationSeconds
        self.embeddingFailureType = embeddingFailureType
    }

    func hasSameAssetMetadata(as other: AssetIndexRecord) -> Bool {
        assetLocalIdentifier == other.assetLocalIdentifier
            && creationDate == other.creationDate
            && mediaType == other.mediaType
            && mediaSubtype == other.mediaSubtype
            && pixelWidth == other.pixelWidth
            && pixelHeight == other.pixelHeight
    }
}

struct IndexStatusSummary: Equatable {
    var totalRecords: Int
    var ocrPending: Int
    var ocrProcessing: Int
    var ocrReady: Int
    var ocrFailed: Int
    var embeddingPending: Int
    var embeddingProcessing: Int
    var embeddingReady: Int
    var embeddingFailed: Int
    var embeddingOutdated: Int

    static let empty = IndexStatusSummary(
        totalRecords: 0,
        ocrPending: 0,
        ocrProcessing: 0,
        ocrReady: 0,
        ocrFailed: 0,
        embeddingPending: 0,
        embeddingProcessing: 0,
        embeddingReady: 0,
        embeddingFailed: 0,
        embeddingOutdated: 0
    )
}

struct IndexSyncResult: Equatable {
    var inserted: Int
    var updated: Int
    var unchanged: Int

    static let empty = IndexSyncResult(inserted: 0, updated: 0, unchanged: 0)
}

struct EmbeddingBatchPolicy: Equatable {
    let maxBatchSize: Int

    static let defaultInteractive = EmbeddingBatchPolicy(maxBatchSize: 20)

    func selectedRecords(from records: [AssetIndexRecord]) -> [AssetIndexRecord] {
        guard maxBatchSize > 0 else {
            return []
        }

        return Array(records.prefix(maxBatchSize))
    }

    func limitDescription(total: Int) -> String {
        guard total > maxBatchSize else {
            return "本次将处理 \(total) 张图片。"
        }

        return "本次先处理 \(maxBatchSize)/\(total) 张图片，剩余图片会保留为待处理或需重建，可再次启动继续。"
    }
}

extension AssetIndexRecord {
    init(assetSummary: PhotoAssetSummary, indexedAt: Date = Date()) {
        self.init(
            assetLocalIdentifier: assetSummary.id,
            creationDate: assetSummary.creationDate,
            mediaType: assetSummary.mediaTypeDescription,
            mediaSubtype: assetSummary.mediaSubtypeDescription,
            pixelWidth: assetSummary.pixelWidth,
            pixelHeight: assetSummary.pixelHeight,
            lastIndexedAt: indexedAt
        )
    }
}
