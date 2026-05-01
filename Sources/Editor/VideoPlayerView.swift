import SwiftUI
import AVKit

/// Plays a local video file with the standard AVKit transport controls.
/// We construct one `AVPlayer` per URL and tear it down when the URL
/// changes so a tab switch doesn't keep the previous file decoding in
/// the background.
struct VideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onDisappear { player.pause() }
            .onChange(of: url) { _, newURL in
                player.pause()
                player = AVPlayer(url: newURL)
            }
    }
}
