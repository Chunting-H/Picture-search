import CoreGraphics
import CoreML
import CryptoKit
import Foundation

struct EmbeddingModelInfo: Equatable {
    let version: String
    let source: String
    let license: String
    let expectedImageModelName: String
    let expectedTextModelName: String
    let configuration: EmbeddingModelConfiguration?

    init(
        version: String,
        source: String,
        license: String,
        expectedImageModelName: String,
        expectedTextModelName: String,
        configuration: EmbeddingModelConfiguration? = nil
    ) {
        self.version = version
        self.source = source
        self.license = license
        self.expectedImageModelName = expectedImageModelName
        self.expectedTextModelName = expectedTextModelName
        self.configuration = configuration
    }

    static let unconfiguredCLIP = EmbeddingModelInfo(
        version: "local-clip-unconfigured",
        source: "待加入本地 Core ML CLIP 图文双塔模型",
        license: "待随模型文件确认",
        expectedImageModelName: "CLIPImageEncoder",
        expectedTextModelName: "CLIPTextEncoder"
    )
}

struct EmbeddingModelConfiguration: Codable, Equatable {
    let imageInputName: String
    let imageOutputName: String
    let textInputName: String
    let textOutputName: String
    let tokenizerResourceName: String?
    let textSequenceLength: Int
    let textPadTokenID: Int32
    let textStartTokenID: Int32?
    let textEndTokenID: Int32?
    let imageInputSize: Int
    let imageMean: [Double]
    let imageStandardDeviation: [Double]

    init(
        imageInputName: String,
        imageOutputName: String,
        textInputName: String,
        textOutputName: String,
        tokenizerResourceName: String?,
        textSequenceLength: Int,
        textPadTokenID: Int32,
        textStartTokenID: Int32? = nil,
        textEndTokenID: Int32? = nil,
        imageInputSize: Int,
        imageMean: [Double],
        imageStandardDeviation: [Double]
    ) {
        self.imageInputName = imageInputName
        self.imageOutputName = imageOutputName
        self.textInputName = textInputName
        self.textOutputName = textOutputName
        self.tokenizerResourceName = tokenizerResourceName
        self.textSequenceLength = textSequenceLength
        self.textPadTokenID = textPadTokenID
        self.textStartTokenID = textStartTokenID
        self.textEndTokenID = textEndTokenID
        self.imageInputSize = imageInputSize
        self.imageMean = imageMean
        self.imageStandardDeviation = imageStandardDeviation
    }

    var validationIssues: [String] {
        var issues: [String] = []

        if imageInputName.isEmpty {
            issues.append("缺少图片编码器输入名")
        }
        if imageOutputName.isEmpty {
            issues.append("缺少图片编码器输出名")
        }
        if textInputName.isEmpty {
            issues.append("缺少文本编码器输入名")
        }
        if textOutputName.isEmpty {
            issues.append("缺少文本编码器输出名")
        }
        if tokenizerResourceName?.isEmpty == true {
            issues.append("tokenizer 资源名为空")
        }
        if tokenizerResourceName == nil {
            issues.append("缺少 tokenizer 资源名")
        }
        if textSequenceLength <= 0 {
            issues.append("文本 token 序列长度必须大于 0")
        }
        if textStartTokenID == nil {
            issues.append("缺少文本起始 token ID")
        }
        if textEndTokenID == nil {
            issues.append("缺少文本结束 token ID")
        }
        if let textStartTokenID, textStartTokenID < 0 {
            issues.append("文本起始 token ID 不能小于 0")
        }
        if let textEndTokenID, textEndTokenID < 0 {
            issues.append("文本结束 token ID 不能小于 0")
        }
        if imageInputSize <= 0 {
            issues.append("图片输入尺寸必须大于 0")
        }
        if imageMean.count != 3 {
            issues.append("图片归一化 mean 必须包含 3 个通道")
        }
        if imageStandardDeviation.count != 3 {
            issues.append("图片归一化 standard deviation 必须包含 3 个通道")
        }

        return issues
    }
}

struct EmbeddingModelManifest: Codable, Equatable {
    let version: String
    let source: String
    let license: String
    let imageModelName: String
    let textModelName: String
    let imageModelFileSizeMB: Double?
    let textModelFileSizeMB: Double?
    let tokenizerFileSizeKB: Double?
    let imageModelSHA256: String?
    let textModelSHA256: String?
    let tokenizerSHA256: String?
    let integrationReason: String?
    let alternativesConsidered: [String]?
    let expectedImpact: String?
    let configuration: EmbeddingModelConfiguration
    let notes: String?

    init(
        version: String,
        source: String,
        license: String,
        imageModelName: String,
        textModelName: String,
        imageModelFileSizeMB: Double?,
        textModelFileSizeMB: Double?,
        tokenizerFileSizeKB: Double?,
        imageModelSHA256: String? = nil,
        textModelSHA256: String? = nil,
        tokenizerSHA256: String? = nil,
        integrationReason: String? = nil,
        alternativesConsidered: [String]? = nil,
        expectedImpact: String? = nil,
        configuration: EmbeddingModelConfiguration,
        notes: String?
    ) {
        self.version = version
        self.source = source
        self.license = license
        self.imageModelName = imageModelName
        self.textModelName = textModelName
        self.imageModelFileSizeMB = imageModelFileSizeMB
        self.textModelFileSizeMB = textModelFileSizeMB
        self.tokenizerFileSizeKB = tokenizerFileSizeKB
        self.imageModelSHA256 = imageModelSHA256
        self.textModelSHA256 = textModelSHA256
        self.tokenizerSHA256 = tokenizerSHA256
        self.integrationReason = integrationReason
        self.alternativesConsidered = alternativesConsidered
        self.expectedImpact = expectedImpact
        self.configuration = configuration
        self.notes = notes
    }

    var modelInfo: EmbeddingModelInfo {
        EmbeddingModelInfo(
            version: version,
            source: source,
            license: license,
            expectedImageModelName: imageModelName,
            expectedTextModelName: textModelName,
            configuration: configuration
        )
    }

    static func decode(from data: Data) throws -> EmbeddingModelManifest {
        do {
            return try JSONDecoder().decode(EmbeddingModelManifest.self, from: data)
        } catch {
            throw EmbeddingServiceError.modelUnavailable("模型 manifest 解析失败：\(error.localizedDescription)")
        }
    }

    static func load(resourceName: String, bundle: Bundle = .main) throws -> EmbeddingModelManifest {
        guard let url = bundle.url(forResource: resourceName, withExtension: nil) else {
            throw EmbeddingServiceError.modelUnavailable("缺少模型 manifest：\(resourceName)。")
        }

        return try load(fileURL: url)
    }

    static func load(fileURL: URL) throws -> EmbeddingModelManifest {
        try decode(from: Data(contentsOf: fileURL))
    }

    var isTemplate: Bool {
        version == "local-clip-template"
            || source.contains("替换")
            || license.contains("替换")
            || notes?.contains("不是已验证模型配置") == true
    }

    var requiredResourceNames: [String] {
        var names = [
            "\(imageModelName).mlmodelc",
            "\(textModelName).mlmodelc"
        ]

        if let tokenizerResourceName = configuration.tokenizerResourceName {
            names.append(tokenizerResourceName)
        }

        return names
    }

    var integrationChecklistLines: [String] {
        [
            "模型版本：\(version)",
            "模型来源：\(source)",
            "许可证：\(license)",
            "图片模型：\(imageModelName).mlmodelc，\(Self.formattedSize(imageModelFileSizeMB, unit: "MB"))",
            "文本模型：\(textModelName).mlmodelc，\(Self.formattedSize(textModelFileSizeMB, unit: "MB"))",
            "tokenizer：\(configuration.tokenizerResourceName ?? "无")，\(Self.formattedSize(tokenizerFileSizeKB, unit: "KB"))",
            "图片模型 SHA-256：\(Self.formattedSHA256(imageModelSHA256))",
            "文本模型 SHA-256：\(Self.formattedSHA256(textModelSHA256))",
            "tokenizer SHA-256：\(Self.formattedSHA256(tokenizerSHA256))",
            "引入原因：\(Self.formattedText(integrationReason))",
            "替代方案：\(Self.formattedList(alternativesConsidered))",
            "影响评估：\(Self.formattedText(expectedImpact))",
            "图片输入：\(configuration.imageInputName) -> \(configuration.imageOutputName)，尺寸 \(configuration.imageInputSize)",
            "文本输入：\(configuration.textInputName) -> \(configuration.textOutputName)，序列长度 \(configuration.textSequenceLength)，起止 token \(Self.formattedTokenID(configuration.textStartTokenID))/\(Self.formattedTokenID(configuration.textEndTokenID))",
            "模板状态：\(isTemplate ? "仍是模板，不能用于验收" : "已替换为真实配置")"
        ]
    }

