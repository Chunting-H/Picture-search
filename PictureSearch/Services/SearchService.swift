import Foundation

struct SearchService {
    private let calendar: Calendar

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    func search(
        query: String,
        indexStore: IndexStore,
        limit: Int = 50,
        referenceDate: Date = Date()
    ) throws -> [SearchResult] {
        let plan = parseQuery(query, referenceDate: referenceDate)
        guard !plan.isEmpty, plan.hasAnySignal, limit > 0 else {
            return []
        }

        return try search(plan: plan, records: indexStore.fetchRecords(), limit: limit)
    }

    func search(plan: SearchQueryPlan, records: [AssetIndexRecord], limit: Int = 50) -> [SearchResult] {
        guard !plan.isEmpty, plan.hasAnySignal, limit > 0 else {
            return []
        }

        return records.compactMap { result(for: $0, plan: plan) }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence == .high
                }
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return (lhs.record.creationDate ?? .distantPast) > (rhs.record.creationDate ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }

    func parseQuery(_ query: String, referenceDate: Date = Date()) -> SearchQueryPlan {
        let normalized = SearchTextNormalizer.normalize(query)
        guard !normalized.isEmpty else {
            return SearchQueryPlan(
                originalQuery: query,
                normalizedQuery: "",
                ocrTerms: [],
                timeRange: nil,
                timeDescription: nil,
                assetTypes: [],
                visualUnavailableMessage: nil
            )
        }

        let timeMatch = parseTimeRange(from: normalized, referenceDate: referenceDate)
        let assetTypes = parseAssetTypes(from: normalized)
        let parsedOCRTerms = parseOCRTerms(from: normalized, assetTypes: assetTypes, timeDescription: timeMatch?.description)
        let looksLikePureVisualQuery = timeMatch == nil && assetTypes.isEmpty && isLikelyPureVisualDescription(normalized)
        let ocrTerms = looksLikePureVisualQuery ? [] : parsedOCRTerms
        let visualUnavailableMessage = looksLikePureVisualQuery
            ? "当前 MVP 尚未启用真实视觉语义模型，不能可靠处理纯画面描述查询。"
            : nil

        return SearchQueryPlan(
            originalQuery: query,
            normalizedQuery: normalized,
            ocrTerms: ocrTerms,
            timeRange: timeMatch?.range,
            timeDescription: timeMatch?.description,
            assetTypes: assetTypes,
            visualUnavailableMessage: visualUnavailableMessage
        )
    }

    func visualSearch(
        query: String,
        indexStore: IndexStore,
        embeddingService: EmbeddingServicing,
        limit: Int = 20
    ) async throws -> [VisualSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty, limit > 0 else {
            return []
        }

        let queryVector = try await embeddingService.encodeText(normalizedQuery)
        return try indexStore.visualSearchCandidates(
            queryVector: queryVector,
            modelVersion: embeddingService.modelInfo.version,
            limit: limit
        )
    }

    func multiSignalSearch(
        query: String,
        indexStore: IndexStore,
        embeddingService: EmbeddingServicing,
        limit: Int = 5,
        referenceDate: Date = Date()
    ) async throws -> [SearchResult] {
        let plan = parseQuery(query, referenceDate: referenceDate)
        guard !plan.isEmpty, limit > 0 else {
            return []
        }

        let records = try indexStore.fetchRecords()
        let structuredResults = search(plan: plan, records: records, limit: records.count)
        let visualResults = try await visualSearch(
            query: query,
            indexStore: indexStore,
            embeddingService: embeddingService,
            limit: records.count
        )

        var merged = Dictionary(uniqueKeysWithValues: structuredResults.map { ($0.id, $0) })
        for visualResult in visualResults where visualResult.score.isFinite {
            let contribution = max(0, visualResult.score) * SearchScoring.visualContributionScale
            let visualReason = SearchMatchReason(
                kind: .visual,
                text: "视觉匹配“\(query)”（相似度 \(String(format: "%.3f", visualResult.score))）",
                scoreContribution: contribution
            )

            if let existing = merged[visualResult.id] {
                let reasons = existing.reasons + [visualReason]
                let score = existing.score + contribution
                merged[visualResult.id] = SearchResult(
                    assetLocalIdentifier: existing.assetLocalIdentifier,
                    title: existing.title,
                    explanation: explanation(score: score, reasons: reasons),
                    score: score,
                    confidence: confidence(for: score),
                    reasons: reasons,
                    record: existing.record
                )
            } else {
                merged[visualResult.id] = SearchResult(
                    assetLocalIdentifier: visualResult.assetLocalIdentifier,
                    title: recordTitle(for: visualResult.record),
                    explanation: explanation(score: contribution, reasons: [visualReason]),
                    score: contribution,
                    confidence: confidence(for: contribution),
                    reasons: [visualReason],
                    record: visualResult.record
                )
            }
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence == .high
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return (lhs.record.creationDate ?? .distantPast) > (rhs.record.creationDate ?? .distantPast)
        }
        .prefix(limit)
        .map { $0 }
    }

