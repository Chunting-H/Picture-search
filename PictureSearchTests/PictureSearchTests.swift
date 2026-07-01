import CoreGraphics
import CoreML
import XCTest
@testable import PictureSearch

final class PictureSearchTests: XCTestCase {
    func testSearchServiceReturnsNoResultsForPureVisualQueryWhenVisualModelUnavailable() {
        let service = SearchService()

        let plan = service.parseQuery("海边夕阳", referenceDate: makeDate(year: 2026, month: 6, day: 29))

        XCTAssertEqual(service.search(plan: plan, records: []), [])
        XCTAssertEqual(plan.visualUnavailableMessage, "当前 MVP 尚未启用真实视觉语义模型，不能可靠处理纯画面描述查询。")
        XCTAssertFalse(plan.hasAnySignal)
    }

    func testSearchQueryParserExtractsTimeTypeAndOCRTerms() {
        let service = SearchService()
        let referenceDate = makeDate(year: 2026, month: 6, day: 29)

        let screenshotPlan = service.parseQuery("包含 Hermes 的截图", referenceDate: referenceDate)
        let summerPlan = service.parseQuery("去年夏天的截图", referenceDate: referenceDate)
        let monthPlan = service.parseQuery("2025 年 10 月的截图", referenceDate: referenceDate)

        XCTAssertEqual(screenshotPlan.ocrTerms, ["hermes"])
        XCTAssertEqual(screenshotPlan.assetTypes, [.screenshot])
        XCTAssertNil(screenshotPlan.timeRange)
        XCTAssertEqual(summerPlan.assetTypes, [.screenshot])
        XCTAssertEqual(summerPlan.timeDescription, "去年夏天")
        XCTAssertEqual(summerPlan.timeRange?.start, makeDate(year: 2025, month: 6, day: 1))
        XCTAssertEqual(summerPlan.timeRange?.end, makeDate(year: 2025, month: 9, day: 1))
        XCTAssertEqual(monthPlan.timeDescription, "2025 年 10 月")
        XCTAssertEqual(monthPlan.timeRange?.start, makeDate(year: 2025, month: 10, day: 1))
        XCTAssertEqual(monthPlan.timeRange?.end, makeDate(year: 2025, month: 11, day: 1))
    }

    func testSearchServiceRanksOCRExactMatchAboveWeakTypeMatch() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try IndexStore(databaseURL: databaseURL)
        _ = try store.upsertAssetSummaries([
            PhotoAssetSummary(
                id: "hermes-shot",
                creationDate: makeDate(year: 2025, month: 10, day: 5),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "截图",
                pixelWidth: 120,
                pixelHeight: 90
            ),
            PhotoAssetSummary(
                id: "other-shot",
                creationDate: makeDate(year: 2025, month: 10, day: 6),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "截图",
                pixelWidth: 120,
                pixelHeight: 90
            )
        ])
        try store.markOCRReady(assetLocalIdentifier: "hermes-shot", text: "订单页面 Hermes Paris", durationSeconds: 0.1)
        try store.markOCRReady(assetLocalIdentifier: "other-shot", text: "普通设置页面", durationSeconds: 0.1)

        let results = try SearchService().search(
            query: "包含 Hermes 的截图",
            indexStore: store,
            referenceDate: makeDate(year: 2026, month: 6, day: 29)
        )

        XCTAssertEqual(results.map(\.assetLocalIdentifier), ["hermes-shot", "other-shot"])
        XCTAssertEqual(results.first?.confidence, .high)
        XCTAssertTrue(results.first?.reasons.contains { $0.kind == .ocr && $0.text.contains("hermes") } == true)
        XCTAssertTrue(results.first?.reasons.contains { $0.kind == .type && $0.text.contains("截图") } == true)
        XCTAssertEqual(results.last?.confidence, .low)

        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testSearchServiceCombinesTimeAndTypeSignals() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try IndexStore(databaseURL: databaseURL)
        _ = try store.upsertAssetSummaries([
            PhotoAssetSummary(
                id: "summer-shot",
                creationDate: makeDate(year: 2025, month: 7, day: 10),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "截图",
                pixelWidth: 120,
                pixelHeight: 90
            ),
            PhotoAssetSummary(
                id: "winter-shot",
                creationDate: makeDate(year: 2025, month: 12, day: 10),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "截图",
                pixelWidth: 120,
                pixelHeight: 90
            ),
            PhotoAssetSummary(
                id: "summer-photo",
                creationDate: makeDate(year: 2025, month: 7, day: 12),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "普通图片",
                pixelWidth: 120,
                pixelHeight: 90
            )
        ])

        let results = try SearchService().search(
            query: "去年夏天的截图",
            indexStore: store,
            referenceDate: makeDate(year: 2026, month: 6, day: 29)
        )

        XCTAssertEqual(results.first?.assetLocalIdentifier, "summer-shot")
        XCTAssertEqual(results.first?.confidence, .high)
        XCTAssertTrue(results.first?.explanation.contains("时间匹配：去年夏天") == true)
        XCTAssertTrue(results.first?.explanation.contains("类型匹配：截图") == true)
        XCTAssertTrue(results.contains { $0.assetLocalIdentifier == "winter-shot" && $0.confidence == .low })
        XCTAssertTrue(results.contains { $0.assetLocalIdentifier == "summer-photo" && $0.confidence == .low })

        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testSearchServiceFindsExplicitMonthAndDocumentOCR() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try IndexStore(databaseURL: databaseURL)
        _ = try store.upsertAssetSummaries([
            PhotoAssetSummary(
                id: "doc-october",
                creationDate: makeDate(year: 2025, month: 10, day: 8),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "普通图片",
                pixelWidth: 120,
                pixelHeight: 90
            )
        ])
        try store.markOCRReady(assetLocalIdentifier: "doc-october", text: "Project Apollo launch checklist", durationSeconds: 0.1)

        let results = try SearchService().search(
            query: "2025 年 10 月文档里的 Apollo",
            indexStore: store,
            referenceDate: makeDate(year: 2026, month: 6, day: 29)
        )

        XCTAssertEqual(results.first?.assetLocalIdentifier, "doc-october")
        XCTAssertEqual(results.first?.confidence, .high)
        XCTAssertTrue(results.first?.reasons.contains { $0.kind == .ocr && $0.text.contains("apollo") } == true)
        XCTAssertTrue(results.first?.reasons.contains { $0.kind == .time } == true)
        XCTAssertTrue(results.first?.reasons.contains { $0.kind == .type && $0.text.contains("文档图") } == true)

        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testSearchServiceTreatsBareMonthAsCurrentYearTimeQuery() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try IndexStore(databaseURL: databaseURL)
        _ = try store.upsertAssetSummaries([
            PhotoAssetSummary(
                id: "june-photo-1",
                creationDate: makeDate(year: 2026, month: 6, day: 3),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "普通图片",
                pixelWidth: 120,
                pixelHeight: 90
            ),
            PhotoAssetSummary(
                id: "june-photo-2",
                creationDate: makeDate(year: 2026, month: 6, day: 29),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "普通图片",
                pixelWidth: 120,
                pixelHeight: 90
            ),
            PhotoAssetSummary(
                id: "may-photo",
                creationDate: makeDate(year: 2026, month: 5, day: 29),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "普通图片",
                pixelWidth: 120,
                pixelHeight: 90
            )
        ])

        let plan = SearchService().parseQuery("6月", referenceDate: makeDate(year: 2026, month: 6, day: 29))
        let results = try SearchService().search(
            query: "6月",
            indexStore: store,
            referenceDate: makeDate(year: 2026, month: 6, day: 29)
        )

        XCTAssertEqual(plan.timeDescription, "2026 年 6 月")
        XCTAssertEqual(plan.ocrTerms, [])
        XCTAssertEqual(Set(results.map(\.assetLocalIdentifier)), ["june-photo-1", "june-photo-2"])
        XCTAssertFalse(results.contains { $0.assetLocalIdentifier == "may-photo" })

        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testAuthorizationStateMessagesIncludeRecoveryGuidance() {
        XCTAssertFalse(PhotoLibraryAuthorizationState.denied.canReadLibrary)
        XCTAssertTrue(PhotoLibraryAuthorizationState.denied.message.contains("系统设置"))
        XCTAssertTrue(PhotoLibraryAuthorizationState.notDetermined.canRequestAccess)
        XCTAssertEqual(PhotoLibraryAuthorizationState.denied.primaryActionTitle, "申请权限")
        XCTAssertTrue(PhotoLibraryAuthorizationState.denied.shouldOpenSettingsForAccessRequest)
        XCTAssertFalse(PhotoLibraryAuthorizationState.notDetermined.shouldOpenSettingsForAccessRequest)
    }

    func testPhotoAssetSummaryFormatsMissingCreationDate() {
        let summary = PhotoAssetSummary(
            id: "local-id",
            creationDate: nil,
            mediaTypeDescription: "照片",
            mediaSubtypeDescription: "普通图片",
            pixelWidth: 100,
            pixelHeight: 80
        )

        XCTAssertEqual(summary.formattedCreationDate, "未知时间")
    }

    func testPhotoLibraryLoadSummaryStartsEmpty() {
        XCTAssertEqual(PhotoLibraryLoadSummary.empty.totalAssets, 0)
        XCTAssertEqual(PhotoLibraryLoadSummary.empty.successfulThumbnails, 0)
        XCTAssertEqual(PhotoLibraryLoadSummary.empty.failedThumbnails, 0)
    }