    var validationIssues: [String] {
        var issues: [String] = []

        if version.isEmpty {
            issues.append("manifest 缺少模型版本")
        }
        if source.isEmpty {
            issues.append("manifest 缺少模型来源")
        }
        if license.isEmpty {
            issues.append("manifest 缺少许可证说明")
        }
        if integrationReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append("manifest 缺少外部模型引入原因")
        }
        if alternativesConsidered?.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) != true {
            issues.append("manifest 缺少外部模型替代方案说明")
        }
        if expectedImpact?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append("manifest 缺少外部模型影响评估")
        }
        issues.append(contentsOf: licenseRestrictionIssues)
        if imageModelName.isEmpty {
            issues.append("manifest 缺少图片模型文件名")
        }
        if textModelName.isEmpty {
            issues.append("manifest 缺少文本模型文件名")
        }
        if imageModelFileSizeMB ?? 0 <= 0 {
            issues.append("manifest 缺少图片模型文件大小")
        }
        if textModelFileSizeMB ?? 0 <= 0 {
            issues.append("manifest 缺少文本模型文件大小")
        }
        if configuration.tokenizerResourceName != nil && tokenizerFileSizeKB ?? 0 <= 0 {
            issues.append("manifest 缺少 tokenizer 文件大小")
        }
        issues.append(contentsOf: self.sha256ValidationIssues)
        if isTemplate {
            issues.append("manifest 仍是模板占位，不能作为真实模型配置")
        }
        issues.append(contentsOf: configuration.validationIssues)

        return issues
    }

    var licenseRestrictionIssues: [String] {
        let normalizedLicense = license
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let restrictedTerms = [
            "research only",
            "research use only",
            "non commercial",
            "noncommercial",
            "academic use only",
            "evaluation only",
            "not for commercial",
            "仅研究",
            "研究用途",
            "非商业",
            "仅评估"
        ]

        guard restrictedTerms.contains(where: { normalizedLicense.contains($0) }) else {
            return []
        }

        return ["manifest 许可证包含研究、评估或非商业限制，不能作为默认可用模型"]
    }

    var sha256ValidationIssues: [String] {
        var issues: [String] = []
        appendSHA256Issue(
            label: "图片模型",
            value: imageModelSHA256,
            issues: &issues
        )
        appendSHA256Issue(
            label: "文本模型",
            value: textModelSHA256,
            issues: &issues
        )
        if configuration.tokenizerResourceName != nil {
            appendSHA256Issue(
                label: "tokenizer",
                value: tokenizerSHA256,
                issues: &issues
            )
        }
        return issues
    }

    private static func formattedSize(_ value: Double?, unit: String) -> String {
        guard let value, value > 0 else {
            return "大小未记录"
        }

        return String(format: "%.2f %@", value, unit)
    }

    private static func formattedSHA256(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "未记录"
        }

        return value
    }

    private static func formattedText(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "未记录"
        }

        return value
    }

    private static func formattedList(_ values: [String]?) -> String {
        let nonEmptyValues = values?.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? []
        guard !nonEmptyValues.isEmpty else {
            return "未记录"
        }

        return nonEmptyValues.joined(separator: "；")
    }

    private static func formattedTokenID(_ value: Int32?) -> String {
        value.map(String.init) ?? "未记录"
    }

    private func appendSHA256Issue(label: String, value: String?, issues: inout [String]) {
        let formattedLabel = label == "tokenizer" ? " tokenizer" : label
        guard let value, !value.isEmpty else {
            issues.append("manifest 缺少\(formattedLabel) SHA-256")
            return
        }

        let pattern = #"^[a-fA-F0-9]{64}$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            issues.append("manifest \(formattedLabel) SHA-256 格式不正确")
            return
        }
    }
}

struct EmbeddingModelResourceAudit {
    static func packagedResources(
        manifest: EmbeddingModelManifest?,
        modelInfo: EmbeddingModelInfo,
        imageModelURL: URL?,
        textModelURL: URL?,
        tokenizerURL: URL?,
        fileManager: FileManager = .default
    ) -> [EmbeddingModelPackagedResource] {
        var resources = [
            packagedResource(
                kind: .imageModel,
                name: "\(modelInfo.expectedImageModelName).mlmodelc",
                url: imageModelURL,
                expectedByteSize: manifest?.imageModelFileSizeMB.map { UInt64($0 * SizeUnit.megabytes.bytes) },
                expectedSHA256: manifest?.imageModelSHA256,
                unit: .megabytes,
                fileManager: fileManager
            ),
            packagedResource(
                kind: .textModel,
                name: "\(modelInfo.expectedTextModelName).mlmodelc",
                url: textModelURL,
                expectedByteSize: manifest?.textModelFileSizeMB.map { UInt64($0 * SizeUnit.megabytes.bytes) },
                expectedSHA256: manifest?.textModelSHA256,
                unit: .megabytes,
                fileManager: fileManager
            )
        ]

        if let tokenizerName = modelInfo.configuration?.tokenizerResourceName {
            resources.append(
                packagedResource(
                    kind: .tokenizer,
                    name: tokenizerName,
                    url: tokenizerURL,
                    expectedByteSize: manifest?.tokenizerFileSizeKB.map { UInt64($0 * SizeUnit.kilobytes.bytes) },
                    expectedSHA256: manifest?.tokenizerSHA256,
                    unit: .kilobytes,
                    fileManager: fileManager
                )
            )
        }

        return resources
    }

    static func sizeIssues(
        manifest: EmbeddingModelManifest,
        imageModelURL: URL?,
        textModelURL: URL?,
        tokenizerURL: URL?,
        fileManager: FileManager = .default
    ) -> [String] {
        var issues: [String] = []

        if let imageModelURL, let issue = sizeIssue(
            resourceName: "\(manifest.imageModelName).mlmodelc",
            actualURL: imageModelURL,
            expectedSize: manifest.imageModelFileSizeMB,
            unit: .megabytes,
            fileManager: fileManager
        ) {
            issues.append(issue)
        }

        if let textModelURL, let issue = sizeIssue(
            resourceName: "\(manifest.textModelName).mlmodelc",
            actualURL: textModelURL,
            expectedSize: manifest.textModelFileSizeMB,
            unit: .megabytes,
            fileManager: fileManager
        ) {
            issues.append(issue)
        }

        if let tokenizerURL,
           let tokenizerName = manifest.configuration.tokenizerResourceName,
           let issue = sizeIssue(
            resourceName: tokenizerName,
            actualURL: tokenizerURL,
            expectedSize: manifest.tokenizerFileSizeKB,
            unit: .kilobytes,
            fileManager: fileManager
           ) {
            issues.append(issue)
        }

        return issues
    }

    static func hashIssues(
        manifest: EmbeddingModelManifest,
        imageModelURL: URL?,
        textModelURL: URL?,
        tokenizerURL: URL?,
        fileManager: FileManager = .default
    ) -> [String] {
        var issues: [String] = []

        if let imageModelURL, let issue = hashIssue(
            resourceName: "\(manifest.imageModelName).mlmodelc",
            actualURL: imageModelURL,
            expectedSHA256: manifest.imageModelSHA256,
            fileManager: fileManager
        ) {
            issues.append(issue)
        }

        if let textModelURL, let issue = hashIssue(
            resourceName: "\(manifest.textModelName).mlmodelc",
            actualURL: textModelURL,
            expectedSHA256: manifest.textModelSHA256,
            fileManager: fileManager
        ) {
            issues.append(issue)
        }

        if let tokenizerURL,
           let tokenizerName = manifest.configuration.tokenizerResourceName,
           let issue = hashIssue(
            resourceName: tokenizerName,
            actualURL: tokenizerURL,
            expectedSHA256: manifest.tokenizerSHA256,
            fileManager: fileManager
           ) {
            issues.append(issue)
        }

        return issues
    }