    private func result(for record: AssetIndexRecord, plan: SearchQueryPlan) -> SearchResult? {
        var score = 0.0
        var reasons: [SearchMatchReason] = []

        if !plan.ocrTerms.isEmpty,
           let reason = ocrReason(for: record, terms: plan.ocrTerms) {
            score += reason.scoreContribution
            reasons.append(reason)
        }

        if let range = plan.timeRange,
           let creationDate = record.creationDate,
           range.contains(creationDate) {
            let contribution = plan.ocrTerms.isEmpty ? 36.0 : 18.0
            score += contribution
            reasons.append(SearchMatchReason(
                kind: .time,
                text: "时间匹配：\(plan.timeDescription ?? "指定时间")",
                scoreContribution: contribution
            ))
        }

        if !plan.assetTypes.isEmpty,
           let reason = typeReason(for: record, assetTypes: plan.assetTypes, strong: plan.ocrTerms.isEmpty) {
            score += reason.scoreContribution
            reasons.append(reason)
        }

        guard score > 0, !reasons.isEmpty else {
            return nil
        }

        let confidence = confidence(for: score)
        let title = recordTitle(for: record)
        let explanation = explanation(score: score, reasons: reasons)

        return SearchResult(
            assetLocalIdentifier: record.assetLocalIdentifier,
            title: title,
            explanation: explanation,
            score: score,
            confidence: confidence,
            reasons: reasons,
            record: record
        )
    }

    private func confidence(for score: Double) -> SearchResultConfidence {
        score >= SearchScoring.highConfidenceThreshold ? .high : .low
    }

    private func explanation(score: Double, reasons: [SearchMatchReason]) -> String {
        ([confidence(for: score).description] + reasons.map(\.text)).joined(separator: "；")
    }

    private func ocrReason(for record: AssetIndexRecord, terms: [String]) -> SearchMatchReason? {
        guard record.ocrStatus == .ready,
              let ocrText = record.ocrText,
              !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let normalizedOCR = SearchTextNormalizer.normalize(ocrText)
        let matchedTerms = terms.filter { normalizedOCR.contains($0) }
        guard !matchedTerms.isEmpty else {
            return nil
        }

        let allTermsMatched = matchedTerms.count == terms.count
        let contribution = allTermsMatched ? 82.0 : 48.0 + Double(matchedTerms.count * 8)
        let snippet = matchedTerms.prefix(3).joined(separator: "、")
        return SearchMatchReason(
            kind: .ocr,
            text: "OCR 命中：\(snippet)",
            scoreContribution: contribution
        )
    }

    private func typeReason(for record: AssetIndexRecord, assetTypes: [SearchAssetType], strong: Bool) -> SearchMatchReason? {
        guard let matchedType = assetTypes.first(where: { record.matches(assetType: $0) }) else {
            return nil
        }

        let contribution = strong ? 34.0 : 16.0
        return SearchMatchReason(
            kind: .type,
            text: "类型匹配：\(matchedType.displayName)",
            scoreContribution: contribution
        )
    }

    private func recordTitle(for record: AssetIndexRecord) -> String {
        let dateText = record.creationDate.map(Self.displayDateFormatter.string(from:)) ?? "未知时间"
        return "\(dateText) · \(record.mediaSubtype)"
    }

    private func parseAssetTypes(from normalizedQuery: String) -> [SearchAssetType] {
        var result: [SearchAssetType] = []
        func append(_ type: SearchAssetType) {
            if !result.contains(type) {
                result.append(type)
            }
        }

        if normalizedQuery.contains("截图") || normalizedQuery.contains("截屏") || normalizedQuery.contains("screenshot") || normalizedQuery.contains("screen shot") {
            append(.screenshot)
        }
        if normalizedQuery.contains("文档图") || normalizedQuery.contains("文档") || normalizedQuery.contains("document") || normalizedQuery.contains("invoice") || normalizedQuery.contains("发票") {
            append(.document)
        }
        if normalizedQuery.contains("照片") || normalizedQuery.contains("图片") || normalizedQuery.contains("photo") || normalizedQuery.contains("image") {
            append(.photo)
        }

        return result
    }

