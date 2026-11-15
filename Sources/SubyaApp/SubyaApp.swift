import CaptionKit
import AppKit
import SwiftUI

@main
struct SubyaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Subya", id: "main") {
            ContentView(model: model)
                .task { await handleLaunchArguments() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Install Command-Line Tool…") { CommandLineTool.install() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Video…") { model.chooseFile() }.keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In Timeline") { model.zoomTimeline(by: 1.5) }
                    .keyboardShortcut("=")
                    .disabled(model.player == nil)
                Button("Zoom Out Timeline") { model.zoomTimeline(by: 1 / 1.5) }
                    .keyboardShortcut("-")
                    .disabled(model.player == nil)
                Button("Fit Timeline") { model.setTimelineZoom(1) }
                    .keyboardShortcut("0")
                    .disabled(model.player == nil)
                Divider()
            }
            CommandMenu("Captions") {
                Button("Add Line at Playhead") { model.addCaption() }
                    .keyboardShortcut("n")
                    .disabled(model.player == nil || model.isBusy)
                Button("Re-split Captions…") { model.resplit() }
                    .disabled(model.words.isEmpty || model.isBusy)
                Divider()
                Button("Trim Video…") { model.startTrimming() }
                    .keyboardShortcut("t")
                    .disabled(model.player == nil || model.isTrimming || (model.isBusy && !model.isTranscribing))
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }

    /// Developer options:
    ///   --open <video>       load a video at launch (the same path as a drop)
    ///   --add-line <seconds> after loading, add a caption line at that time (like + Line)
    ///   --zoom <n>           after loading, zoom the timeline in n times
    ///   --crop <shape>       after loading, crop to the centred 1:1, 9:16, 4:5 or 16:9
    ///   --crop-edit          after loading, open the crop editor
    ///   --trim <from-to>     after loading, trim (as in `subya burn --trim`, e.g. 4-11)
    ///   --trim-edit          leave the trim editor open (alone, or after --trim)
    ///   --hover-controls     show the caption position track as if the pointer were over
    ///                        the video
    ///   --simulate-drag <s>  after loading, move the second caption back and forth 60
    ///                        times a second for s seconds through the timeline's drag
    ///                        path, then print how far the run loop fell behind (for
    ///                        profiling with `sample`)
    ///   --settings <tab>     open Settings on "general" or "styles"; with --snapshot, the
    ///                        image is of the Settings window (works without --open)
    ///   --snapshot <png>     after loading, save an image of the window (for checking layout
    ///                        without screen-recording permission; video frames come out black)
    @MainActor
    private func handleLaunchArguments() async {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.count > i + 1 else { return nil }
            return args[i + 1]
        }
        if args.contains("--settings") {
            // ContentView opens Settings (openSettings is only available in views).
            try? await Task.sleep(for: .seconds(2.5))
            if let path = value(after: "--snapshot"),
               let window = NSApp.windows.first(where: { $0.isVisible && $0.title != "Subya" }) {
                Self.snapshot(window, to: path)
            }
            return
        }
        guard let path = value(after: "--open") else { return }
        model.open(URL(fileURLWithPath: path))

        // Trim as soon as the video is in, as someone would while it transcribes (which
        // restarts transcription for just the trimmed part).
        let started = Date()
        try? await Task.sleep(for: .milliseconds(300))
        while model.player == nil || model.duration == 0 { try? await Task.sleep(for: .milliseconds(50)) }
        if let text = value(after: "--trim"), let trim = Trim(parsing: text, duration: model.duration) {
            model.startTrimming()
            model.setTrimEdge(.start, to: trim.start)
            model.setTrimEdge(.end, to: trim.end)
            if !args.contains("--trim-edit") { model.finishTrimming() }
        } else if args.contains("--trim-edit") {
            model.startTrimming()
        }

        // Wait for loading and transcription to finish.
        while model.isBusy { try? await Task.sleep(for: .milliseconds(100)) }
        print(String(format: "loaded in %.1f s: %d captions, %.2f–%.2f s", Date().timeIntervalSince(started),
                     model.captions.count, model.captions.first?.start ?? 0, model.captions.last?.end ?? 0))
        fflush(stdout)
        if let aspect = value(after: "--crop").flatMap(Crop.Aspect.init(name:)) {
            model.startCropping()
            model.setCropAspect(aspect)
            if !args.contains("--crop-edit") { model.finishCropping() }
        } else if args.contains("--crop-edit") {
            model.startCropping()
        }
        if let zoom = value(after: "--zoom").flatMap(Double.init) {
            model.setTimelineZoom(zoom)
        }
        if let seconds = value(after: "--add-line").flatMap(Double.init) {
            model.seek(to: seconds)
            try? await Task.sleep(for: .milliseconds(300))
            model.addCaption()
        } else if !model.isTrimming {
            model.seek(to: model.isTrimmed ? model.trim.start + 0.5 : 4.5)
        }
        if let seconds = value(after: "--simulate-drag").flatMap(Double.init) {
            await simulateDrag(seconds: seconds)
        }
        if let path = value(after: "--snapshot") {
            try? await Task.sleep(for: .seconds(1))
            if let window = NSApp.windows.first(where: { $0.isVisible }) {
                Self.snapshot(window, to: path)
            }
        }
    }

    @MainActor
    private func simulateDrag(seconds: Double) async {
        guard model.captions.count > 1 else { return }
        let id = model.captions[1].id
        let base = model.captions[1].start
        model.selectedCaptionID = id
        let ticks = Int(seconds * 60)
        let start = Date()
        var worst = 0.0
        var last = Date()
        for i in 0..<ticks {
            model.moveCaption(id, toStart: base + 0.6 * sin(Double(i) / 12))
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date()
            worst = max(worst, now.timeIntervalSince(last))
            last = now
        }
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "simulate-drag: %d ticks in %.2f s (ideal %.2f s), worst gap %.0f ms",
                     ticks, elapsed, Double(ticks) * 0.016, worst * 1000))
        fflush(stdout)
    }

    @MainActor
    private static func snapshot(_ window: NSWindow, to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
