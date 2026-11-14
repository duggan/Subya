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
    let styles = StyleStore()

    /// The style picked in the main window, plus its quick adjustments (position, size
    /// and caps), remembered between launches.
    var choice: StyleChoice = AppModel.savedChoice() {
        didSet {
            guard choice != oldValue else { return }
            refreshOverlay()
            if let data = try? JSONEncoder().encode(choice) { UserDefaults.standard.set(data, forKey: Self.choiceKey) }
        }
    }

    /// The style captions are drawn in: the chosen style with the quick adjustments applied.
    var style: CaptionStyle {
        var style = styles.style(id: choice.styleID) ?? .default
        style.position = choice.position
        style.scale = choice.scale
        style.allCaps = choice.allCaps
        style.display = choice.display
        return style
    }

    var status = ""
    var isBusy = false
    var errorMessage: String?
    var isPlaying = false
    var currentTime: Double = 0
    /// How far the timeline is zoomed in: 1 fits the whole video in view.
    private(set) var timelineZoom: Double = 1
    /// Up to about 400 points per second on a 600-point timeline, so short words have room.
    var maxTimelineZoom: Double { max(4, duration * 400 / 600) }

    func setTimelineZoom(_ zoom: Double) {
        timelineZoom = min(max(zoom, 1), maxTimelineZoom)
    }

    func zoomTimeline(by factor: Double) { setTimelineZoom(timelineZoom * factor) }

    /// Set after adding a line, so the view can focus and scroll to its text field.
    var focusRequest: Caption.ID?
    private(set) var duration: Double = 0

    @ObservationIgnored private var asset: AVURLAsset?
    @ObservationIgnored private var composition: AVVideoComposition?
    @ObservationIgnored private let overlay = CaptionOverlay()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    /// The transcript's words, kept so captions can be re-split with new settings.
    private(set) var words: [Word] = []

    private static let choiceKey = "styleChoice"

    struct StyleChoice: Codable, Equatable {
        var styleID: CaptionStyle.ID
        var position: CaptionStyle.Position
        var scale: Double
        var allCaps: Bool
        var display: CaptionStyle.Display

        init(_ style: CaptionStyle) {
            styleID = style.id
            position = style.position
            scale = style.scale
            allCaps = style.allCaps
            display = style.display
        }

        // Saved choices from before `display` existed still load.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            styleID = try c.decode(CaptionStyle.ID.self, forKey: .styleID)
            position = try c.decode(CaptionStyle.Position.self, forKey: .position)
            scale = try c.decode(Double.self, forKey: .scale)
            allCaps = try c.decode(Bool.self, forKey: .allCaps)
            display = try c.decodeIfPresent(CaptionStyle.Display.self, forKey: .display) ?? .line
        }
    }

    init() {
        Pref.register()
        styles.onChange = { [weak self] old in self?.stylesChanged(from: old) }
        if styles.style(id: choice.styleID) == nil { choice = StyleChoice(.default) }
    }

    private static func savedChoice() -> StyleChoice {
        guard let data = UserDefaults.standard.data(forKey: choiceKey),
              let choice = try? JSONDecoder().decode(StyleChoice.self, from: data) else { return StyleChoice(.default) }
        return choice
    }

    /// Picking a style resets the quick adjustments to that style's own.
    func selectStyle(_ id: CaptionStyle.ID) {
        guard let style = styles.style(id: id) else { return }
        choice = StyleChoice(style)
    }

    /// When the chosen style is edited in Settings, show the edit straight away (its
    /// position, size and caps replace the quick adjustments). If it was deleted, fall
    /// back to Classic.
    private func stylesChanged(from old: [CaptionStyle]) {
        guard let current = styles.style(id: choice.styleID) else {
            choice = StyleChoice(.default)
            return
        }
        let previous = (CaptionStyle.builtIns + old).first { $0.id == choice.styleID }
        if previous != current {
            choice = StyleChoice(current)
            refreshOverlay()  // colours or font may have changed even if the choice didn't
        }
    }

    func open(_ url: URL) {
        Task { await load(url) }
    }

    func load(_ url: URL) async {
        isBusy = true
        errorMessage = nil
        captions = []
        words = []
        timelineZoom = 1
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

            // Silent clips are common for memes: load them with no captions, ready for
            // lines added by hand, rather than failing.
            var hasAudio = true
            do {
                words = try await Transcriber.words(for: url, locale: Pref.locale) { msg in
                    Task { @MainActor in self.status = msg }
                }
            } catch CaptionError.noAudio {
                hasAudio = false
            }
            captions = Pref.captions(from: words, videoEnd: duration)
            status = if !captions.isEmpty {
                "\(captions.count) captions. Edit any text, then Export."
            } else {
                "\(hasAudio ? "No speech found" : "No audio"). Add lines with + Line (⌘N)."
            }
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

    /// Adds an empty caption at the playhead, for a line nobody says out loud.
    func addCaption() {
        guard player != nil, !isBusy else { return }
        player?.pause()
        focusRequest = captions.insertCaption(at: currentTime, videoEnd: duration)
        status = "\(captions.count) captions. Type the new line, then Export."
    }

    // MARK: Timeline edits. The preview follows the edge being dragged.

    func moveCaption(_ id: Caption.ID, toStart start: Double) {
        captions.moveCaption(id, toStart: start, videoEnd: duration)
        if let cap = captions.first(where: { $0.id == id }) { seek(to: cap.start) }
    }

    func setEdge(_ edge: CaptionEdge, of id: Caption.ID, to time: Double) {
        captions.setEdge(edge, of: id, to: time, videoEnd: duration)
        guard let cap = captions.first(where: { $0.id == id }) else { return }
        // For the end, show the caption's last frame rather than the frame after it.
        seek(to: edge == .start ? cap.start : max(cap.start, cap.end - 0.04))
    }

    /// Moves when a word appears (one-word display); the preview shows that word.
    func setWordStart(_ index: Int, of id: Caption.ID, to time: Double) {
        captions.setWordStart(index, of: id, to: time)
        guard let cap = captions.first(where: { $0.id == id }), cap.timedWords.indices.contains(index) else { return }
        seek(to: cap.timedWords[index].start)
    }

    /// Jumps to a caption (or a time within it) and focuses its text in the list.
    func select(_ id: Caption.ID, at time: Double? = nil) {
        guard let cap = captions.first(where: { $0.id == id }) else { return }
        player?.pause()
        seek(to: time ?? cap.start)
        focusRequest = id
    }

    /// Re-splits the transcript into captions with the current settings, replacing edits.
    func resplit() {
        guard !words.isEmpty, !isBusy else { return }
        let alert = NSAlert()
        alert.messageText = "Re-split captions?"
        alert.informativeText = "This rebuilds the captions from the transcript with your current splitting settings. Your edits and added lines will be replaced."
        alert.addButton(withTitle: "Re-split")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        captions = Pref.captions(from: words, videoEnd: duration)
        status = "\(captions.count) captions. Edit any text, then Export."
    }

    func delete(_ caption: Caption) {
        captions.removeAll { $0.id == caption.id }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    /// Exports to where the settings say: next to the original, a chosen folder, or
    /// wherever the save panel says. Never overwrites without asking.
    func exportVideo() {
        guard let videoURL else { return }
        let defaults = Pref.defaults
        let suffix = defaults.string(forKey: Pref.exportSuffix) ?? "-captioned"
        let location = ExportLocation(rawValue: defaults.string(forKey: Pref.exportLocation) ?? "") ?? .beside
        let folderPath = defaults.string(forKey: Pref.exportFolder) ?? ""
        var isDirectory: ObjCBool = false
        let folder: URL? = switch location {
        case .beside: videoURL.deletingLastPathComponent()
        case .folder where FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory)
            && isDirectory.boolValue: URL(fileURLWithPath: folderPath)
        default: nil
        }
        if let folder {
            Task { await export(to: ExportNaming.url(for: videoURL, in: folder, suffix: suffix)) }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = videoURL.deletingPathExtension().lastPathComponent + suffix + ".mp4"
        panel.directoryURL = videoURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let out = panel.url else { return }
        Task { await export(to: out) }
    }

    func export(to out: URL) async {
        guard let asset else { return }
        isBusy = true
        status = "Exporting…"
        defer { isBusy = false }
        player?.pause()
        let quality = ExportQuality(rawValue: Pref.defaults.string(forKey: Pref.exportQuality) ?? "") ?? .high
        do {
            // Export draws with its own overlay, at the export's frame size.
            let exportOverlay = CaptionOverlay()
            let composition = try await CaptionRenderer.composition(for: asset, overlay: exportOverlay,
                                                                    maxLongSide: quality.maxLongSide)
            exportOverlay.update(captions, size: composition.renderSize, style: style)
            try await CaptionRenderer.export(asset: asset, composition: composition, to: out)
            let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize).map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? ""
            status = "Saved \(out.lastPathComponent) (\(size))."
            if Pref.defaults.bool(forKey: Pref.revealAfterExport) {
                NSWorkspace.shared.activateFileViewerSelecting([out])
            }
        } catch {
            errorMessage = error.localizedDescription
            status = ""
        }
    }
}