    static func byteSize(at url: URL, fileManager: FileManager = .default) throws -> UInt64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw EmbeddingServiceError.modelUnavailable("资源不存在：\(url.lastPathComponent)。")
        }

        if !isDirectory.boolValue {
            let size = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            return size?.uint64Value ?? 0
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += UInt64(values.fileSize ?? 0)
            }
        }

        return total
    }

    static func sha256(at url: URL, fileManager: FileManager = .default) throws -> String {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw EmbeddingServiceError.modelUnavailable("资源不存在：\(url.lastPathComponent)。")
        }

        if !isDirectory.boolValue {
            return Self.hexDigest(SHA256.hash(data: try Data(contentsOf: url)))
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return Self.hexDigest(SHA256.hash(data: Data()))
        }

        var fileURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                fileURLs.append(fileURL)
            }
        }

        var hasher = SHA256()
        for fileURL in fileURLs.sorted(by: { $0.path < $1.path }) {
            let relativePath = fileURL.path
                .replacingOccurrences(of: url.path + "/", with: "")
            if let pathData = relativePath.data(using: .utf8) {
                hasher.update(data: pathData)
            }
            hasher.update(data: Data([0]))
            hasher.update(data: try Data(contentsOf: fileURL))
        }

        return Self.hexDigest(hasher.finalize())
    }

    private static func packagedResource(
        kind: EmbeddingModelPackagedResource.Kind,
        name: String,
        url: URL?,
        expectedByteSize: UInt64?,
        expectedSHA256: String?,
        unit: SizeUnit,
        fileManager: FileManager
    ) -> EmbeddingModelPackagedResource {
        guard let url else {
            return EmbeddingModelPackagedResource(
                kind: kind,
                name: name,
                isPresent: false,
                actualByteSize: nil,
                expectedByteSize: expectedByteSize,
                actualSHA256: nil,
                expectedSHA256: expectedSHA256,
                issue: "未找到"
            )
        }

        do {
            let actualByteSize = try byteSize(at: url, fileManager: fileManager)
            let issues = [
                sizeIssue(
                resourceName: name,
                actualURL: url,
                expectedSize: expectedByteSize.map { Double($0) / unit.bytes },
                unit: unit,
                fileManager: fileManager
                ),
                hashIssue(
                    resourceName: name,
                    actualURL: url,
                    expectedSHA256: expectedSHA256,
                    fileManager: fileManager
                )
            ].compactMap { $0 }
            return EmbeddingModelPackagedResource(
                kind: kind,
                name: name,
                isPresent: true,
                actualByteSize: actualByteSize,
                expectedByteSize: expectedByteSize,
                actualSHA256: try? sha256(at: url, fileManager: fileManager),
                expectedSHA256: expectedSHA256,
                issue: issues.isEmpty ? nil : issues.joined(separator: "；")
            )
        } catch {
            return EmbeddingModelPackagedResource(
                kind: kind,
                name: name,
                isPresent: true,
                actualByteSize: nil,
                expectedByteSize: expectedByteSize,
                actualSHA256: nil,
                expectedSHA256: expectedSHA256,
                issue: "文件大小读取失败：\(error.localizedDescription)"
            )
        }
    }

    private static func sizeIssue(
        resourceName: String,
        actualURL: URL,
        expectedSize: Double?,
        unit: SizeUnit,
        fileManager: FileManager
    ) -> String? {
        guard let expectedSize, expectedSize > 0 else {
            return nil
        }

        do {
            let actualBytes = try byteSize(at: actualURL, fileManager: fileManager)
            let expectedBytes = expectedSize * unit.bytes
            let actualSize = Double(actualBytes) / unit.bytes
            let toleranceBytes = max(expectedBytes * 0.05, unit.minimumToleranceBytes)

            guard abs(Double(actualBytes) - expectedBytes) > toleranceBytes else {
                return nil
            }

            return "\(resourceName) 实际大小 \(Self.format(actualSize, unit: unit)) 与 manifest 记录 \(Self.format(expectedSize, unit: unit)) 不一致"
        } catch {
            return "\(resourceName) 文件大小读取失败：\(error.localizedDescription)"
        }
    }

    private static func hashIssue(
        resourceName: String,
        actualURL: URL,
        expectedSHA256: String?,
        fileManager: FileManager
    ) -> String? {
        guard let expectedSHA256, !expectedSHA256.isEmpty else {
            return nil
        }

        do {
            let actualSHA256 = try sha256(at: actualURL, fileManager: fileManager)
            guard actualSHA256.lowercased() != expectedSHA256.lowercased() else {
                return nil
            }

            return "\(resourceName) SHA-256 与 manifest 记录不一致"
        } catch {
            return "\(resourceName) SHA-256 读取失败：\(error.localizedDescription)"
        }
    }

    private static func hexDigest<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func format(_ value: Double, unit: SizeUnit) -> String {
        String(format: "%.2f %@", value, unit.label)
    }

    private enum SizeUnit {
        case megabytes
        case kilobytes

        var bytes: Double {
            switch self {
            case .megabytes:
                return 1024 * 1024
            case .kilobytes:
                return 1024
            }
        }

        var minimumToleranceBytes: Double {
            switch self {
            case .megabytes:
                return 100 * 1024
            case .kilobytes:
                return 1 * 1024
            }
        }

        var label: String {
            switch self {
            case .megabytes:
                return "MB"
            case .kilobytes:
                return "KB"
            }
        }
    }
}

struct EmbeddingModelPackagedResource: Equatable {
    enum Kind: String, Equatable {
        case imageModel = "图片模型"
        case textModel = "文本模型"
        case tokenizer = "tokenizer"
    }

    let kind: Kind
    let name: String
    let isPresent: Bool
    let actualByteSize: UInt64?
    let expectedByteSize: UInt64?
    let actualSHA256: String?
    let expectedSHA256: String?
    let issue: String?

    var isValid: Bool {
        isPresent && issue == nil
    }

    var summaryLine: String {
        let presenceText = isPresent ? "已打包" : "未打包"
        let actualText = actualByteSize.map(Self.formatByteSize) ?? "实际大小未知"
        let expectedText = expectedByteSize.map(Self.formatByteSize) ?? "manifest 未记录大小"
        let hashText = Self.hashSummary(actual: actualSHA256, expected: expectedSHA256)
        let statusText = isValid ? "可用于预检" : "需处理"
        let issueText = issue.map { "，问题：\($0)" } ?? ""
        return "\(kind.rawValue)：\(name)，\(presenceText)，\(actualText)，manifest \(expectedText)，\(hashText)，\(statusText)\(issueText)"
    }

    var manifestSuggestionLines: [String] {
        guard isPresent else {
            return []
        }

        var lines: [String] = []
        if let actualByteSize {
            lines.append("\"\(sizeManifestKey)\": \(Self.formatManifestSize(actualByteSize, kind: kind))")
        }
        if let actualSHA256, !actualSHA256.isEmpty {
            lines.append("\"\(shaManifestKey)\": \"\(actualSHA256)\"")
        }

        return lines
    }

    private var sizeManifestKey: String {
        switch kind {
        case .imageModel:
            return "imageModelFileSizeMB"
        case .textModel:
            return "textModelFileSizeMB"
        case .tokenizer:
            return "tokenizerFileSizeKB"
        }
    }

    private var shaManifestKey: String {
        switch kind {
        case .imageModel:
            return "imageModelSHA256"
        case .textModel:
            return "textModelSHA256"
        case .tokenizer:
            return "tokenizerSHA256"
        }
    }

    private static func formatByteSize(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= 1024 * 1024 {
            return String(format: "%.2f MB", value / 1024 / 1024)
        }

        if value >= 1024 {
            return String(format: "%.2f KB", value / 1024)
        }

        return "\(bytes) B"
    }

    private static func formatManifestSize(_ bytes: UInt64, kind: Kind) -> String {
        let denominator: Double
        switch kind {
        case .imageModel, .textModel:
            denominator = 1024 * 1024
        case .tokenizer:
            denominator = 1024
        }

        return String(format: "%.6f", Double(bytes) / denominator)
    }

    private static func hashSummary(actual: String?, expected: String?) -> String {
        guard let expected, !expected.isEmpty else {
            return "manifest 未记录 SHA-256"
        }
        guard let actual, !actual.isEmpty else {
            return "SHA-256 未读取"
        }

        return actual.lowercased() == expected.lowercased()
            ? "SHA-256 匹配"
            : "SHA-256 不一致"
    }
}

struct EmbeddingModelReadinessReport: Equatable {
    let modelInfo: EmbeddingModelInfo
    let integrationChecklistLines: [String]
    let packagedResources: [EmbeddingModelPackagedResource]
    let manifestIssue: String?
    let hasImageModel: Bool
    let hasTextModel: Bool
    let hasTokenizer: Bool
    let configurationIssues: [String]

    init(
        modelInfo: EmbeddingModelInfo,
        integrationChecklistLines: [String] = [],
        packagedResources: [EmbeddingModelPackagedResource] = [],
        manifestIssue: String?,
        hasImageModel: Bool,
        hasTextModel: Bool,
        hasTokenizer: Bool,
        configurationIssues: [String]
    ) {
        self.modelInfo = modelInfo
        self.integrationChecklistLines = integrationChecklistLines
        self.packagedResources = packagedResources
        self.manifestIssue = manifestIssue
        self.hasImageModel = hasImageModel
        self.hasTextModel = hasTextModel
        self.hasTokenizer = hasTokenizer
        self.configurationIssues = configurationIssues
    }

    var isReady: Bool {
        manifestIssue == nil && hasImageModel && hasTextModel && hasTokenizer && configurationIssues.isEmpty
    }

    var missingItems: [String] {
        var items: [String] = []
        if !hasImageModel {
            items.append("\(modelInfo.expectedImageModelName).mlmodelc")
        }
        if !hasTextModel {
            items.append("\(modelInfo.expectedTextModelName).mlmodelc")
        }
        if let tokenizerName = modelInfo.configuration?.tokenizerResourceName, !hasTokenizer {
            items.append(tokenizerName)
        }
        if modelInfo.configuration == nil {
            items.append("模型输入输出和预处理配置")
        }

        return items
    }

