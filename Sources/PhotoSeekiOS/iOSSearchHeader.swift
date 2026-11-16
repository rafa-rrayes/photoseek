#if os(iOS)
import SwiftUI
import PhotoSeekCore

/// Always-visible header: search field + settings, and a second row with the
/// media-type filter and Select controls when there are results.
///
/// This deliberately does NOT use `.searchable` — on iOS 26 the system search
/// field floats at the bottom and hides the navigation toolbar while a query
/// is active, which made Select/filter/settings unreachable.
struct iOSSearchHeader: View {
    @Binding var query: String
    @Binding var mediaTypeFilter: MediaTypeFilter
    var isLoading: Bool
    var isSelectMode: Bool
    var showFilterRow: Bool
    var isIndexing: Bool
    var indexingDone: Int
    var indexingTotal: Int
    var onSelectToggle: () -> Void
    var onSelectAll: () -> Void
    var onSettingsTap: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                searchField
                settingsButton
            }

            if isSelectMode {
                selectRow
            } else if showFilterRow {
                filterRow
            }

            if isIndexing {
                indexingBanner
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(height: 0.5)
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField("Search your photos…", text: $query)
                .font(.body)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private var settingsButton: some View {
        Button(action: onSettingsTap) {
            Image(systemName: "gearshape.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    // MARK: - Filter / Select rows

    private var filterRow: some View {
        HStack(spacing: 12) {
            Picker("Type", selection: $mediaTypeFilter) {
                Text("All").tag(MediaTypeFilter.all)
                Text("Photos").tag(MediaTypeFilter.photos)
                Text("Videos").tag(MediaTypeFilter.videos)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Spacer(minLength: 8)

            Button("Select") {
                searchFocused = false
                onSelectToggle()
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    private var selectRow: some View {
        HStack {
            Button("Select All", action: onSelectAll)
                .font(.subheadline)

            Spacer()

            Button("Done", action: onSelectToggle)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Indexing banner

    private var indexingBanner: some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(indexingDone),
                         total: max(Double(indexingTotal), 1))
                .progressViewStyle(.linear)

            Text("Indexing \(indexingDone)/\(indexingTotal)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
    }
}
#endif
