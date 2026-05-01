import SwiftUI
import AppKit

/// Image viewer with fit-to-window-by-default sizing, pinch / scroll
/// magnification, and an explicit zoom toolbar. Backed by `NSImageView`
/// so animated GIFs play natively. The image is rendered at its natural
/// pixel size inside an `NSScrollView`, which handles magnification and
/// scrolling for everything bigger than the visible area.
struct ImageViewerView: View {
    let url: URL

    @StateObject private var controller = ImageZoomController()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ImageScrollHost(url: url, controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZoomToolbar(controller: controller)
                .padding(.leading, 14)
                .padding(.bottom, 14)
        }
    }
}

/// Holds the magnification state shared between the SwiftUI controls
/// and the underlying `NSScrollView`. Driven from both directions —
/// pinch / scroll updates flow up here from the scroll view, and the
/// toolbar's buttons send commands down.
@MainActor
final class ImageZoomController: ObservableObject {
    @Published private(set) var displayMagnification: CGFloat = 1.0
    @Published private(set) var fitMagnification: CGFloat = 1.0
    @Published private(set) var imageSize: CGSize = .zero
    @Published private(set) var isLoaded: Bool = false
    /// `true` when the current magnification matches the computed fit
    /// value — drives the toolbar's "fit" button highlight.
    var isFitMode: Bool {
        guard fitMagnification > 0 else { return false }
        return abs(displayMagnification - fitMagnification) < 0.001
    }

    static let minMagnification: CGFloat = 0.05
    static let maxMagnification: CGFloat = 32.0

    weak var scrollView: NSScrollView?

    func report(magnification: CGFloat) {
        // Mirror the scroll view's magnification into our published
        // state so the toolbar reflects pinch / Cmd-scroll changes.
        if abs(displayMagnification - magnification) > 0.0001 {
            displayMagnification = magnification
        }
    }

    func updateFitMagnification(_ value: CGFloat, applyIfFit: Bool) {
        guard value.isFinite, value > 0 else { return }
        let wasFit = isFitMode
        fitMagnification = value
        if applyIfFit && wasFit {
            apply(magnification: value)
        }
    }

    func reportImageLoaded(size: CGSize) {
        imageSize = size
        isLoaded = true
    }

    func zoomIn()  { apply(magnification: clamp(displayMagnification * 1.25)) }
    func zoomOut() { apply(magnification: clamp(displayMagnification * 0.8)) }
    func fitToWindow() { apply(magnification: clamp(fitMagnification)) }
    func actualSize()  { apply(magnification: 1.0) }

    private func apply(magnification: CGFloat) {
        guard let scroll = scrollView else { return }
        let center = CGPoint(
            x: scroll.contentView.bounds.midX,
            y: scroll.contentView.bounds.midY
        )
        scroll.setMagnification(magnification, centeredAt: center)
        displayMagnification = magnification
    }

    private func clamp(_ m: CGFloat) -> CGFloat {
        max(Self.minMagnification, min(Self.maxMagnification, m))
    }
}

private struct ZoomToolbar: View {
    @ObservedObject var controller: ImageZoomController
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            iconButton(symbol: "minus", help: "Zoom out") {
                controller.zoomOut()
            }
            Text(percentString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44)
            iconButton(symbol: "plus", help: "Zoom in") {
                controller.zoomIn()
            }
            divider
            iconButton(
                symbol: "arrow.up.left.and.arrow.down.right",
                help: "Fit to window",
                emphasized: controller.isFitMode
            ) {
                controller.fitToWindow()
            }
            iconButton(symbol: "1.magnifyingglass", help: "Actual size (100%)") {
                controller.actualSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .modifier(StatusPillSurface(useGlass: windowGlass))
        .opacity(controller.isLoaded ? 1.0 : 0.0)
    }

    private var percentString: String {
        let pct = Int((controller.displayMagnification * 100).rounded())
        return "\(pct)%"
    }

    private var divider: some View {
        Capsule().fill(.secondary.opacity(0.4)).frame(width: 1, height: 14)
    }

