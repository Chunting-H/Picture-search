import SwiftUI

struct IndexingStatusView: View {
    @State private var showsTaskDetails = false

    let summary: IndexStatusSummary
    let lastSyncResult: IndexSyncResult
    let message: String
    let isLoading: Bool
    let isProcessingOCR: Bool
    let ocrMessage: String
    let ocrPerformanceSummary: OCRPerformanceSummary
    let isProcessingEmbedding: Bool
    let embeddingMessage: String
    let embeddingReadinessReport: EmbeddingModelReadinessReport
    let embeddingValidationPreflightReport: EmbeddingValidationPreflightReport
    let embeddingValidationReport: EmbeddingValidationReport?
    let embeddingValidationMessage: String
    let isRunningEmbeddingValidation: Bool
    let startOCR: () -> Void
    let retryFailedOCR: () -> Void
    let startEmbedding: () -> Void
    let retryFailedEmbedding: () -> Void
    let runEmbeddingValidation: () -> Void
    let clearIndex: () -> Void

    private let badgeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("02 / INDEX")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                    Text("本地索引")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                Spacer()
                Button(role: .destructive) {
                    clearIndex()
                } label: {
                    Image(systemName: "trash")
                }
                .help("清除本地索引")
                .controlSize(.small)
                .disabled(isLoading || summary.totalRecords == 0)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            LazyVGrid(columns: badgeColumns, alignment: .leading, spacing: 8) {
                StatusBadge(title: "记录", value: summary.totalRecords)
                StatusBadge(title: "新增", value: lastSyncResult.inserted)
                StatusBadge(title: "更新", value: lastSyncResult.updated)
                StatusBadge(title: "未变化", value: lastSyncResult.unchanged)
            }

            TaskStatusGroup(
                title: "OCR",
                pending: summary.ocrPending,
                processing: summary.ocrProcessing,
                ready: summary.ocrReady,
                failed: summary.ocrFailed
            )

            DisclosureGroup(isExpanded: $showsTaskDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    TaskStatusGroup(
                        title: "向量",
                        pending: summary.embeddingPending,
                        processing: summary.embeddingProcessing,
                        ready: summary.embeddingReady,
                        failed: summary.embeddingFailed,
                        outdated: summary.embeddingOutdated
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("OCR 处理")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(ocrMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("平均耗时 \(ocrPerformanceSummary.formattedAverageDuration)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("失败类型 \(ocrPerformanceSummary.formattedFailureTypes)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button {
                                startOCR()
                            } label: {
                                Label(isProcessingOCR ? "处理中..." : "开始 OCR", systemImage: "text.viewfinder")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoading || isProcessingOCR || summary.ocrPending == 0)

                            Button {
                                retryFailedOCR()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("重试失败 OCR")
                            .disabled(isLoading || isProcessingOCR || summary.ocrFailed == 0)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("视觉语义索引")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(embeddingMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        EmbeddingReadinessView(report: embeddingReadinessReport)
                        Text("为当前已读取的全部图片生成真实视觉向量；单张失败不会中断后续任务。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button {
                                startEmbedding()
                            } label: {
                                Label(
                                    isProcessingEmbedding ? "构建中..." : "构建视觉索引",
                                    systemImage: "sparkles.rectangle.stack"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                isLoading
                                    || isProcessingEmbedding
                                    || summary.embeddingPending + summary.embeddingOutdated + summary.embeddingFailed == 0
                            )

                            Button {
                                retryFailedEmbedding()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("重试视觉索引失败项")
                            .disabled(isLoading || isProcessingEmbedding || summary.embeddingFailed == 0)

                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("索引操作与详情")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .controlSize(.small)
        }
        .foregroundStyle(AppTheme.ink)
        .consolePanel()
    }
}

private struct EmbeddingValidationResultView: View {
    let message: String
    let report: EmbeddingValidationReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                report?.passed == true ? "技术验证通过" : "技术验证状态",
                systemImage: report?.passed == true ? "checkmark.seal" : "waveform.path.ecg"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(report?.passed == true ? .green : .secondary)

            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let report {
                ForEach(report.summaryLines, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct EmbeddingReadinessView: View {
    let report: EmbeddingModelReadinessReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(report.isReady ? "本地模型已就绪" : "本地模型未就绪", systemImage: report.isReady ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(report.isReady ? .green : .secondary)

            ForEach(report.diagnosticLines, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !report.packagedResourceLines.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                Text("模型资源打包清单")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ForEach(report.packagedResourceLines, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !report.manifestSuggestionLines.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                Text("manifest 建议字段")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ForEach(report.manifestSuggestionLines, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct EmbeddingPreflightView: View {
    let report: EmbeddingValidationPreflightReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                report.canLoadSamples ? "技术验证预检可继续" : "技术验证预检未通过",
                systemImage: report.canLoadSamples ? "checkmark.seal" : "list.bullet.clipboard"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(report.canLoadSamples ? .green : .secondary)

            ForEach(report.summaryLines, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct StatusBadge: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(value > 0 ? AppTheme.ink : AppTheme.ink.opacity(0.3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TaskStatusGroup: View {
    let title: String
    let pending: Int
    let processing: Int
    let ready: Int
    let failed: Int
    var outdated: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        var parts = [
            "待处理 \(pending)",
            "处理中 \(processing)",
            "完成 \(ready)",
            "失败 \(failed)"
        ]
        if outdated > 0 {
            parts.append("需重建 \(outdated)")
        }
        return parts.joined(separator: " · ")
    }
}
