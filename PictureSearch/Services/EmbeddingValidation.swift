import CoreGraphics
import Foundation

enum EmbeddingQueryLanguage: String, CaseIterable, Codable, Equatable {
    case chinese
    case english
    case mixed

    var displayName: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "英文"
        case .mixed:
            return "中英文混合"
        }
    }
}

struct EmbeddingValidationSample {
    let id: String
    let image: CGImage
    let relatedQuery: String
    let unrelatedQuery: String
    let language: EmbeddingQueryLanguage
}

struct EmbeddingValidationSampleDescriptor: Codable, Equatable {
    let sampleID: String
    let assetLocalIdentifier: String
    let relatedQuery: String
    let unrelatedQuery: String
    let language: EmbeddingQueryLanguage

    var validationIssues: [String] {
        var issues: [String] = []

        if sampleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("样本 ID 为空")
        }
        if assetLocalIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Photos 资产标识为空")
        }
        if relatedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("相关查询为空")
        }
        if unrelatedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("无关查询为空")
        }
        if relatedQuery == unrelatedQuery {
            issues.append("相关查询和无关查询不能相同")
        }

        return issues
    }
}

struct EmbeddingValidationSampleDescriptorDocument: Codable, Equatable {
    let samples: [EmbeddingValidationSampleDescriptor]

    static let empty = EmbeddingValidationSampleDescriptorDocument(samples: [])
    static let bundledResourceName = "EmbeddingValidationSamples.json"

    static func bundled(
        resourceName: String = bundledResourceName,
        bundle: Bundle = .main
    ) -> EmbeddingValidationSampleDescriptorBundleResult {
        guard let url = bundle.url(forResource: resourceName, withExtension: nil) else {
            let audit = empty.audit().addingIssue(
                EmbeddingValidationSampleDescriptorIssue(
                    sampleID: "样本描述文件",
                    reason: "App bundle 中未找到 \(resourceName)。请基于 docs/视觉模型验证样本.example.json 填写真实 Photos 样本，并将真实样本描述文件作为资源加入工程。"
                )
            )
            return EmbeddingValidationSampleDescriptorBundleResult(document: .empty, audit: audit)
        }

        do {
            let document = try decode(from: Data(contentsOf: url))
            return EmbeddingValidationSampleDescriptorBundleResult(
                document: document,
                audit: document.audit()
            )
        } catch {
            let audit = empty.audit().addingIssue(
                EmbeddingValidationSampleDescriptorIssue(
                    sampleID: "样本描述文件",
                    reason: "无法解析 App bundle 中的 \(resourceName)。请检查 JSON 格式、字段名称和 language 取值。"
                )
            )
            return EmbeddingValidationSampleDescriptorBundleResult(document: .empty, audit: audit)
        }
    }

    static func decode(from data: Data) throws -> EmbeddingValidationSampleDescriptorDocument {
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(EmbeddingValidationSampleDescriptorDocument.self, from: data) {
            return document
        }

        return EmbeddingValidationSampleDescriptorDocument(
            samples: try decoder.decode([EmbeddingValidationSampleDescriptor].self, from: data)
        )
    }

    static func bundledAudit(
        resourceName: String = bundledResourceName,
        bundle: Bundle = .main
    ) -> EmbeddingValidationSampleDescriptorAudit {
        bundled(resourceName: resourceName, bundle: bundle).audit
    }

    func audit(
        requiredSampleCount: Int = 5,
        requiredLanguages: Set<EmbeddingQueryLanguage> = Set(EmbeddingQueryLanguage.allCases)
    ) -> EmbeddingValidationSampleDescriptorAudit {
        var issues: [EmbeddingValidationSampleDescriptorIssue] = []

        if samples.count < requiredSampleCount {
            issues.append(
                EmbeddingValidationSampleDescriptorIssue(
                    sampleID: "样本数量",
                    reason: "至少需要 \(requiredSampleCount) 张测试图片，当前只有 \(samples.count) 张。"
                )
            )
        }

        let coveredLanguages = Set(samples.map(\.language))
        let missingLanguages = requiredLanguages.subtracting(coveredLanguages)
        if !missingLanguages.isEmpty {
            issues.append(
                EmbeddingValidationSampleDescriptorIssue(
                    sampleID: "语言覆盖",
                    reason: "缺少查询语言覆盖：\(EmbeddingValidationFormatter.languages(missingLanguages))。"
                )
            )
        }

        var seenSampleIDs: Set<String> = []
        for (index, sample) in samples.enumerated() {
            let issueSampleID = sample.sampleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "未命名样本 #\(index + 1)"
                : sample.sampleID

            let descriptorIssues = sample.validationIssues
            if !descriptorIssues.isEmpty {
                issues.append(
                    EmbeddingValidationSampleDescriptorIssue(
                        sampleID: issueSampleID,
                        reason: descriptorIssues.joined(separator: "、")
                    )
                )
            }

            if !sample.sampleID.isEmpty && !seenSampleIDs.insert(sample.sampleID).inserted {
                issues.append(
                    EmbeddingValidationSampleDescriptorIssue(
                        sampleID: issueSampleID,
                        reason: "样本 ID 重复"
                    )
                )
            }
        }

        return EmbeddingValidationSampleDescriptorAudit(
            sampleCount: samples.count,
            coveredLanguages: coveredLanguages,
            requiredLanguages: requiredLanguages,
            issues: issues
        )
    }
}

