#if os(iOS)
import SwiftUI
import DejaViCore

struct iOSContentView: View {
    @Bindable var viewModel: SearchViewModel
    @State private var showSettings = false
    @State private var showAlbumPicker = false
    @State private var viewerTarget: ViewerTarget?

    private var trimmedQuery: String {
        viewModel.query.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Group {
            if !viewModel.hasApiKey && !viewModel.isStoreLoaded {
                setupView
            } else {
                mainContent
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedCount)
        .alert("Delete \(viewModel.selectedCount) item\(viewModel.selectedCount == 1 ? "" : "s")?",
               isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) { Task { await viewModel.deleteSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move \(viewModel.selectedCount == 1 ? "this item" : "these items") to Recently Deleted.")
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                iOSSettingsView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showAlbumPicker) {
            iOSAlbumPicker(
                viewModel: viewModel,
                onSelect: { name in Task { await viewModel.addSelectedToAlbum(name) } },
                onCreateNew: { name in Task { await viewModel.createAlbumWithSelected(name) } }
            )
        }
        .fullScreenCover(item: $viewerTarget) { target in
            iOSPhotoViewer(viewModel: viewModel, initialUUID: target.uuid)
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        contentBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                iOSSearchHeader(
                    query: $viewModel.query,
                    mediaTypeFilter: $viewModel.mediaTypeFilter,
                    isLoading: viewModel.isLoading,
                    isSelectMode: viewModel.isSelectMode,
                    showFilterRow: !viewModel.results.isEmpty
                        && !trimmedQuery.isEmpty
                        && viewModel.errorMessage == nil,
                    isIndexing: viewModel.isIndexing,
                    indexingDone: viewModel.indexingDone,
                    indexingTotal: viewModel.indexingTotal,
                    onSelectToggle: { viewModel.toggleSelectMode() },
                    onSelectAll: { viewModel.selectAll() },
                    onSettingsTap: { showSettings = true }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isSelectMode || viewModel.hasSelection {
                    iOSActionBar(
                        selectedCount: viewModel.selectedCount,
                        onFavorite: { Task { await viewModel.favoriteSelected() } },
                        onUnfavorite: { Task { await viewModel.unfavoriteSelected() } },
                        onAddToAlbum: { showAlbumPicker = true },
                        onDelete: { viewModel.confirmDelete() },
                        onClearSelection: { viewModel.clearSelection() }
                    )
                }
            }
    }

    @ViewBuilder
    private var contentBody: some View {
        if let error = viewModel.errorMessage {
            errorView(error)
        } else if trimmedQuery.isEmpty {
            emptyState
        } else if viewModel.results.isEmpty && !viewModel.isLoading {
            ContentUnavailableView.search(text: trimmedQuery)
        } else {
            iOSPhotoGrid(
                results: viewModel.results,
                selectedUUIDs: viewModel.selectedUUIDs,
                isSelectMode: viewModel.isSelectMode,
                isLoadingMore: viewModel.isLoadingMore,
                onSelect: { viewModel.toggleSelection($0) },
                onEnterSelectMode: { viewModel.enterSelectMode(selecting: $0) },
                onReachEnd: { Task { await viewModel.loadMore() } },
                onOpenPhoto: { viewerTarget = ViewerTarget(uuid: $0) }
            )
        }
    }

    // MARK: - Setup / onboarding

    private var setupView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("DejaVi")
                .font(.title.bold())

            Text("Search your photos using natural language")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("You need a Gemini API key (free) to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Link("Get your free API key at Google AI Studio",
                     destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.subheadline)
            }

            SecureField("Paste your API key", text: Bindable(SettingsManager.shared).apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 40)
                .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            if viewModel.indexedCount > 0 {
                Text("Search your photos with natural language")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                suggestionChips
                    .padding(.top, 4)

                Text("\(viewModel.indexedCount) items indexed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            } else {
                Text("No photos indexed yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings to Index Photos") {
                    showSettings = true
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var suggestionChips: some View {
        HStack(spacing: 8) {
            ForEach(["birthday cake", "beach sunset", "screenshots"], id: \.self) { suggestion in
                Button {
                    viewModel.query = suggestion
                } label: {
                    Text(suggestion)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}
#endif
