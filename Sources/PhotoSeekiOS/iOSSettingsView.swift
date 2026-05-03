#if os(iOS)
import SwiftUI
import PhotoSeekCore

struct iOSSettingsView: View {
    @Bindable var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showApiKey = false
    @State private var showRemoveKeyAlert = false
    @State private var showClearIndexAlert = false
    @State private var libraryStats: LibraryStats?
    @State private var isScanningStats = false

    private var settings: SettingsManager { SettingsManager.shared }

    var body: some View {
        Form {
            apiKeySection
            indexingSection
            libraryStatsSection
            displaySection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Remove API Key?", isPresented: $showRemoveKeyAlert) {
            Button("Remove", role: .destructive) { settings.removeApiKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to re-enter your Gemini API key to use search.")
        }
        .alert("Clear Index?", isPresented: $showClearIndexAlert) {
            Button("Clear", role: .destructive) { Task { await viewModel.clearIndex() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all indexed photos. You will need to re-index.")
        }
    }

    // MARK: - API Key

    private var apiKeySection: some View {
        Section("Gemini API Key") {
            if showApiKey {
                TextField("API key", text: Bindable(settings).apiKey)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                SecureField("Paste your API key", text: Bindable(settings).apiKey)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Button(showApiKey ? "Hide Key" : "Show Key") {
                showApiKey.toggle()
            }

            if settings.hasApiKey {
                Button("Remove API Key", role: .destructive) {
                    showRemoveKeyAlert = true
                }
            }

            if !settings.hasApiKey {
                Link("Get a free API key at Google AI Studio",
                     destination: URL(string: "https://aistudio.google.com/apikey")!)
            }
        }
    }

    // MARK: - Indexing

    private var indexingSection: some View {
        Section("Indexing") {
            if viewModel.isIndexing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(viewModel.indexingDone),
                                 total: max(Double(viewModel.indexingTotal), 1))
                    HStack {
                        Text("\(viewModel.indexingDone)/\(viewModel.indexingTotal)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") { viewModel.stopIndexing() }
                    }
                }
            } else {
                Button("Index Library") {
                    Task {
                        await viewModel.indexPhotos()
                        await viewModel.indexVideos()
                    }
                }
                .disabled(!settings.hasApiKey)

                Button("Re-index All") {
                    Task { await viewModel.reindexAll() }
                }
                .disabled(!settings.hasApiKey)

                Toggle("Index videos", isOn: Bindable(settings).indexVideosEnabled)

                Button("Clear Index", role: .destructive) {
                    showClearIndexAlert = true
                }
                .disabled(viewModel.indexedCount == 0)
            }
        }
    }

    // MARK: - Library Stats

    private var libraryStatsSection: some View {
        Section("Library") {
            HStack {
                Text("\(viewModel.indexedCount) items indexed")
                Spacer()
                if isScanningStats {
                    ProgressView()
                } else {
                    Button("Scan") {
                        isScanningStats = true
                        Task {
                            libraryStats = await viewModel.photoProvider?.scanLibraryStats()
                            isScanningStats = false
                        }
                    }
                }
            }

            if let stats = libraryStats {
                LabeledContent("Total Photos", value: "\(stats.totalPhotos)")
                LabeledContent("Total Videos", value: "\(stats.totalVideos)")
                let total = stats.totalPhotos + stats.totalVideos
                if total > 0 {
                    let pct = Int(round(Double(viewModel.indexedCount) / Double(total) * 100))
                    LabeledContent("Indexed", value: "\(pct)%")
                }
            }

            if let date = settings.lastIndexedDate {
                LabeledContent("Last Indexed", value: date.formatted(.relative(presentation: .named)))
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section("Display") {
            Toggle("Show Similarity %", isOn: Bindable(settings).showSimilarityPercent)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            Text("Semantic photo search powered by Gemini")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