struct EmbeddingValidationSampleDescriptorBundleResult: Equatable {
    let document: EmbeddingValidationSampleDescriptorDocument
    let audit: EmbeddingValidationSampleDescriptorAudit
}

struct EmbeddingValidationSampleDescriptorIssue: Equatable {
    let sampleID: String
    let reason: String
}

struct EmbeddingValidationSampleDescriptorAudit: Equatable {
    let sampleCount: Int
    let coveredLanguages: Set<EmbeddingQueryLanguage>
    let requiredLanguages: Set<EmbeddingQueryLanguage>
    let issues: [EmbeddingValidationSampleDescriptorIssue]

    var isReadyForImageLoading: Bool {
        issues.isEmpty
    }

    var missingLanguages: Set<EmbeddingQueryLanguage> {
        requiredLanguages.subtracting(coveredLanguages)
    }

    var privacySafeSummaryLines: [String] {
        var lines = [
            "样本数量：\(sampleCount)",
            "语言覆盖：\(EmbeddingValidationFormatter.languages(coveredLanguages))",
            "缺失语言：\(missingLanguages.isEmpty ? "无" : EmbeddingValidationFormatter.languages(missingLanguages))",
            "验证状态：\(isReadyForImageLoading ? "可读取图片" : "需要修正样本描述")"
        ]

        if issues.isEmpty {
            lines.append("样本问题：无")
        } else {
            lines.append(contentsOf: issues.map { issue in
                "样本问题：\(issue.sampleID)：\(issue.reason)"
            })
        }

        return lines
    }

    func addingIssue(_ issue: EmbeddingValidationSampleDescriptorIssue) -> EmbeddingValidationSampleDescriptorAudit {
        EmbeddingValidationSampleDescriptorAudit(
            sampleCount: sampleCount,
            coveredLanguages: coveredLanguages,
            requiredLanguages: requiredLanguages,
            issues: issues + [issue]
        )
    }
}

struct EmbeddingValidationSampleLoadIssue: Equatable {
    let sampleID: String
    let reason: String
}

struct EmbeddingValidationSampleLoadResult {
    let samples: [EmbeddingValidationSample]
    let issues: [EmbeddingValidationSampleLoadIssue]

    var isReadyForValidation: Bool {
        !samples.isEmpty && issues.isEmpty
    }
}

struct EmbeddingValidationPreflightReport: Equatable {
    let modelReadinessReport: EmbeddingModelReadinessReport
    let sampleAudit: EmbeddingValidationSampleDescriptorAudit

    var canLoadSamples: Bool {
        modelReadinessReport.isReady && sampleAudit.isReadyForImageLoading
    }

    var summaryLines: [String] {
        var lines = [
            "预检状态：\(canLoadSamples ? "可读取样本并运行技术验证" : "需要先修正模型或样本描述")",
            "模型状态：\(modelReadinessReport.isReady ? "就绪" : "未就绪")"
        ]

        lines.append(contentsOf: modelReadinessReport.diagnosticLines.map { "模型诊断：\($0)" })
        lines.append(contentsOf: sampleAudit.privacySafeSummaryLines.map { "样本诊断：\($0)" })
        lines.append("下一步：\(nextAction)")
        return lines
    }

    var nextAction: String {
        if !modelReadinessReport.isReady {
            return modelReadinessReport.recoveryMessage
        }

        if !sampleAudit.isReadyForImageLoading {
            return "请修正样本描述文件，确保至少 5 张样本并覆盖中文、英文和中英文混合查询。"
        }

        return "可以通过 PhotoKit 在本机读取样本图片，并运行 EmbeddingValidationService 生成技术验证报告。"
    }

