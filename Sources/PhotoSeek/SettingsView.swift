import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var photosPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
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

            // API Key
            VStack(alignment: .leading, spacing: 6) {
                Text("Gemini API Key")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField("Paste your API key", text: Bindable(SettingsManager.shared).apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
            }

            Divider()

            // Index Status
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Index")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.indexedCount) photos")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                TextField("Photos library path", text: $photosPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                HStack {
                    if viewModel.isIndexing {
                        ProgressView(value: Double(viewModel.indexingDone),
                                     total: max(Double(viewModel.indexingTotal), 1))
                            .frame(maxWidth: .infinity)
                        Text("\(viewModel.indexingDone)/\(viewModel.indexingTotal)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button("Stop") { viewModel.stopIndexing() }
                            .controlSize(.small)
                    } else {
                        Button("Index New Photos") {
                            Task { await viewModel.indexPhotos(from: photosPath) }
                        }
                        .disabled(!viewModel.hasApiKey || photosPath.isEmpty)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            photosPath = "\(home)/Pictures/Photos Library.photoslibrary/originals"
        }
    }
}