    var diagnosticLines: [String] {
        var lines = [
            "模型版本：\(modelInfo.version)",
            "模型来源：\(modelInfo.source)",
            "许可证：\(modelInfo.license)"
        ]

        if isReady {
            lines.append("状态：模型资源和配置已就绪。")
        } else {
            if let manifestIssue {
                lines.append("manifest 问题：\(manifestIssue)")
            }
            let missingText = missingItems.isEmpty ? "无" : missingItems.joined(separator: "、")
            let issueText = configurationIssues.isEmpty ? "无" : configurationIssues.joined(separator: "、")
            lines.append("缺少资源：\(missingText)")
            lines.append("配置问题：\(issueText)")
        }

        return lines
    }

    var packagedResourceLines: [String] {
        packagedResources.map(\.summaryLine)
    }

    var manifestSuggestionLines: [String] {
        packagedResources.flatMap(\.manifestSuggestionLines)
    }

    var recoveryMessage: String {
        let allItems = [manifestIssue].compactMap { $0 } + missingItems + configurationIssues
        guard !allItems.isEmpty else {
            return "模型资源和配置已就绪。"
        }

        return "请先补齐：\(allItems.joined(separator: "、"))。"
    }
}

struct EmbeddingModelPackageReport: Equatable {
    let packageURL: URL
    let manifestFileName: String
    let manifest: EmbeddingModelManifest?
    let readinessReport: EmbeddingModelReadinessReport

    var isReadyForRuntimeValidation: Bool {
        readinessReport.isReady
    }

    var summaryLines: [String] {
        var lines = [
            "模型包目录：\(packageURL.lastPathComponent)",
            "manifest：\(manifestFileName)",
            "状态：\(isReadyForRuntimeValidation ? "模型包预检可进入真实样本技术验证尝试" : "仍需补齐模型包")"
        ]

        lines.append(contentsOf: readinessReport.diagnosticLines)
        if !readinessReport.packagedResourceLines.isEmpty {
            lines.append("资源清单：")
            lines.append(contentsOf: readinessReport.packagedResourceLines)
        }
        if !readinessReport.manifestSuggestionLines.isEmpty {
            lines.append("manifest 建议字段：")
            lines.append(contentsOf: readinessReport.manifestSuggestionLines)
        }
        lines.append("恢复动作：\(readinessReport.recoveryMessage)")
        return lines
    }

    var markdownReport: String {
        var lines = [
            "# 本地图文模型包预检报告",
            "",
            "- 模型包目录：\(packageURL.lastPathComponent)",
            "- manifest：\(manifestFileName)",
            "- 状态：\(isReadyForRuntimeValidation ? "模型包预检可进入真实样本技术验证尝试" : "仍需补齐模型包")",
            "",
            "## 模型诊断",
            ""
        ]

        lines.append(contentsOf: readinessReport.diagnosticLines.map { "- \($0)" })

        if !readinessReport.packagedResourceLines.isEmpty {
            lines.append("")
            lines.append("## 资源清单")
            lines.append("")
            lines.append(contentsOf: readinessReport.packagedResourceLines.map { "- \($0)" })
        }

        if !readinessReport.manifestSuggestionLines.isEmpty {
            lines.append("")
            lines.append("## manifest 建议字段")
            lines.append("")
            lines.append("```json")
            lines.append(contentsOf: readinessReport.manifestSuggestionLines)
            lines.append("```")
        }

        lines.append("")
        lines.append("## 限制")
        lines.append("")
        lines.append("- 本报告会验证本地资源存在性、manifest 元数据、文件大小、SHA-256，并尝试加载 Core ML 模型和检查 manifest 声明的输入输出接口、输入 shape 和输入数据类型。")
        lines.append("- 本报告不会运行图片编码、文本编码或相似度比较。")
        lines.append("- 本报告不证明图文向量处于同一语义空间，也不替代 5 张真实 Photos 样本技术验证。")
        lines.append("- 不应把通过本预检的模型直接标记为视觉语义搜索已完成。")

        return lines.joined(separator: "\n")
    }
}

struct EmbeddingModelPackageInspector {
    static let defaultManifestFileName = "EmbeddingModelManifest.json"

    static func inspect(
        packageURL: URL,
        manifestFileName: String = defaultManifestFileName,
        fileManager: FileManager = .default
    ) -> EmbeddingModelPackageReport {
        let manifestURL = packageURL.appendingPathComponent(manifestFileName)
        let manifest: EmbeddingModelManifest
        do {
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                throw EmbeddingServiceError.modelUnavailable("缺少模型 manifest：\(manifestFileName)。")
            }
            manifest = try EmbeddingModelManifest.decode(from: Data(contentsOf: manifestURL))
        } catch {
            let readinessReport = EmbeddingModelReadinessReport(
                modelInfo: .unconfiguredCLIP,
                manifestIssue: error.localizedDescription,
                hasImageModel: false,
                hasTextModel: false,
                hasTokenizer: false,
                configurationIssues: []
            )
            return EmbeddingModelPackageReport(
                packageURL: packageURL,
                manifestFileName: manifestFileName,
                manifest: nil,
                readinessReport: readinessReport
            )
        }

        let imageModelURL = existingURL(
            packageURL.appendingPathComponent("\(manifest.imageModelName).mlmodelc", isDirectory: true),
            fileManager: fileManager
        )
        let textModelURL = existingURL(
            packageURL.appendingPathComponent("\(manifest.textModelName).mlmodelc", isDirectory: true),
            fileManager: fileManager
        )
        let tokenizerURL = manifest.configuration.tokenizerResourceName.flatMap { name in
            existingURL(packageURL.appendingPathComponent(name), fileManager: fileManager)
        }

        var configurationIssues = manifest.validationIssues
        configurationIssues.append(contentsOf: EmbeddingModelResourceAudit.sizeIssues(
            manifest: manifest,
            imageModelURL: imageModelURL,
            textModelURL: textModelURL,
            tokenizerURL: tokenizerURL,
            fileManager: fileManager
        ))
        configurationIssues.append(contentsOf: EmbeddingModelResourceAudit.hashIssues(
            manifest: manifest,
            imageModelURL: imageModelURL,
            textModelURL: textModelURL,
            tokenizerURL: tokenizerURL,
            fileManager: fileManager
        ))
        configurationIssues.append(contentsOf: EmbeddingModelRuntimeAudit.runtimeIssues(
            manifest: manifest,
            imageModelURL: imageModelURL,
            textModelURL: textModelURL
        ))

        let packagedResources = EmbeddingModelResourceAudit.packagedResources(
            manifest: manifest,
            modelInfo: manifest.modelInfo,
            imageModelURL: imageModelURL,
            textModelURL: textModelURL,
            tokenizerURL: tokenizerURL,
            fileManager: fileManager
        )
        let readinessReport = EmbeddingModelReadinessReport(
            modelInfo: manifest.modelInfo,
            integrationChecklistLines: manifest.integrationChecklistLines,
            packagedResources: packagedResources,
            manifestIssue: nil,
            hasImageModel: imageModelURL != nil,
            hasTextModel: textModelURL != nil,
            hasTokenizer: manifest.configuration.tokenizerResourceName == nil || tokenizerURL != nil,
            configurationIssues: configurationIssues
        )

        return EmbeddingModelPackageReport(
            packageURL: packageURL,
            manifestFileName: manifestFileName,
            manifest: manifest,
            readinessReport: readinessReport
        )
    }

    private static func existingURL(_ url: URL, fileManager: FileManager) -> URL? {
        fileManager.fileExists(atPath: url.path) ? url : nil
    }
}

struct EmbeddingModelRuntimeAudit {
    static func runtimeIssues(
        manifest: EmbeddingModelManifest,
        imageModelURL: URL?,
        textModelURL: URL?
    ) -> [String] {
        var issues: [String] = []
        issues.append(contentsOf: modelIssues(
            resourceName: "\(manifest.imageModelName).mlmodelc",
            url: imageModelURL,
            inputName: manifest.configuration.imageInputName,
            outputName: manifest.configuration.imageOutputName,
            expectedInputShape: [
                1,
                3,
                manifest.configuration.imageInputSize,
                manifest.configuration.imageInputSize
            ],
            expectedInputDataType: .float32,
            allowsImageInput: true
        ))
        issues.append(contentsOf: modelIssues(
            resourceName: "\(manifest.textModelName).mlmodelc",
            url: textModelURL,
            inputName: manifest.configuration.textInputName,
            outputName: manifest.configuration.textOutputName,
            expectedInputShape: [
                1,
                manifest.configuration.textSequenceLength
            ],
            expectedInputDataType: .int32,
            allowsImageInput: false
        ))
        return issues
    }

    private static func modelIssues(
        resourceName: String,
        url: URL?,
        inputName: String,
        outputName: String,
        expectedInputShape: [Int],
        expectedInputDataType: MLMultiArrayDataType,
        allowsImageInput: Bool
    ) -> [String] {
        guard let url else {
            return []
        }

        do {
            let model = try MLModel(contentsOf: url)
            return interfaceIssues(
                resourceName: resourceName,
                model: model,
                inputName: inputName,
                outputName: outputName,
                expectedInputShape: expectedInputShape,
                expectedInputDataType: expectedInputDataType,
                allowsImageInput: allowsImageInput
            )
        } catch {
            return ["\(resourceName) Core ML 加载失败：\(error.localizedDescription)"]
        }
    }

