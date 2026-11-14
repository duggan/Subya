import AVKit
import SwiftUI

/// AVKit's native player view. Used instead of SwiftUI's VideoPlayer, which crashed in
/// this SwiftPM-built app. Playback controls are ContentView's transport bar.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none  // our own transport bar sits below
        view.player = player
        return view
    }

    /// Take whatever space is offered, so siblings (the transport bar) keep their height.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVPlayerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 480, height: proposal.height ?? 270)
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