    private func parseOCRTerms(
        from normalizedQuery: String,
        assetTypes: [SearchAssetType],
        timeDescription: String?
    ) -> [String] {
        var text = normalizedQuery
        let removablePhrases = [
            "包含", "含有", "带有", "里面有", "的", "找", "查找", "搜索",
            "最近", "去年夏天", "去年", "今年", "截图", "截屏", "照片", "图片",
            "文档图", "文档", "screenshot", "screen shot", "photo", "image", "document",
            "invoice", "发票"
        ]

        for phrase in removablePhrases {
            text = text.replacingOccurrences(of: phrase, with: " ")
        }

        if let timeDescription {
            text = text.replacingOccurrences(of: SearchTextNormalizer.normalize(timeDescription), with: " ")
        }

        text = text.replacingOccurrences(
            of: #"\b\d{4}\s*年?\s*\d{0,2}\s*月?\b"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?<!\d)\d{1,2}\s*月"#,
            with: " ",
            options: .regularExpression
        )

        let tokens = text
            .components(separatedBy: SearchTextNormalizer.termSeparators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                token.count >= 2 && !Self.stopWords.contains(token)
            }

        if tokens.isEmpty, assetTypes.isEmpty, timeDescription == nil {
            return []
        }

        return Array(NSOrderedSet(array: tokens).compactMap { $0 as? String })
    }

    private func isLikelyPureVisualDescription(_ normalizedQuery: String) -> Bool {
        Self.visualSceneKeywords.contains { normalizedQuery.contains($0) }
    }

    private func parseTimeRange(from normalizedQuery: String, referenceDate: Date) -> (range: DateInterval, description: String)? {
        let year = calendar.component(.year, from: referenceDate)

        if normalizedQuery.contains("去年夏天") {
            return dateInterval(year: year - 1, month: 6, monthCount: 3, description: "去年夏天")
        }

        if normalizedQuery.contains("去年") {
            return yearInterval(year - 1, description: "去年")
        }

        if normalizedQuery.contains("今年") {
            return yearInterval(year, description: "今年")
        }

        if normalizedQuery.contains("最近") {
            let start = calendar.date(byAdding: .day, value: -30, to: referenceDate) ?? referenceDate
            return (DateInterval(start: start, end: referenceDate), "最近 30 天")
        }

        if let explicitMonth = explicitYearMonth(in: normalizedQuery) {
            return dateInterval(
                year: explicitMonth.year,
                month: explicitMonth.month,
                monthCount: 1,
                description: "\(explicitMonth.year) 年 \(explicitMonth.month) 月"
            )
        }

        if let month = bareMonth(in: normalizedQuery) {
            return dateInterval(
                year: year,
                month: month,
                monthCount: 1,
                description: "\(year) 年 \(month) 月"
            )
        }

        return nil
    }

    private func explicitYearMonth(in text: String) -> (year: Int, month: Int)? {
        let pattern = #"(\d{4})\s*年?\s*(\d{1,2})\s*月"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 3,
              let yearRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let year = Int(text[yearRange]),
              let month = Int(text[monthRange]),
              (1...12).contains(month) else {
            return nil
        }

        return (year, month)
    }

    private func bareMonth(in text: String) -> Int? {
        let pattern = #"(?<!\d)(\d{1,2})\s*月"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 2,
              let monthRange = Range(match.range(at: 1), in: text),
              let month = Int(text[monthRange]),
              (1...12).contains(month) else {
            return nil
        }

        return month
    }

    private func yearInterval(_ year: Int, description: String) -> (range: DateInterval, description: String)? {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return nil
        }

        return (DateInterval(start: start, end: end), description)
    }

    private func dateInterval(year: Int, month: Int, monthCount: Int, description: String) -> (range: DateInterval, description: String)? {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(byAdding: .month, value: monthCount, to: start) else {
            return nil
        }

        return (DateInterval(start: start, end: end), description)
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let stopWords: Set<String> = [
        "the", "and", "with", "for", "from", "里的", "中的", "一个", "一张"
    ]

    private static let visualSceneKeywords = [
        "海边", "夕阳", "日落", "沙滩", "蓝天", "风景", "猫", "狗", "食物",
        "餐厅", "城市夜景", "beach", "sunset", "landscape", "cat", "dog", "food"
    ]
}

private enum SearchTextNormalizer {
    static let termSeparators = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)

    static func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension AssetIndexRecord {
    func matches(assetType: SearchAssetType) -> Bool {
        let metadata = SearchTextNormalizer.normalize("\(mediaType) \(mediaSubtype)")
        switch assetType {
        case .screenshot:
            return metadata.contains("截图") || metadata.contains("截屏") || metadata.contains("screenshot")
        case .photo:
            return metadata.contains("照片") || metadata.contains("图片") || metadata.contains("photo")
        case .document:
            if metadata.contains("文档") || metadata.contains("document") {
                return true
            }
            return ocrStatus == .ready && !(ocrText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