    private static func interfaceIssues(
        resourceName: String,
        model: MLModel,
        inputName: String,
        outputName: String,
        expectedInputShape: [Int],
        expectedInputDataType: MLMultiArrayDataType,
        allowsImageInput: Bool
    ) -> [String] {
        var issues: [String] = []
        let inputs = model.modelDescription.inputDescriptionsByName
        let outputs = model.modelDescription.outputDescriptionsByName

        if let input = inputs[inputName] {
            if allowsImageInput, input.type == .image {
                if input.imageConstraint?.pixelsWide != expectedInputShape.last
                    || input.imageConstraint?.pixelsHigh != expectedInputShape.last {
                    issues.append("\(resourceName) 图片输入尺寸与 manifest 不一致")
                }
            } else if input.type != .multiArray {
                issues.append("\(resourceName) 输入 \(inputName) 类型不是 MLMultiArray")
            } else {
                issues.append(contentsOf: multiArrayInputIssues(
                    resourceName: resourceName,
                    inputName: inputName,
                    actualShape: input.multiArrayConstraint?.shape,
                    actualDataType: input.multiArrayConstraint?.dataType,
                    expectedShape: expectedInputShape,
                    expectedDataType: expectedInputDataType
                ))
            }
        } else {
            issues.append("\(resourceName) 缺少输入 \(inputName)")
        }

        if let output = outputs[outputName] {
            if output.type != .multiArray {
                issues.append("\(resourceName) 输出 \(outputName) 类型不是 MLMultiArray")
            }
        } else {
            issues.append("\(resourceName) 缺少输出 \(outputName)")
        }

        return issues
    }

    static func multiArrayInputIssues(
        resourceName: String,
        inputName: String,
        actualShape: [NSNumber]?,
        actualDataType: MLMultiArrayDataType?,
        expectedShape: [Int],
        expectedDataType: MLMultiArrayDataType
    ) -> [String] {
        shapeIssues(
            resourceName: resourceName,
            inputName: inputName,
            actualShape: actualShape,
            expectedShape: expectedShape
        ) + dataTypeIssues(
            resourceName: resourceName,
            inputName: inputName,
            actualDataType: actualDataType,
            expectedDataType: expectedDataType
        )
    }

    static func shapeIssues(
        resourceName: String,
        inputName: String,
        actualShape: [NSNumber]?,
        expectedShape: [Int]
    ) -> [String] {
        guard let actualShape, !actualShape.isEmpty else {
            return ["\(resourceName) 输入 \(inputName) 未声明 MLMultiArray shape，无法确认与 manifest 一致"]
        }

        let actualValues = actualShape.map(\.intValue)
        guard actualValues == expectedShape else {
            return [
                "\(resourceName) 输入 \(inputName) shape \(formatShape(actualValues)) 与 manifest 预期 \(formatShape(expectedShape)) 不一致"
            ]
        }

        return []
    }

    static func dataTypeIssues(
        resourceName: String,
        inputName: String,
        actualDataType: MLMultiArrayDataType?,
        expectedDataType: MLMultiArrayDataType
    ) -> [String] {
        guard let actualDataType else {
            return ["\(resourceName) 输入 \(inputName) 未声明 MLMultiArray 数据类型，无法确认与 manifest 一致"]
        }

        guard actualDataType == expectedDataType else {
            return [
                "\(resourceName) 输入 \(inputName) 数据类型 \(formatDataType(actualDataType)) 与预期 \(formatDataType(expectedDataType)) 不一致"
            ]
        }

        return []
    }

    private static func formatShape(_ values: [Int]) -> String {
        "[" + values.map(String.init).joined(separator: ",") + "]"
    }

    private static func formatDataType(_ dataType: MLMultiArrayDataType) -> String {
        switch dataType {
        case .double:
            return "double"
        case .float32:
            return "float32"
        case .float16:
            return "float16"
        case .int32:
            return "int32"
        case .int8:
            return "int8"
        @unknown default:
            return "unknown"
        }
    }
}

enum EmbeddingFailureType: String, CaseIterable, Codable, Equatable {
    case modelUnavailable
    case imageUnavailable
    case imageEncodingFailed
    case textEncodingFailed
    case vectorDimensionMismatch
    case unknown

    var displayName: String {
        switch self {
        case .modelUnavailable:
            return "模型不可用"
        case .imageUnavailable:
            return "图片不可用"
        case .imageEncodingFailed:
            return "图片向量失败"
        case .textEncodingFailed:
            return "文本向量失败"
        case .vectorDimensionMismatch:
            return "向量维度不一致"
        case .unknown:
            return "未知失败"
        }
    }
}

enum EmbeddingServiceError: LocalizedError, Equatable {
    case modelUnavailable(String)
    case imageEncodingFailed(String)
    case textEncodingFailed(String)
    case vectorDimensionMismatch(image: Int, text: Int)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let message):
            return "本地图文向量模型不可用：\(message)"
        case .imageEncodingFailed(let message):
            return "图片向量生成失败：\(message)"
        case .textEncodingFailed(let message):
            return "文本向量生成失败：\(message)"
        case .vectorDimensionMismatch(let image, let text):
            return "图文向量维度不一致：图片 \(image)，文本 \(text)。"
        }
    }

    var failureType: EmbeddingFailureType {
        switch self {
        case .modelUnavailable:
            return .modelUnavailable
        case .imageEncodingFailed:
            return .imageEncodingFailed
        case .textEncodingFailed:
            return .textEncodingFailed
        case .vectorDimensionMismatch:
            return .vectorDimensionMismatch
        }
    }
}

struct EmbeddingVector: Codable, Equatable {
    let values: [Float]

    var dimension: Int {
        values.count
    }

    func normalized() -> EmbeddingVector {
        let magnitude = sqrt(values.reduce(Float(0)) { $0 + ($1 * $1) })
        guard magnitude > 0 else {
            return self
        }

        return EmbeddingVector(values: values.map { $0 / magnitude })
    }

    func cosineSimilarity(to other: EmbeddingVector) throws -> Double {
        guard values.count == other.values.count else {
            throw EmbeddingServiceError.vectorDimensionMismatch(
                image: values.count,
                text: other.values.count
            )
        }

        let left = normalized().values
        let right = other.normalized().values
        let score = zip(left, right).reduce(Float(0)) { result, pair in
            result + pair.0 * pair.1
        }
        return Double(score)
    }

    func encodedData() -> Data {
        values.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    static func decode(from data: Data) -> EmbeddingVector? {
        guard data.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            return nil
        }

        let count = data.count / MemoryLayout<Float>.stride
        let values = data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self).prefix(count))
        }
        return EmbeddingVector(values: values)
    }
}

struct EmbeddingImagePreprocessor {
    static func normalizedCHWArray(
        from image: CGImage,
        size: Int,
        mean: [Double],
        standardDeviation: [Double]
    ) throws -> MLMultiArray {
        guard size > 0, mean.count == 3, standardDeviation.count == 3 else {
            throw EmbeddingServiceError.imageEncodingFailed("图片预处理参数不完整。")
        }

        let side = min(image.width, image.height)
        let cropRect = CGRect(
            x: (image.width - side) / 2,
            y: (image.height - side) / 2,
            width: side,
            height: side
        )
        let croppedImage = image.cropping(to: cropRect) ?? image
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: size * size * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw EmbeddingServiceError.imageEncodingFailed("无法创建图片预处理缓冲区。")
        }

        context.interpolationQuality = .high
        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: size), NSNumber(value: size)],
            dataType: .float32
        )
        let output = array.dataPointer.bindMemory(to: Float32.self, capacity: 3 * size * size)

        for y in 0..<size {
            for x in 0..<size {
                let pixelOffset = (y * bytesPerRow) + (x * bytesPerPixel)
                let channels = [
                    Double(pixels[pixelOffset]) / 255.0,
                    Double(pixels[pixelOffset + 1]) / 255.0,
                    Double(pixels[pixelOffset + 2]) / 255.0
                ]

                for channel in 0..<3 {
                    let outputOffset = channel * size * size + y * size + x
                    output[outputOffset] = Float((channels[channel] - mean[channel]) / standardDeviation[channel])
                }
            }
        }

        return array
    }
}

struct EmbeddingTokenizedText: Equatable {
    let tokenIDs: [Int32]
}

protocol EmbeddingTextTokenizing: Sendable {
    func tokenize(_ text: String) throws -> EmbeddingTokenizedText
}

struct UnavailableEmbeddingTokenizer: EmbeddingTextTokenizing {
    func tokenize(_ text: String) throws -> EmbeddingTokenizedText {
        throw EmbeddingServiceError.textEncodingFailed(
            "尚未接入真实 tokenizer。请加入与本地文本编码器匹配的 tokenizer，并确认许可证、词表和预处理规则。"
        )
    }
}

struct EmbeddingBPETokenizerSpec: Codable, Equatable {
    let vocabulary: [String: Int32]
    let merges: [[String]]
    let startToken: String
    let endToken: String
    let unknownToken: String?
    let lowercasesInput: Bool

