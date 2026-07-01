import SwiftUI

enum AppTheme {
    static let ink = Color(red: 0.12, green: 0.20, blue: 0.20)
    static let paper = Color(red: 0.965, green: 0.98, blue: 0.975)
    static let sidebar = Color(red: 0.91, green: 0.96, blue: 0.95)
    static let accent = Color(red: 0.22, green: 0.58, blue: 0.51)
    static let mint = Color(red: 0.24, green: 0.67, blue: 0.53)
    static let line = Color(red: 0.18, green: 0.34, blue: 0.32).opacity(0.12)
}

extension View {
    func consolePanel() -> some View {
        self
            .padding(12)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()

    var body: some View {
        mainContent
        .frame(minWidth: 1120, minHeight: 720)
        .background(AppTheme.paper)
        .tint(AppTheme.accent)
        .sheet(
            isPresented: Binding(
                get: { viewModel.previewAsset != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.closePreview()
                    }
                }
            )
        ) {
            if let previewAsset = viewModel.previewAsset {
                PhotoPreviewSheet(
                    asset: previewAsset,
                    image: viewModel.previewImage,
                    message: viewModel.previewMessage,
                    isLoading: viewModel.isLoadingPreview,
                    close: {
                        viewModel.closePreview()
                    }
                )
            }
        }
        .task {
            if viewModel.authorizationState.canReadLibrary && viewModel.assets.isEmpty {
                await viewModel.loadRecentAssets()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("PS / 01")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                Circle()
                    .fill(viewModel.authorizationState.canReadLibrary ? AppTheme.mint : AppTheme.accent)
                    .frame(width: 7, height: 7)
            }

            Text("Picture\nSearch")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(0)

            Text("本机多信号照片检索")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.55))
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.authorizationState.canReadLibrary {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        authorizationPanel
                        indexingPanel
                        searchPanel

                        Text(viewModel.statusMessage)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.ink.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                }
                .frame(width: 320)
                .background(AppTheme.sidebar)

                libraryPanel
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    authorizationPanel

                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink.opacity(0.55))
                }
                .padding(28)
                .frame(width: 380)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(AppTheme.sidebar)

                VStack(alignment: .leading, spacing: 18) {
                    Text("你的照片。\n你的设备。\n你的搜索。")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Rectangle()
                        .fill(AppTheme.accent)
                        .frame(width: 72, height: 6)
                    Text("授权后，PictureSearch 仅通过 PhotoKit 读取图片，并在本机完成 OCR、视觉向量与索引。")
                        .font(.custom("Avenir Next", size: 15))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 480, alignment: .leading)
                }
                .padding(48)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var authorizationPanel: some View {
        AuthorizationView(
            state: viewModel.authorizationState,
            isLoading: viewModel.isLoading,
            requestAccess: {
                Task {
                    await viewModel.requestAccessAndLoad()
                }
            },
            refreshStatus: {
                viewModel.refreshAuthorizationState()
            }
        )
    }

    private var indexingPanel: some View {
        IndexingStatusView(
            summary: viewModel.indexSummary,
            lastSyncResult: viewModel.lastIndexSyncResult,
            message: viewModel.indexStatusMessage,
            isLoading: viewModel.isLoading,
            isProcessingOCR: viewModel.isProcessingOCR,
            ocrMessage: viewModel.ocrStatusMessage,
            ocrPerformanceSummary: viewModel.ocrPerformanceSummary,
            isProcessingEmbedding: viewModel.isProcessingEmbedding,
            embeddingMessage: viewModel.embeddingStatusMessage,
            embeddingReadinessReport: viewModel.embeddingReadinessReport,
            embeddingValidationPreflightReport: viewModel.embeddingValidationPreflightReport,
            embeddingValidationReport: viewModel.embeddingValidationReport,
            embeddingValidationMessage: viewModel.embeddingValidationMessage,
            isRunningEmbeddingValidation: viewModel.isRunningEmbeddingValidation,
            startOCR: {
                viewModel.processPendingOCR()
            },
            retryFailedOCR: {
                viewModel.retryFailedOCR()
            },
            startEmbedding: {
                viewModel.processPendingEmbeddings()
            },
            retryFailedEmbedding: {
                viewModel.retryFailedEmbeddings()
            },
            runEmbeddingValidation: {
                viewModel.runEmbeddingValidation()
            },
            clearIndex: {
                viewModel.clearLocalIndex()
            }
        )
    }

    private var searchPanel: some View {
        NaturalLanguageSearchView(
            query: $viewModel.searchQuery,
            results: viewModel.searchResults,
            message: viewModel.searchMessage,
            isDisabled: viewModel.isLoading,
            runSearch: {
                viewModel.runNaturalLanguageSearch()
            },
            queryChanged: {
                viewModel.searchQueryDidChange()
            }
        )
    }

    private var visualSearchPanel: some View {
        VisualSearchVerificationView(
            query: $viewModel.visualSearchQuery,
            results: viewModel.visualSearchResults,
            message: viewModel.visualSearchMessage,
            isRunning: viewModel.isRunningVisualSearch,
            isDisabled: viewModel.isLoading || viewModel.isProcessingEmbedding,
            runSearch: {
                viewModel.runVisualSearch()
            }
        )
    }

    private var libraryPanel: some View {
        LibraryGridView(
            assets: viewModel.displayedAssets,
            thumbnails: viewModel.thumbnails,
            searchResults: Dictionary(uniqueKeysWithValues: viewModel.searchResults.map { ($0.id, $0) }),
            summary: viewModel.displayedSummary,
            isLoading: viewModel.isLoading,
            isShowingSearchResults: viewModel.isShowingSearchResults,
            selectedScope: $viewModel.selectedScope,
            scopeChanged: {
                Task {
                    await viewModel.loadSelectedScope()
                }
            },
            reload: {
                Task {
                    await viewModel.loadRecentAssets()
                }
            },
            clearSearch: {
                viewModel.clearSearchResults()
            },
            openPreview: { asset in
                viewModel.openPreview(for: asset)
            }
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