    var markdownReport: String {
        var lines = [
            "# 本地图文向量技术验证预检报告",
            "",
            "- 预检状态：\(canLoadSamples ? "可继续" : "未通过")",
            "- 模型版本：\(modelReadinessReport.modelInfo.version)",
            "- 模型来源：\(modelReadinessReport.modelInfo.source)",
            "- 许可证：\(modelReadinessReport.modelInfo.license)",
            "- 样本数量：\(sampleAudit.sampleCount)",
            "- 语言覆盖：\(EmbeddingValidationFormatter.languages(sampleAudit.coveredLanguages))",
            "- 缺失语言：\(sampleAudit.missingLanguages.isEmpty ? "无" : EmbeddingValidationFormatter.languages(sampleAudit.missingLanguages))",
            "",
            "## 模型诊断",
            ""
        ]

        lines.append(contentsOf: modelReadinessReport.diagnosticLines.map {
            "- \(EmbeddingValidationFormatter.markdownInline($0))"
        })

        lines.append(contentsOf: [
            "",
            "## 样本诊断",
            ""
        ])

        lines.append(contentsOf: sampleAudit.privacySafeSummaryLines.map {
            "- \(EmbeddingValidationFormatter.markdownInline($0))"
        })

        lines.append(contentsOf: [
            "",
            "## 下一步",
            "",
            "- \(EmbeddingValidationFormatter.markdownInline(nextAction))",
            "- 隐私：预检报告只记录样本 ID、数量、语言覆盖和问题原因，不写入 Photos 资产标识。"
        ])

        return lines.joined(separator: "\n")
    }
}

enum EmbeddingValidationImageLoadResult {
    case success(CGImage)
    case failure(String)
}

struct EmbeddingValidationSampleLoader {
    static func loadSamples(
        from descriptors: [EmbeddingValidationSampleDescriptor],
        imageProvider: (String) async -> EmbeddingValidationImageLoadResult
    ) async -> EmbeddingValidationSampleLoadResult {
        var samples: [EmbeddingValidationSample] = []
        var issues: [EmbeddingValidationSampleLoadIssue] = []

        for descriptor in descriptors {
            let descriptorIssues = descriptor.validationIssues
            guard descriptorIssues.isEmpty else {
                issues.append(
                    EmbeddingValidationSampleLoadIssue(
                        sampleID: descriptor.sampleID,
                        reason: descriptorIssues.joined(separator: "、")
                    )
                )
                continue
            }

            let imageResult = await imageProvider(descriptor.assetLocalIdentifier)
            switch imageResult {
            case .success(let image):
                samples.append(
                    EmbeddingValidationSample(
                        id: descriptor.sampleID,
                        image: image,
                        relatedQuery: descriptor.relatedQuery,
                        unrelatedQuery: descriptor.unrelatedQuery,
                        language: descriptor.language
                    )
                )
            case .failure(let reason):
                issues.append(
                    EmbeddingValidationSampleLoadIssue(
                        sampleID: descriptor.sampleID,
                        reason: reason
                    )
                )
            }
        }

        return EmbeddingValidationSampleLoadResult(samples: samples, issues: issues)
    }
}

struct EmbeddingValidationCaseResult: Equatable {
    let sampleID: String
    let language: EmbeddingQueryLanguage?
    let imageDimension: Int?
    let textDimension: Int?
    let relatedScore: Double?
    let unrelatedScore: Double?
    let passed: Bool
    let failureReason: String?
    let imageEncodingDurationSeconds: Double?
    let relatedTextEncodingDurationSeconds: Double?
    let unrelatedTextEncodingDurationSeconds: Double?
    let totalDurationSeconds: Double?

    var scoreGap: Double? {
        guard let relatedScore, let unrelatedScore else {
            return nil
        }

        return relatedScore - unrelatedScore
    }

    init(
        sampleID: String,
        language: EmbeddingQueryLanguage?,
        imageDimension: Int?,
        textDimension: Int?,
        relatedScore: Double?,
        unrelatedScore: Double?,
        passed: Bool,
        failureReason: String?,
        imageEncodingDurationSeconds: Double? = nil,
        relatedTextEncodingDurationSeconds: Double? = nil,
        unrelatedTextEncodingDurationSeconds: Double? = nil,
        totalDurationSeconds: Double? = nil
    ) {
        self.sampleID = sampleID
        self.language = language
        self.imageDimension = imageDimension
        self.textDimension = textDimension
        self.relatedScore = relatedScore
        self.unrelatedScore = unrelatedScore
        self.passed = passed
        self.failureReason = failureReason
        self.imageEncodingDurationSeconds = imageEncodingDurationSeconds
        self.relatedTextEncodingDurationSeconds = relatedTextEncodingDurationSeconds
        self.unrelatedTextEncodingDurationSeconds = unrelatedTextEncodingDurationSeconds
        self.totalDurationSeconds = totalDurationSeconds
    }