    var validationIssues: [String] {
        var issues: [String] = []

        if vocabulary.isEmpty {
            issues.append("tokenizer 词表为空")
        }
        if vocabulary[startToken] == nil {
            issues.append("tokenizer 词表缺少起始 token：\(startToken)")
        }
        if vocabulary[endToken] == nil {
            issues.append("tokenizer 词表缺少结束 token：\(endToken)")
        }
        if let unknownToken, vocabulary[unknownToken] == nil {
            issues.append("tokenizer 词表缺少 unknown token：\(unknownToken)")
        }
        for merge in merges where merge.count != 2 {
            issues.append("tokenizer merges 中存在非二元合并规则")
            break
        }

        return issues
    }
}

struct EmbeddingBPETokenizer: EmbeddingTextTokenizing {
    private let spec: EmbeddingBPETokenizerSpec
    private let mergeRanks: [TokenPair: Int]

    init(spec: EmbeddingBPETokenizerSpec) throws {
        let issues = spec.validationIssues
        guard issues.isEmpty else {
            throw EmbeddingServiceError.textEncodingFailed(issues.joined(separator: "、"))
        }

        var ranks: [TokenPair: Int] = [:]
        for (index, merge) in spec.merges.enumerated() {
            ranks[TokenPair(left: merge[0], right: merge[1])] = index
        }

        self.spec = spec
        self.mergeRanks = ranks
    }

    var startTokenID: Int32? {
        spec.vocabulary[spec.startToken]
    }

    var endTokenID: Int32? {
        spec.vocabulary[spec.endToken]
    }

    func specialTokenIssues(configuration: EmbeddingModelConfiguration) -> [String] {
        var issues: [String] = []
        if let expectedStart = configuration.textStartTokenID,
           let actualStart = startTokenID,
           expectedStart != actualStart {
            issues.append("tokenizer 起始 token ID \(actualStart) 与 manifest 记录 \(expectedStart) 不一致")
        }
        if let expectedEnd = configuration.textEndTokenID,
           let actualEnd = endTokenID,
           expectedEnd != actualEnd {
            issues.append("tokenizer 结束 token ID \(actualEnd) 与 manifest 记录 \(expectedEnd) 不一致")
        }
        return issues
    }

    static func load(from url: URL) throws -> EmbeddingBPETokenizer {
        do {
            let spec = try JSONDecoder().decode(
                EmbeddingBPETokenizerSpec.self,
                from: Data(contentsOf: url)
            )
            return try EmbeddingBPETokenizer(spec: spec)
        } catch let error as EmbeddingServiceError {
            throw error
        } catch {
            throw EmbeddingServiceError.textEncodingFailed("tokenizer 解析失败：\(error.localizedDescription)")
        }
    }

    func tokenize(_ text: String) throws -> EmbeddingTokenizedText {
        guard let startTokenID = spec.vocabulary[spec.startToken],
              let endTokenID = spec.vocabulary[spec.endToken] else {
            throw EmbeddingServiceError.textEncodingFailed("tokenizer 缺少起始或结束 token ID。")
        }

        let normalizedText = spec.lowercasesInput ? text.lowercased() : text
        var tokenIDs = [startTokenID]
        for word in normalizedText.split(whereSeparator: \.isWhitespace) {
            let pieces = bpePieces(for: String(word))
            for piece in pieces {
                if let tokenID = spec.vocabulary[piece] {
                    tokenIDs.append(tokenID)
                } else if let unknownToken = spec.unknownToken,
                          let unknownTokenID = spec.vocabulary[unknownToken] {
                    tokenIDs.append(unknownTokenID)
                } else {
                    throw EmbeddingServiceError.textEncodingFailed("tokenizer 词表缺少 token：\(piece)。")
                }
            }
        }
        tokenIDs.append(endTokenID)

        return EmbeddingTokenizedText(tokenIDs: tokenIDs)
    }

    private func bpePieces(for word: String) -> [String] {
        if spec.vocabulary[word] != nil {
            return [word]
        }

        var pieces = word.map { String($0) }
        guard pieces.count > 1 else {
            return pieces
        }

        while let merge = bestMerge(in: pieces) {
            var nextPieces: [String] = []
            var index = 0
            while index < pieces.count {
                if index < pieces.count - 1,
                   pieces[index] == merge.left,
                   pieces[index + 1] == merge.right {
                    nextPieces.append(merge.left + merge.right)
                    index += 2
                } else {
                    nextPieces.append(pieces[index])
                    index += 1
                }
            }

            if nextPieces == pieces {
                break
            }
            pieces = nextPieces
        }

        return pieces
    }

    private func bestMerge(in pieces: [String]) -> TokenPair? {
        var selectedPair: TokenPair?
        var selectedRank = Int.max

        for index in 0..<(pieces.count - 1) {
            let pair = TokenPair(left: pieces[index], right: pieces[index + 1])
            guard let rank = mergeRanks[pair], rank < selectedRank else {
                continue
            }

            selectedPair = pair
            selectedRank = rank
        }

        return selectedPair
    }

    private struct TokenPair: Hashable {
        let left: String
        let right: String
    }
}

struct CLIPBPETokenizer: EmbeddingTextTokenizing {
    private let vocabulary: [String: Int32]
    private let mergeRanks: [TokenPair: Int]
    private let byteEncoder: [UInt8: Character]
    private let startToken: String
    private let endToken: String

    init(vocabularyURL: URL, mergesURL: URL) throws {
        let loadedVocabulary: [String: Int32]
        do {
            let data = try Data(contentsOf: vocabularyURL)
            loadedVocabulary = try JSONDecoder().decode([String: Int32].self, from: data)
            self.vocabulary = loadedVocabulary
            let lines = try String(contentsOf: mergesURL, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.hasPrefix("#") }
            self.mergeRanks = Dictionary(uniqueKeysWithValues: lines.enumerated().compactMap { index, line in
                let parts = line.split(separator: " ").map(String.init)
                guard parts.count == 2 else {
                    return nil
                }
                return (TokenPair(left: parts[0], right: parts[1]), index)
            })
            self.byteEncoder = Self.makeByteEncoder()
        } catch {
            throw EmbeddingServiceError.textEncodingFailed("CLIP tokenizer 加载失败：\(error.localizedDescription)")
        }

        guard let startToken = ["<|startoftext|>", "<start_of_text>"].first(where: {
                  loadedVocabulary[$0] != nil
              }),
              let endToken = ["<|endoftext|>", "<end_of_text>"].first(where: {
                  loadedVocabulary[$0] != nil
              }) else {
            throw EmbeddingServiceError.textEncodingFailed("CLIP tokenizer 缺少起止 token。")
        }
        self.startToken = startToken
        self.endToken = endToken
    }

    var startTokenID: Int32? {
        vocabulary[startToken]
    }

    var endTokenID: Int32? {
        vocabulary[endToken]
    }

    func tokenize(_ text: String) throws -> EmbeddingTokenizedText {
        guard let startTokenID, let endTokenID else {
            throw EmbeddingServiceError.textEncodingFailed("CLIP tokenizer 缺少起止 token ID。")
        }

        let normalized = text.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(normalized.startIndex..., in: normalized)
        var tokenIDs = [startTokenID]

        for match in regex.matches(in: normalized, range: range) {
            guard let tokenRange = Range(match.range, in: normalized) else {
                continue
            }
            let byteEncoded = String(normalized[tokenRange].utf8.compactMap { byteEncoder[$0] })
            for piece in bpePieces(for: byteEncoded) {
                guard let tokenID = vocabulary[piece] else {
                    throw EmbeddingServiceError.textEncodingFailed("CLIP tokenizer 词表缺少 token：\(piece)。")
                }
                tokenIDs.append(tokenID)
            }
        }
        tokenIDs.append(endTokenID)
        return EmbeddingTokenizedText(tokenIDs: tokenIDs)
    }

    private func bpePieces(for token: String) -> [String] {
        var pieces = token.map(String.init)
        guard !pieces.isEmpty else {
            return []
        }
        pieces[pieces.count - 1] += "</w>"

        while pieces.count > 1 {
            var selected: TokenPair?
            var selectedRank = Int.max
            for index in 0..<(pieces.count - 1) {
                let pair = TokenPair(left: pieces[index], right: pieces[index + 1])
                if let rank = mergeRanks[pair], rank < selectedRank {
                    selected = pair
                    selectedRank = rank
                }
            }
            guard let selected else {
                break
            }

            var merged: [String] = []
            var index = 0
            while index < pieces.count {
                if index < pieces.count - 1,
                   pieces[index] == selected.left,
                   pieces[index + 1] == selected.right {
                    merged.append(selected.left + selected.right)
                    index += 2
                } else {
                    merged.append(pieces[index])
                    index += 1
                }
            }
            pieces = merged
        }
        return pieces
    }