    func testPhotoLibraryTimeScopeStartDates() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 26
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: components)!

        XCTAssertNotNil(PhotoLibraryTimeScope.lastWeek.startDate(now: now, calendar: calendar))
        XCTAssertNotNil(PhotoLibraryTimeScope.lastMonth.startDate(now: now, calendar: calendar))
        XCTAssertNotNil(PhotoLibraryTimeScope.lastYear.startDate(now: now, calendar: calendar))
        XCTAssertNil(PhotoLibraryTimeScope.all.startDate(now: now, calendar: calendar))
        XCTAssertEqual(PhotoLibraryTimeScope.all.title, "全部")
    }

    func testAssetIndexRecordStartsWithPendingTasks() {
        let summary = PhotoAssetSummary(
            id: "asset-1",
            creationDate: nil,
            mediaTypeDescription: "照片",
            mediaSubtypeDescription: "截图",
            pixelWidth: 120,
            pixelHeight: 90
        )

        let record = AssetIndexRecord(assetSummary: summary)

        XCTAssertEqual(record.assetLocalIdentifier, "asset-1")
        XCTAssertEqual(record.ocrStatus, .pending)
        XCTAssertEqual(record.embeddingStatus, .pending)
        XCTAssertNil(record.ocrText)
        XCTAssertNil(record.imageEmbedding)
        XCTAssertNil(record.ocrDurationSeconds)
        XCTAssertNil(record.ocrFailureType)
        XCTAssertNil(record.embeddingDurationSeconds)
        XCTAssertNil(record.embeddingFailureType)
    }

    func testEmbeddingBatchPolicyLimitsInteractiveBatchSize() {
        let records = (0..<75).map { index in
            AssetIndexRecord(
                assetLocalIdentifier: "asset-\(index)",
                creationDate: nil,
                mediaType: "照片",
                mediaSubtype: "普通图片",
                pixelWidth: 100,
                pixelHeight: 80
            )
        }
        let policy = EmbeddingBatchPolicy.defaultInteractive

        let selected = policy.selectedRecords(from: records)

        XCTAssertEqual(selected.count, 20)
        XCTAssertEqual(selected.first?.assetLocalIdentifier, "asset-0")
        XCTAssertEqual(selected.last?.assetLocalIdentifier, "asset-19")
        XCTAssertTrue(policy.limitDescription(total: 75).contains("20/75"))
        XCTAssertTrue(policy.limitDescription(total: 75).contains("再次启动继续"))
        XCTAssertEqual(policy.limitDescription(total: 12), "本次将处理 12 张图片。")
        XCTAssertEqual(EmbeddingBatchPolicy(maxBatchSize: 0).selectedRecords(from: records), [])
    }

    func testEmbeddingInferenceExecutionPolicyDocumentsBackgroundInference() {
        XCTAssertEqual(EmbeddingInferenceExecutionPolicy.priority, .utility)
        XCTAssertNil(EmbeddingInferenceExecutionPolicy.mainThreadIssue(operation: "图片向量推理", isMainThread: false))
        XCTAssertEqual(
            EmbeddingInferenceExecutionPolicy.mainThreadIssue(operation: "图片向量推理", isMainThread: true),
            "图片向量推理 不应在主线程运行。请通过后台任务执行本地 Core ML 推理，避免阻塞界面。"
        )
    }

    func testIndexStorePersistsAndDeduplicatesRecords() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try IndexStore(databaseURL: databaseURL)

        let summary = PhotoAssetSummary(
            id: "asset-1",
            creationDate: Date(timeIntervalSince1970: 100),
            mediaTypeDescription: "照片",
            mediaSubtypeDescription: "普通图片",
            pixelWidth: 100,
            pixelHeight: 80
        )

        let firstSync = try store.upsertAssetSummaries([summary], indexedAt: Date(timeIntervalSince1970: 200))
        let secondSync = try store.upsertAssetSummaries([summary], indexedAt: Date(timeIntervalSince1970: 300))
        let status = try store.summary()

        XCTAssertEqual(firstSync.inserted, 1)
        XCTAssertEqual(secondSync.unchanged, 1)
        XCTAssertEqual(status.totalRecords, 1)
        XCTAssertEqual(status.ocrPending, 1)
        XCTAssertEqual(status.embeddingPending, 1)

        try store.clearAll()
        XCTAssertEqual(try store.summary().totalRecords, 0)

        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testOCRTextNormalizerRemovesEmptyLinesAndExtraWhitespace() {
        let normalized = OCRTextNormalizer.normalize([
            "  Hello   world  ",
            "",
            "  中文   文本\n混排  "
        ])

        XCTAssertEqual(normalized, "Hello world\n中文 文本 混排")
    }

    func testOCRServiceProtocolSupportsMockResult() async throws {
        let service = MockOCRService(
            result: OCRRecognitionResult(text: "模拟 OCR 文本", durationSeconds: 0.5)
        )
        let image = try makeTestCGImage()

        let result = try await service.recognizeText(in: image)

        XCTAssertEqual(result.text, "模拟 OCR 文本")
        XCTAssertEqual(result.durationSeconds, 0.5)
    }

    func testIndexStoreTracksOCRStatusDurationAndFailureType() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try IndexStore(databaseURL: databaseURL)

        let summaries = [
            PhotoAssetSummary(
                id: "asset-ready",
                creationDate: Date(timeIntervalSince1970: 100),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "截图",
                pixelWidth: 100,
                pixelHeight: 80
            ),
            PhotoAssetSummary(
                id: "asset-failed",
                creationDate: Date(timeIntervalSince1970: 90),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "普通图片",
                pixelWidth: 120,
                pixelHeight: 90
            )
        ]

        _ = try store.upsertAssetSummaries(summaries)
        try store.markOCRProcessing(assetLocalIdentifier: "asset-ready")
        try store.markOCRReady(
            assetLocalIdentifier: "asset-ready",
            text: "测试文字",
            durationSeconds: 1.25,
            indexedAt: Date(timeIntervalSince1970: 200)
        )
        try store.markOCRFailed(
            assetLocalIdentifier: "asset-failed",
            failureType: .imageUnavailable,
            reason: "iCloud 图片暂时不可用",
            durationSeconds: nil,
            indexedAt: Date(timeIntervalSince1970: 210)
        )

        let status = try store.summary()
        let ready = try store.record(for: "asset-ready")
        let failed = try store.record(for: "asset-failed")
        let performance = try store.ocrPerformanceSummary()
        let retryCandidates = try store.fetchOCRCandidates(includeFailed: true)

        XCTAssertEqual(status.ocrReady, 1)
        XCTAssertEqual(status.ocrFailed, 1)
        XCTAssertEqual(ready?.ocrText, "测试文字")
        XCTAssertEqual(ready?.ocrDurationSeconds, 1.25)
        XCTAssertNil(ready?.ocrFailureType)
        XCTAssertEqual(failed?.ocrFailureType, .imageUnavailable)
        XCTAssertEqual(failed?.failureReason, "iCloud 图片暂时不可用")
        XCTAssertEqual(performance.averageDurationSeconds, 1.25)
        XCTAssertEqual(performance.failureCounts[.imageUnavailable], 1)
        XCTAssertEqual(retryCandidates.map(\.assetLocalIdentifier), ["asset-failed"])

        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testEmbeddingVectorEncodingAndCosineSimilarity() throws {
        let vector = EmbeddingVector(values: [3, 0, 4])
        let decoded = EmbeddingVector.decode(from: vector.encodedData())

        XCTAssertEqual(decoded?.values, [3, 0, 4])
        XCTAssertEqual(try vector.cosineSimilarity(to: EmbeddingVector(values: [3, 0, 4])), 1, accuracy: 0.0001)
        XCTAssertEqual(try vector.cosineSimilarity(to: EmbeddingVector(values: [0, 1, 0])), 0, accuracy: 0.0001)
    }

    func testEmbeddingServiceReportsModelReadinessGaps() {
        let service = EmbeddingService()
        let report = service.modelReadinessReport()

        XCTAssertFalse(report.isReady)
        XCTAssertFalse(report.hasImageModel)
        XCTAssertFalse(report.hasTextModel)
        XCTAssertTrue(report.recoveryMessage.contains("模型输入输出和预处理配置"))
        XCTAssertTrue(report.packagedResourceLines.contains { $0.contains("CLIPImageEncoder.mlmodelc") && $0.contains("未打包") })
        XCTAssertTrue(report.packagedResourceLines.contains { $0.contains("CLIPTextEncoder.mlmodelc") && $0.contains("未打包") })
        XCTAssertThrowsError(try service.validateModelAvailability()) { error in
            XCTAssertTrue(error.localizedDescription.contains("本地图文向量模型不可用"))
        }
    }

    func testEmbeddingServiceFallsBackWhenBundledManifestIsMissing() {
        let service = EmbeddingService.bundledOrUnconfigured(
            manifestResourceName: "MissingEmbeddingModelManifest.json",
            bundle: Bundle.main
        )
        let report = service.modelReadinessReport()

        XCTAssertEqual(service.modelInfo.version, "local-clip-unconfigured")
        XCTAssertFalse(report.isReady)
        XCTAssertTrue(report.manifestIssue?.contains("缺少模型 manifest") == true)
        XCTAssertTrue(report.diagnosticLines.contains { $0.contains("manifest 问题") && $0.contains("MissingEmbeddingModelManifest.json") })
        XCTAssertTrue(report.recoveryMessage.contains("MissingEmbeddingModelManifest.json"))
        XCTAssertTrue(report.recoveryMessage.contains("模型输入输出和预处理配置"))
    }

    func testEmbeddingServiceLoadsLocalModelPackageResources() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let imageModelURL = directory.appendingPathComponent("CLIPImageEncoder.mlmodelc", isDirectory: true)
        let textModelURL = directory.appendingPathComponent("CLIPTextEncoder.mlmodelc", isDirectory: true)
        let tokenizerURL = directory.appendingPathComponent("clip_tokenizer.json")
        try FileManager.default.createDirectory(at: imageModelURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: textModelURL, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 1024).write(to: imageModelURL.appendingPathComponent("weights.bin"))
        try Data(repeating: 8, count: 2048).write(to: textModelURL.appendingPathComponent("weights.bin"))
        try """
        {
          "vocabulary": {
            "<s>": 49406,
            "</s>": 49407,
            "<unk>": 0,
            "h": 1,
            "i": 2,
            "hi": 3
          },
          "merges": [["h", "i"]],
          "startToken": "<s>",
          "endToken": "</s>",
          "unknownToken": "<unk>",
          "lowercasesInput": true
        }
        """.data(using: .utf8)!.write(to: tokenizerURL)

        let imageSHA256 = try EmbeddingModelResourceAudit.sha256(at: imageModelURL)
        let textSHA256 = try EmbeddingModelResourceAudit.sha256(at: textModelURL)
        let tokenizerSHA256 = try EmbeddingModelResourceAudit.sha256(at: tokenizerURL)
        let manifest = EmbeddingModelManifest(
            version: "local-package-service-test",
            source: "本机 Application Support 模型包测试",
            license: "MIT",
            imageModelName: "CLIPImageEncoder",
            textModelName: "CLIPTextEncoder",
            imageModelFileSizeMB: 1024.0 / 1024.0 / 1024.0,
            textModelFileSizeMB: 2048.0 / 1024.0 / 1024.0,
            tokenizerFileSizeKB: Double(try EmbeddingModelResourceAudit.byteSize(at: tokenizerURL)) / 1024.0,
            imageModelSHA256: imageSHA256,
            textModelSHA256: textSHA256,
            tokenizerSHA256: tokenizerSHA256,
            integrationReason: "验证 App 能从本机模型包目录加载真实模型资源。",
            alternativesConsidered: ["仅依赖 App bundle 会要求每次模型变更都修改 Xcode 资源。"],
            expectedImpact: "允许用户在本机放置模型包，仍保留 manifest、许可证、大小和 SHA-256 校验。",
            configuration: EmbeddingModelConfiguration(
                imageInputName: "image",
                imageOutputName: "image_embedding",
                textInputName: "tokens",
                textOutputName: "text_embedding",
                tokenizerResourceName: "clip_tokenizer.json",
                textSequenceLength: 77,
                textPadTokenID: 0,
                textStartTokenID: 49406,
                textEndTokenID: 49407,
                imageInputSize: 224,
                imageMean: [0.481, 0.457, 0.408],
                imageStandardDeviation: [0.268, 0.261, 0.275]
            ),
            notes: "测试 manifest，模型目录不是有效 Core ML 编译产物。"
        )
        try JSONEncoder().encode(manifest)
            .write(to: directory.appendingPathComponent("EmbeddingModelManifest.json"))

        let service = EmbeddingService.localPackageOrUnconfigured(localPackageURL: directory)
        let report = service.modelReadinessReport()

        XCTAssertEqual(service.modelInfo.version, "local-package-service-test")
        XCTAssertTrue(report.hasImageModel)
        XCTAssertTrue(report.hasTextModel)
        XCTAssertTrue(report.hasTokenizer)
        XCTAssertFalse(report.configurationIssues.contains { $0.contains("tokenizer") })
        XCTAssertTrue(report.configurationIssues.contains { $0.contains("CLIPImageEncoder.mlmodelc") && $0.contains("Core ML 加载失败") })
        XCTAssertTrue(report.packagedResourceLines.contains { $0.contains("CLIPImageEncoder.mlmodelc") && $0.contains("已打包") && $0.contains("SHA-256 匹配") })
        XCTAssertTrue(report.packagedResourceLines.contains { $0.contains("clip_tokenizer.json") && $0.contains("SHA-256 匹配") })
        XCTAssertThrowsError(try service.validateModelAvailability())

        try? FileManager.default.removeItem(at: directory)
    }

    func testEmbeddingReadinessReportSeparatesMissingItemsAndConfigurationIssues() {
        let info = EmbeddingModelInfo(
            version: "test-config",
            source: "测试模型",
            license: "测试许可证",
            expectedImageModelName: "ImageEncoder",
            expectedTextModelName: "TextEncoder",
            configuration: EmbeddingModelConfiguration(
                imageInputName: "",
                imageOutputName: "image_embedding",
                textInputName: "tokens",
                textOutputName: "text_embedding",
                tokenizerResourceName: "Tokenizer.json",
                textSequenceLength: 77,
                textPadTokenID: 0,
                imageInputSize: 224,
                imageMean: [0.481, 0.457, 0.408],
                imageStandardDeviation: [0.268, 0.261, 0.275]
            )
        )
        let report = EmbeddingModelReadinessReport(
            modelInfo: info,
            manifestIssue: "测试 manifest 缺少资源大小",
            hasImageModel: false,
            hasTextModel: true,
            hasTokenizer: false,
            configurationIssues: info.configuration?.validationIssues ?? []
        )

        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.missingItems, ["ImageEncoder.mlmodelc", "Tokenizer.json"])
        XCTAssertTrue(report.configurationIssues.contains("缺少图片编码器输入名"))
        XCTAssertTrue(report.recoveryMessage.contains("测试 manifest 缺少资源大小"))
        XCTAssertTrue(report.recoveryMessage.contains("ImageEncoder.mlmodelc"))
        XCTAssertTrue(report.diagnosticLines.contains("模型版本：test-config"))
        XCTAssertTrue(report.diagnosticLines.contains("manifest 问题：测试 manifest 缺少资源大小"))
        XCTAssertTrue(report.diagnosticLines.contains { $0.contains("缺少资源：ImageEncoder.mlmodelc、Tokenizer.json") })
    }

    func testEmbeddingReadinessRequiresCleanManifestIssue() {
        let report = EmbeddingModelReadinessReport(
            modelInfo: EmbeddingModelInfo(
                version: "test-model",
                source: "测试模型",
                license: "测试许可证",
                expectedImageModelName: "ImageEncoder",
                expectedTextModelName: "TextEncoder",
                configuration: EmbeddingModelConfiguration(
                    imageInputName: "image",
                    imageOutputName: "image_embedding",
                    textInputName: "tokens",
                    textOutputName: "text_embedding",
                    tokenizerResourceName: nil,
                    textSequenceLength: 77,
                    textPadTokenID: 0,
                    imageInputSize: 224,
                    imageMean: [0.481, 0.457, 0.408],
                    imageStandardDeviation: [0.268, 0.261, 0.275]
                )
            ),
            manifestIssue: "manifest 仍是模板占位，不能作为真实模型配置",
            hasImageModel: true,
            hasTextModel: true,
            hasTokenizer: true,
            configurationIssues: []
        )

        XCTAssertFalse(report.isReady)
        XCTAssertTrue(report.recoveryMessage.contains("manifest 仍是模板占位"))
    }

    func testEmbeddingModelConfigurationValidatesRequiredFields() {
        let configuration = EmbeddingModelConfiguration(
            imageInputName: "",
            imageOutputName: "",
            textInputName: "",
            textOutputName: "",
            tokenizerResourceName: "",
            textSequenceLength: 0,
            textPadTokenID: 0,
            imageInputSize: 0,
            imageMean: [0.5],
            imageStandardDeviation: [0.5, 0.5]
        )

        XCTAssertTrue(configuration.validationIssues.contains("缺少图片编码器输入名"))
        XCTAssertTrue(configuration.validationIssues.contains("缺少文本编码器输出名"))
        XCTAssertTrue(configuration.validationIssues.contains("tokenizer 资源名为空"))
        XCTAssertTrue(configuration.validationIssues.contains("文本 token 序列长度必须大于 0"))
        XCTAssertTrue(configuration.validationIssues.contains("缺少文本起始 token ID"))
        XCTAssertTrue(configuration.validationIssues.contains("缺少文本结束 token ID"))
        XCTAssertTrue(configuration.validationIssues.contains("图片输入尺寸必须大于 0"))
        XCTAssertTrue(configuration.validationIssues.contains("图片归一化 mean 必须包含 3 个通道"))
        XCTAssertTrue(configuration.validationIssues.contains("图片归一化 standard deviation 必须包含 3 个通道"))
    }

    func testEmbeddingModelManifestDecodesModelInfo() throws {
        let json = """
        {
          "version": "openai-clip-vit-b32-coreml-test",
          "source": "OpenAI CLIP ViT-B/32 Core ML 转换测试",
          "license": "MIT",
          "imageModelName": "CLIPImageEncoder",
          "textModelName": "CLIPTextEncoder",
          "imageModelFileSizeMB": 98.5,
          "textModelFileSizeMB": 63.25,
          "tokenizerFileSizeKB": 512.0,
          "imageModelSHA256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "textModelSHA256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "tokenizerSHA256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
          "integrationReason": "需要用本地图文双塔模型支持画面描述类自然语言找图。",
          "alternativesConsidered": [
            "Apple MobileCLIP 官方权重仅限研究用途，暂不作为默认内置模型。",
            "云端 embedding 不符合本机处理和不上传图片的隐私边界。"
          ],
          "expectedImpact": "预计增加 App 体积、首次模型加载耗时和单张推理耗时，需要通过真实样本记录性能。",
          "notes": "测试 manifest，不包含真实模型文件。",
          "configuration": {
            "imageInputName": "image",
            "imageOutputName": "image_embedding",
            "textInputName": "tokens",
            "textOutputName": "text_embedding",
            "tokenizerResourceName": "clip_vocab.json",
            "textSequenceLength": 77,
            "textPadTokenID": 0,
            "textStartTokenID": 49406,
            "textEndTokenID": 49407,
            "imageInputSize": 224,
            "imageMean": [0.48145466, 0.4578275, 0.40821073],
            "imageStandardDeviation": [0.26862954, 0.26130258, 0.27577711]
          }
        }
        """.data(using: .utf8)!

        let manifest = try EmbeddingModelManifest.decode(from: json)
        let service = EmbeddingService(manifest: manifest)

        XCTAssertEqual(manifest.validationIssues, [])
        XCTAssertEqual(service.modelInfo.version, "openai-clip-vit-b32-coreml-test")
        XCTAssertEqual(service.modelInfo.source, "OpenAI CLIP ViT-B/32 Core ML 转换测试")
        XCTAssertEqual(service.modelInfo.license, "MIT")
        XCTAssertEqual(service.modelInfo.expectedImageModelName, "CLIPImageEncoder")
        XCTAssertEqual(service.modelInfo.configuration?.textSequenceLength, 77)
        XCTAssertEqual(service.modelInfo.configuration?.imageMean.count, 3)
        XCTAssertEqual(manifest.requiredResourceNames, [
            "CLIPImageEncoder.mlmodelc",
            "CLIPTextEncoder.mlmodelc",
            "clip_vocab.json"
        ])
        XCTAssertTrue(manifest.integrationChecklistLines.contains("图片模型：CLIPImageEncoder.mlmodelc，98.50 MB"))
        XCTAssertTrue(manifest.integrationChecklistLines.contains("tokenizer：clip_vocab.json，512.00 KB"))
        XCTAssertTrue(manifest.integrationChecklistLines.contains("图片模型 SHA-256：aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
        XCTAssertTrue(manifest.integrationChecklistLines.contains("引入原因：需要用本地图文双塔模型支持画面描述类自然语言找图。"))
        XCTAssertTrue(manifest.integrationChecklistLines.contains { $0.contains("替代方案：Apple MobileCLIP 官方权重仅限研究用途") })
        XCTAssertTrue(manifest.integrationChecklistLines.contains { $0.contains("影响评估：预计增加 App 体积") })
        XCTAssertTrue(manifest.integrationChecklistLines.contains { $0.contains("起止 token 49406/49407") })
    }

    func testEmbeddingModelResourceAuditChecksPackagedFileSizesAndHashes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let imageModelURL = directory.appendingPathComponent("CLIPImageEncoder.mlmodelc", isDirectory: true)
        let textModelURL = directory.appendingPathComponent("CLIPTextEncoder.mlmodelc", isDirectory: true)
        let tokenizerURL = directory.appendingPathComponent("clip_vocab.json")
        try FileManager.default.createDirectory(at: imageModelURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: textModelURL, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2048).write(to: imageModelURL.appendingPathComponent("weights.bin"))
        try Data(repeating: 2, count: 4096).write(to: textModelURL.appendingPathComponent("weights.bin"))
        try Data(repeating: 3, count: 2048).write(to: tokenizerURL)

        let imageSHA256 = try EmbeddingModelResourceAudit.sha256(at: imageModelURL)
        let tokenizerSHA256 = try EmbeddingModelResourceAudit.sha256(at: tokenizerURL)
        let manifest = EmbeddingModelManifest(
            version: "size-audit-test",
            source: "测试模型",
            license: "测试许可证",
            imageModelName: "CLIPImageEncoder",
            textModelName: "CLIPTextEncoder",
            imageModelFileSizeMB: 2048.0 / 1024.0 / 1024.0,
            textModelFileSizeMB: 50,
            tokenizerFileSizeKB: 2,
            imageModelSHA256: imageSHA256,
            textModelSHA256: String(repeating: "f", count: 64),
            tokenizerSHA256: tokenizerSHA256,
            configuration: EmbeddingModelConfiguration(
                imageInputName: "image",
                imageOutputName: "image_embedding",
                textInputName: "tokens",
                textOutputName: "text_embedding",
                tokenizerResourceName: "clip_vocab.json",
                textSequenceLength: 77,
                textPadTokenID: 0,
                imageInputSize: 224,
                imageMean: [0.481, 0.457, 0.408],
                imageStandardDeviation: [0.268, 0.261, 0.275]
            ),
            notes: nil
        )

        let imageBytes = try EmbeddingModelResourceAudit.byteSize(at: imageModelURL)
        let issues = EmbeddingModelResourceAudit.sizeIssues(
            manifest: manifest,
            imageModelURL: imageModelURL,
            textModelURL: textModelURL,
            tokenizerURL: tokenizerURL
        )
        let hashIssues = EmbeddingModelResourceAudit.hashIssues(
            manifest: manifest,
            imageModelURL: imageModelURL,
            textModelURL: textModelURL,
            tokenizerURL: tokenizerURL
        )
        let resources = EmbeddingModelResourceAudit.packagedResources(
            manifest: manifest,
            modelInfo: manifest.modelInfo,
            imageModelURL: imageModelURL,
            textModelURL: textModelURL,
            tokenizerURL: tokenizerURL
        )

        XCTAssertEqual(imageBytes, 2048)
        XCTAssertFalse(issues.contains { $0.contains("CLIPImageEncoder.mlmodelc") })
        XCTAssertFalse(issues.contains { $0.contains("clip_vocab.json") })
        XCTAssertTrue(issues.contains { $0.contains("CLIPTextEncoder.mlmodelc") && $0.contains("manifest 记录") })
        XCTAssertFalse(hashIssues.contains { $0.contains("CLIPImageEncoder.mlmodelc") })
        XCTAssertFalse(hashIssues.contains { $0.contains("clip_vocab.json") })
        XCTAssertTrue(hashIssues.contains { $0.contains("CLIPTextEncoder.mlmodelc") && $0.contains("SHA-256") })
        XCTAssertEqual(resources.count, 3)
        XCTAssertTrue(resources.contains {
            $0.name == "CLIPImageEncoder.mlmodelc" && $0.isPresent && $0.isValid && $0.actualByteSize == 2048 && $0.actualSHA256 == imageSHA256
        })
        XCTAssertTrue(resources.contains {
            $0.name == "CLIPTextEncoder.mlmodelc" && $0.isPresent && !$0.isValid && $0.issue?.contains("manifest 记录") == true && $0.issue?.contains("SHA-256") == true
        })
        XCTAssertTrue(resources.contains {
            $0.name == "clip_vocab.json" && $0.summaryLine.contains("2.00 KB") && $0.summaryLine.contains("SHA-256 匹配") && $0.isValid
        })

        let report = EmbeddingModelReadinessReport(
            modelInfo: manifest.modelInfo,
            packagedResources: resources,
            manifestIssue: nil,
            hasImageModel: true,
            hasTextModel: true,
            hasTokenizer: true,
            configurationIssues: []
        )

        XCTAssertTrue(report.manifestSuggestionLines.contains("\"imageModelFileSizeMB\": 0.001953"))
        XCTAssertTrue(report.manifestSuggestionLines.contains("\"tokenizerFileSizeKB\": 2.000000"))
        XCTAssertTrue(report.manifestSuggestionLines.contains("\"imageModelSHA256\": \"\(imageSHA256)\""))
        XCTAssertTrue(report.manifestSuggestionLines.contains("\"tokenizerSHA256\": \"\(tokenizerSHA256)\""))

        try? FileManager.default.removeItem(at: directory)
    }

    func testEmbeddingModelPackageInspectorReportsMissingManifest() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let report = EmbeddingModelPackageInspector.inspect(packageURL: directory)

        XCTAssertFalse(report.isReadyForRuntimeValidation)
        XCTAssertNil(report.manifest)
        XCTAssertTrue(report.readinessReport.manifestIssue?.contains("缺少模型 manifest") == true)
        XCTAssertTrue(report.summaryLines.contains { $0.contains("恢复动作") && $0.contains("EmbeddingModelManifest.json") })
        XCTAssertTrue(report.markdownReport.contains("尝试加载 Core ML 模型"))
        XCTAssertTrue(report.markdownReport.contains("输入 shape 和输入数据类型"))
        XCTAssertTrue(report.markdownReport.contains("不会运行图片编码、文本编码或相似度比较"))
    }

    func testEmbeddingModelPackageInspectorRejectsResourcesThatCannotLoadAsCoreML() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let imageModelURL = directory.appendingPathComponent("CLIPImageEncoder.mlmodelc", isDirectory: true)
        let textModelURL = directory.appendingPathComponent("CLIPTextEncoder.mlmodelc", isDirectory: true)
        let tokenizerURL = directory.appendingPathComponent("clip_vocab.json")
        try FileManager.default.createDirectory(at: imageModelURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: textModelURL, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 3072).write(to: imageModelURL.appendingPathComponent("weights.bin"))
        try Data(repeating: 5, count: 4096).write(to: textModelURL.appendingPathComponent("weights.bin"))
        try Data(repeating: 6, count: 1024).write(to: tokenizerURL)

        let imageSHA256 = try EmbeddingModelResourceAudit.sha256(at: imageModelURL)
        let textSHA256 = try EmbeddingModelResourceAudit.sha256(at: textModelURL)
        let tokenizerSHA256 = try EmbeddingModelResourceAudit.sha256(at: tokenizerURL)
        let manifest = EmbeddingModelManifest(
            version: "local-package-test",
            source: "本地候选模型包测试",
            license: "MIT",
            imageModelName: "CLIPImageEncoder",
            textModelName: "CLIPTextEncoder",
            imageModelFileSizeMB: 3072.0 / 1024.0 / 1024.0,
            textModelFileSizeMB: 4096.0 / 1024.0 / 1024.0,
            tokenizerFileSizeKB: 1,
            imageModelSHA256: imageSHA256,
            textModelSHA256: textSHA256,
            tokenizerSHA256: tokenizerSHA256,
            configuration: EmbeddingModelConfiguration(
                imageInputName: "image",
                imageOutputName: "image_embedding",
                textInputName: "tokens",
                textOutputName: "text_embedding",
                tokenizerResourceName: "clip_vocab.json",
                textSequenceLength: 77,
                textPadTokenID: 0,
                imageInputSize: 224,
                imageMean: [0.481, 0.457, 0.408],
                imageStandardDeviation: [0.268, 0.261, 0.275]
            ),
            notes: nil
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: directory.appendingPathComponent("EmbeddingModelManifest.json"))

        let report = EmbeddingModelPackageInspector.inspect(packageURL: directory)

        XCTAssertFalse(report.isReadyForRuntimeValidation)
        XCTAssertEqual(report.manifest?.version, "local-package-test")
        XCTAssertTrue(report.readinessReport.packagedResourceLines.contains { $0.contains("CLIPImageEncoder.mlmodelc") && $0.contains("SHA-256 匹配") })
        XCTAssertTrue(report.readinessReport.manifestSuggestionLines.contains("\"imageModelSHA256\": \"\(imageSHA256)\""))
        XCTAssertTrue(report.readinessReport.manifestSuggestionLines.contains("\"textModelFileSizeMB\": 0.003906"))
        XCTAssertTrue(report.readinessReport.configurationIssues.contains { $0.contains("CLIPImageEncoder.mlmodelc") && $0.contains("Core ML 加载失败") })
        XCTAssertTrue(report.readinessReport.configurationIssues.contains { $0.contains("CLIPTextEncoder.mlmodelc") && $0.contains("Core ML 加载失败") })
        XCTAssertTrue(report.markdownReport.contains("manifest 建议字段"))
        XCTAssertTrue(report.markdownReport.contains("模型包预检可进入真实样本技术验证尝试") == false)
        XCTAssertTrue(report.markdownReport.contains("尝试加载 Core ML 模型"))
        XCTAssertTrue(report.markdownReport.contains("不证明图文向量处于同一语义空间"))

        try? FileManager.default.removeItem(at: directory)
    }

    func testEmbeddingModelRuntimeAuditValidatesMultiArrayInputShapeAndDataType() {
        let cleanIssues = EmbeddingModelRuntimeAudit.multiArrayInputIssues(
            resourceName: "CLIPImageEncoder.mlmodelc",
            inputName: "image",
            actualShape: [1, 3, 224, 224],
            actualDataType: .float32,
            expectedShape: [1, 3, 224, 224],
            expectedDataType: .float32
        )
        let shapeIssues = EmbeddingModelRuntimeAudit.shapeIssues(
            resourceName: "CLIPImageEncoder.mlmodelc",
            inputName: "image",
            actualShape: [1, 224, 224, 3],
            expectedShape: [1, 3, 224, 224]
        )
        let missingShapeIssues = EmbeddingModelRuntimeAudit.shapeIssues(
            resourceName: "CLIPImageEncoder.mlmodelc",
            inputName: "image",
            actualShape: nil,
            expectedShape: [1, 3, 224, 224]
        )
        let dataTypeIssues = EmbeddingModelRuntimeAudit.dataTypeIssues(
            resourceName: "CLIPTextEncoder.mlmodelc",
            inputName: "tokens",
            actualDataType: .float32,
            expectedDataType: .int32
        )

        XCTAssertEqual(cleanIssues, [])
        XCTAssertEqual(
            shapeIssues,
            ["CLIPImageEncoder.mlmodelc 输入 image shape [1,224,224,3] 与 manifest 预期 [1,3,224,224] 不一致"]
        )
        XCTAssertEqual(
            missingShapeIssues,
            ["CLIPImageEncoder.mlmodelc 输入 image 未声明 MLMultiArray shape，无法确认与 manifest 一致"]
        )
        XCTAssertEqual(
            dataTypeIssues,
            ["CLIPTextEncoder.mlmodelc 输入 tokens 数据类型 float32 与预期 int32 不一致"]
        )
    }

    func testEmbeddingModelManifestValidatesRequiredMetadata() throws {
        let manifest = EmbeddingModelManifest(
            version: "",
            source: "",
            license: "",
            imageModelName: "",
            textModelName: "",
            imageModelFileSizeMB: nil,
            textModelFileSizeMB: nil,
            tokenizerFileSizeKB: nil,
            configuration: EmbeddingModelConfiguration(
                imageInputName: "",
                imageOutputName: "",
                textInputName: "",
                textOutputName: "",
                tokenizerResourceName: "",
                textSequenceLength: 0,
                textPadTokenID: 0,
                imageInputSize: 0,
                imageMean: [],
                imageStandardDeviation: []
            ),
            notes: nil
        )

        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少模型版本"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少模型来源"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少许可证说明"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少外部模型引入原因"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少外部模型替代方案说明"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少外部模型影响评估"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少图片模型文件名"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少文本模型文件名"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少图片模型文件大小"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少文本模型文件大小"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少 tokenizer 文件大小"))
        XCTAssertTrue(manifest.validationIssues.contains("缺少图片编码器输入名"))
    }

    func testEmbeddingModelManifestRejectsRestrictedModelLicenses() {
        let manifest = EmbeddingModelManifest(
            version: "restricted-license-test",
            source: "测试模型",
            license: "Research only, non-commercial use",
            imageModelName: "CLIPImageEncoder",
            textModelName: "CLIPTextEncoder",
            imageModelFileSizeMB: 1,
            textModelFileSizeMB: 1,
            tokenizerFileSizeKB: 1,
            configuration: EmbeddingModelConfiguration(
                imageInputName: "image",
                imageOutputName: "image_embedding",
                textInputName: "tokens",
                textOutputName: "text_embedding",
                tokenizerResourceName: "clip_vocab.json",
                textSequenceLength: 77,
                textPadTokenID: 0,
                imageInputSize: 224,
                imageMean: [0.481, 0.457, 0.408],
                imageStandardDeviation: [0.268, 0.261, 0.275]
            ),
            notes: nil
        )
        let service = EmbeddingService(manifest: manifest)
        let report = service.modelReadinessReport()

        XCTAssertTrue(manifest.licenseRestrictionIssues.contains("manifest 许可证包含研究、评估或非商业限制，不能作为默认可用模型"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 许可证包含研究、评估或非商业限制，不能作为默认可用模型"))
        XCTAssertFalse(report.isReady)
        XCTAssertTrue(report.manifestIssue?.contains("许可证") == true)
        XCTAssertThrowsError(try service.validateModelAvailability()) { error in
            XCTAssertTrue(error.localizedDescription.contains("许可证"))
        }
    }

    func testEmbeddingModelManifestAllowsPermissiveLicenseText() {
        let manifest = EmbeddingModelManifest(
            version: "permissive-license-test",
            source: "测试模型",
            license: "MIT",
            imageModelName: "CLIPImageEncoder",
            textModelName: "CLIPTextEncoder",
            imageModelFileSizeMB: 1,
            textModelFileSizeMB: 1,
            tokenizerFileSizeKB: 1,
            configuration: EmbeddingModelConfiguration(
                imageInputName: "image",
                imageOutputName: "image_embedding",
                textInputName: "tokens",
                textOutputName: "text_embedding",
                tokenizerResourceName: "clip_vocab.json",
                textSequenceLength: 77,
                textPadTokenID: 0,
                imageInputSize: 224,
                imageMean: [0.481, 0.457, 0.408],
                imageStandardDeviation: [0.268, 0.261, 0.275]
            ),
            notes: nil
        )

        XCTAssertEqual(manifest.licenseRestrictionIssues, [])
        XCTAssertFalse(manifest.validationIssues.contains { $0.contains("许可证包含") })
    }

    func testEmbeddingModelManifestTemplateDocumentsLocalModelContract() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PictureSearch/Resources/EmbeddingModelManifest.example.json")
        let manifest = try EmbeddingModelManifest.decode(from: Data(contentsOf: url))
        let service = EmbeddingService(manifest: manifest)
        let report = service.modelReadinessReport()

        XCTAssertEqual(manifest.version, "local-clip-template")
        XCTAssertEqual(manifest.imageModelName, "CLIPImageEncoder")
        XCTAssertEqual(manifest.textModelName, "CLIPTextEncoder")
        XCTAssertEqual(manifest.configuration.textSequenceLength, 77)
        XCTAssertEqual(manifest.configuration.textStartTokenID, 49406)
        XCTAssertEqual(manifest.configuration.textEndTokenID, 49407)
        XCTAssertEqual(manifest.configuration.imageInputSize, 224)
        XCTAssertEqual(manifest.configuration.imageMean.count, 3)
        XCTAssertEqual(manifest.configuration.imageStandardDeviation.count, 3)
        XCTAssertTrue(manifest.isTemplate)
        XCTAssertTrue(manifest.validationIssues.contains("manifest 仍是模板占位，不能作为真实模型配置"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少图片模型文件大小"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少文本模型文件大小"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少 tokenizer 文件大小"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少图片模型 SHA-256"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少文本模型 SHA-256"))
        XCTAssertTrue(manifest.validationIssues.contains("manifest 缺少 tokenizer SHA-256"))
        XCTAssertTrue(manifest.integrationChecklistLines.contains("模板状态：仍是模板，不能用于验收"))
        XCTAssertTrue(manifest.source.contains("替换"))
        XCTAssertTrue(manifest.license.contains("替换"))
        XCTAssertTrue(manifest.notes?.contains("不是已验证模型配置") == true)
        XCTAssertTrue(report.manifestIssue?.contains("manifest 仍是模板占位") == true)
        XCTAssertTrue(report.recoveryMessage.contains("manifest 仍是模板占位"))
    }

    func testEmbeddingTextInputBuilderPadsTokenIDs() throws {
        let array = try EmbeddingTextInputBuilder.tokenArray(
            from: EmbeddingTokenizedText(tokenIDs: [49406, 320, 49407]),
            sequenceLength: 5,
            padTokenID: 0
        )
        let values = array.dataPointer.bindMemory(to: Int32.self, capacity: array.count)

        XCTAssertEqual(array.shape, [1, 5])
        XCTAssertEqual(Array(UnsafeBufferPointer(start: values, count: array.count)), [49406, 320, 49407, 0, 0])
    }

    func testEmbeddingTextInputBuilderRejectsLongTokenSequence() {
        XCTAssertThrowsError(
            try EmbeddingTextInputBuilder.tokenArray(
                from: EmbeddingTokenizedText(tokenIDs: [1, 2, 3]),
                sequenceLength: 2,
                padTokenID: 0
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("超出模型序列长度"))
        }
    }

    func testEmbeddingBPETokenizerLoadsLocalJSONVocabulary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tokenizerURL = directory.appendingPathComponent("tokenizer.json")
        let tokenizerJSON = """
        {
          "vocabulary": {
            "<s>": 1,
            "</s>": 2,
            "<unk>": 3,
            "h": 4,
            "i": 5,
            "hi": 6,
            "!": 7
          },
          "merges": [["h", "i"]],
          "startToken": "<s>",
          "endToken": "</s>",
          "unknownToken": "<unk>",
          "lowercasesInput": true
        }
        """.data(using: .utf8)!
        try tokenizerJSON.write(to: tokenizerURL)

        let tokenizer = try EmbeddingBPETokenizer.load(from: tokenizerURL)
        let tokenized = try tokenizer.tokenize("Hi !")

        XCTAssertEqual(tokenized.tokenIDs, [1, 6, 7, 2])

        try? FileManager.default.removeItem(at: directory)
    }

    func testBundledEmbeddingServiceReportsTokenizerParseFailure() throws {
        let bundle = try makeTemporaryResourceBundle(resources: [
            "EmbeddingModelManifest.json": """
            {
              "version": "local-tokenizer-parse-test",
              "source": "本地 tokenizer 解析测试",
              "license": "测试许可证",
              "imageModelName": "CLIPImageEncoder",
              "textModelName": "CLIPTextEncoder",
              "imageModelFileSizeMB": 1.0,
              "textModelFileSizeMB": 1.0,
              "tokenizerFileSizeKB": 1.0,
              "integrationReason": "测试 tokenizer 解析失败时的诊断。",
              "alternativesConsidered": ["测试用例不引入真实模型。"],
              "expectedImpact": "仅用于单元测试，不影响 App 体积。",
              "configuration": {
                "imageInputName": "image",
                "imageOutputName": "image_embedding",
                "textInputName": "tokens",
                "textOutputName": "text_embedding",
                "tokenizerResourceName": "clip_tokenizer.json",
                "textSequenceLength": 77,
                "textPadTokenID": 0,
                "textStartTokenID": 1,
                "textEndTokenID": 2,
                "imageInputSize": 224,
                "imageMean": [0.48145466, 0.4578275, 0.40821073],
                "imageStandardDeviation": [0.26862954, 0.26130258, 0.27577711]
              }
            }
            """,
            "clip_tokenizer.json": "{ invalid tokenizer json"
        ])

        let service = EmbeddingService.bundledOrUnconfigured(bundle: bundle)
        let report = service.modelReadinessReport()

        XCTAssertFalse(report.isReady)
        XCTAssertTrue(report.configurationIssues.contains { $0.contains("tokenizer 解析失败") })
    }

    func testBundledEmbeddingServiceReportsTokenizerSpecialTokenMismatch() throws {
        let bundle = try makeTemporaryResourceBundle(resources: [
            "EmbeddingModelManifest.json": """
            {
              "version": "local-tokenizer-special-token-test",
              "source": "本地 tokenizer 起止 token 测试",
              "license": "MIT",
              "imageModelName": "CLIPImageEncoder",
              "textModelName": "CLIPTextEncoder",
              "imageModelFileSizeMB": 1.0,
              "textModelFileSizeMB": 1.0,
              "tokenizerFileSizeKB": 1.0,
              "imageModelSHA256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "textModelSHA256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
              "tokenizerSHA256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
              "integrationReason": "测试 tokenizer 起止 token 与 manifest 不一致时的诊断。",
              "alternativesConsidered": ["测试用例不引入真实模型。"],
              "expectedImpact": "仅用于单元测试，不影响 App 体积。",
              "configuration": {
                "imageInputName": "image",
                "imageOutputName": "image_embedding",
                "textInputName": "tokens",
                "textOutputName": "text_embedding",
                "tokenizerResourceName": "clip_tokenizer.json",
                "textSequenceLength": 77,
                "textPadTokenID": 0,
                "textStartTokenID": 49406,
                "textEndTokenID": 49407,
                "imageInputSize": 224,
                "imageMean": [0.48145466, 0.4578275, 0.40821073],
                "imageStandardDeviation": [0.26862954, 0.26130258, 0.27577711]
              }
            }
            """,
            "clip_tokenizer.json": """
            {
              "vocabulary": {
                "<s>": 1,
                "</s>": 2,
                "<unk>": 3
              },
              "merges": [],
              "startToken": "<s>",
              "endToken": "</s>",
              "unknownToken": "<unk>",
              "lowercasesInput": true
            }
            """
        ])

        let service = EmbeddingService.bundledOrUnconfigured(bundle: bundle)
        let report = service.modelReadinessReport()

        XCTAssertFalse(report.isReady)
        XCTAssertTrue(report.configurationIssues.contains { $0.contains("tokenizer 起始 token ID 1 与 manifest 记录 49406 不一致") })
        XCTAssertTrue(report.configurationIssues.contains { $0.contains("tokenizer 结束 token ID 2 与 manifest 记录 49407 不一致") })
    }

    func testEmbeddingImagePreprocessorCreatesNormalizedCHWArray() throws {
        let image = try makeTestCGImage()

        let array = try EmbeddingImagePreprocessor.normalizedCHWArray(
            from: image,
            size: 2,
            mean: [0.5, 0.5, 0.5],
            standardDeviation: [0.5, 0.5, 0.5]
        )
        let values = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)

        XCTAssertEqual(array.shape, [1, 3, 2, 2])
        XCTAssertEqual(array.count, 12)
        XCTAssertEqual(values[0], 1, accuracy: 0.001)
        XCTAssertEqual(values[4], 1, accuracy: 0.001)
        XCTAssertEqual(values[8], 1, accuracy: 0.001)
    }

    func testEmbeddingModelOutputDecoderFlattensMultiArray() throws {
        let array = try MLMultiArray(shape: [1, 3], dataType: .float32)
        let values = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
        values[0] = 0.1
        values[1] = 0.2
        values[2] = 0.3

        let vector = try EmbeddingModelOutputDecoder.vector(from: array)

        XCTAssertEqual(vector.values, [0.1, 0.2, 0.3])
    }

    func testIndexStorePersistsEmbeddingVectorAndSearchesByCosine() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try IndexStore(databaseURL: databaseURL)

        let summaries = [
            PhotoAssetSummary(
                id: "asset-sea",
                creationDate: Date(timeIntervalSince1970: 100),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "普通图片",
                pixelWidth: 100,
                pixelHeight: 80
            ),
            PhotoAssetSummary(
                id: "asset-doc",
                creationDate: Date(timeIntervalSince1970: 90),
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "截图",
                pixelWidth: 120,
                pixelHeight: 90
            )
        ]

        _ = try store.upsertAssetSummaries(summaries)
        try store.markEmbeddingReady(
            assetLocalIdentifier: "asset-sea",
            vector: EmbeddingVector(values: [1, 0, 0]),
            modelVersion: "test-model",
            durationSeconds: 0.2
        )
        try store.markEmbeddingReady(
            assetLocalIdentifier: "asset-doc",
            vector: EmbeddingVector(values: [0, 1, 0]),
            modelVersion: "test-model",
            durationSeconds: 0.3
        )

        let results = try store.visualSearchCandidates(
            queryVector: EmbeddingVector(values: [0.9, 0.1, 0]),
            modelVersion: "test-model",
            limit: 2
        )
        let status = try store.summary()
        let currentModelStatus = try store.summary(currentEmbeddingModelVersion: "test-model")
        let newerModelStatus = try store.summary(currentEmbeddingModelVersion: "new-test-model")
        let readyRecord = try store.record(for: "asset-sea")
        let outdatedCandidates = try store.fetchEmbeddingCandidates(
            includeFailed: false,
            modelVersion: "new-test-model"
        )

        XCTAssertEqual(results.map(\.assetLocalIdentifier), ["asset-sea", "asset-doc"])
        XCTAssertGreaterThan(results[0].score, results[1].score)
        XCTAssertEqual(status.embeddingReady, 2)
        XCTAssertEqual(status.embeddingOutdated, 0)
        XCTAssertEqual(currentModelStatus.embeddingReady, 2)
        XCTAssertEqual(currentModelStatus.embeddingOutdated, 0)
        XCTAssertEqual(newerModelStatus.embeddingReady, 0)
        XCTAssertEqual(newerModelStatus.embeddingOutdated, 2)
        XCTAssertEqual(outdatedCandidates.map(\.assetLocalIdentifier), ["asset-sea", "asset-doc"])
        XCTAssertEqual(readyRecord?.modelVersion, "test-model")
        XCTAssertEqual(readyRecord?.embeddingDurationSeconds, 0.2)

        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testSearchServiceUsesTextEmbeddingForVisualSearch() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try IndexStore(databaseURL: databaseURL)
        _ = try store.upsertAssetSummaries([
            PhotoAssetSummary(
                id: "asset-1",
                creationDate: nil,
                mediaTypeDescription: "照片",
                mediaSubtypeDescription: "普通图片",
                pixelWidth: 100,
                pixelHeight: 80
            )
        ])
        try store.markEmbeddingReady(
            assetLocalIdentifier: "asset-1",
            vector: EmbeddingVector(values: [1, 0]),
            modelVersion: "mock-model",
            durationSeconds: 0.1
        )

        let service = SearchService()
        let results = try await service.visualSearch(
            query: "海边夕阳",
            indexStore: store,
            embeddingService: MockEmbeddingService(textVector: EmbeddingVector(values: [1, 0]))
        )

        XCTAssertEqual(results.first?.assetLocalIdentifier, "asset-1")
        XCTAssertEqual(results.first?.score ?? 0, 1, accuracy: 0.0001)

        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testSearchServiceSkipsEmptyVisualQueryAndInvalidLimit() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try IndexStore(databaseURL: databaseURL)
        let service = SearchService()
        let embeddingService = FailingTextEmbeddingService()

        let blankResults = try await service.visualSearch(
            query: "   ",
            indexStore: store,
            embeddingService: embeddingService
        )
        let zeroLimitResults = try await service.visualSearch(
            query: "海边夕阳",
            indexStore: store,
            embeddingService: embeddingService,
            limit: 0
        )

        XCTAssertEqual(blankResults, [])
        XCTAssertEqual(zeroLimitResults, [])

        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testEmbeddingValidationRequiresFiveSamples() async throws {
        let service = EmbeddingValidationService(
            embeddingService: MockEmbeddingService(textVector: EmbeddingVector(values: [1, 0]))
        )
        let image = try makeTestCGImage()

        let report = await service.validate(samples: [
            EmbeddingValidationSample(
                id: "sample-1",
                image: image,
                relatedQuery: "海边夕阳",
                unrelatedQuery: "英文文档截图",
                language: .chinese
            )
        ])

        XCTAssertFalse(report.passed)
        XCTAssertTrue(report.failureReasons.contains { $0.contains("至少需要 5 张测试图片") })
    }

    func testEmbeddingValidationSampleDescriptorRejectsInvalidQueries() {
        let descriptor = EmbeddingValidationSampleDescriptor(
            sampleID: "sample-1",
            assetLocalIdentifier: "asset-1",
            relatedQuery: "海边夕阳",
            unrelatedQuery: "海边夕阳",
            language: .chinese
        )

        XCTAssertTrue(descriptor.validationIssues.contains("相关查询和无关查询不能相同"))
    }

    func testEmbeddingValidationSampleDescriptorDocumentDecodesArrayAndAuditsCoverage() throws {
        let json = """
        [
          {
            "sampleID": "zh-1",
            "assetLocalIdentifier": "private-asset-id-1",
            "relatedQuery": "海边夕阳",
            "unrelatedQuery": "无关文档",
            "language": "chinese"
          },
          {
            "sampleID": "en-1",
            "assetLocalIdentifier": "private-asset-id-2",
            "relatedQuery": "beach sunset",
            "unrelatedQuery": "invoice screenshot",
            "language": "english"
          }
        ]
        """

        let document = try EmbeddingValidationSampleDescriptorDocument.decode(from: Data(json.utf8))
        let audit = document.audit()

        XCTAssertEqual(document.samples.count, 2)
        XCTAssertFalse(audit.isReadyForImageLoading)
        XCTAssertEqual(audit.coveredLanguages, [.chinese, .english])
        XCTAssertEqual(audit.missingLanguages, [.mixed])
        XCTAssertTrue(audit.privacySafeSummaryLines.contains { $0.contains("至少需要 5 张测试图片") })
        XCTAssertTrue(audit.privacySafeSummaryLines.contains { $0.contains("缺少查询语言覆盖") && $0.contains("中英文混合") })
        XCTAssertFalse(audit.privacySafeSummaryLines.joined(separator: "\n").contains("private-asset-id"))
    }

    func testEmbeddingValidationSampleDescriptorDocumentDecodesWrappedSamplesAndRejectsPrivateIDLeaks() throws {
        let json = """
        {
          "samples": [
            {
              "sampleID": "zh-1",
              "assetLocalIdentifier": "private-asset-id-1",
              "relatedQuery": "海边夕阳",
              "unrelatedQuery": "无关文档",
              "language": "chinese"
            },
            {
              "sampleID": "en-1",
              "assetLocalIdentifier": "private-asset-id-2",
              "relatedQuery": "beach sunset",
              "unrelatedQuery": "invoice screenshot",
              "language": "english"
            },
            {
              "sampleID": "mix-1",
              "assetLocalIdentifier": "private-asset-id-3",
              "relatedQuery": "海边 sunset",
              "unrelatedQuery": "invoice screenshot",
              "language": "mixed"
            },
            {
              "sampleID": "zh-2",
              "assetLocalIdentifier": "private-asset-id-4",
              "relatedQuery": "黑色猫",
              "unrelatedQuery": "无关文档",
              "language": "chinese"
            },
            {
              "sampleID": "zh-3",
              "assetLocalIdentifier": "private-asset-id-5",
              "relatedQuery": "餐厅食物",
              "unrelatedQuery": "无关文档",
              "language": "chinese"
            }
          ]
        }
        """

        let document = try EmbeddingValidationSampleDescriptorDocument.decode(from: Data(json.utf8))
        let audit = document.audit()
        let summary = audit.privacySafeSummaryLines.joined(separator: "\n")

        XCTAssertEqual(document.samples.count, 5)
        XCTAssertTrue(audit.isReadyForImageLoading)
        XCTAssertEqual(audit.missingLanguages, [])
        XCTAssertTrue(summary.contains("验证状态：可读取图片"))
        XCTAssertFalse(summary.contains("private-asset-id"))
    }

    func testEmbeddingValidationSampleDescriptorDocumentFlagsDuplicatesWithoutAssetID() {
        let document = EmbeddingValidationSampleDescriptorDocument(samples: [
            EmbeddingValidationSampleDescriptor(
                sampleID: "zh-1",
                assetLocalIdentifier: "private-asset-id-1",
                relatedQuery: "海边夕阳",
                unrelatedQuery: "无关文档",
                language: .chinese
            ),
            EmbeddingValidationSampleDescriptor(
                sampleID: "zh-1",
                assetLocalIdentifier: "private-asset-id-2",
                relatedQuery: "黑色猫",
                unrelatedQuery: "无关文档",
                language: .chinese
            )
        ])

        let audit = document.audit(requiredSampleCount: 1, requiredLanguages: [.chinese])
        let summary = audit.privacySafeSummaryLines.joined(separator: "\n")

        XCTAssertFalse(audit.isReadyForImageLoading)
        XCTAssertTrue(summary.contains("样本 ID 重复"))
        XCTAssertFalse(summary.contains("private-asset-id"))
    }

    func testEmbeddingValidationPreflightCombinesModelReadinessAndSampleAuditWithoutPrivateIDs() {
        let document = EmbeddingValidationSampleDescriptorDocument(samples: [
            EmbeddingValidationSampleDescriptor(
                sampleID: "zh-1",
                assetLocalIdentifier: "private-asset-id-1",
                relatedQuery: "海边夕阳",
                unrelatedQuery: "无关文档",
                language: .chinese
            )
        ])
        let report = EmbeddingValidationPreflightReport(
            modelReadinessReport: EmbeddingService().modelReadinessReport(),
            sampleAudit: document.audit()
        )

        XCTAssertFalse(report.canLoadSamples)
        XCTAssertTrue(report.summaryLines.contains("预检状态：需要先修正模型或样本描述"))
        XCTAssertTrue(report.summaryLines.contains { $0.contains("模型状态：未就绪") })
        XCTAssertTrue(report.nextAction.contains("请先补齐"))
        XCTAssertTrue(report.markdownReport.contains("# 本地图文向量技术验证预检报告"))
        XCTAssertTrue(report.markdownReport.contains("样本数量：1"))
        XCTAssertTrue(report.markdownReport.contains("缺失语言"))
        XCTAssertFalse(report.summaryLines.joined(separator: "\n").contains("private-asset-id"))
        XCTAssertFalse(report.markdownReport.contains("private-asset-id"))
    }

    func testEmbeddingValidationPreflightAllowsSampleLoadingWhenModelAndSamplesAreReady() {
        let descriptors = [
            EmbeddingValidationSampleDescriptor(sampleID: "zh-1", assetLocalIdentifier: "private-asset-id-1", relatedQuery: "海边夕阳", unrelatedQuery: "无关文档", language: .chinese),
            EmbeddingValidationSampleDescriptor(sampleID: "en-1", assetLocalIdentifier: "private-asset-id-2", relatedQuery: "beach sunset", unrelatedQuery: "无关文档", language: .english),
            EmbeddingValidationSampleDescriptor(sampleID: "mix-1", assetLocalIdentifier: "private-asset-id-3", relatedQuery: "海边 sunset", unrelatedQuery: "无关文档", language: .mixed),
            EmbeddingValidationSampleDescriptor(sampleID: "zh-2", assetLocalIdentifier: "private-asset-id-4", relatedQuery: "餐厅食物", unrelatedQuery: "无关文档", language: .chinese),
            EmbeddingValidationSampleDescriptor(sampleID: "en-2", assetLocalIdentifier: "private-asset-id-5", relatedQuery: "product photo", unrelatedQuery: "无关文档", language: .english)
        ]
        let validationService = ValidationEmbeddingService(
            imageVector: EmbeddingVector(values: [1, 0]),
            textVectors: [:]
        )
        let report = EmbeddingValidationPreflightReport(
            modelReadinessReport: validationService.modelReadinessReport(),
            sampleAudit: EmbeddingValidationSampleDescriptorDocument(samples: descriptors).audit()
        )

        XCTAssertTrue(report.canLoadSamples)
        XCTAssertEqual(report.nextAction, "可以通过 PhotoKit 在本机读取样本图片，并运行 EmbeddingValidationService 生成技术验证报告。")
        XCTAssertTrue(report.markdownReport.contains("- 预检状态：可继续"))
        XCTAssertTrue(report.markdownReport.contains("- 缺失语言：无"))
        XCTAssertFalse(report.markdownReport.contains("private-asset-id"))
    }

    func testEmbeddingValidationPreflightWithEmptySampleDocumentRequiresRealSamples() {
        let validationService = ValidationEmbeddingService(
            imageVector: EmbeddingVector(values: [1, 0]),
            textVectors: [:]
        )
        let report = EmbeddingValidationPreflightReport(
            modelReadinessReport: validationService.modelReadinessReport(),
            sampleAudit: EmbeddingValidationSampleDescriptorDocument.empty.audit()
        )
        let summary = report.summaryLines.joined(separator: "\n")

        XCTAssertFalse(report.canLoadSamples)
        XCTAssertTrue(summary.contains("模型状态：就绪"))
        XCTAssertTrue(summary.contains("样本诊断：样本数量：0"))
        XCTAssertTrue(summary.contains("至少需要 5 张测试图片"))
        XCTAssertEqual(report.nextAction, "请修正样本描述文件，确保至少 5 张样本并覆盖中文、英文和中英文混合查询。")
        XCTAssertFalse(summary.contains("private-asset-id"))
        XCTAssertFalse(report.markdownReport.contains("private-asset-id"))
    }

    func testBundledEmbeddingValidationSampleAuditReportsMissingResourceSafely() throws {
        let bundle = try makeTemporaryResourceBundle(resources: [:])

        let audit = EmbeddingValidationSampleDescriptorDocument.bundledAudit(bundle: bundle)
        let summary = audit.privacySafeSummaryLines.joined(separator: "\n")

        XCTAssertFalse(audit.isReadyForImageLoading)
        XCTAssertTrue(summary.contains("App bundle 中未找到 EmbeddingValidationSamples.json"))
        XCTAssertTrue(summary.contains("至少需要 5 张测试图片"))
        XCTAssertFalse(summary.contains("assetLocalIdentifier"))
        XCTAssertFalse(summary.contains("private-asset-id"))
    }

    func testBundledEmbeddingValidationSampleAuditLoadsValidSampleResource() throws {
        let json = """
        {
          "samples": [
            { "sampleID": "zh-1", "assetLocalIdentifier": "private-asset-id-1", "relatedQuery": "海边夕阳", "unrelatedQuery": "无关文档", "language": "chinese" },
            { "sampleID": "en-1", "assetLocalIdentifier": "private-asset-id-2", "relatedQuery": "beach sunset", "unrelatedQuery": "unrelated document", "language": "english" },
            { "sampleID": "mix-1", "assetLocalIdentifier": "private-asset-id-3", "relatedQuery": "海边 sunset", "unrelatedQuery": "无关文档", "language": "mixed" },
            { "sampleID": "zh-2", "assetLocalIdentifier": "private-asset-id-4", "relatedQuery": "餐厅食物", "unrelatedQuery": "无关文档", "language": "chinese" },
            { "sampleID": "en-2", "assetLocalIdentifier": "private-asset-id-5", "relatedQuery": "product photo", "unrelatedQuery": "unrelated document", "language": "english" }
          ]
        }
        """
        let bundle = try makeTemporaryResourceBundle(resources: [
            EmbeddingValidationSampleDescriptorDocument.bundledResourceName: json
        ])

        let audit = EmbeddingValidationSampleDescriptorDocument.bundledAudit(bundle: bundle)
        let summary = audit.privacySafeSummaryLines.joined(separator: "\n")

        XCTAssertTrue(audit.isReadyForImageLoading)
        XCTAssertEqual(audit.sampleCount, 5)
        XCTAssertTrue(summary.contains("缺失语言：无"))
        XCTAssertFalse(summary.contains("private-asset-id"))
    }

    func testBundledEmbeddingValidationSampleResultKeepsDocumentForRuntimeValidation() throws {
        let json = """
        [
          { "sampleID": "zh-1", "assetLocalIdentifier": "private-asset-id-1", "relatedQuery": "海边夕阳", "unrelatedQuery": "无关文档", "language": "chinese" },
          { "sampleID": "en-1", "assetLocalIdentifier": "private-asset-id-2", "relatedQuery": "beach sunset", "unrelatedQuery": "unrelated document", "language": "english" },
          { "sampleID": "mix-1", "assetLocalIdentifier": "private-asset-id-3", "relatedQuery": "海边 sunset", "unrelatedQuery": "无关文档", "language": "mixed" },
          { "sampleID": "zh-2", "assetLocalIdentifier": "private-asset-id-4", "relatedQuery": "餐厅食物", "unrelatedQuery": "无关文档", "language": "chinese" },
          { "sampleID": "en-2", "assetLocalIdentifier": "private-asset-id-5", "relatedQuery": "product photo", "unrelatedQuery": "unrelated document", "language": "english" }
        ]
        """
        let bundle = try makeTemporaryResourceBundle(resources: [
            EmbeddingValidationSampleDescriptorDocument.bundledResourceName: json
        ])

        let result = EmbeddingValidationSampleDescriptorDocument.bundled(bundle: bundle)
        let summary = result.audit.privacySafeSummaryLines.joined(separator: "\n")

        XCTAssertEqual(result.document.samples.map(\.sampleID), ["zh-1", "en-1", "mix-1", "zh-2", "en-2"])
        XCTAssertTrue(result.audit.isReadyForImageLoading)
        XCTAssertFalse(summary.contains("private-asset-id"))
    }

    func testBundledEmbeddingValidationSampleAuditHandlesInvalidJSONWithoutLeakingPrivateIDs() throws {
        let invalidJSON = """
        { "samples": [ { "assetLocalIdentifier": "private-asset-id-1", "language": "unknown" } ] }
        """
        let bundle = try makeTemporaryResourceBundle(resources: [
            EmbeddingValidationSampleDescriptorDocument.bundledResourceName: invalidJSON
        ])

        let audit = EmbeddingValidationSampleDescriptorDocument.bundledAudit(bundle: bundle)
        let summary = audit.privacySafeSummaryLines.joined(separator: "\n")

        XCTAssertFalse(audit.isReadyForImageLoading)
        XCTAssertTrue(summary.contains("无法解析 App bundle 中的 EmbeddingValidationSamples.json"))
        XCTAssertFalse(summary.contains("private-asset-id"))
        XCTAssertFalse(summary.contains("unknown"))
    }

    func testEmbeddingValidationSampleLoaderBuildsSamplesWithoutExposingAssetIDs() async throws {
        let image = try makeTestCGImage()
        let descriptors = [
            EmbeddingValidationSampleDescriptor(
                sampleID: "zh-1",
                assetLocalIdentifier: "private-asset-id-1",
                relatedQuery: "海边夕阳",
                unrelatedQuery: "无关文档",
                language: .chinese
            ),
            EmbeddingValidationSampleDescriptor(
                sampleID: "missing-1",
                assetLocalIdentifier: "private-asset-id-2",
                relatedQuery: "城市夜景",
                unrelatedQuery: "无关文档",
                language: .chinese
            )
        ]

        let result = await EmbeddingValidationSampleLoader.loadSamples(from: descriptors) { localIdentifier in
            localIdentifier == "private-asset-id-1"
                ? .success(image)
                : .failure("测试图片不可用")
        }

        XCTAssertEqual(result.samples.count, 1)
        XCTAssertEqual(result.samples.first?.id, "zh-1")
        XCTAssertEqual(result.samples.first?.relatedQuery, "海边夕阳")
        XCTAssertEqual(result.issues, [
            EmbeddingValidationSampleLoadIssue(sampleID: "missing-1", reason: "测试图片不可用")
        ])
        XCTAssertFalse(result.isReadyForValidation)
        XCTAssertFalse(result.samples.contains { $0.id.contains("private-asset-id") })
    }

    func testEmbeddingValidationChecksDimensionsAndSimilarity() async throws {
        let service = EmbeddingValidationService(
            embeddingService: ValidationEmbeddingService(
                imageVector: EmbeddingVector(values: [1, 0]),
                textVectors: [
                    "海边夕阳": EmbeddingVector(values: [1, 0]),
                    "beach sunset": EmbeddingVector(values: [1, 0]),
                    "海边 sunset": EmbeddingVector(values: [1, 0]),
                    "黑色猫": EmbeddingVector(values: [1, 0]),
                    "餐厅食物": EmbeddingVector(values: [1, 0]),
                    "无关文档": EmbeddingVector(values: [0, 1])
                ]
            )
        )
        let image = try makeTestCGImage()
        let samples = [
            EmbeddingValidationSample(id: "zh-1", image: image, relatedQuery: "海边夕阳", unrelatedQuery: "无关文档", language: .chinese),
            EmbeddingValidationSample(id: "en-1", image: image, relatedQuery: "beach sunset", unrelatedQuery: "无关文档", language: .english),
            EmbeddingValidationSample(id: "mix-1", image: image, relatedQuery: "海边 sunset", unrelatedQuery: "无关文档", language: .mixed),
            EmbeddingValidationSample(id: "zh-2", image: image, relatedQuery: "黑色猫", unrelatedQuery: "无关文档", language: .chinese),
            EmbeddingValidationSample(id: "zh-3", image: image, relatedQuery: "餐厅食物", unrelatedQuery: "无关文档", language: .chinese)
        ]

        let report = await service.validate(samples: samples)

        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.caseResults.count, 5)
        XCTAssertEqual(Set(report.caseResults.compactMap(\.language)), [.chinese, .english, .mixed])
        XCTAssertTrue(report.caseResults.allSatisfy { ($0.relatedScore ?? 0) > ($0.unrelatedScore ?? 1) })
        XCTAssertTrue(report.summaryLines.contains("模型版本：validation-mock"))
        XCTAssertTrue(report.summaryLines.contains("验证状态：通过"))
        XCTAssertTrue(report.summaryLines.contains { $0.contains("语言覆盖：") && $0.contains("中文") && $0.contains("英文") && $0.contains("中英文混合") })
        XCTAssertTrue(report.summaryLines.contains("缺失语言：无"))
        XCTAssertTrue(report.summaryLines.contains("最小相似度差距：0.0500"))
        XCTAssertTrue(report.summaryLines.contains { $0.contains("zh-1：通过") && $0.contains("相关 1.0000") && $0.contains("无关 0.0000") && $0.contains("差距 1.0000") && $0.contains("耗时") })
        XCTAssertTrue(report.summaryLines.contains("接入清单：模型版本：validation-mock"))
        XCTAssertTrue(report.summaryLines.contains("就绪诊断：状态：模型资源和配置已就绪。"))
        XCTAssertTrue(report.caseResults.allSatisfy { ($0.scoreGap ?? 0) > report.requiredSimilarityMargin })
        XCTAssertTrue(report.averageSampleDurationSeconds >= 0)
        XCTAssertTrue(report.caseResults.allSatisfy { $0.totalDurationSeconds != nil })
        XCTAssertTrue(report.caseResults.allSatisfy { $0.imageEncodingDurationSeconds != nil })
        XCTAssertTrue(report.caseResults.allSatisfy { $0.relatedTextEncodingDurationSeconds != nil })
        XCTAssertTrue(report.caseResults.allSatisfy { $0.unrelatedTextEncodingDurationSeconds != nil })
        XCTAssertTrue(report.markdownReport.contains("# 本地图文向量技术验证报告"))
        XCTAssertTrue(report.markdownReport.contains("- 模型版本：validation-mock"))
        XCTAssertTrue(report.markdownReport.contains("- 最小相似度差距：0.0500"))
        XCTAssertTrue(report.markdownReport.contains("- 平均单样本耗时："))
        XCTAssertTrue(report.markdownReport.contains("## 模型接入清单"))
        XCTAssertTrue(report.markdownReport.contains("- 图片模型：ValidationImage.mlmodelc，1.00 MB"))
        XCTAssertTrue(report.markdownReport.contains("## 模型就绪诊断"))
        XCTAssertTrue(report.markdownReport.contains("- 状态：模型资源和配置已就绪。"))
        XCTAssertTrue(report.markdownReport.contains("| 样本 | 语言 | 图片维度 | 文本维度 | 相关分数 | 无关分数 | 相似度差距 | 图片耗时 | 相关文本耗时 | 无关文本耗时 | 总耗时 | 状态 | 失败原因 |"))
        XCTAssertTrue(report.markdownReport.contains("| zh-1 | 中文 | 2 | 2 | 1.0000 | 0.0000 | 1.0000 |"))
        XCTAssertTrue(report.markdownReport.contains("秒 | 通过 | 无 |"))
        XCTAssertTrue(report.markdownReport.contains("- 结论：当前样本通过技术验证。"))
        XCTAssertTrue(report.markdownReport.contains("- 隐私：验证过程应在本机运行，不上传图片、OCR 文本或向量。"))
    }

    func testEmbeddingValidationGateRequiresPassedCurrentModelReport() {
        let passedReport = makeEmbeddingValidationReport(
            modelVersion: "model-v1",
            passed: true
        )
        let failedReport = makeEmbeddingValidationReport(
            modelVersion: "model-v1",
            passed: false
        )

        let missingGate = EmbeddingValidationGate.evaluate(
            report: nil,
            currentModelVersion: "model-v1"
        )
        let outdatedGate = EmbeddingValidationGate.evaluate(
            report: passedReport,
            currentModelVersion: "model-v2"
        )
        let failedGate = EmbeddingValidationGate.evaluate(
            report: failedReport,
            currentModelVersion: "model-v1"
        )
        let passedGate = EmbeddingValidationGate.evaluate(
            report: passedReport,
            currentModelVersion: "model-v1"
        )
        let summaryGate = EmbeddingValidationGate.evaluate(
            report: nil,
            summary: EmbeddingValidationSummary(report: passedReport),
            currentModelVersion: "model-v1"
        )

        XCTAssertFalse(missingGate.canUseVisualEmbedding)
        XCTAssertTrue(missingGate.recoveryMessage.contains("请先运行本地图文向量技术验证"))
        XCTAssertFalse(outdatedGate.canUseVisualEmbedding)
        XCTAssertTrue(outdatedGate.recoveryMessage.contains("当前模型版本为 model-v2"))
        XCTAssertFalse(failedGate.canUseVisualEmbedding)
        XCTAssertTrue(failedGate.recoveryMessage.contains("技术验证未通过"))
        XCTAssertTrue(passedGate.canUseVisualEmbedding)
        XCTAssertTrue(summaryGate.canUseVisualEmbedding)
    }

    func testEmbeddingValidationRequiresLanguageCoverage() async throws {
        let service = EmbeddingValidationService(
            embeddingService: ValidationEmbeddingService(
                imageVector: EmbeddingVector(values: [1, 0]),
                textVectors: [
                    "海边夕阳": EmbeddingVector(values: [1, 0]),
                    "黑色猫": EmbeddingVector(values: [1, 0]),
                    "餐厅食物": EmbeddingVector(values: [1, 0]),
                    "城市夜景": EmbeddingVector(values: [1, 0]),
                    "产品照片": EmbeddingVector(values: [1, 0]),
                    "无关文档": EmbeddingVector(values: [0, 1])
                ]
            )
        )
        let image = try makeTestCGImage()
        let samples = [
            EmbeddingValidationSample(id: "zh-1", image: image, relatedQuery: "海边夕阳", unrelatedQuery: "无关文档", language: .chinese),
            EmbeddingValidationSample(id: "zh-2", image: image, relatedQuery: "黑色猫", unrelatedQuery: "无关文档", language: .chinese),
            EmbeddingValidationSample(id: "zh-3", image: image, relatedQuery: "餐厅食物", unrelatedQuery: "无关文档", language: .chinese),
            EmbeddingValidationSample(id: "zh-4", image: image, relatedQuery: "城市夜景", unrelatedQuery: "无关文档", language: .chinese),
            EmbeddingValidationSample(id: "zh-5", image: image, relatedQuery: "产品照片", unrelatedQuery: "无关文档", language: .chinese)
        ]

        let report = await service.validate(samples: samples)

        XCTAssertFalse(report.passed)
        XCTAssertEqual(report.coveredLanguages, [.chinese])
        XCTAssertEqual(report.missingLanguages, [.english, .mixed])
        XCTAssertTrue(report.failureReasons.contains { $0.contains("查询语言覆盖") })
        XCTAssertTrue(report.summaryLines.contains("验证状态：未通过"))
        XCTAssertTrue(report.summaryLines.contains { $0.contains("缺失语言：") && $0.contains("英文") && $0.contains("中英文混合") })
        XCTAssertTrue(report.markdownReport.contains("- 结论：当前样本未通过技术验证，不能标记视觉语义搜索完成。"))
        XCTAssertTrue(report.markdownReport.contains("失败原因：技术验证样本缺少查询语言覆盖"))
    }

    func testEmbeddingValidationRequiresSimilarityMargin() async throws {
        let almostRelatedUnrelatedVector = EmbeddingVector(values: [0.98, 0.198997487])
        let service = EmbeddingValidationService(
            embeddingService: ValidationEmbeddingService(
                imageVector: EmbeddingVector(values: [1, 0]),
                textVectors: [
                    "海边夕阳": EmbeddingVector(values: [1, 0]),
                    "beach sunset": EmbeddingVector(values: [1, 0]),
                    "海边 sunset": EmbeddingVector(values: [1, 0]),
                    "黑色猫": EmbeddingVector(values: [1, 0]),
                    "餐厅食物": EmbeddingVector(values: [1, 0]),
                    "无关文档": almostRelatedUnrelatedVector
                ]
            )
        )
        let image = try makeTestCGImage()
        let samples = [
            EmbeddingValidationSample(id: "zh-1", image: image, relatedQuery: "海边夕阳", unrelatedQuery: "无关文档", language: .chinese),
            EmbeddingValidationSample(id: "en-1", image: image, relatedQuery: "beach sunset", unrelatedQuery: "无关文档", language: .english),
            EmbeddingValidationSample(id: "mix-1", image: image, relatedQuery: "海边 sunset", unrelatedQuery: "无关文档", language: .mixed),
            EmbeddingValidationSample(id: "zh-2", image: image, relatedQuery: "黑色猫", unrelatedQuery: "无关文档", language: .chinese),
            EmbeddingValidationSample(id: "zh-3", image: image, relatedQuery: "餐厅食物", unrelatedQuery: "无关文档", language: .chinese)
        ]

        let report = await service.validate(samples: samples, similarityMargin: 0.05)

        XCTAssertFalse(report.passed)
        XCTAssertEqual(report.requiredSimilarityMargin, 0.05)
        XCTAssertTrue(report.caseResults.allSatisfy { ($0.scoreGap ?? 1) < 0.05 })
        XCTAssertTrue(report.failureReasons.allSatisfy { $0.contains("当前差距 0.0200") && $0.contains("需要大于 0.0500") })
        XCTAssertTrue(report.summaryLines.contains("最小相似度差距：0.0500"))
        XCTAssertTrue(report.summaryLines.contains { $0.contains("zh-1：未通过") && $0.contains("差距 0.0200") })
        XCTAssertTrue(report.markdownReport.contains("| zh-1 | 中文 | 2 | 2 | 1.0000 | 0.9800 | 0.0200 |"))
        XCTAssertTrue(report.markdownReport.contains("需要大于 0.0500"))
    }

    func testEmbeddingValidationMarkdownEscapesTableCells() {
        let report = EmbeddingValidationReport(
            modelInfo: EmbeddingModelInfo(
                version: "model|pipe",
                source: "测试模型",
                license: "测试许可证",
                expectedImageModelName: "Image",
                expectedTextModelName: "Text"
            ),
            requiredSampleCount: 1,
            requiredLanguages: [.chinese],
            caseResults: [
                EmbeddingValidationCaseResult(
                    sampleID: "sample|1",
                    language: .chinese,
                    imageDimension: nil,
                    textDimension: nil,
                    relatedScore: nil,
                    unrelatedScore: nil,
                    passed: false,
                    failureReason: "相关|无关 分数不足"
                )
            ]
        )

        XCTAssertTrue(report.markdownReport.contains("| sample\\|1 | 中文 | 未生成 | 未生成 | 未生成 | 未生成 | 未生成 | 未记录 | 未记录 | 未记录 | 未记录 | 未通过 | 相关\\|无关 分数不足 |"))
        XCTAssertTrue(report.markdownReport.contains("失败原因：相关\\|无关 分数不足"))
    }

    func testEmbeddingValidationReportStoreWritesMarkdownWithoutPrivateAssetID() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Reports", isDirectory: true)
        let report = EmbeddingValidationReport(
            modelInfo: EmbeddingModelInfo(
                version: "validation-model",
                source: "测试模型",
                license: "测试许可证",
                expectedImageModelName: "Image",
                expectedTextModelName: "Text"
            ),
            requiredSampleCount: 1,
            requiredLanguages: [.chinese],
            caseResults: [
                EmbeddingValidationCaseResult(
                    sampleID: "zh-1",
                    language: .chinese,
                    imageDimension: 2,
                    textDimension: 2,
                    relatedScore: 0.9,
                    unrelatedScore: 0.1,
                    passed: true,
                    failureReason: nil,
                    totalDurationSeconds: 0.25
                )
            ]
        )

        let fileURL = try EmbeddingValidationReportStore.save(
            report: report,
            directoryURL: directoryURL
        )
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let summaryURL = directoryURL.appendingPathComponent(EmbeddingValidationReportStore.defaultSummaryFileName)
        let summaryContents = try String(contentsOf: summaryURL, encoding: .utf8)
        let summary = try XCTUnwrap(EmbeddingValidationReportStore.loadSummary(directoryURL: directoryURL))

        XCTAssertEqual(fileURL.lastPathComponent, EmbeddingValidationReportStore.defaultFileName)
        XCTAssertTrue(contents.contains("# 本地图文向量技术验证报告"))
        XCTAssertTrue(contents.contains("- 模型版本：validation-model"))
        XCTAssertTrue(contents.contains("- 结论：当前样本通过技术验证。"))
        XCTAssertFalse(contents.contains("private-asset-id"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: summaryURL.path))
        XCTAssertEqual(summary.modelVersion, "validation-model")
        XCTAssertTrue(summary.passed)
        XCTAssertEqual(summary.sampleCount, 1)
        XCTAssertEqual(summary.coveredLanguages, [.chinese])
        XCTAssertFalse(summaryContents.contains("private-asset-id"))

        try? FileManager.default.removeItem(at: directoryURL.deletingLastPathComponent())
    }

    private func makeTestCGImage() throws -> CGImage {
        let data = [UInt8](repeating: 255, count: 4)
        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let image = CGImage(
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw NSError(domain: "PictureSearchTests", code: 1)
        }

        return image
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeEmbeddingValidationReport(
        modelVersion: String,
        passed: Bool
    ) -> EmbeddingValidationReport {
        let languages: [EmbeddingQueryLanguage] = [.chinese, .english, .mixed]
        let caseResults = languages.enumerated().map { index, language in
            EmbeddingValidationCaseResult(
                sampleID: "gate-\(index)",
                language: language,
                imageDimension: 2,
                textDimension: 2,
                relatedScore: passed ? 1.0 : 0.1,
                unrelatedScore: 0.0,
                passed: passed,
                failureReason: passed ? nil : "测试未通过"
            )
        }

        return EmbeddingValidationReport(
            modelInfo: EmbeddingModelInfo(
                version: modelVersion,
                source: "测试模型",
                license: "MIT",
                expectedImageModelName: "Image",
                expectedTextModelName: "Text"
            ),
            requiredSampleCount: 3,
            requiredLanguages: Set(languages),
            caseResults: caseResults
        )
    }

    private func makeTemporaryResourceBundle(resources: [String: String]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bundle")
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>com.local.PictureSearchTests.\(UUID().uuidString)</string>
          <key>CFBundlePackageType</key>
          <string>BNDL</string>
        </dict>
        </plist>
        """.data(using: .utf8)!
        try infoPlist.write(to: contentsURL.appendingPathComponent("Info.plist"))

        for (name, contents) in resources {
            try contents.data(using: .utf8)?.write(to: resourcesURL.appendingPathComponent(name))
        }

        guard let bundle = Bundle(url: bundleURL) else {
            throw NSError(domain: "PictureSearchTests", code: 2)
        }

        return bundle
    }
}

private struct MockOCRService: OCRServicing {
    let result: OCRRecognitionResult

    func recognizeText(in image: CGImage) async throws -> OCRRecognitionResult {
        result
    }
}

private struct MockEmbeddingService: EmbeddingServicing {
    let modelInfo = EmbeddingModelInfo(
        version: "mock-model",
        source: "测试 mock",
        license: "测试",
        expectedImageModelName: "MockImage",
        expectedTextModelName: "MockText"
    )
    let textVector: EmbeddingVector

    func modelReadinessReport() -> EmbeddingModelReadinessReport {
        EmbeddingModelReadinessReport(
            modelInfo: modelInfo,
            manifestIssue: nil,
            hasImageModel: true,
            hasTextModel: true,
            hasTokenizer: true,
            configurationIssues: []
        )
    }

    func validateModelAvailability() throws {}

    func encodeImage(_ image: CGImage) async throws -> EmbeddingVector {
        EmbeddingVector(values: [1, 0])
    }

    func encodeText(_ text: String) async throws -> EmbeddingVector {
        textVector
    }
}

private struct FailingTextEmbeddingService: EmbeddingServicing {
    let modelInfo = EmbeddingModelInfo(
        version: "failing-text-model",
        source: "测试 mock",
        license: "测试",
        expectedImageModelName: "FailingImage",
        expectedTextModelName: "FailingText"
    )

    func modelReadinessReport() -> EmbeddingModelReadinessReport {
        EmbeddingModelReadinessReport(
            modelInfo: modelInfo,
            manifestIssue: nil,
            hasImageModel: true,
            hasTextModel: true,
            hasTokenizer: true,
            configurationIssues: []
        )
    }

    func validateModelAvailability() throws {}

    func encodeImage(_ image: CGImage) async throws -> EmbeddingVector {
        throw EmbeddingServiceError.imageEncodingFailed("测试不应调用图片编码")
    }

    func encodeText(_ text: String) async throws -> EmbeddingVector {
        throw EmbeddingServiceError.textEncodingFailed("空查询或无效 limit 不应调用文本编码")
    }
}

private struct ValidationEmbeddingService: EmbeddingServicing {
    let modelInfo = EmbeddingModelInfo(
        version: "validation-mock",
        source: "测试 mock",
        license: "测试",
        expectedImageModelName: "ValidationImage",
        expectedTextModelName: "ValidationText"
    )
    let imageVector: EmbeddingVector
    let textVectors: [String: EmbeddingVector]

    func modelReadinessReport() -> EmbeddingModelReadinessReport {
        EmbeddingModelReadinessReport(
            modelInfo: modelInfo,
            integrationChecklistLines: [
                "模型版本：validation-mock",
                "模型来源：测试 mock",
                "许可证：测试",
                "图片模型：ValidationImage.mlmodelc，1.00 MB",
                "文本模型：ValidationText.mlmodelc，1.00 MB",
                "tokenizer：测试 tokenizer，1.00 KB"
            ],
            manifestIssue: nil,
            hasImageModel: true,
            hasTextModel: true,
            hasTokenizer: true,
            configurationIssues: []
        )
    }

    func validateModelAvailability() throws {}

    func encodeImage(_ image: CGImage) async throws -> EmbeddingVector {
        imageVector
    }

    func encodeText(_ text: String) async throws -> EmbeddingVector {
        guard let vector = textVectors[text] else {
            throw EmbeddingServiceError.textEncodingFailed("测试向量不存在")
        }

        return vector
    }
}
