import AppKit
import SwiftUI

struct LibraryGridView: View {
    let assets: [PhotoAssetSummary]
    let thumbnails: [String: PhotoThumbnail]
    let searchResults: [String: SearchResult]
    let summary: PhotoLibraryLoadSummary
    let isLoading: Bool
    let isShowingSearchResults: Bool
    @Binding var selectedScope: PhotoLibraryTimeScope
    let scopeChanged: () -> Void
    let reload: () -> Void
    let clearSearch: () -> Void
    let openPreview: (PhotoAssetSummary) -> Void

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: isShowingSearchResults ? 190 : 92,
                    maximum: isShowingSearchResults ? 240 : 124
                ),
                spacing: 12
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(AppTheme.accent)
                .frame(height: 3)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    titleBlock
                    Spacer()
                    controls
                }

                VStack(alignment: .leading, spacing: 10) {
                    titleBlock
                    controls
                }
            }
            .frame(minHeight: 34)

            if assets.isEmpty {
                ContentUnavailableView(
                    isShowingSearchResults ? "没有搜索结果" : "暂无图片",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(isShowingSearchResults ? "换一个文字、时间或类型再搜索。" : "授权成功后会在这里展示\(selectedScope.title)的 Photos 图片。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(assets) { asset in
                            Button {
                                openPreview(asset)
                            } label: {
                                PhotoAssetCell(
                                    asset: asset,
                                    thumbnail: thumbnails[asset.id],
                                    searchResult: searchResults[asset.id]
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollIndicators(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(selectedScope.title)图片")
                .opacity(isShowingSearchResults ? 0 : 1)
                .overlay(alignment: .leading) {
                    if isShowingSearchResults {
                        Text("搜索结果")
                    }
                }
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text("总数 \(summary.totalAssets) · 成功 \(summary.successfulThumbnails) · 失败 \(summary.failedThumbnails)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if isShowingSearchResults {
                Button {
                    clearSearch()
                } label: {
                    Label("退出搜索", systemImage: "xmark")
                }
            }

            Picker("读取范围", selection: $selectedScope) {
                ForEach(PhotoLibraryTimeScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 330)
            .disabled(isLoading)
            .onChange(of: selectedScope) { _, _ in
                scopeChanged()
            }

            Button {
                reload()
            } label: {
                Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
            }
            .help(isLoading ? "正在读取" : "重新读取")
            .disabled(isLoading)
        }
        .controlSize(.small)
    }
}

private struct PhotoAssetCell: View {
    let asset: PhotoAssetSummary
    let thumbnail: PhotoThumbnail?
    let searchResult: SearchResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(.quaternary)

                    if let image = thumbnail?.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } else if let failureReason = thumbnail?.failureReason {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                            Text(failureReason)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.58)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 46)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(asset.formattedCreationDate)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text("\(asset.mediaSubtypeDescription) · \(asset.pixelWidth) × \(asset.pixelHeight)")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                    .padding(7)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if let searchResult {
                HStack {
                    Text("MATCH SCORE")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", searchResult.score))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                }

                ForEach(searchResult.reasons, id: \.text) { reason in
                    Label(reason.text, systemImage: icon(for: reason.kind))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(searchResult == nil ? 0 : 8)
        .background(searchResult == nil ? Color.clear : Color(nsColor: .controlBackgroundColor))
        .overlay {
            if searchResult != nil {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.ink.opacity(0.16), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func icon(for kind: SearchMatchKind) -> String {
        switch kind {
        case .ocr:
            return "text.viewfinder"
        case .visual:
            return "eye"
        case .time:
            return "calendar"
        case .type:
            return "photo.on.rectangle"
        }
    }
}

struct PhotoPreviewSheet: View {
    let asset: PhotoAssetSummary
    let image: NSImage?
    let message: String
    let isLoading: Bool
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.formattedCreationDate)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("\(asset.mediaSubtypeDescription) · \(asset.pixelWidth) × \(asset.pixelHeight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("关闭预览")
                .keyboardShortcut(.cancelAction)
            }

            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.82))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    ContentUnavailableView(
                        "无法显示预览",
                        systemImage: "photo",
                        description: Text(message.isEmpty ? "系统没有返回可显示图片。" : message)
                    )
                    .foregroundStyle(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !message.isEmpty, image != nil {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 14)
        .padding(24)
        .frame(minWidth: 760, minHeight: 560)
        .presentationBackground(.clear)
    }
}