    private static func makeByteEncoder() -> [UInt8: Character] {
        var bytes = Array(33...126) + Array(161...172) + Array(174...255)
        var unicodeValues = bytes
        var extra = 0
        for byte in 0...255 where !bytes.contains(byte) {
            bytes.append(byte)
            unicodeValues.append(256 + extra)
            extra += 1
        }

        return Dictionary(uniqueKeysWithValues: zip(bytes, unicodeValues).compactMap { byte, value in
            UnicodeScalar(value).map { (UInt8(byte), Character(String($0))) }
        })
    }

    private struct TokenPair: Hashable {
        let left: String
        let right: String
    }
}

struct EmbeddingTextInputBuilder {
    static func tokenArray(
        from tokenizedText: EmbeddingTokenizedText,
        sequenceLength: Int,
        padTokenID: Int32
    ) throws -> MLMultiArray {
        guard sequenceLength > 0 else {
            throw EmbeddingServiceError.textEncodingFailed("文本 token 序列长度必须大于 0。")
        }
        guard !tokenizedText.tokenIDs.isEmpty else {
            throw EmbeddingServiceError.textEncodingFailed("tokenizer 返回了空 token 序列。")
        }
        guard tokenizedText.tokenIDs.count <= sequenceLength else {
            throw EmbeddingServiceError.textEncodingFailed(
                "文本 token 数量 \(tokenizedText.tokenIDs.count) 超出模型序列长度 \(sequenceLength)。"
            )
        }

        let array = try MLMultiArray(
            shape: [1, NSNumber(value: sequenceLength)],
            dataType: .int32
        )
        let values = array.dataPointer.bindMemory(to: Int32.self, capacity: sequenceLength)

        for index in 0..<sequenceLength {
            values[index] = index < tokenizedText.tokenIDs.count
                ? tokenizedText.tokenIDs[index]
                : padTokenID
        }

        return array
    }
}

struct EmbeddingModelOutputDecoder {
    static func vector(from multiArray: MLMultiArray) throws -> EmbeddingVector {
        guard multiArray.count > 0 else {
            throw EmbeddingServiceError.imageEncodingFailed("模型输出为空向量。")
        }

        var values: [Float] = []
        values.reserveCapacity(multiArray.count)

        switch multiArray.dataType {
        case .float32:
            let pointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: multiArray.count)
            for index in 0..<multiArray.count {
                values.append(pointer[index])
            }
        case .double:
            let pointer = multiArray.dataPointer.bindMemory(to: Double.self, capacity: multiArray.count)
            for index in 0..<multiArray.count {
                values.append(Float(pointer[index]))
            }
        case .int32:
            let pointer = multiArray.dataPointer.bindMemory(to: Int32.self, capacity: multiArray.count)
            for index in 0..<multiArray.count {
                values.append(Float(pointer[index]))
            }
        default:
            for index in 0..<multiArray.count {
                values.append(multiArray[index].floatValue)
            }
        }

        return EmbeddingVector(values: values)
    }
}

protocol EmbeddingServicing {
    var modelInfo: EmbeddingModelInfo { get }
    func modelReadinessReport() -> EmbeddingModelReadinessReport
    func validateModelAvailability() throws
    func encodeImage(_ image: CGImage) async throws -> EmbeddingVector
    func encodeText(_ text: String) async throws -> EmbeddingVector
}

struct EmbeddingInferenceExecutionPolicy {
    static let priority: TaskPriority = .utility

    static func mainThreadIssue(
        operation: String,
        isMainThread: Bool = Thread.isMainThread
    ) -> String? {
        guard isMainThread else {
            return nil
        }

        return "\(operation) 不应在主线程运行。请通过后台任务执行本地 Core ML 推理，避免阻塞界面。"
    }

    static func validateBackgroundExecution(operation: String) throws {
        if let issue = mainThreadIssue(operation: operation) {
            throw EmbeddingServiceError.modelUnavailable(issue)
        }
    }
}

struct EmbeddingService: EmbeddingServicing {
    static let defaultManifestResourceName = "EmbeddingModelManifest.json"
    static let defaultLocalPackageDirectoryName = "EmbeddingModelPackage"

    let modelInfo: EmbeddingModelInfo
    private let bundle: Bundle
    private let localModelPackageURL: URL?
    private let tokenizer: any EmbeddingTextTokenizing
    private let manifest: EmbeddingModelManifest?
    private let manifestIssue: String?
    private let tokenizerIssue: String?

    init(
        modelInfo: EmbeddingModelInfo = .unconfiguredCLIP,
        bundle: Bundle = .main,
        localModelPackageURL: URL? = nil,
        tokenizer: any EmbeddingTextTokenizing = UnavailableEmbeddingTokenizer(),
        manifest: EmbeddingModelManifest? = nil,
        manifestIssue: String? = nil,
        tokenizerIssue: String? = nil
    ) {
        self.modelInfo = modelInfo
        self.bundle = bundle
        self.localModelPackageURL = localModelPackageURL
        self.tokenizer = tokenizer
        self.manifest = manifest
        self.manifestIssue = manifestIssue
        self.tokenizerIssue = tokenizerIssue
    }

    init(
        manifest: EmbeddingModelManifest,
        bundle: Bundle = .main,
        localModelPackageURL: URL? = nil,
        tokenizer: any EmbeddingTextTokenizing = UnavailableEmbeddingTokenizer(),
        tokenizerIssue: String? = nil
    ) {
        self.init(
            modelInfo: manifest.modelInfo,
            bundle: bundle,
            localModelPackageURL: localModelPackageURL,
            tokenizer: tokenizer,
            manifest: manifest,
            manifestIssue: manifest.validationIssues.isEmpty
                ? nil
                : manifest.validationIssues.joined(separator: "、"),
            tokenizerIssue: tokenizerIssue
        )
    }

    static func bundledOrUnconfigured(
        manifestResourceName: String = defaultManifestResourceName,
        bundle: Bundle = .main,
        tokenizer: (any EmbeddingTextTokenizing)? = nil
    ) -> EmbeddingService {
        let manifest: EmbeddingModelManifest
        do {
            manifest = try EmbeddingModelManifest.load(
                resourceName: manifestResourceName,
                bundle: bundle
            )
        } catch {
            return EmbeddingService(
                modelInfo: .unconfiguredCLIP,
                bundle: bundle,
                tokenizer: tokenizer ?? UnavailableEmbeddingTokenizer(),
                manifest: nil,
                manifestIssue: error.localizedDescription
            )
        }

        let tokenizerLoadResult = loadBundledTokenizer(
            manifest: manifest,
            bundle: bundle,
            overrideTokenizer: tokenizer
        )
        return EmbeddingService(
            manifest: manifest,
            bundle: bundle,
            tokenizer: tokenizerLoadResult.tokenizer,
            tokenizerIssue: tokenizerLoadResult.issue
        )
    }

    static func localPackageOrBundledOrUnconfigured(
        localPackageURL: URL = defaultLocalPackageURL(),
        manifestResourceName: String = defaultManifestResourceName,
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        tokenizer: (any EmbeddingTextTokenizing)? = nil
    ) -> EmbeddingService {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: localPackageURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return localPackageOrUnconfigured(
                localPackageURL: localPackageURL,
                manifestResourceName: manifestResourceName,
                bundle: bundle,
                fileManager: fileManager,
                tokenizer: tokenizer
            )
        }

