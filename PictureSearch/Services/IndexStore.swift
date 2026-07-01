import Foundation
import SQLite3

enum IndexStoreError: LocalizedError, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "打开本地索引失败：\(message)"
        case .prepareFailed(let message):
            return "准备本地索引语句失败：\(message)"
        case .stepFailed(let message):
            return "执行本地索引语句失败：\(message)"
        case .bindFailed(let message):
            return "写入本地索引参数失败：\(message)"
        }
    }
}

final class IndexStore {
    private let databaseURL: URL
    private var database: OpaquePointer?

    init(databaseURL: URL = IndexStore.defaultDatabaseURL()) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            throw IndexStoreError.openFailed(message)
        }

        try execute("""
        CREATE TABLE IF NOT EXISTS asset_index_records (
            assetLocalIdentifier TEXT PRIMARY KEY NOT NULL,
            creationDate REAL,
            mediaType TEXT NOT NULL,
            mediaSubtype TEXT NOT NULL,
            pixelWidth INTEGER NOT NULL,
            pixelHeight INTEGER NOT NULL,
            ocrText TEXT,
            ocrStatus TEXT NOT NULL,
            imageEmbedding BLOB,
            embeddingStatus TEXT NOT NULL,
            modelVersion TEXT,
            lastIndexedAt REAL,
            failureReason TEXT,
            ocrDurationSeconds REAL,
            ocrFailureType TEXT,
            embeddingDurationSeconds REAL,
            embeddingFailureType TEXT
        );
        """)
        try addColumnIfNeeded(name: "ocrDurationSeconds", definition: "REAL")
        try addColumnIfNeeded(name: "ocrFailureType", definition: "TEXT")
        try addColumnIfNeeded(name: "embeddingDurationSeconds", definition: "REAL")
        try addColumnIfNeeded(name: "embeddingFailureType", definition: "TEXT")
    }

    deinit {
        sqlite3_close(database)
    }

    static func defaultDatabaseURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("PictureSearch", isDirectory: true)
            .appendingPathComponent("Index.sqlite")
    }

    func upsertAssetSummaries(_ summaries: [PhotoAssetSummary], indexedAt: Date = Date()) throws -> IndexSyncResult {
        var result = IndexSyncResult.empty

        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for summary in summaries {
                let incoming = AssetIndexRecord(assetSummary: summary, indexedAt: indexedAt)
                if let existing = try record(for: incoming.assetLocalIdentifier) {
                    if existing.hasSameAssetMetadata(as: incoming) {
                        result.unchanged += 1
                    } else {
                        var updated = existing
                        updated.creationDate = incoming.creationDate
                        updated.mediaType = incoming.mediaType
                        updated.mediaSubtype = incoming.mediaSubtype
                        updated.pixelWidth = incoming.pixelWidth
                        updated.pixelHeight = incoming.pixelHeight
                        updated.lastIndexedAt = indexedAt
                        try updateRecordPreservingTaskState(updated)
                        result.updated += 1
                    }
                } else {
                    try insertRecord(incoming)
                    result.inserted += 1
                }
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }

        return result
    }

    func summary(currentEmbeddingModelVersion: String? = nil) throws -> IndexStatusSummary {
        let records = try fetchRecords()
        return records.reduce(into: .empty) { summary, record in
            summary.totalRecords += 1
            switch record.ocrStatus {
            case .pending:
                summary.ocrPending += 1
            case .processing:
                summary.ocrProcessing += 1
            case .ready:
                summary.ocrReady += 1
            case .failed:
                summary.ocrFailed += 1
            }

            switch record.embeddingStatus {
            case .pending:
                summary.embeddingPending += 1
            case .processing:
                summary.embeddingProcessing += 1
            case .ready:
                if let currentEmbeddingModelVersion,
                   record.modelVersion != currentEmbeddingModelVersion {
                    summary.embeddingOutdated += 1
                } else {
                    summary.embeddingReady += 1
                }
            case .failed:
                summary.embeddingFailed += 1
            }
        }
    }

    func ocrPerformanceSummary() throws -> OCRPerformanceSummary {
        let records = try fetchRecords()
        let durations = records.compactMap(\.ocrDurationSeconds)
        let averageDuration = durations.isEmpty
            ? nil
            : durations.reduce(0, +) / Double(durations.count)
        let failureCounts = records.reduce(into: [OCRFailureType: Int]()) { result, record in
            guard let failureType = record.ocrFailureType else {
                return
            }

            result[failureType, default: 0] += 1
        }

        return OCRPerformanceSummary(
            averageDurationSeconds: averageDuration,
            failureCounts: failureCounts
        )
    }

    func fetchOCRCandidates(includeFailed: Bool) throws -> [AssetIndexRecord] {
        let statuses = includeFailed
            ? [IndexTaskStatus.pending.rawValue, IndexTaskStatus.failed.rawValue]
            : [IndexTaskStatus.pending.rawValue]
        let placeholders = Array(repeating: "?", count: statuses.count).joined(separator: ", ")
        let sql = """
        SELECT assetLocalIdentifier, creationDate, mediaType, mediaSubtype,
               pixelWidth, pixelHeight, ocrText, ocrStatus, imageEmbedding,
               embeddingStatus, modelVersion, lastIndexedAt, failureReason,
               ocrDurationSeconds, ocrFailureType, embeddingDurationSeconds,
               embeddingFailureType
        FROM asset_index_records
        WHERE ocrStatus IN (\(placeholders))
        ORDER BY creationDate DESC;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        for (offset, status) in statuses.enumerated() {
            try bindText(status, to: Int32(offset + 1), in: statement)
        }

        var records: [AssetIndexRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(readRecord(from: statement))
        }

        return records
    }

    func fetchRecords() throws -> [AssetIndexRecord] {
        let sql = """
        SELECT assetLocalIdentifier, creationDate, mediaType, mediaSubtype,
               pixelWidth, pixelHeight, ocrText, ocrStatus, imageEmbedding,
               embeddingStatus, modelVersion, lastIndexedAt, failureReason,
               ocrDurationSeconds, ocrFailureType, embeddingDurationSeconds,
               embeddingFailureType
        FROM asset_index_records
        ORDER BY creationDate DESC;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        var records: [AssetIndexRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(readRecord(from: statement))
        }

        return records
    }

    func record(for assetLocalIdentifier: String) throws -> AssetIndexRecord? {
        let sql = """
        SELECT assetLocalIdentifier, creationDate, mediaType, mediaSubtype,
               pixelWidth, pixelHeight, ocrText, ocrStatus, imageEmbedding,
               embeddingStatus, modelVersion, lastIndexedAt, failureReason,
               ocrDurationSeconds, ocrFailureType, embeddingDurationSeconds,
               embeddingFailureType
        FROM asset_index_records
        WHERE assetLocalIdentifier = ?;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bindText(assetLocalIdentifier, to: 1, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return readRecord(from: statement)
        }

        return nil
    }

    func clearAll() throws {
        try execute("DELETE FROM asset_index_records;")
    }

    func fetchEmbeddingCandidates(includeFailed: Bool, modelVersion: String) throws -> [AssetIndexRecord] {
        let sql = """
        SELECT assetLocalIdentifier, creationDate, mediaType, mediaSubtype,
               pixelWidth, pixelHeight, ocrText, ocrStatus, imageEmbedding,
               embeddingStatus, modelVersion, lastIndexedAt, failureReason,
               ocrDurationSeconds, ocrFailureType, embeddingDurationSeconds,
               embeddingFailureType
        FROM asset_index_records
        WHERE embeddingStatus = ?
           OR (embeddingStatus = ? AND ? = 1)
           OR (embeddingStatus = ? AND (modelVersion IS NULL OR modelVersion != ?))
        ORDER BY creationDate DESC;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bindText(IndexTaskStatus.pending.rawValue, to: 1, in: statement)
        try bindText(IndexTaskStatus.failed.rawValue, to: 2, in: statement)
        sqlite3_bind_int(statement, 3, includeFailed ? 1 : 0)
        try bindText(IndexTaskStatus.ready.rawValue, to: 4, in: statement)
        try bindText(modelVersion, to: 5, in: statement)

        var records: [AssetIndexRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(readRecord(from: statement))
        }

        return records
    }

    func markEmbeddingProcessing(assetLocalIdentifier: String) throws {
        let sql = """
        UPDATE asset_index_records
        SET embeddingStatus = ?, failureReason = NULL, embeddingFailureType = NULL
        WHERE assetLocalIdentifier = ?;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bindText(IndexTaskStatus.processing.rawValue, to: 1, in: statement)
        try bindText(assetLocalIdentifier, to: 2, in: statement)
        try step(statement)
    }

    func markEmbeddingReady(
        assetLocalIdentifier: String,
        vector: EmbeddingVector,
        modelVersion: String,
        durationSeconds: Double,
        indexedAt: Date = Date()
    ) throws {
        let sql = """
        UPDATE asset_index_records
        SET imageEmbedding = ?, embeddingStatus = ?, modelVersion = ?,
            embeddingDurationSeconds = ?, embeddingFailureType = NULL,
            failureReason = NULL, lastIndexedAt = ?
        WHERE assetLocalIdentifier = ?;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bindOptionalData(vector.normalized().encodedData(), to: 1, in: statement)
        try bindText(IndexTaskStatus.ready.rawValue, to: 2, in: statement)
        try bindText(modelVersion, to: 3, in: statement)
        try bindDouble(durationSeconds, to: 4, in: statement)
        try bindOptionalDate(indexedAt, to: 5, in: statement)
        try bindText(assetLocalIdentifier, to: 6, in: statement)
        try step(statement)
    }

    func markEmbeddingFailed(
        assetLocalIdentifier: String,
        failureType: EmbeddingFailureType,
        reason: String,
        durationSeconds: Double?,
        indexedAt: Date = Date()
    ) throws {
        let sql = """
        UPDATE asset_index_records
        SET embeddingStatus = ?, failureReason = ?, embeddingFailureType = ?,
            embeddingDurationSeconds = ?, lastIndexedAt = ?
        WHERE assetLocalIdentifier = ?;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bindText(IndexTaskStatus.failed.rawValue, to: 1, in: statement)
        try bindText(reason, to: 2, in: statement)
        try bindText(failureType.rawValue, to: 3, in: statement)
        try bindOptionalDouble(durationSeconds, to: 4, in: statement)
        try bindOptionalDate(indexedAt, to: 5, in: statement)
        try bindText(assetLocalIdentifier, to: 6, in: statement)
        try step(statement)
    }

    func visualSearchCandidates(
        queryVector: EmbeddingVector,
        modelVersion: String,
        limit: Int
    ) throws -> [VisualSearchResult] {
        let records = try fetchRecords()
        return try records.compactMap { record in
            guard record.embeddingStatus == .ready,
                  record.modelVersion == modelVersion,
                  let data = record.imageEmbedding,
                  let imageVector = EmbeddingVector.decode(from: data) else {
                return nil
            }

            let score = try imageVector.cosineSimilarity(to: queryVector)
            return VisualSearchResult(
                assetLocalIdentifier: record.assetLocalIdentifier,
                score: score,
                explanation: "视觉语义相似度 \(String(format: "%.3f", score))",
                record: record
            )
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }

    func markOCRProcessing(assetLocalIdentifier: String) throws {
        let sql = """
        UPDATE asset_index_records
        SET ocrStatus = ?, failureReason = NULL, ocrFailureType = NULL
        WHERE assetLocalIdentifier = ?;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bindText(IndexTaskStatus.processing.rawValue, to: 1, in: statement)
        try bindText(assetLocalIdentifier, to: 2, in: statement)
        try step(statement)
    }

    func markOCRReady(assetLocalIdentifier: String, text: String, durationSeconds: Double, indexedAt: Date = Date()) throws {
        let sql = """
        UPDATE asset_index_records
        SET ocrText = ?, ocrStatus = ?, ocrDurationSeconds = ?,
            failureReason = NULL, ocrFailureType = NULL, lastIndexedAt = ?
        WHERE assetLocalIdentifier = ?;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bindOptionalText(text.isEmpty ? nil : text, to: 1, in: statement)
        try bindText(IndexTaskStatus.ready.rawValue, to: 2, in: statement)
        try bindDouble(durationSeconds, to: 3, in: statement)
        try bindOptionalDate(indexedAt, to: 4, in: statement)
        try bindText(assetLocalIdentifier, to: 5, in: statement)
        try step(statement)
    }

    func markOCRFailed(
        assetLocalIdentifier: String,
        failureType: OCRFailureType,
        reason: String,
        durationSeconds: Double?,
        indexedAt: Date = Date()
    ) throws {
        let sql = """
        UPDATE asset_index_records
        SET ocrStatus = ?, failureReason = ?, ocrFailureType = ?,
            ocrDurationSeconds = ?, lastIndexedAt = ?
        WHERE assetLocalIdentifier = ?;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bindText(IndexTaskStatus.failed.rawValue, to: 1, in: statement)
        try bindText(reason, to: 2, in: statement)
        try bindText(failureType.rawValue, to: 3, in: statement)
        try bindOptionalDouble(durationSeconds, to: 4, in: statement)
        try bindOptionalDate(indexedAt, to: 5, in: statement)
        try bindText(assetLocalIdentifier, to: 6, in: statement)
        try step(statement)
    }

    private func insertRecord(_ record: AssetIndexRecord) throws {
        let sql = """
        INSERT INTO asset_index_records (
            assetLocalIdentifier, creationDate, mediaType, mediaSubtype,
            pixelWidth, pixelHeight, ocrText, ocrStatus, imageEmbedding,
            embeddingStatus, modelVersion, lastIndexedAt, failureReason,
            ocrDurationSeconds, ocrFailureType, embeddingDurationSeconds,
            embeddingFailureType
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bind(record, to: statement)
        try step(statement)
    }

    private func updateRecordPreservingTaskState(_ record: AssetIndexRecord) throws {
        let sql = """
        UPDATE asset_index_records
        SET creationDate = ?, mediaType = ?, mediaSubtype = ?,
            pixelWidth = ?, pixelHeight = ?, lastIndexedAt = ?
        WHERE assetLocalIdentifier = ?;
        """

        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bindOptionalDate(record.creationDate, to: 1, in: statement)
        try bindText(record.mediaType, to: 2, in: statement)
        try bindText(record.mediaSubtype, to: 3, in: statement)
        sqlite3_bind_int(statement, 4, Int32(record.pixelWidth))
        sqlite3_bind_int(statement, 5, Int32(record.pixelHeight))
        try bindOptionalDate(record.lastIndexedAt, to: 6, in: statement)
        try bindText(record.assetLocalIdentifier, to: 7, in: statement)
        try step(statement)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw IndexStoreError.stepFailed(lastErrorMessage())
        }
    }

    private func addColumnIfNeeded(name: String, definition: String) throws {
        guard try !tableHasColumn(name) else {
            return
        }

        try execute("ALTER TABLE asset_index_records ADD COLUMN \(name) \(definition);")
    }

    private func tableHasColumn(_ columnName: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(asset_index_records);")
        defer {
            sqlite3_finalize(statement)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            if columnText(statement, 1) == columnName {
                return true
            }
        }

        return false
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IndexStoreError.prepareFailed(lastErrorMessage())
        }

        return statement
    }

    private func step(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IndexStoreError.stepFailed(lastErrorMessage())
        }
    }

    private func bind(_ record: AssetIndexRecord, to statement: OpaquePointer?) throws {
        try bindText(record.assetLocalIdentifier, to: 1, in: statement)
        try bindOptionalDate(record.creationDate, to: 2, in: statement)
        try bindText(record.mediaType, to: 3, in: statement)
        try bindText(record.mediaSubtype, to: 4, in: statement)
        sqlite3_bind_int(statement, 5, Int32(record.pixelWidth))
        sqlite3_bind_int(statement, 6, Int32(record.pixelHeight))
        try bindOptionalText(record.ocrText, to: 7, in: statement)
        try bindText(record.ocrStatus.rawValue, to: 8, in: statement)
        try bindOptionalData(record.imageEmbedding, to: 9, in: statement)
        try bindText(record.embeddingStatus.rawValue, to: 10, in: statement)
        try bindOptionalText(record.modelVersion, to: 11, in: statement)
        try bindOptionalDate(record.lastIndexedAt, to: 12, in: statement)
        try bindOptionalText(record.failureReason, to: 13, in: statement)
        try bindOptionalDouble(record.ocrDurationSeconds, to: 14, in: statement)
        try bindOptionalText(record.ocrFailureType?.rawValue, to: 15, in: statement)
        try bindOptionalDouble(record.embeddingDurationSeconds, to: 16, in: statement)
        try bindOptionalText(record.embeddingFailureType?.rawValue, to: 17, in: statement)
    }

    private func bindDouble(_ value: Double, to index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw IndexStoreError.bindFailed(lastErrorMessage())
        }
    }

    private func bindOptionalDouble(_ value: Double?, to index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }

        try bindDouble(value, to: index, in: statement)
    }

    private func bindText(_ value: String, to index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw IndexStoreError.bindFailed(lastErrorMessage())
        }
    }

    private func bindOptionalText(_ value: String?, to index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }

        try bindText(value, to: index, in: statement)
    }

    private func bindOptionalDate(_ value: Date?, to index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }

        guard sqlite3_bind_double(statement, index, value.timeIntervalSince1970) == SQLITE_OK else {
            throw IndexStoreError.bindFailed(lastErrorMessage())
        }
    }

    private func bindOptionalData(_ value: Data?, to index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }

        try value.withUnsafeBytes { rawBuffer in
            guard sqlite3_bind_blob(
                statement,
                index,
                rawBuffer.baseAddress,
                Int32(value.count),
                SQLITE_TRANSIENT
            ) == SQLITE_OK else {
                throw IndexStoreError.bindFailed(lastErrorMessage())
            }
        }
    }

    private func readRecord(from statement: OpaquePointer?) -> AssetIndexRecord {
        AssetIndexRecord(
            assetLocalIdentifier: columnText(statement, 0) ?? "",
            creationDate: columnDate(statement, 1),
            mediaType: columnText(statement, 2) ?? "",
            mediaSubtype: columnText(statement, 3) ?? "",
            pixelWidth: Int(sqlite3_column_int(statement, 4)),
            pixelHeight: Int(sqlite3_column_int(statement, 5)),
            ocrText: columnText(statement, 6),
            ocrStatus: IndexTaskStatus(rawValue: columnText(statement, 7) ?? "") ?? .failed,
            imageEmbedding: columnData(statement, 8),
            embeddingStatus: IndexTaskStatus(rawValue: columnText(statement, 9) ?? "") ?? .failed,
            modelVersion: columnText(statement, 10),
            lastIndexedAt: columnDate(statement, 11),
            failureReason: columnText(statement, 12),
            ocrDurationSeconds: columnDouble(statement, 13),
            ocrFailureType: columnText(statement, 14).flatMap(OCRFailureType.init(rawValue:)),
            embeddingDurationSeconds: columnDouble(statement, 15),
            embeddingFailureType: columnText(statement, 16).flatMap(EmbeddingFailureType.init(rawValue:))
        )
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }

        return String(cString: text)
    }

    private func columnDate(_ statement: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private func columnDouble(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return sqlite3_column_double(statement, index)
    }

    private func columnData(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }

        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: count)
    }

    private func lastErrorMessage() -> String {
        guard let database else {
            return "数据库未打开"
        }

        return String(cString: sqlite3_errmsg(database))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
