import SwiftUI
import PhotoSeekCore

struct ContentView: View {
    @Bindable var viewModel: SearchViewModel
    @State private var showSettings = false
    @State private var showAlbumPicker = false

    private var settings: SettingsManager { SettingsManager.shared }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.hasApiKey && !viewModel.isStoreLoaded {
                setupView
            } else {
                SearchBar(
                    query: $viewModel.query,
                    mediaTypeFilter: $viewModel.mediaTypeFilter,
                    isLoading: viewModel.isLoading,
                    indexedCount: viewModel.indexedCount,
                    isSelectMode: viewModel.isSelectMode,
                    hasResults: !viewModel.results.isEmpty,
                    showFilter: !viewModel.results.isEmpty
                        && !viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty
                        && viewModel.errorMessage == nil,
                    onSelectToggle: { viewModel.toggleSelectMode() },
                    onSettingsTap: { showSettings = true }
                )

                Divider()

                if let error = viewModel.errorMessage {
                    errorView(error)
                } else if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    emptyState
                } else if viewModel.results.isEmpty && !viewModel.isLoading {
                    noResults
                } else {
                    PhotoGrid(
                        results: viewModel.results,
                        selectedUUIDs: viewModel.selectedUUIDs,
                        isSelectMode: viewModel.isSelectMode,
                        isLoadingMore: viewModel.isLoadingMore,
                        onSelect: { viewModel.toggleSelection($0) },
                        onReachEnd: { Task { await viewModel.loadMore() } }
                    )
                }

                if viewModel.hasSelection {
                    Divider()
                    ActionBar(
                        selectedCount: viewModel.selectedCount,
                        onFavorite: { Task { await viewModel.favoriteSelected() } },
                        onUnfavorite: { Task { await viewModel.unfavoriteSelected() } },
                        onAddToAlbum: { showAlbumPicker = true },
                        onNewAlbum: { showAlbumPicker = true },
                        onDelete: { viewModel.confirmDelete() },
                        onClearSelection: { viewModel.clearSelection() }
                    )
                }
            }
        }
        .frame(width: 680, height: 520)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadStore()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
                .background(panelBackground)
                .preferredColorScheme(.dark)
        }
        .alert("Delete \(viewModel.selectedCount) photo\(viewModel.selectedCount == 1 ? "" : "s")?",
               isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) { Task { await viewModel.deleteSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move \(viewModel.selectedCount == 1 ? "this photo" : "these photos") to Recently Deleted in Photos.")
        }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPickerSheet(
                albums: PhotosActions.fetchAlbumNames(),
                onSelect: { name in Task { await viewModel.addSelectedToAlbum(name) } },
                onCreateNew: { name in Task { await viewModel.createAlbumWithSelected(name) } }
            )
            .background(panelBackground)
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if settings.solidDarkMode {
            Color(red: 0.10, green: 0.10, blue: 0.11)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private var setupView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("PhotoSeek")
                .font(.system(size: 22, weight: .semibold))

            if !SettingsManager.shared.hasApiKey {
                Text("Search your photos using natural language")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("You need a Gemini API key (free) to get started.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Link("Get your free API key at Google AI Studio",
                         destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.system(size: 13))
                }

                SecureField("Paste your API key", text: Bindable(SettingsManager.shared).apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: 350)
                    .padding(.top, 4)
            } else {
                Label("API key saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13))

                Text("Now index your photo library so PhotoSeek can search it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Button("Open Settings to Start Indexing") {
                    showSettings = true
                }
                .controlSize(.large)
            }

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
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("\(viewModel.indexedCount) photos indexed")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                Text("No photos indexed yet")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Button("Open Settings to Index Photos") {
                    showSettings = true
                }
                .font(.system(size: 12))
            }
            Spacer()
        }
    }

    private var noResults: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No matching photos")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
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
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}
