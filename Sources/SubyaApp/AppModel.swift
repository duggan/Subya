import CaptionKit
import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    var videoURL: URL?
    var player: AVPlayer?
    var captions: [Caption] = [] { didSet { if captions != oldValue { refreshOverlay() } } }
    /// The caption look, remembered between launches.
    var style: CaptionStyle = AppModel.savedStyle() {
        didSet {
            guard style != oldValue else { return }
            refreshOverlay()
            if let data = try? JSONEncoder().encode(style) { UserDefaults.standard.set(data, forKey: Self.styleKey) }
        }
    }
    var status = ""
    var isBusy = false
    var errorMessage: String?
    var isPlaying = false
    var currentTime: Double = 0
    private(set) var duration: Double = 0

    @ObservationIgnored private var asset: AVURLAsset?
    @ObservationIgnored private var composition: AVVideoComposition?
    @ObservationIgnored private let overlay = CaptionOverlay()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    private static let styleKey = "captionStyle"

    private static func savedStyle() -> CaptionStyle {
        guard let data = UserDefaults.standard.data(forKey: styleKey),
              let style = try? JSONDecoder().decode(CaptionStyle.self, from: data) else { return .default }
        return style
    }

    /// Picking a font also picks its usual case (Meme is all caps); the toggle can override it.
    func setFont(_ font: CaptionStyle.Font) {
        style.font = font
        style.allCaps = font.prefersAllCaps
    }

    func open(_ url: URL) {
        Task { await load(url) }
    }

    func load(_ url: URL) async {
        isBusy = true
        errorMessage = nil
        captions = []
        videoURL = url
        defer { isBusy = false }
        do {
            let asset = AVURLAsset(url: url)
            self.asset = asset
            duration = try await asset.load(.duration).seconds
            let comp = try await CaptionRenderer.composition(for: asset, overlay: overlay)
            composition = comp
            let item = AVPlayerItem(asset: asset)
            item.videoComposition = comp
            attach(AVPlayer(playerItem: item))

            let words = try await Transcriber.words(for: url) { msg in
                Task { @MainActor in self.status = msg }
            }
            captions = Chunker.captions(from: words, videoEnd: duration)
            status = captions.isEmpty ? "No speech found." : "\(captions.count) captions. Edit any text, then Export."
        } catch {
            errorMessage = error.localizedDescription
            status = ""
        }
    }

    func refreshOverlay() {
        guard let comp = composition else { return }
        overlay.update(captions, size: comp.renderSize, style: style)
        // Redraw the paused frame so edits show immediately. Reassigning the composition makes
        // the player re-render the current frame; seeking to the current time does not (it's
        // treated as a no-op, so the preview lagged until the next seek or play).
        if let item = player?.currentItem, player?.rate == 0 {
            item.videoComposition = comp
        }
    }

    private func attach(_ newPlayer: AVPlayer) {
        if let player, let timeObserver { player.removeTimeObserver(timeObserver) }
        statusObservation = nil
        player?.pause()
        player = newPlayer
        currentTime = 0
        isPlaying = false
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.currentTime = time.seconds }
        }
        statusObservation = newPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= duration - 0.05 { seek(to: 0) }
            player.play()
        }
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player?.seek(to: CMTime(seconds: seconds + 0.01, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func play(_ caption: Caption) {
        seek(to: caption.start)
        player?.play()
    }

    func delete(_ caption: Caption) {
        captions.removeAll { $0.id == caption.id }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func exportVideo() {
        guard let videoURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = videoURL.deletingPathExtension().lastPathComponent + "-captioned.mp4"
        panel.directoryURL = videoURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let out = panel.url else { return }
        Task { await export(to: out) }
    }

    func export(to out: URL) async {
        guard let asset, let composition else { return }
        isBusy = true
        status = "Exporting…"
        defer { isBusy = false }
        player?.pause()
        overlay.update(captions, size: composition.renderSize, style: style)
        do {
            try await CaptionRenderer.export(asset: asset, composition: composition, to: out)
            let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize).map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? ""
            status = "Saved \(out.lastPathComponent) (\(size))."
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch {
            errorMessage = error.localizedDescription
            status = ""
        }
    }
}