    var summaryLine: String {
        let languageText = language?.displayName ?? "无语言"
        let dimensionText: String
        if let imageDimension, let textDimension {
            dimensionText = "图片维度 \(imageDimension)，文本维度 \(textDimension)"
        } else {
            dimensionText = "维度未生成"
        }

        let scoreText: String
        if let relatedScore, let unrelatedScore {
            let gapText = scoreGap.map { "，差距 \(EmbeddingValidationFormatter.score($0))" } ?? ""
            scoreText = "相关 \(EmbeddingValidationFormatter.score(relatedScore))，无关 \(EmbeddingValidationFormatter.score(unrelatedScore))\(gapText)"
        } else {
            scoreText = "分数未生成"
        }

        let statusText = passed ? "通过" : "未通过"
        let durationText = totalDurationSeconds.map {
            "，耗时 \(EmbeddingValidationFormatter.duration($0))"
        } ?? ""
        let reasonText = failureReason.map { "，原因：\($0)" } ?? ""
        return "\(sampleID)：\(statusText)，\(languageText)，\(dimensionText)，\(scoreText)\(durationText)\(reasonText)"
    }
}

struct EmbeddingValidationReport: Equatable {
    let modelInfo: EmbeddingModelInfo
    let modelIntegrationChecklistLines: [String]
    let modelReadinessDiagnosticLines: [String]
    let requiredSampleCount: Int
    let requiredLanguages: Set<EmbeddingQueryLanguage>
    let requiredSimilarityMargin: Double
    let caseResults: [EmbeddingValidationCaseResult]

    init(
        modelInfo: EmbeddingModelInfo,
        modelIntegrationChecklistLines: [String] = [],
        modelReadinessDiagnosticLines: [String] = [],
        requiredSampleCount: Int,
        requiredLanguages: Set<EmbeddingQueryLanguage>,
        requiredSimilarityMargin: Double = 0.05,
        caseResults: [EmbeddingValidationCaseResult]
    ) {
        self.modelInfo = modelInfo
        self.modelIntegrationChecklistLines = modelIntegrationChecklistLines
        self.modelReadinessDiagnosticLines = modelReadinessDiagnosticLines
        self.requiredSampleCount = requiredSampleCount
        self.requiredLanguages = requiredLanguages
        self.requiredSimilarityMargin = requiredSimilarityMargin
        self.caseResults = caseResults
    }

    var passed: Bool {
        caseResults.allSatisfy(\.passed) && missingLanguages.isEmpty
    }

    var failureReasons: [String] {
        caseResults.compactMap(\.failureReason)
    }

    var coveredLanguages: Set<EmbeddingQueryLanguage> {
        Set(caseResults.compactMap(\.language))
    }

    var missingLanguages: Set<EmbeddingQueryLanguage> {
        requiredLanguages.subtracting(coveredLanguages)
    }

    var summaryLines: [String] {
        var lines = [
            "模型版本：\(modelInfo.version)",
            "模型来源：\(modelInfo.source)",
            "许可证：\(modelInfo.license)",
            "验证状态：\(passed ? "通过" : "未通过")",
            "样本数量：\(caseResults.filter { $0.language != nil }.count)/\(requiredSampleCount)",
            "语言覆盖：\(EmbeddingValidationFormatter.languages(coveredLanguages))",
            "缺失语言：\(missingLanguages.isEmpty ? "无" : EmbeddingValidationFormatter.languages(missingLanguages))",
            "最小相似度差距：\(EmbeddingValidationFormatter.score(requiredSimilarityMargin))"
        ]

        lines.append(contentsOf: caseResults.map(\.summaryLine))

        if !modelIntegrationChecklistLines.isEmpty {
            lines.append(contentsOf: modelIntegrationChecklistLines.map { "接入清单：\($0)" })
        }
        if !modelReadinessDiagnosticLines.isEmpty {
            lines.append(contentsOf: modelReadinessDiagnosticLines.map { "就绪诊断：\($0)" })
        }

        if failureReasons.isEmpty {
            lines.append("失败原因：无")
        } else {
            lines.append("失败原因：\(failureReasons.joined(separator: "；"))")
        }

        return lines
    }

