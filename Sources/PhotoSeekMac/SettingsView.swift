import SwiftUI
import PhotoSeekCore

struct SettingsView: View {
    @Bindable var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showApiKey = false
    @State private var showRemoveKeyAlert = false
    @State private var showClearIndexAlert = false
    @State private var showIndexingStartedAlert = false
    @State private var libraryStats: LibraryStats?
    @State private var isScanningStats = false
    @State private var photosLibraryAccessible: Bool = PhotosLibraryAccess.shared.canReadLibrary

    private var settings: SettingsManager { SettingsManager.shared }
var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !photosLibraryAccessible {
                        photosLibraryAccessSection
                    }
                    apiKeySection
                    Divider()
                    indexFoldersSection
                    Divider()
                    libraryStatsSection
                    Divider()
                    indexingSection
                    Divider()
                    generalSection
                    Divider()
                    aboutSection
                }
                .padding(20)
            }

            if showIndexingStartedAlert {
                indexingStartedOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: showIndexingStartedAlert)
        .frame(width: 460, height: 520)
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
            Text("This will remove all indexed photos from the database. You will need to re-index.")
        }
    }

    private var indexingStartedOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { showIndexingStartedAlert = false }

            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.primary)

                Text("Indexing started")
                    .font(.system(size: 15, weight: .semibold))

                Text("Press Esc to hide this window — indexing will continue in the background. Progress is shown in the menu bar.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showIndexingStartedAlert = false
                    dismiss()
                } label: {
                    Text("Got it")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
            }
            .padding(20)
            .frame(width: 300)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Photos Library Access

    private var photosLibraryAccessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Photos Library access required")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("PhotoSeek reads your Photos Library directly from disk. Grant access once so it can index your photos and load thumbnails.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Grant Photos Library Access…") {
                if PhotosLibraryAccess.shared.requestAccess() {
                    photosLibraryAccessible = PhotosLibraryAccess.shared.canReadLibrary
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(.orange.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.orange.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - API Key

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gemini API Key")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if showApiKey {
                    TextField("API key", text: Bindable(settings).apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                } else {
                    SecureField("Paste your API key", text: Bindable(settings).apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }

                Button(action: { showApiKey.toggle() }) {
                    Image(systemName: showApiKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(showApiKey ? "Hide API key" : "Show API key")

                if settings.hasApiKey {
                    Button(action: { showRemoveKeyAlert = true }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Remove API key")
                }
            }

            if !settings.hasApiKey {
                Link("Get a free API key at Google AI Studio",
                     destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.system(size: 11))
            }
        }
    }

    // MARK: - Index Folders

    private var indexFoldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Index Folders")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !settings.indexFolders.contains(defaultPhotosLibraryFolder) {
                    Button(action: addPhotosLibraryDefault) {
                        Label("Add Photos Library", systemImage: "photo.stack")
                            .font(.system(size: 11))
                    }
                    .controlSize(.small)
                }
                Button(action: addFolder) {
                    Label("Add Folder", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
            }

            if settings.indexFolders.isEmpty {
                Text("No folders added. Add a folder to start indexing.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 4) {
                    ForEach(settings.indexFolders, id: \.self) { folder in
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                            Text(abbreviatePath(folder))
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(action: { removeFolder(folder) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                    }
                }
            }
        }
    }

    // MARK: - Library Stats

    private var libraryStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Library")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if isScanningStats {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Scan") {
                        isScanningStats = true
                        Task {
                            libraryStats = await viewModel.scanLibraryStats()
                            isScanningStats = false
                        }
                    }
                    .controlSize(.small)
                }
            }

            if let stats = libraryStats {
                HStack(spacing: 16) {
                    statBadge(label: "Total Photos", count: stats.totalPhotos, color: .blue)
                    statBadge(label: "Total Videos", count: stats.totalVideos, color: .purple)
                    statBadge(label: "iCloud Only", count: stats.iCloudOnly + stats.iCloudOnlyVideos, color: .orange)
                }
            }

            HStack(spacing: 4) {
                if let stats = libraryStats {
                    let total = stats.totalPhotos + stats.totalVideos
                    if total > 0 {
                        let pct = Int(round(Double(viewModel.indexedCount) / Double(total) * 100))
                        Text("\(formatNumber(viewModel.indexedCount)) indexed (\(pct)%)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(formatNumber(viewModel.indexedCount)) indexed")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(formatNumber(viewModel.indexedCount)) indexed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let date = settings.lastIndexedDate {
                Text("Last indexed: \(date.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func statBadge(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(formatNumber(count))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Indexing

    private var indexingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Indexing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if viewModel.isIndexing {
                VStack(spacing: 6) {
                    ProgressView(value: Double(viewModel.indexingDone),
                                 total: max(Double(viewModel.indexingTotal), 1))
                    HStack {
                        Text("\(viewModel.indexingDone)/\(viewModel.indexingTotal)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") { viewModel.stopIndexing() }
                            .controlSize(.small)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button("Index All") {
                            showIndexingStartedAlert = true
                            Task {
                                await viewModel.indexAllFolders(
                                    includeVideos: settings.indexVideosEnabled,
                                    includeICloud: settings.indexIncludeICloud
                                )
                            }
                        }
                        .disabled(!settings.hasApiKey || settings.indexFolders.isEmpty)
                        .controlSize(.small)

                        Button("Re-index All") {
                            showIndexingStartedAlert = true
                            Task { await viewModel.reindexAll() }
                        }
                        .disabled(!settings.hasApiKey || settings.indexFolders.isEmpty)
                        .controlSize(.small)

                        Spacer()

                        Button("Clear Index") {
                            showClearIndexAlert = true
                        }
                        .foregroundStyle(.red)
                        .controlSize(.small)
                        .disabled(viewModel.indexedCount == 0)
                    }

                    HStack(spacing: 16) {
                        Toggle("Include Videos", isOn: Bindable(settings).indexVideosEnabled)
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                        Toggle("Include iCloud", isOn: Bindable(settings).indexIncludeICloud)
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Toggle("Show Similarity %", isOn: Bindable(settings).showSimilarityPercent)
                .font(.system(size: 13))
            Toggle("Launch at Login", isOn: Bindable(settings).launchAtLogin)
                .font(.system(size: 13))
            Toggle("Solid Dark Background", isOn: Bindable(settings).solidDarkMode)
                .font(.system(size: 13))
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("About")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            Text("PhotoSeek v\(version)")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text("Semantic photo search powered by Gemini")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private var defaultPhotosLibraryFolder: String {
        PhotosLibraryAccess.shared.libraryURL.appendingPathComponent("originals").path
    }

    private func addPhotosLibraryDefault() {
        let path = defaultPhotosLibraryFolder
        if !settings.indexFolders.contains(path) {
            settings.indexFolders.append(path)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Choose a folder to index photos from"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if !settings.indexFolders.contains(path) {
                settings.indexFolders.append(path)
            }
        }
    }

    private func removeFolder(_ folder: String) {
        settings.indexFolders.removeAll { $0 == folder }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
