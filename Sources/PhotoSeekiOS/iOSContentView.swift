#if os(iOS)
import SwiftUI
import PhotoSeekCore

struct iOSContentView: View {
    @Bindable var viewModel: SearchViewModel
    @State private var showSettings = false
    @State private var showAlbumPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasApiKey && !viewModel.isStoreLoaded {
                    setupView
                } else if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    emptyState
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if viewModel.results.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView.search(text: viewModel.query)
                } else {
                    iOSPhotoGrid(
                        results: viewModel.results,
                        selectedUUIDs: viewModel.selectedUUIDs,
                        isSelectMode: viewModel.isSelectMode,
                        isLoadingMore: viewModel.isLoadingMore,
                        onSelect: { viewModel.toggleSelection($0) },
                        onReachEnd: { Task { await viewModel.loadMore() } },
                        onOpenPhoto: { uuid in
                            viewModel.photoActions?.openPhoto(uuid)
                        }
                    )
                }
            }
            .navigationTitle("PhotoSeek")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: "Search your photos...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.results.isEmpty {
                        Button(viewModel.isSelectMode ? "Done" : "Select") {
                            viewModel.toggleSelectMode()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.hasSelection {
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
            .alert("Delete \(viewModel.selectedCount) photo\(viewModel.selectedCount == 1 ? "" : "s")?",
                   isPresented: $viewModel.showDeleteConfirmation) {
                Button("Delete", role: .destructive) { Task { await viewModel.deleteSelected() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will move \(viewModel.selectedCount == 1 ? "this photo" : "these photos") to Recently Deleted.")
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
        }
    }

    private var setupView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("PhotoSeek")
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
                Text("\(viewModel.indexedCount) photos indexed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No photos indexed yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings to Index Photos") {
                    showSettings = true
                }
                .font(.subheadline)
            }
            Spacer()
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
