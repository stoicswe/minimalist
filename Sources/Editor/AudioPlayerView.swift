import SwiftUI
import AppKit
import AVFoundation
import Combine

/// Audio file viewer. Drives an `AVPlayer` for playback while showing
/// embedded artwork (when present), the track's title / artist, and
/// custom transport controls — play / pause, scrubber, time displays.
/// We don't reuse `VideoPlayer` because it renders an empty surface
/// for audio-only items; building the view ourselves lets us actually
/// present the media instead of a black box.
struct AudioPlayerView: View {
    let url: URL

    @StateObject private var coordinator = AudioPlayerCoordinator()
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 30)

            ArtworkView(image: coordinator.artwork)
                .frame(width: 280, height: 280)

            VStack(spacing: 4) {
                Text(coordinator.title ?? url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let artist = coordinator.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 480)
            .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            TransportControls(coordinator: coordinator)
                .frame(maxWidth: 520)

            Spacer(minLength: 30)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) { await coordinator.load(url: url) }
        .onDisappear { coordinator.pause() }
    }
}

private struct ArtworkView: View {
    let image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 0.5)
                    )
                Image(systemName: "music.note")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            .shadow(color: .black.opacity(0.15), radius: 14, y: 5)
        }
    }
}

private struct TransportControls: View {
    @ObservedObject var coordinator: AudioPlayerCoordinator

    /// Local override of the slider's value while the user is actively
    /// dragging — without this, the periodic time observer fights the
    /// drag and the slider snaps back as you scrub.
    @State private var scrubValue: Double? = nil

    var body: some View {
        VStack(spacing: 10) {
            Slider(
                value: scrubBinding,
                in: 0...max(coordinator.duration, 0.001),
                onEditingChanged: handleEditing
            )
            .tint(.accentColor)
            .disabled(!coordinator.isReady)

            HStack {
                Text(formatTime(displayedTime))
                Spacer()
                Text("-" + formatTime(max(0, coordinator.duration - displayedTime)))
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)

            HStack(spacing: 32) {
                transportButton(
                    symbol: "gobackward.10",
                    help: "Back 10 seconds",
                    size: 18
                ) {
                    coordinator.skip(by: -10)
                }

                Button(action: { coordinator.togglePlayPause() }) {
                    Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!coordinator.isReady)
                .keyboardShortcut(.space, modifiers: [])

                transportButton(
                    symbol: "goforward.10",
                    help: "Forward 10 seconds",
                    size: 18
                ) {
                    coordinator.skip(by: 10)
                }
            }
            .padding(.top, 4)
        }
    }

    private var displayedTime: Double {
        scrubValue ?? coordinator.currentTime
    }

    private var scrubBinding: Binding<Double> {
        Binding(
            get: { scrubValue ?? coordinator.currentTime },
            set: { newValue in scrubValue = newValue }
        )
    }

    private func handleEditing(_ editing: Bool) {
        if !editing, let target = scrubValue {
            coordinator.seek(to: target)
            scrubValue = nil
        }
    }

    private func transportButton(
        symbol: String,
        help: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(!coordinator.isReady)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

@MainActor
final class AudioPlayerCoordinator: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var artwork: NSImage?

    private var player: AVPlayer?
    private var loadedURL: URL?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func load(url: URL) async {
        // If we're already pointing at the same file (tab reopened, or
        // the view re-applied), don't tear everything down.
        if loadedURL == url, player != nil { return }
        teardown()
        loadedURL = url

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        self.player = player

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.isReady = (item.status == .readyToPlay)
            }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = (player.rate > 0)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.player?.seek(to: .zero)
                self?.isPlaying = false
            }
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            guard let self, seconds.isFinite else { return }
            Task { @MainActor in self.currentTime = seconds }
        }

        // Pull duration + common metadata up front so the UI can
        // populate its labels without waiting for playback to start.
        let asset = AVURLAsset(url: url)
        if let cmDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cmDuration)
            if seconds.isFinite, seconds > 0 {
                self.duration = seconds
            }
        }
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue) {
                        self.title = value
                    }
                case .commonKeyArtist:
                    if let value = try? await item.load(.stringValue) {
                        self.artist = value
                    }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        self.artwork = image
                    }
                default:
                    break
                }
            }
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
    }

    func pause() {
        player?.pause()
    }

    func seek(to seconds: Double) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    func skip(by seconds: Double) {
        seek(to: max(0, min(duration, currentTime + seconds)))
    }

    private func teardown() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        statusObservation = nil
        rateObservation = nil
        player?.pause()
        player = nil
        isPlaying = false
        isReady = false
        currentTime = 0
        duration = 0
        title = nil
        artist = nil
        artwork = nil
    }
}