    private func iconButton(
        symbol: String,
        help: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(emphasized ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Bridges SwiftUI to a custom `NSScrollView` subclass that emits
/// callbacks on bounds changes so we can keep the fit magnification in
/// sync as the user resizes the window.
private struct ImageScrollHost: NSViewRepresentable {
    let url: URL
    @ObservedObject var controller: ImageZoomController

    func makeNSView(context: Context) -> ResizingScrollView {
        let scroll = ResizingScrollView()
        scroll.allowsMagnification = true
        scroll.minMagnification = ImageZoomController.minMagnification
        scroll.maxMagnification = ImageZoomController.maxMagnification
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.autohidesScrollers = true

        let imageView = NSImageView()
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        imageView.animates = true
        scroll.documentView = imageView

        // Magnification deltas — pinch + Cmd-scroll — flow through
        // NSScrollView.magnifyEndedNotification. We mirror the value
        // into the controller so the toolbar's percentage stays live.
        context.coordinator.scrollView = scroll
        context.coordinator.imageView = imageView
        context.coordinator.controller = controller
        controller.scrollView = scroll
        context.coordinator.installObservers()

        scroll.onResize = { [weak coord = context.coordinator] in
            coord?.recomputeFit(applyingIfFit: true)
        }

        loadImage(into: imageView, scrollView: scroll, coordinator: context.coordinator)
        return scroll
    }

    func updateNSView(_ scroll: ResizingScrollView, context: Context) {
        // If the URL changed (e.g., the file was renamed and reopened),
        // swap the image and reset to fit.
        if context.coordinator.lastURL != url,
           let imageView = scroll.documentView as? NSImageView {
            loadImage(into: imageView, scrollView: scroll, coordinator: context.coordinator)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func loadImage(
        into imageView: NSImageView,
        scrollView: ResizingScrollView,
        coordinator: Coordinator
    ) {
        coordinator.lastURL = url
        guard let image = NSImage(contentsOf: url) else {
            imageView.image = nil
            controller.reportImageLoaded(size: .zero)
            return
        }
        imageView.image = image

        // Drive the document view's frame from the image's pixel size
        // so magnification scales the whole view uniformly. Fall back
        // to NSImage.size for non-bitmap representations.
        let pixelSize = pixelDimensions(for: image) ?? image.size
        imageView.setFrameSize(pixelSize)
        controller.reportImageLoaded(size: pixelSize)
        coordinator.recomputeFit(applyingIfFit: false)
        // Default to fit on first load.
        scrollView.magnification = controller.fitMagnification
        controller.report(magnification: scrollView.magnification)
    }

    private func pixelDimensions(for image: NSImage) -> CGSize? {
        var width = 0
        var height = 0
        for rep in image.representations {
            width = max(width, rep.pixelsWide)
            height = max(height, rep.pixelsHigh)
        }
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    @MainActor
    final class Coordinator {
        weak var scrollView: NSScrollView?
        weak var imageView: NSImageView?
        weak var controller: ImageZoomController?
        var lastURL: URL?
        private var magnifyObserver: NSObjectProtocol?

        deinit {
            if let observer = magnifyObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func installObservers() {
            guard let scroll = scrollView else { return }
            magnifyObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveMagnifyNotification,
                object: scroll,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.controller?.report(magnification: scroll.magnification)
                }
            }
        }

        func recomputeFit(applyingIfFit: Bool) {
            guard let scroll = scrollView,
                  let controller,
                  controller.imageSize.width > 0,
                  controller.imageSize.height > 0
            else { return }
            let bounds = scroll.contentView.bounds.size
            guard bounds.width > 0, bounds.height > 0 else { return }
            let fit = min(
                bounds.width  / controller.imageSize.width,
                bounds.height / controller.imageSize.height
            )
            // Don't auto-magnify above 1.0 — small images stay at their
            // natural size centered in the view rather than blowing up
            // and looking blurry. The user can still zoom past 100%
            // manually.
            let clampedFit = min(fit, 1.0)
            controller.updateFitMagnification(clampedFit, applyIfFit: applyingIfFit)
        }
    }

    /// `NSScrollView` subclass that runs a callback every time its
    /// frame changes — used to keep the fit magnification synced as the
    /// window resizes.
    final class ResizingScrollView: NSScrollView {
        var onResize: (() -> Void)?

        override func tile() {
            super.tile()
            onResize?()
        }
    }
}