    var markdownReport: String {
        markdownLines.joined(separator: "\n")
    }

    var markdownLines: [String] {
        var lines = [
            "# 本地图文向量技术验证报告",
            "",
            "## 模型信息",
            "",
            "- 模型版本：\(modelInfo.version)",
            "- 模型来源：\(modelInfo.source)",
            "- 许可证：\(modelInfo.license)",
            "- 验证状态：\(passed ? "通过" : "未通过")",
            "- 样本数量：\(caseResults.filter { $0.language != nil }.count)/\(requiredSampleCount)",
            "- 语言覆盖：\(EmbeddingValidationFormatter.languages(coveredLanguages))",
            "- 缺失语言：\(missingLanguages.isEmpty ? "无" : EmbeddingValidationFormatter.languages(missingLanguages))",
            "- 最小相似度差距：\(EmbeddingValidationFormatter.score(requiredSimilarityMargin))",
            "- 平均单样本耗时：\(EmbeddingValidationFormatter.duration(averageSampleDurationSeconds))",
            "",
            "## 模型接入清单",
            ""
        ]

        if modelIntegrationChecklistLines.isEmpty {
            lines.append("- 未提供真实模型 manifest 接入清单。")
        } else {
            lines.append(contentsOf: modelIntegrationChecklistLines.map {
                "- \(EmbeddingValidationFormatter.markdownInline($0))"
            })
        }

        lines.append(contentsOf: [
            "",
            "## 模型就绪诊断",
            ""
        ])

        if modelReadinessDiagnosticLines.isEmpty {
            lines.append("- 未提供模型就绪诊断。")
        } else {
            lines.append(contentsOf: modelReadinessDiagnosticLines.map {
                "- \(EmbeddingValidationFormatter.markdownInline($0))"
            })
        }

        lines.append(contentsOf: [
            "",
            "## 样本结果",
            "",
            "| 样本 | 语言 | 图片维度 | 文本维度 | 相关分数 | 无关分数 | 相似度差距 | 图片耗时 | 相关文本耗时 | 无关文本耗时 | 总耗时 | 状态 | 失败原因 |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
        ])

        lines.append(contentsOf: caseResults.map(markdownTableRow(for:)))

        lines.append(contentsOf: [
            "",
            "## 结论与限制",
            "",
            "- 结论：\(passed ? "当前样本通过技术验证。" : "当前样本未通过技术验证，不能标记视觉语义搜索完成。")",
            "- 限制：该报告只验证当前样本、当前模型版本和当前预处理配置，不代表完整 Photos 图库搜索效果。",
            "- 限制：真实验收仍需记录模型文件大小、处理耗时、中英文效果对比和少量真实查询结果。",
            "- 隐私：验证过程应在本机运行，不上传图片、OCR 文本或向量。"
        ])

        if !failureReasons.isEmpty {
            lines.append("- 失败原因：\(failureReasons.map(EmbeddingValidationFormatter.markdownInline).joined(separator: "；"))")
        }

        return lines
    }

    var averageSampleDurationSeconds: Double {
        let durations = caseResults.compactMap(\.totalDurationSeconds)
        guard !durations.isEmpty else {
            return 0
        }

        return durations.reduce(0, +) / Double(durations.count)
    }

    private func markdownTableRow(for result: EmbeddingValidationCaseResult) -> String {
        let language = result.language?.displayName ?? "无"
        let imageDimension = result.imageDimension.map(String.init) ?? "未生成"
        let textDimension = result.textDimension.map(String.init) ?? "未生成"
        let relatedScore = result.relatedScore.map(EmbeddingValidationFormatter.score) ?? "未生成"
        let unrelatedScore = result.unrelatedScore.map(EmbeddingValidationFormatter.score) ?? "未生成"
        let scoreGap = result.scoreGap.map(EmbeddingValidationFormatter.score) ?? "未生成"
        let imageDuration = result.imageEncodingDurationSeconds.map(EmbeddingValidationFormatter.duration) ?? "未记录"
        let relatedTextDuration = result.relatedTextEncodingDurationSeconds.map(EmbeddingValidationFormatter.duration) ?? "未记录"
        let unrelatedTextDuration = result.unrelatedTextEncodingDurationSeconds.map(EmbeddingValidationFormatter.duration) ?? "未记录"
        let totalDuration = result.totalDurationSeconds.map(EmbeddingValidationFormatter.duration) ?? "未记录"
        let status = result.passed ? "通过" : "未通过"
        let failureReason = result.failureReason ?? "无"

        let cells: [String] = [
            result.sampleID,
            language,
            imageDimension,
            textDimension,
            relatedScore,
            unrelatedScore,
            scoreGap,
            imageDuration,
            relatedTextDuration,
            unrelatedTextDuration,
            totalDuration,
            status,
            failureReason
        ]

        return cells
            .map(EmbeddingValidationFormatter.markdownCell)
            .joined(separator: " | ")
            .withTableRowDelimiters()
    }
}

