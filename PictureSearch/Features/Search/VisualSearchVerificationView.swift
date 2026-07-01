import SwiftUI

struct NaturalLanguageSearchView: View {
    @Binding var query: String

    let results: [SearchResult]
    let message: String
    let isDisabled: Bool
    let runSearch: () -> Void
    let queryChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("03 / SEARCH")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.accent)

            Text("多信号搜索")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                TextField("Hermes 截图", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: query) { _, _ in
                        queryChanged()
                    }
                    .onSubmit {
                        runSearch()
                    }

                Button {
                    runSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .help("搜索")
                .disabled(isDisabled)
            }
            .controlSize(.small)

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(results.prefix(5)) { result in
                        SearchResultRow(result: result)
                    }
                }
            }
        }
        .foregroundStyle(AppTheme.ink)
        .consolePanel()
    }
}

private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(result.record.mediaSubtype)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.0f", result.score))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(result.explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(formattedDate) · \(result.record.pixelWidth) × \(result.record.pixelHeight)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(7)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
    }

    private var formattedDate: String {
        guard let creationDate = result.record.creationDate else {
            return "未知时间"
        }

        return Self.dateFormatter.string(from: creationDate)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}

struct VisualSearchVerificationView: View {
    @Binding var query: String

    let results: [VisualSearchResult]
    let message: String
    let isRunning: Bool
    let isDisabled: Bool
    let runSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("视觉查询验证")
                .font(.headline)
                .fontWeight(.semibold)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                TextField("例如：海边夕阳", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRunning)
                    .onSubmit {
                        runSearch()
                    }

                Button(isRunning ? "检索中..." : "检索") {
                    runSearch()
                }
                .disabled(isDisabled || isRunning)
            }
            .controlSize(.small)

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(results.prefix(5)) { result in
                        VisualSearchResultRow(result: result)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct VisualSearchResultRow: View {
    let result: VisualSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(result.record.mediaSubtype)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.3f", result.score))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(result.explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(formattedDate) · \(result.record.pixelWidth) × \(result.record.pixelHeight)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(7)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }

    private var formattedDate: String {
        guard let creationDate = result.record.creationDate else {
            return "未知时间"
        }

        return Self.dateFormatter.string(from: creationDate)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}
