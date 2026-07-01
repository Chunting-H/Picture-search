import AppKit
import Foundation
import Photos

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    @Published private(set) var authorizationState: PhotoLibraryAuthorizationState
    @Published private(set) var assets: [PhotoAssetSummary] = []
    @Published private(set) var thumbnails: [String: PhotoThumbnail] = [:]
    @Published private(set) var loadSummary = PhotoLibraryLoadSummary.empty
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = "尚未读取图库。"
    @Published private(set) var indexSummary = IndexStatusSummary.empty
    @Published private(set) var lastIndexSyncResult = IndexSyncResult.empty
    @Published private(set) var indexStatusMessage = "本地索引尚未初始化。"
    @Published private(set) var ocrPerformanceSummary = OCRPerformanceSummary.empty
    @Published private(set) var ocrStatusMessage = "OCR 尚未开始。"
    @Published private(set) var isProcessingOCR = false
    @Published private(set) var embeddingStatusMessage = "视觉语义模型尚未配置。"
    @Published private(set) var embeddingReadinessReport: EmbeddingModelReadinessReport
    @Published private(set) var embeddingValidationPreflightReport: EmbeddingValidationPreflightReport
    @Published private(set) var embeddingValidationReport: EmbeddingValidationReport?
    @Published private(set) var embeddingValidationSummary: EmbeddingValidationSummary?
    @Published private(set) var embeddingValidationMessage = "技术验证尚未开始。"
    @Published private(set) var isRunningEmbeddingValidation = false
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var searchResultAssets: [PhotoAssetSummary] = []
    @Published private(set) var searchMessage = "输入文字、时间或类型后，可搜索已完成 OCR 的本地索引。"
    @Published var visualSearchQuery = ""
    @Published private(set) var visualSearchResults: [VisualSearchResult] = []
    @Published private(set) var visualSearchMessage = "视觉查询验证尚未开始。"
    @Published private(set) var isRunningVisualSearch = false
    @Published private(set) var isProcessingEmbedding = false
    @Published private(set) var previewAsset: PhotoAssetSummary?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var previewMessage = ""
    @Published private(set) var isLoadingPreview = false
    @Published var selectedScope: PhotoLibraryTimeScope = .lastMonth

    private let service: PhotoLibraryService
    private let ocrService: OCRServicing
    private let embeddingService: EmbeddingServicing
    private let searchService: SearchService
    private let indexStore: IndexStore?
    private let embeddingBatchPolicy: EmbeddingBatchPolicy
    private let embeddingSampleDocument: EmbeddingValidationSampleDescriptorDocument
    private let embeddingSampleAudit: EmbeddingValidationSampleDescriptorAudit
    private var searchDebounceTask: Task<Void, Never>?

    init(
        service: PhotoLibraryService = PhotoLibraryService(),
        ocrService: OCRServicing = OCRService(),
        embeddingService: EmbeddingServicing = EmbeddingService.localPackageOrBundledOrUnconfigured(),
        searchService: SearchService = SearchService(),
        embeddingBatchPolicy: EmbeddingBatchPolicy = .defaultInteractive,
        embeddingSampleBundle: EmbeddingValidationSampleDescriptorBundleResult = EmbeddingValidationSampleDescriptorDocument.bundled(),
        indexStore: IndexStore? = try? IndexStore()
    ) {
        self.service = service
        self.ocrService = ocrService
        self.embeddingService = embeddingService
        self.searchService = searchService
        self.embeddingBatchPolicy = embeddingBatchPolicy
        self.indexStore = indexStore
        self.authorizationState = service.authorizationState()
        let readinessReport = embeddingService.modelReadinessReport()
        self.embeddingReadinessReport = readinessReport
        self.embeddingSampleDocument = embeddingSampleBundle.document
        self.embeddingSampleAudit = embeddingSampleBundle.audit
        self.embeddingValidationPreflightReport = EmbeddingValidationPreflightReport(
            modelReadinessReport: readinessReport,
            sampleAudit: embeddingSampleBundle.audit
        )
        let persistedSummary = EmbeddingValidationReportStore.loadSummary()
        self.embeddingValidationSummary = persistedSummary
        let validationGate = EmbeddingValidationGate.evaluate(
            report: nil,
            summary: persistedSummary,
            currentModelVersion: embeddingService.modelInfo.version
        )
        self.embeddingValidationMessage = validationGate.canUseVisualEmbedding
            ? "已加载本机技术验证摘要：\(persistedSummary?.summaryLine ?? validationGate.recoveryMessage)"
            : (embeddingValidationPreflightReport.canLoadSamples
                ? "技术验证预检通过，可读取样本并运行本地图文向量验证。"
                : embeddingValidationPreflightReport.nextAction)

        refreshIndexSummary()

        if authorizationState.canReadLibrary {
            statusMessage = "已授权，点击刷新可读取\(selectedScope.title)的图片。"
        }
    }

    var displayedAssets: [PhotoAssetSummary] {
        isShowingSearchResults ? searchResultAssets : assets
    }

    var displayedSummary: PhotoLibraryLoadSummary {
        guard isShowingSearchResults else {
            return loadSummary
        }

        let successfulThumbnails = searchResultAssets.filter { thumbnails[$0.id]?.didLoadSuccessfully == true }.count
        let failedThumbnails = searchResultAssets.filter { thumbnails[$0.id]?.failureReason != nil }.count
        return PhotoLibraryLoadSummary(
            totalAssets: searchResultAssets.count,
            successfulThumbnails: successfulThumbnails,
            failedThumbnails: failedThumbnails
        )
    }

    var isShowingSearchResults: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func requestAccessAndLoad() async {
        if authorizationState.canRequestAccess {
            authorizationState = await service.requestAuthorization()
        } else if authorizationState.shouldOpenSettingsForAccessRequest {
            let didOpenSettings = service.openPhotoPrivacySettings()
            statusMessage = didOpenSettings
                ? "已打开系统设置。请为 PictureSearch 开启 Photos 权限，然后回到应用点击“刷新状态”。"
                : "无法自动打开系统设置。请手动进入“隐私与安全性 > 照片”为 PictureSearch 开启权限。"
            return
        } else {
            authorizationState = service.authorizationState()
        }

        guard authorizationState.canReadLibrary else {
            assets = []
            thumbnails = [:]
            loadSummary = .empty
            lastIndexSyncResult = .empty
            statusMessage = authorizationState.message
            return
        }

        await loadRecentAssets()
    }

    func refreshAuthorizationState() {
        authorizationState = service.authorizationState()
        if !authorizationState.canReadLibrary {
            assets = []
            thumbnails = [:]
            loadSummary = .empty
            statusMessage = authorizationState.message
        }
    }

    func loadRecentAssets() async {
        guard authorizationState.canReadLibrary else {
            statusMessage = authorizationState.message
            return
        }

        isLoading = true
        let scope = selectedScope
        statusMessage = "正在读取\(scope.title)的图片..."
        thumbnails = [:]

        let photoAssets = service.fetchImageAssets(in: scope)
        assets = photoAssets.map { service.summary(for: $0) }
        syncIndex(with: assets)
        loadSummary = PhotoLibraryLoadSummary(
            totalAssets: assets.count,
            successfulThumbnails: 0,
            failedThumbnails: 0
        )

        for asset in photoAssets {
            let thumbnail = await service.requestThumbnail(
                for: asset,
                targetSize: CGSize(width: 240, height: 240)
            )

            thumbnails[thumbnail.id] = thumbnail
            if thumbnail.didLoadSuccessfully {
                loadSummary.successfulThumbnails += 1
            } else {
                loadSummary.failedThumbnails += 1
            }
        }

        isLoading = false
        statusMessage = assets.isEmpty ? scope.emptyDescription : "已读取\(scope.title)的 \(assets.count) 张图片。"
    }

    func loadSelectedScope() async {
        await loadRecentAssets()
    }

    func clearLocalIndex() {
        guard let indexStore else {
            indexStatusMessage = "本地索引不可用，无法清除。"
            return
        }

        do {
            try indexStore.clearAll()
            indexSummary = .empty
            ocrPerformanceSummary = .empty
            lastIndexSyncResult = .empty
            indexStatusMessage = "已清除本地索引。Photos 原图不会被修改或删除。"
            ocrStatusMessage = "OCR 状态已随本地索引清除。"
            embeddingStatusMessage = "视觉语义索引已随本地索引清除。"
        } catch {
            indexStatusMessage = "清除本地索引失败：\(error.localizedDescription)"
        }
    }

    func processPendingOCR() {
        startOCRProcessing(includeFailed: false)
    }

    func retryFailedOCR() {
        startOCRProcessing(includeFailed: true)
    }

    func processPendingEmbeddings() {
        startEmbeddingProcessing(includeFailed: true)
    }

    func retryFailedEmbeddings() {
        startEmbeddingProcessing(includeFailed: true)
    }

    func runNaturalLanguageSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchResultAssets = []
            searchMessage = "请输入文字、时间或类型后再搜索。"
            return
        }

        guard let indexStore else {
            searchResults = []
            searchResultAssets = []
            searchMessage = "本地索引不可用，无法搜索。"
            return
        }

        let searchService = searchService
        let embeddingService = embeddingService
        let canUseVisual = embeddingReadinessReport.isReady && indexSummary.embeddingReady > 0
        searchResults = []
        searchResultAssets = []
        searchMessage = canUseVisual ? "正在融合 OCR、视觉、时间和类型信号..." : "正在搜索 OCR、时间和类型索引..."

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let results: [SearchResult]
                if canUseVisual {
                    results = try await searchService.multiSignalSearch(
                        query: query,
                        indexStore: indexStore,
                        embeddingService: embeddingService,
                        limit: 5
                    )
                } else {
                    results = try searchService.search(query: query, indexStore: indexStore, limit: 5)
                }
                await self?.finishNaturalLanguageSearch(
                    results: results,
                    usedVisualSignal: canUseVisual
                )
            } catch {
                await self?.finishNaturalLanguageSearch(
                    results: [],
                    usedVisualSignal: false,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    func searchQueryDidChange() {
        searchDebounceTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            clearSearchResults()
            return
        }

        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }
            self?.runNaturalLanguageSearch()
        }
    }

    func clearSearchResults() {
        searchDebounceTask?.cancel()
        searchQuery = ""
        searchResults = []
        searchResultAssets = []
        searchMessage = "已退出搜索结果，右侧恢复当前读取范围。"
    }

    func openPreview(for asset: PhotoAssetSummary) {
        previewAsset = asset
        previewImage = thumbnails[asset.id]?.image
        previewMessage = previewImage == nil ? "正在读取大图预览..." : ""
        isLoadingPreview = true

        guard let photoAsset = service.fetchImageAsset(localIdentifier: asset.id) else {
            isLoadingPreview = false
            previewMessage = "Photos 中未找到该图片，可能已被删除或授权范围已变化。"
            return
        }

        let service = service
        Task {
            let preview = await service.requestPreviewImage(for: photoAsset)
            guard self.previewAsset?.id == asset.id else {
                return
            }

            self.previewImage = preview.image
            self.previewMessage = preview.failureReason ?? ""
            self.isLoadingPreview = false
        }
    }

    func closePreview() {
        previewAsset = nil
        previewImage = nil
        previewMessage = ""
        isLoadingPreview = false
    }

    func runEmbeddingValidation() {
        guard !isRunningEmbeddingValidation else {
            embeddingValidationMessage = "技术验证正在运行，请等待当前任务完成。"
            return
        }

        guard authorizationState.canReadLibrary else {
            embeddingValidationMessage = "需要 Photos 权限后才能通过 PhotoKit 读取验证样本。"
            return
        }

        refreshEmbeddingValidationPreflight()
        guard embeddingValidationPreflightReport.canLoadSamples else {
            embeddingValidationMessage = embeddingValidationPreflightReport.nextAction
            return
        }

        let descriptors = embeddingSampleDocument.samples
        guard !descriptors.isEmpty else {
            embeddingValidationMessage = "技术验证样本为空，请先将真实样本描述文件加入 App bundle。"
            return
        }

        let service = service
        let validationService = EmbeddingValidationService(embeddingService: embeddingService)
        isRunningEmbeddingValidation = true
        embeddingValidationReport = nil
        embeddingValidationSummary = nil
        embeddingValidationMessage = "正在通过 PhotoKit 读取样本并运行本地图文向量技术验证..."

        Task.detached(priority: .utility) { [weak self] in
            let sampleLoadResult = await service.loadEmbeddingValidationSamples(from: descriptors)
            guard sampleLoadResult.isReadyForValidation else {
                let issueText = sampleLoadResult.issues
                    .map { "\($0.sampleID)：\($0.reason)" }
                    .joined(separator: "；")
                await self?.finishEmbeddingValidation(
                    report: nil,
                    message: issueText.isEmpty
                        ? "技术验证样本读取失败：未读取到可验证图片。"
                        : "技术验证样本读取失败：\(issueText)"
                )
                return
            }

            let report = await validationService.validate(samples: sampleLoadResult.samples)
            let reportLocationMessage: String
            do {
                let reportURL = try EmbeddingValidationReportStore.save(report: report)
                reportLocationMessage = "报告已保存到本机：\(reportURL.path)"
            } catch {
                reportLocationMessage = "报告保存失败：\(error.localizedDescription)"
            }

            await self?.finishEmbeddingValidation(
                report: report,
                message: report.passed
                    ? "本地图文向量技术验证通过。\(reportLocationMessage)"
                    : "本地图文向量技术验证未通过，请查看样本结果和失败原因。\(reportLocationMessage)"
            )
        }
    }

    func runVisualSearch() {
        let query = visualSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            visualSearchResults = []
            visualSearchMessage = "请输入画面描述后再运行视觉查询。"
            return
        }

        guard !isRunningVisualSearch else {
            visualSearchMessage = "视觉查询正在运行，请等待当前任务完成。"
            return
        }

        guard authorizationState.canReadLibrary else {
            visualSearchResults = []
            visualSearchMessage = "需要 Photos 权限后才能验证视觉查询结果。"
            return
        }

        guard let indexStore else {
            visualSearchResults = []
            visualSearchMessage = "本地索引不可用，无法执行视觉查询。"
            return
        }

        refreshEmbeddingValidationPreflight()
        guard embeddingReadinessReport.isReady else {
            visualSearchResults = []
            visualSearchMessage = "视觉模型未就绪，无法把查询文本生成向量。\(embeddingReadinessReport.recoveryMessage)"
            return
        }

        let validationGate = EmbeddingValidationGate.evaluate(
            report: embeddingValidationReport,
            summary: embeddingValidationSummary,
            currentModelVersion: embeddingService.modelInfo.version
        )
        guard validationGate.canUseVisualEmbedding else {
            visualSearchResults = []
            visualSearchMessage = "视觉查询需要先通过当前模型版本的技术验证。\(validationGate.recoveryMessage)"
            return
        }

        guard indexSummary.embeddingReady > 0 else {
            visualSearchResults = []
            visualSearchMessage = "当前没有 ready 的视觉向量。请先完成视觉索引。"
            return
        }

        let searchService = searchService
        let embeddingService = embeddingService
        isRunningVisualSearch = true
        visualSearchResults = []
        visualSearchMessage = "正在本机生成查询向量并检索已索引图片..."

        Task.detached(priority: .utility) { [weak self] in
            do {
                let results = try await searchService.visualSearch(
                    query: query,
                    indexStore: indexStore,
                    embeddingService: embeddingService,
                    limit: 10
                )
                await self?.finishVisualSearch(
                    results: results,
                    message: results.isEmpty
                        ? "没有找到视觉相似结果。可能是视觉索引尚未完成，或当前查询与已索引图片相关性较低。"
                        : "已返回 \(results.count) 条视觉相似候选。结果仅来自本地图片向量和文本查询向量。"
                )
            } catch {
                await self?.finishVisualSearch(
                    results: [],
                    message: "视觉查询失败：\(error.localizedDescription)"
                )
            }
        }
    }

    private func syncIndex(with assetSummaries: [PhotoAssetSummary]) {
        guard let indexStore else {
            indexSummary = .empty
            lastIndexSyncResult = .empty
            indexStatusMessage = "本地索引不可用，请重启应用或检查磁盘权限。"
            return
        }

        do {
            lastIndexSyncResult = try indexStore.upsertAssetSummaries(assetSummaries)
            refreshIndexSummary()
            indexStatusMessage = "已同步所选范围内资产到本地索引。OCR 任务可在本地后台处理，向量任务保持 pending。"
        } catch {
            indexStatusMessage = "同步本地索引失败：\(error.localizedDescription)"
        }
    }

    private func loadMissingSearchResultThumbnails(for summaries: [PhotoAssetSummary]) {
        let missingAssets = summaries.filter { thumbnails[$0.id] == nil }
        guard !missingAssets.isEmpty else {
            return
        }

        let service = service
        Task {
            for summary in missingAssets {
                guard let asset = service.fetchImageAsset(localIdentifier: summary.id) else {
                    thumbnails[summary.id] = PhotoThumbnail(
                        id: summary.id,
                        image: nil,
                        failureReason: "Photos 中未找到该搜索结果图片。"
                    )
                    continue
                }

                let thumbnail = await service.requestThumbnail(
                    for: asset,
                    targetSize: CGSize(width: 360, height: 360)
                )
                thumbnails[thumbnail.id] = thumbnail
            }
        }
    }

    private func startOCRProcessing(includeFailed: Bool) {
        guard !isProcessingOCR else {
            ocrStatusMessage = "OCR 正在处理中，请等待当前任务完成。"
            return
        }

        guard authorizationState.canReadLibrary else {
            ocrStatusMessage = "需要 Photos 权限后才能执行 OCR。"
            return
        }

        guard let indexStore else {
            ocrStatusMessage = "本地索引不可用，无法执行 OCR。"
            return
        }

        let service = service
        let ocrService = ocrService
        isProcessingOCR = true
        ocrStatusMessage = includeFailed ? "正在准备重试失败 OCR 任务..." : "正在准备 OCR 任务..."

        Task.detached(priority: .utility) { [weak self] in
            do {
                let candidates = try indexStore.fetchOCRCandidates(includeFailed: includeFailed)
                guard !candidates.isEmpty else {
                    await self?.finishOCRProcessing(
                        message: includeFailed
                            ? "没有 pending 或 failed 的 OCR 任务需要处理。"
                            : "没有 pending 的 OCR 任务需要处理。"
                    )
                    return
                }

                for (index, record) in candidates.enumerated() {
                    let progressText = "\(index + 1)/\(candidates.count)"
                    do {
                        try indexStore.markOCRProcessing(assetLocalIdentifier: record.assetLocalIdentifier)
                        await self?.updateOCRProgress(message: "正在 OCR：\(progressText)")

                        guard let asset = service.fetchImageAsset(localIdentifier: record.assetLocalIdentifier) else {
                            try indexStore.markOCRFailed(
                                assetLocalIdentifier: record.assetLocalIdentifier,
                                failureType: .assetNotFound,
                                reason: "Photos 中未找到该图片资产，可能已被删除或授权范围已变化。",
                                durationSeconds: nil
                            )
                            await self?.refreshOCRState()
                            continue
                        }

                        let imageResult = await service.requestImageForOCR(for: asset)
                        switch imageResult {
                        case .success(let image):
                            let result = try await ocrService.recognizeText(in: image)
                            try indexStore.markOCRReady(
                                assetLocalIdentifier: record.assetLocalIdentifier,
                                text: result.text,
                                durationSeconds: result.durationSeconds
                            )
                        case .failure(let failure):
                            try indexStore.markOCRFailed(
                                assetLocalIdentifier: record.assetLocalIdentifier,
                                failureType: failure.type,
                                reason: failure.reason,
                                durationSeconds: nil
                            )
                        }

                        await self?.refreshOCRState()
                    } catch {
                        try? indexStore.markOCRFailed(
                            assetLocalIdentifier: record.assetLocalIdentifier,
                            failureType: .recognitionFailed,
                            reason: error.localizedDescription,
                            durationSeconds: nil
                        )
                        await self?.updateOCRProgress(
                            message: "OCR 单张处理失败：\(error.localizedDescription)。任务会继续处理后续图片。"
                        )
                    }
                }

                await self?.finishOCRProcessing(
                    message: "OCR 本地处理完成。成功、失败和平均耗时已写入本地索引。"
                )
            } catch {
                await self?.finishOCRProcessing(message: "OCR 启动失败：\(error.localizedDescription)")
            }
        }
    }

    private func startEmbeddingProcessing(includeFailed: Bool) {
        guard !isProcessingEmbedding else {
            embeddingStatusMessage = "视觉语义索引正在处理中，请等待当前任务完成。"
            return
        }

        guard authorizationState.canReadLibrary else {
            embeddingStatusMessage = "需要 Photos 权限后才能执行视觉语义索引。"
            return
        }

        guard let indexStore else {
            embeddingStatusMessage = "本地索引不可用，无法执行视觉语义索引。"
            return
        }

        do {
            refreshEmbeddingValidationPreflight()
            try embeddingService.validateModelAvailability()
        } catch {
            embeddingStatusMessage = "\(error.localizedDescription) 不会上传图片，也不会使用人工标签代替视觉搜索。"
            return
        }

        let service = service
        let embeddingService = embeddingService
        let selectedAssetIDs = assets.map(\.id)
        isProcessingEmbedding = true
        embeddingStatusMessage = "正在准备当前已读取的 \(selectedAssetIDs.count) 张图片的视觉索引..."

        Task.detached(priority: .utility) { [weak self] in
            do {
                let candidates = try indexStore.fetchEmbeddingCandidates(
                    includeFailed: includeFailed,
                    modelVersion: embeddingService.modelInfo.version
                )
                let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.assetLocalIdentifier, $0) })
                let batch = selectedAssetIDs.compactMap { candidateByID[$0] }
                let existingReady = try indexStore.fetchRecords().filter {
                    selectedAssetIDs.contains($0.assetLocalIdentifier)
                        && $0.embeddingStatus == .ready
                        && $0.modelVersion == embeddingService.modelInfo.version
                }.count

                guard !batch.isEmpty else {
                    await self?.finishEmbeddingProcessing(
                        message: "视觉索引无需处理：当前读取的 \(selectedAssetIDs.count) 张中已有 \(existingReady) 张成功。"
                    )
                    return
                }

                var succeeded = existingReady
                var failed = 0

                for (index, record) in batch.enumerated() {
                    let progressText = "\(index + 1)/\(batch.count)"
                    let startDate = Date()
                    do {
                        try indexStore.markEmbeddingProcessing(assetLocalIdentifier: record.assetLocalIdentifier)
                        await self?.updateEmbeddingProgress(message: "正在生成视觉向量：\(progressText)")

                        guard let asset = service.fetchImageAsset(localIdentifier: record.assetLocalIdentifier) else {
                            try indexStore.markEmbeddingFailed(
                                assetLocalIdentifier: record.assetLocalIdentifier,
                                failureType: .imageUnavailable,
                                reason: "Photos 中未找到该图片资产，可能已被删除或授权范围已变化。",
                                durationSeconds: nil
                            )
                            failed += 1
                            await self?.refreshEmbeddingState()
                            continue
                        }

                        let imageResult = await service.requestImageForOCR(for: asset)
                        switch imageResult {
                        case .success(let image):
                            let vector = try await embeddingService.encodeImage(image)
                            try indexStore.markEmbeddingReady(
                                assetLocalIdentifier: record.assetLocalIdentifier,
                                vector: vector,
                                modelVersion: embeddingService.modelInfo.version,
                                durationSeconds: Date().timeIntervalSince(startDate)
                            )
                            succeeded += 1
                        case .failure(let failure):
                            try indexStore.markEmbeddingFailed(
                                assetLocalIdentifier: record.assetLocalIdentifier,
                                failureType: .imageUnavailable,
                                reason: failure.reason,
                                durationSeconds: nil
                            )
                            failed += 1
                        }

                        await self?.refreshEmbeddingState()
                    } catch let error as EmbeddingServiceError {
                        try? indexStore.markEmbeddingFailed(
                            assetLocalIdentifier: record.assetLocalIdentifier,
                            failureType: error.failureType,
                            reason: error.localizedDescription,
                            durationSeconds: Date().timeIntervalSince(startDate)
                        )
                        await self?.updateEmbeddingProgress(
                            message: "视觉索引单张处理失败：\(error.localizedDescription)。任务会继续处理后续图片。"
                        )
                        failed += 1
                    } catch {
                        try? indexStore.markEmbeddingFailed(
                            assetLocalIdentifier: record.assetLocalIdentifier,
                            failureType: .unknown,
                            reason: error.localizedDescription,
                            durationSeconds: Date().timeIntervalSince(startDate)
                        )
                        await self?.updateEmbeddingProgress(
                            message: "视觉索引单张处理失败：\(error.localizedDescription)。任务会继续处理后续图片。"
                        )
                        failed += 1
                    }
                }

                await self?.finishEmbeddingProcessing(
                    message: "视觉索引完成：目标 \(selectedAssetIDs.count) 张，成功 \(succeeded) 张，失败 \(failed) 张。"
                )
            } catch {
                await self?.finishEmbeddingProcessing(message: "视觉语义索引启动失败：\(error.localizedDescription)")
            }
        }
    }

    private func finishNaturalLanguageSearch(
        results: [SearchResult],
        usedVisualSignal: Bool,
        errorMessage: String? = nil
    ) {
        searchResults = results
        searchResultAssets = results.map { PhotoAssetSummary(indexRecord: $0.record) }
        loadMissingSearchResultThumbnails(for: searchResultAssets)

        if let errorMessage {
            searchMessage = "搜索失败：\(errorMessage)"
        } else if results.isEmpty {
            searchMessage = "没有找到结果。索引未完成时，结果可能不完整。"
        } else {
            let signals = usedVisualSignal ? "OCR、视觉、时间和类型" : "OCR、时间和类型"
            searchMessage = "Top \(results.count) 融合结果，已使用可适用的\(signals)信号。"
        }
    }

    private func updateOCRProgress(message: String) {
        ocrStatusMessage = message
        refreshIndexSummary()
    }

    private func finishOCRProcessing(message: String) {
        isProcessingOCR = false
        ocrStatusMessage = message
        refreshIndexSummary()
    }

    private func refreshOCRState() {
        refreshIndexSummary()
    }

    private func updateEmbeddingProgress(message: String) {
        embeddingStatusMessage = message
        refreshIndexSummary()
    }

    private func finishEmbeddingProcessing(message: String) {
        isProcessingEmbedding = false
        embeddingStatusMessage = message
        refreshIndexSummary()
    }

    private func finishEmbeddingValidation(report: EmbeddingValidationReport?, message: String) {
        isRunningEmbeddingValidation = false
        embeddingValidationReport = report
        if let report {
            embeddingValidationSummary = EmbeddingValidationSummary(report: report)
        } else {
            embeddingValidationSummary = nil
        }
        embeddingValidationMessage = message
    }

    private func finishVisualSearch(results: [VisualSearchResult], message: String) {
        isRunningVisualSearch = false
        visualSearchResults = results
        visualSearchMessage = message
    }

    private func refreshEmbeddingState() {
        refreshIndexSummary()
    }

    private func refreshEmbeddingValidationPreflight() {
        embeddingReadinessReport = embeddingService.modelReadinessReport()
        embeddingValidationPreflightReport = EmbeddingValidationPreflightReport(
            modelReadinessReport: embeddingReadinessReport,
            sampleAudit: embeddingSampleAudit
        )
    }

    private func refreshIndexSummary() {
        guard let indexStore else {
            indexSummary = .empty
            ocrPerformanceSummary = .empty
            indexStatusMessage = "本地索引不可用，请重启应用或检查磁盘权限。"
            return
        }

        do {
            indexSummary = try indexStore.summary(
                currentEmbeddingModelVersion: embeddingService.modelInfo.version
            )
            ocrPerformanceSummary = try indexStore.ocrPerformanceSummary()
            indexStatusMessage = indexSummary.totalRecords == 0
                ? "本地索引为空。授权并读取图库后会创建索引记录。"
                : "已加载已有本地索引记录。"
        } catch {
            indexSummary = .empty
            ocrPerformanceSummary = .empty
            indexStatusMessage = "加载本地索引失败：\(error.localizedDescription)"
        }
    }
}