struct EmbeddingValidationGate: Equatable {
    let canUseVisualEmbedding: Bool
    let recoveryMessage: String

    static func evaluate(
        report: EmbeddingValidationReport?,
        summary: EmbeddingValidationSummary? = nil,
        currentModelVersion: String
    ) -> EmbeddingValidationGate {
        if let report {
            return evaluate(
                modelVersion: report.modelInfo.version,
                passed: report.passed,
                currentModelVersion: currentModelVersion
            )
        }

        if let summary {
            return evaluate(
                modelVersion: summary.modelVersion,
                passed: summary.passed,
                currentModelVersion: currentModelVersion
            )
        }

        return EmbeddingValidationGate(
            canUseVisualEmbedding: false,
            recoveryMessage: "请先运行本地图文向量技术验证，并确认当前模型版本通过 5 张真实 Photos 样本验证。"
        )
    }

    private static func evaluate(
        modelVersion: String,
        passed: Bool,
        currentModelVersion: String
    ) -> EmbeddingValidationGate {
        guard modelVersion == currentModelVersion else {
            return EmbeddingValidationGate(
                canUseVisualEmbedding: false,
                recoveryMessage: "技术验证记录属于模型版本 \(modelVersion)，当前模型版本为 \(currentModelVersion)。请重新运行技术验证。"
            )
        }

        guard passed else {
            return EmbeddingValidationGate(
                canUseVisualEmbedding: false,
                recoveryMessage: "当前模型版本的技术验证未通过，不能开始视觉索引或视觉查询。"
            )
        }

        return EmbeddingValidationGate(
            canUseVisualEmbedding: true,
            recoveryMessage: "当前模型版本已通过技术验证。"
        )
    }
}

struct EmbeddingValidationSummary: Codable, Equatable {
    let modelVersion: String
    let modelSource: String
    let license: String
    let passed: Bool
    let validatedAt: Date
    let sampleCount: Int
    let requiredSampleCount: Int
    let coveredLanguages: [EmbeddingQueryLanguage]
    let missingLanguages: [EmbeddingQueryLanguage]
    let requiredSimilarityMargin: Double
    let averageSampleDurationSeconds: Double?

    init(report: EmbeddingValidationReport, validatedAt: Date = Date()) {
        self.modelVersion = report.modelInfo.version
        self.modelSource = report.modelInfo.source
        self.license = report.modelInfo.license
        self.passed = report.passed
        self.validatedAt = validatedAt
        self.sampleCount = report.caseResults.filter { $0.language != nil }.count
        self.requiredSampleCount = report.requiredSampleCount
        self.coveredLanguages = report.coveredLanguages.sortedByDisplayName()
        self.missingLanguages = report.missingLanguages.sortedByDisplayName()
        self.requiredSimilarityMargin = report.requiredSimilarityMargin
        self.averageSampleDurationSeconds = report.averageSampleDurationSeconds
    }

    var summaryLine: String {
        let status = passed ? "通过" : "未通过"
        let covered = EmbeddingValidationFormatter.languages(Set(coveredLanguages))
        let missing = missingLanguages.isEmpty
            ? "无"
            : EmbeddingValidationFormatter.languages(Set(missingLanguages))
        return "模型版本 \(modelVersion) 技术验证\(status)，样本 \(sampleCount)/\(requiredSampleCount)，语言覆盖：\(covered)，缺失语言：\(missing)。"
    }
}

struct EmbeddingValidationReportStore {
    static let defaultFileName = "EmbeddingValidationReport.md"
    static let defaultSummaryFileName = "EmbeddingValidationSummary.json"

    static func save(
        report: EmbeddingValidationReport,
        directoryURL: URL = defaultDirectoryURL(),
        fileName: String = defaultFileName,
        summaryFileName: String = defaultSummaryFileName,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard let data = report.markdownReport.data(using: .utf8) else {
            throw EmbeddingServiceError.modelUnavailable("技术验证报告无法编码为 UTF-8。")
        }

        try data.write(to: fileURL, options: .atomic)
        try saveSummary(
            EmbeddingValidationSummary(report: report),
            directoryURL: directoryURL,
            fileName: summaryFileName,
            fileManager: fileManager
        )
        return fileURL
    }

