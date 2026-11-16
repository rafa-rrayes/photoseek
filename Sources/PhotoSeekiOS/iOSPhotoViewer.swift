#if os(iOS)
import SwiftUI
import Photos
import AVFoundation
import PhotoSeekCore

struct ViewerTarget: Identifiable {
    let uuid: String
    var id: String { uuid }
}

/// Full-screen in-app viewer: swipe between results, pinch/double-tap zoom,
/// video playback, favorite/share/delete — without leaving the search.
struct iOSPhotoViewer: View {
    @Bindable var viewModel: SearchViewModel
    let initialUUID: String
    @Environment(\.dismiss) private var dismiss

    @State private var selection: String
    @State private var isFavorite = false
    @State private var showChrome = true
    @State private var sharePayload: SharePayload?
    @State private var isPreparingShare = false

    init(viewModel: SearchViewModel, initialUUID: String) {
        self.viewModel = viewModel
        self.initialUUID = initialUUID
        _selection = State(initialValue: initialUUID)
    }

    private var currentResult: SearchResult? {
        viewModel.results.first { $0.uuid == selection }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(viewModel.results) { result in
                    ViewerPage(
                        result: result,
                        onSingleTap: {
                            withAnimation(.easeInOut(duration: 0.15)) { showChrome.toggle() }
                        },
                        onPlayVideo: {
                            viewModel.photoActions?.openVideo(result.uuid)
                        }
                    )
                    .tag(result.uuid)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if showChrome { topBar }
        }
        .overlay(alignment: .bottom) {
            if showChrome { bottomBar }
        }
        .statusBarHidden(!showChrome)
        .preferredColorScheme(.dark)
        .task(id: selection) {
            refreshFavorite()
            if selection == viewModel.results.last?.uuid {
                await viewModel.loadMore()
            }
        }
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: viewModel.results.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("Close")

            Spacer()

            if let result = currentResult {
                VStack(spacing: 1) {
                    if let date = parseDate(result.date) {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
            }

            Spacer()

            if let result = currentResult {
                Text("\(Int(result.score * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .accessibilityLabel("Match score")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .background(
            LinearGradient(colors: [.black.opacity(0.5), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
        .transition(.opacity)
    }

    private var bottomBar: some View {
        HStack {
            chromeButton(isFavorite ? "heart.fill" : "heart",
                         label: isFavorite ? "Unfavorite" : "Favorite",
                         tint: isFavorite ? .pink : .white) {
                Task { await toggleFavorite() }
            }

            Spacer()

            chromeButton(isPreparingShare ? "ellipsis" : "square.and.arrow.up", label: "Share") {
                Task { await shareCurrent() }
            }

            Spacer()

            chromeButton("trash", label: "Delete", tint: .red) {
                Task { await deleteCurrent() }
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
        .transition(.opacity)
    }

    private func chromeButton(_ systemImage: String,
                              label: String,
                              tint: Color = .white,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func refreshFavorite() {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [selection], options: nil)
        isFavorite = assets.firstObject?.isFavorite ?? false
    }

    private func toggleFavorite() async {
        guard let actions = viewModel.photoActions else { return }
        if isFavorite {
            _ = await actions.unfavorite([selection])
        } else {
            _ = await actions.favorite([selection])
        }
        refreshFavorite()
    }

    private func deleteCurrent() async {
        let uuid = selection
        // Pick the neighbor to land on before mutating results.
        let uuids = viewModel.results.map(\.uuid)
        var next: String?
        if let idx = uuids.firstIndex(of: uuid) {
            next = idx + 1 < uuids.count ? uuids[idx + 1] : (idx > 0 ? uuids[idx - 1] : nil)
        }

        // PhotoKit shows its own system confirmation; no extra alert needed.
        let deleted = await viewModel.deleteItems([uuid])
        guard deleted else { return }

        if let next {
            selection = next
        } else {
            dismiss()
        }
    }

    private func shareCurrent() async {
        guard !isPreparingShare, let result = currentResult else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        if result.mediaType == .video {
            if let url = await videoURL(for: result.uuid) {
                sharePayload = SharePayload(items: [url])
            }
        } else if let image = await iOSImageCache.shared.fullImage(
            for: result.uuid,
            targetSize: PHImageManagerMaximumSize
        ) {
            sharePayload = SharePayload(items: [image])
        }
    }

    private func videoURL(for uuid: String) async -> URL? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [uuid], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat

        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
    }

    private func parseDate(_ iso: String) -> Date? {
        guard !iso.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }
}

// MARK: - Page

private struct ViewerPage: View {
    let result: SearchResult
    var onSingleTap: () -> Void
    var onPlayVideo: () -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if result.mediaType == .video {
                videoBody
            } else if let image {
                ZoomableImageView(image: image, onSingleTap: onSingleTap)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: result.uuid) {
            // Show the (usually cached) thumbnail instantly, then swap in
            // the screen-quality image.
            if image == nil {
                image = await iOSImageCache.shared.thumbnail(for: result.uuid)
            }
            if let full = await iOSImageCache.shared.fullImage(for: result.uuid) {
                image = full
            }
        }
    }

    private var videoBody: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .tint(.white)
            }

            Button(action: onPlayVideo) {
                Image(systemName: "play.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .accessibilityLabel("Play video")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSingleTap)
    }
}

// MARK: - Zoomable image (UIScrollView-backed)

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var onSingleTap: () -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bouncesZoom = true
        scroll.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scroll.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleSingleTap))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scroll.setZoomScale(1, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onSingleTap: () -> Void

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleSingleTap() {
            onSingleTap()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5,
                                  height: scroll.bounds.height / 2.5)
                let rect = CGRect(x: point.x - size.width / 2,
                                  y: point.y - size.height / 2,
                                  width: size.width,
                                  height: size.height)
                scroll.zoom(to: rect, animated: true)
            }
        }
    }
}

// MARK: - Share sheet

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