        return bundledOrUnconfigured(
            manifestResourceName: manifestResourceName,
            bundle: bundle,
            tokenizer: tokenizer
        )
    }

    static func localPackageOrUnconfigured(
        localPackageURL: URL,
        manifestResourceName: String = defaultManifestResourceName,
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        tokenizer: (any EmbeddingTextTokenizing)? = nil
    ) -> EmbeddingService {
        let manifestURL = localPackageURL.appendingPathComponent(manifestResourceName)
        let manifest: EmbeddingModelManifest
        do {
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                throw EmbeddingServiceError.modelUnavailable("本机模型包缺少模型 manifest：\(manifestResourceName)。")
            }
            manifest = try EmbeddingModelManifest.load(fileURL: manifestURL)
        } catch {
            return EmbeddingService(
                modelInfo: .unconfiguredCLIP,
                bundle: bundle,
                localModelPackageURL: localPackageURL,
                tokenizer: tokenizer ?? UnavailableEmbeddingTokenizer(),
                manifest: nil,
                manifestIssue: error.localizedDescription
            )
        }

        let tokenizerLoadResult = loadTokenizer(
            manifest: manifest,
            resourceURL: { resourceName in
                let url = localPackageURL.appendingPathComponent(resourceName)
                return fileManager.fileExists(atPath: url.path) ? url : nil
            },
            overrideTokenizer: tokenizer
        )
        return EmbeddingService(
            manifest: manifest,
            bundle: bundle,
            localModelPackageURL: localPackageURL,
            tokenizer: tokenizerLoadResult.tokenizer,
            tokenizerIssue: tokenizerLoadResult.issue
        )
    }

    static func defaultLocalPackageURL(fileManager: FileManager = .default) -> URL {
        if let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return applicationSupportURL
                .appendingPathComponent("PictureSearch", isDirectory: true)
                .appendingPathComponent(defaultLocalPackageDirectoryName, isDirectory: true)
        }

        return fileManager.temporaryDirectory
            .appendingPathComponent("PictureSearch", isDirectory: true)
            .appendingPathComponent(defaultLocalPackageDirectoryName, isDirectory: true)
    }

    private static func loadBundledTokenizer(
        manifest: EmbeddingModelManifest,
        bundle: Bundle,
        overrideTokenizer: (any EmbeddingTextTokenizing)?
    ) -> (tokenizer: any EmbeddingTextTokenizing, issue: String?) {
        loadTokenizer(
            manifest: manifest,
            resourceURL: { resourceName in
                bundle.url(forResource: resourceName, withExtension: nil)
            },
            overrideTokenizer: overrideTokenizer
        )
    }

    private static func loadTokenizer(
        manifest: EmbeddingModelManifest,
        resourceURL: (String) -> URL?,
        overrideTokenizer: (any EmbeddingTextTokenizing)?
    ) -> (tokenizer: any EmbeddingTextTokenizing, issue: String?) {
        if let overrideTokenizer {
            return (overrideTokenizer, nil)
        }

        guard let tokenizerResourceName = manifest.configuration.tokenizerResourceName else {
            return (
                UnavailableEmbeddingTokenizer(),
                "manifest 缺少 tokenizer 资源名"
            )
        }

        guard let tokenizerURL = resourceURL(tokenizerResourceName) else {
            return (UnavailableEmbeddingTokenizer(), nil)
        }

        do {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: tokenizerURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                let tokenizer = try CLIPBPETokenizer(
                    vocabularyURL: tokenizerURL.appendingPathComponent("vocab.json"),
                    mergesURL: tokenizerURL.appendingPathComponent("merges.txt")
                )
                var issues: [String] = []
                if manifest.configuration.textStartTokenID != tokenizer.startTokenID {
                    issues.append("tokenizer 起始 token ID 与 manifest 不一致")
                }
                if manifest.configuration.textEndTokenID != tokenizer.endTokenID {
                    issues.append("tokenizer 结束 token ID 与 manifest 不一致")
                }
                return (tokenizer, issues.isEmpty ? nil : issues.joined(separator: "、"))
            }

            let tokenizer = try EmbeddingBPETokenizer.load(from: tokenizerURL)
            let specialTokenIssues = tokenizer.specialTokenIssues(
                configuration: manifest.configuration
            )
            return (
                tokenizer,
                specialTokenIssues.isEmpty ? nil : specialTokenIssues.joined(separator: "、")
            )
        } catch {
            return (UnavailableEmbeddingTokenizer(), error.localizedDescription)
        }
    }

    func validateModelAvailability() throws {
        let report = modelReadinessReport()
        guard report.isReady else {
            throw EmbeddingServiceError.modelUnavailable(report.recoveryMessage)
        }
    }

    func modelReadinessReport() -> EmbeddingModelReadinessReport {
        let imageModelURL = resourceURL(
            forResource: modelInfo.expectedImageModelName,
            withExtension: "mlmodelc"
        )
        let textModelURL = resourceURL(
            forResource: modelInfo.expectedTextModelName,
            withExtension: "mlmodelc"
        )
        let tokenizerURL = modelInfo.configuration?.tokenizerResourceName.flatMap { name in
            resourceURL(forResource: name, withExtension: nil)
        }
        let tokenizerIsReady = modelInfo.configuration?.tokenizerResourceName == nil || tokenizerURL != nil
        var configurationIssues = modelInfo.configuration?.validationIssues ?? []
        if let tokenizerIssue {
            configurationIssues.append(tokenizerIssue)
        }
        if let manifest {
            configurationIssues.append(contentsOf: EmbeddingModelResourceAudit.sizeIssues(
                manifest: manifest,
                imageModelURL: imageModelURL,
                textModelURL: textModelURL,
                tokenizerURL: tokenizerURL
            ))
            configurationIssues.append(contentsOf: EmbeddingModelResourceAudit.hashIssues(
                manifest: manifest,
                imageModelURL: imageModelURL,
                textModelURL: textModelURL,
                tokenizerURL: tokenizerURL
            ))
            configurationIssues.append(contentsOf: EmbeddingModelRuntimeAudit.runtimeIssues(
                manifest: manifest,
                imageModelURL: imageModelURL,
                textModelURL: textModelURL
            ))
        }
        let packagedResources = EmbeddingModelResourceAudit.packagedResources(
            manifest: manifest,
            modelInfo: modelInfo,
            imageModelURL: imageModelURL,
            textModelURL: textModelURL,
            tokenizerURL: tokenizerURL
        )

        return EmbeddingModelReadinessReport(
            modelInfo: modelInfo,
            integrationChecklistLines: manifest?.integrationChecklistLines ?? [],
            packagedResources: packagedResources,
            manifestIssue: manifestIssue,
            hasImageModel: imageModelURL != nil,
            hasTextModel: textModelURL != nil,
            hasTokenizer: tokenizerIsReady,
            configurationIssues: configurationIssues
        )
    }

    func encodeImage(_ image: CGImage) async throws -> EmbeddingVector {
        try validateModelAvailability()
        guard let configuration = modelInfo.configuration else {
            throw EmbeddingServiceError.imageEncodingFailed("缺少图片编码器配置。")
        }
        guard let imageModelURL = resourceURL(
            forResource: modelInfo.expectedImageModelName,
            withExtension: "mlmodelc"
        ) else {
            throw EmbeddingServiceError.modelUnavailable("缺少 \(modelInfo.expectedImageModelName).mlmodelc。")
        }

        return try await Task.detached(priority: EmbeddingInferenceExecutionPolicy.priority) {
            try EmbeddingInferenceExecutionPolicy.validateBackgroundExecution(operation: "图片向量推理")
            let imageModel = try MLModel(contentsOf: imageModelURL)
            guard let inputDescription = imageModel.modelDescription
                .inputDescriptionsByName[configuration.imageInputName] else {
                throw EmbeddingServiceError.imageEncodingFailed("图片编码器缺少输入 \(configuration.imageInputName)。")
            }
            let imageFeature: MLFeatureValue
            if inputDescription.type == .image, let constraint = inputDescription.imageConstraint {
                imageFeature = try MLFeatureValue(
                    cgImage: image,
                    constraint: constraint,
                    options: nil
                )
            } else {
                let imageArray = try EmbeddingImagePreprocessor.normalizedCHWArray(
                    from: image,
                    size: configuration.imageInputSize,
                    mean: configuration.imageMean,
                    standardDeviation: configuration.imageStandardDeviation
                )
                imageFeature = MLFeatureValue(multiArray: imageArray)
            }
            let input = try MLDictionaryFeatureProvider(dictionary: [
                configuration.imageInputName: imageFeature
            ])
            let output = try imageModel.prediction(from: input)

            guard let vectorOutput = output.featureValue(for: configuration.imageOutputName)?.multiArrayValue else {
                throw EmbeddingServiceError.imageEncodingFailed("图片编码器未返回 \(configuration.imageOutputName) 向量。")
            }

            return try EmbeddingModelOutputDecoder.vector(from: vectorOutput)
        }.value
    }

    func encodeText(_ text: String) async throws -> EmbeddingVector {
        try validateModelAvailability()
        guard let configuration = modelInfo.configuration else {
            throw EmbeddingServiceError.textEncodingFailed("缺少文本编码器配置。")
        }
        guard let textModelURL = resourceURL(
            forResource: modelInfo.expectedTextModelName,
            withExtension: "mlmodelc"
        ) else {
            throw EmbeddingServiceError.modelUnavailable("缺少 \(modelInfo.expectedTextModelName).mlmodelc。")
        }

        let tokenizer = tokenizer
        return try await Task.detached(priority: EmbeddingInferenceExecutionPolicy.priority) {
            try EmbeddingInferenceExecutionPolicy.validateBackgroundExecution(operation: "文本向量推理")
            let tokenizedText = try tokenizer.tokenize(text)
            let tokenArray = try EmbeddingTextInputBuilder.tokenArray(
                from: tokenizedText,
                sequenceLength: configuration.textSequenceLength,
                padTokenID: configuration.textPadTokenID
            )
            let textModel = try MLModel(contentsOf: textModelURL)
            let input = try MLDictionaryFeatureProvider(dictionary: [
                configuration.textInputName: tokenArray
            ])
            let output = try textModel.prediction(from: input)

            guard let vectorOutput = output.featureValue(for: configuration.textOutputName)?.multiArrayValue else {
                throw EmbeddingServiceError.textEncodingFailed("文本编码器未返回 \(configuration.textOutputName) 向量。")
            }

            return try EmbeddingModelOutputDecoder.vector(from: vectorOutput)
        }.value
    }

    private func resourceURL(forResource name: String, withExtension fileExtension: String?) -> URL? {
        if let localModelPackageURL {
            let fileName = fileExtension.map { "\(name).\($0)" } ?? name
            let localURL = localModelPackageURL.appendingPathComponent(
                fileName,
                isDirectory: fileExtension == "mlmodelc"
            )
            if FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
        }

        return bundle.url(forResource: name, withExtension: fileExtension)
    }
}