    @discardableResult
    static func saveSummary(
        _ summary: EmbeddingValidationSummary,
        directoryURL: URL = defaultDirectoryURL(),
        fileName: String = defaultSummaryFileName,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let fileURL = directoryURL.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func loadSummary(
        directoryURL: URL = defaultDirectoryURL(),
        fileName: String = defaultSummaryFileName,
        fileManager: FileManager = .default
    ) -> EmbeddingValidationSummary? {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(
                EmbeddingValidationSummary.self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            return nil
        }
    }

    static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        if let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return applicationSupportURL.appendingPathComponent("PictureSearch", isDirectory: true)
        }

        return fileManager.temporaryDirectory.appendingPathComponent("PictureSearch", isDirectory: true)
    }
}

enum EmbeddingValidationFormatter {
    static func score(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    static func duration(_ value: Double) -> String {
        guard value > 0 else {
            return "未记录"
        }

        return String(format: "%.3f 秒", value)
    }

    static func languages(_ languages: Set<EmbeddingQueryLanguage>) -> String {
        guard !languages.isEmpty else {
            return "无"
        }

        return languages
            .map(\.displayName)
            .sorted()
            .joined(separator: "、")
    }

    static func markdownCell(_ value: String) -> String {
        markdownInline(value.isEmpty ? "无" : value)
    }

    static func markdownInline(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

private extension Set where Element == EmbeddingQueryLanguage {
    func sortedByDisplayName() -> [EmbeddingQueryLanguage] {
        sorted { $0.displayName < $1.displayName }
    }
}

private extension String {
    func withTableRowDelimiters() -> String {
        "| \(self) |"
    }
}

struct EmbeddingValidationService {
    let embeddingService: EmbeddingServicing

    func validate(
        samples: [EmbeddingValidationSample],
        requiredSampleCount: Int = 5,
        requiredLanguages: Set<EmbeddingQueryLanguage> = Set(EmbeddingQueryLanguage.allCases),
        similarityMargin: Double = 0.05
    ) async -> EmbeddingValidationReport {
        var results: [EmbeddingValidationCaseResult] = []
        let readinessReport = embeddingService.modelReadinessReport()

        if samples.count < requiredSampleCount {
            results.append(
                EmbeddingValidationCaseResult(
                    sampleID: "样本数量",
                    language: nil,
                    imageDimension: nil,
                    textDimension: nil,
                    relatedScore: nil,
                    unrelatedScore: nil,
                    passed: false,
                    failureReason: "至少需要 \(requiredSampleCount) 张测试图片，当前只有 \(samples.count) 张。"
                )
            )
        }

        let sampleLanguages = Set(samples.map(\.language))
        let missingLanguages = requiredLanguages.subtracting(sampleLanguages)
        if !missingLanguages.isEmpty {
            let missingText = missingLanguages
                .map(\.displayName)
                .sorted()
                .joined(separator: "、")
            results.append(
                EmbeddingValidationCaseResult(
                    sampleID: "语言覆盖",
                    language: nil,
                    imageDimension: nil,
                    textDimension: nil,
                    relatedScore: nil,
                    unrelatedScore: nil,
                    passed: false,
                    failureReason: "技术验证样本缺少查询语言覆盖：\(missingText)。"
                )
            )
        }

        do {
            try embeddingService.validateModelAvailability()
        } catch {
            results.append(
                EmbeddingValidationCaseResult(
                    sampleID: "模型加载",
                    language: nil,
                    imageDimension: nil,
                    textDimension: nil,
                    relatedScore: nil,
                    unrelatedScore: nil,
                    passed: false,
                    failureReason: error.localizedDescription
                )
            )
            return EmbeddingValidationReport(
                modelInfo: embeddingService.modelInfo,
                modelIntegrationChecklistLines: readinessReport.integrationChecklistLines,
                modelReadinessDiagnosticLines: readinessReport.diagnosticLines,
                requiredSampleCount: requiredSampleCount,
                requiredLanguages: requiredLanguages,
                requiredSimilarityMargin: similarityMargin,
                caseResults: results
            )
        }

        for sample in samples {
            results.append(await validateSample(sample, similarityMargin: similarityMargin))
        }

        return EmbeddingValidationReport(
            modelInfo: embeddingService.modelInfo,
            modelIntegrationChecklistLines: readinessReport.integrationChecklistLines,
            modelReadinessDiagnosticLines: readinessReport.diagnosticLines,
            requiredSampleCount: requiredSampleCount,
            requiredLanguages: requiredLanguages,
            requiredSimilarityMargin: similarityMargin,
            caseResults: results
        )
    }

    private func validateSample(
        _ sample: EmbeddingValidationSample,
        similarityMargin: Double
    ) async -> EmbeddingValidationCaseResult {
        let totalStartDate = Date()
        var imageEncodingDuration: Double?
        var relatedTextEncodingDuration: Double?
        var unrelatedTextEncodingDuration: Double?

        do {
            let imageStartDate = Date()
            let imageVector = try await embeddingService.encodeImage(sample.image)
            imageEncodingDuration = Date().timeIntervalSince(imageStartDate)

            let relatedTextStartDate = Date()
            let relatedTextVector = try await embeddingService.encodeText(sample.relatedQuery)
            relatedTextEncodingDuration = Date().timeIntervalSince(relatedTextStartDate)

            let unrelatedTextStartDate = Date()
            let unrelatedTextVector = try await embeddingService.encodeText(sample.unrelatedQuery)
            unrelatedTextEncodingDuration = Date().timeIntervalSince(unrelatedTextStartDate)

            guard imageVector.dimension == relatedTextVector.dimension else {
                return EmbeddingValidationCaseResult(
                    sampleID: sample.id,
                    language: sample.language,
                    imageDimension: imageVector.dimension,
                    textDimension: relatedTextVector.dimension,
                    relatedScore: nil,
                    unrelatedScore: nil,
                    passed: false,
                    failureReason: "图片向量和文本向量维度不一致。",
                    imageEncodingDurationSeconds: imageEncodingDuration,
                    relatedTextEncodingDurationSeconds: relatedTextEncodingDuration,
                    unrelatedTextEncodingDurationSeconds: unrelatedTextEncodingDuration,
                    totalDurationSeconds: Date().timeIntervalSince(totalStartDate)
                )
            }

            guard imageVector.dimension == unrelatedTextVector.dimension else {
                return EmbeddingValidationCaseResult(
                    sampleID: sample.id,
                    language: sample.language,
                    imageDimension: imageVector.dimension,
                    textDimension: unrelatedTextVector.dimension,
                    relatedScore: nil,
                    unrelatedScore: nil,
                    passed: false,
                    failureReason: "图片向量和无关查询向量维度不一致。",
                    imageEncodingDurationSeconds: imageEncodingDuration,
                    relatedTextEncodingDurationSeconds: relatedTextEncodingDuration,
                    unrelatedTextEncodingDurationSeconds: unrelatedTextEncodingDuration,
                    totalDurationSeconds: Date().timeIntervalSince(totalStartDate)
                )
            }

            let relatedScore = try imageVector.cosineSimilarity(to: relatedTextVector)
            let unrelatedScore = try imageVector.cosineSimilarity(to: unrelatedTextVector)
            let scoreGap = relatedScore - unrelatedScore
            let passed = scoreGap > similarityMargin

            return EmbeddingValidationCaseResult(
                sampleID: sample.id,
                language: sample.language,
                imageDimension: imageVector.dimension,
                textDimension: relatedTextVector.dimension,
                relatedScore: relatedScore,
                unrelatedScore: unrelatedScore,
                passed: passed,
                failureReason: passed ? nil : "相关查询相似度没有稳定高于无关查询，当前差距 \(EmbeddingValidationFormatter.score(scoreGap))，需要大于 \(EmbeddingValidationFormatter.score(similarityMargin))。",
                imageEncodingDurationSeconds: imageEncodingDuration,
                relatedTextEncodingDurationSeconds: relatedTextEncodingDuration,
                unrelatedTextEncodingDurationSeconds: unrelatedTextEncodingDuration,
                totalDurationSeconds: Date().timeIntervalSince(totalStartDate)
            )
        } catch {
            return EmbeddingValidationCaseResult(
                sampleID: sample.id,
                language: sample.language,
                imageDimension: nil,
                textDimension: nil,
                relatedScore: nil,
                unrelatedScore: nil,
                passed: false,
                failureReason: error.localizedDescription,
                imageEncodingDurationSeconds: imageEncodingDuration,
                relatedTextEncodingDurationSeconds: relatedTextEncodingDuration,
                unrelatedTextEncodingDurationSeconds: unrelatedTextEncodingDuration,
                totalDurationSeconds: Date().timeIntervalSince(totalStartDate)
            )
        }
    }
}
