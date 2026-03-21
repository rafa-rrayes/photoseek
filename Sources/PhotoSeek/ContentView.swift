import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: SearchViewModel
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.hasApiKey && !viewModel.isStoreLoaded {
                setupView
            } else {
                SearchBar(
                    query: $viewModel.query,
                    isLoading: viewModel.isLoading,
                    indexedCount: viewModel.indexedCount,
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
                        isLoadingMore: viewModel.isLoadingMore,
                        onReachEnd: { Task { await viewModel.loadMore() } }
                    )
                }
            }
        }
        .frame(width: 680, height: 520)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadStore()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
                .background(.ultraThinMaterial)
                .preferredColorScheme(.dark)
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
            Text("Enter your Gemini API key to get started")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            SecureField("Paste your API key", text: Bindable(SettingsManager.shared).apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 350)
                .padding(.top, 8)

            if SettingsManager.shared.hasApiKey {
                Label("Key saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13))
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
            Text("Search your photos with natural language")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            if viewModel.indexedCount > 0 {
                Text("\(viewModel.indexedCount) photos indexed")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
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
