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

        // Wait for loading and transcription to finish.
        try? await Task.sleep(for: .milliseconds(300))
        for _ in 0..<600 where model.isBusy || model.player == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let zoom = value(after: "--zoom").flatMap(Double.init) {
            model.setTimelineZoom(zoom)
        }
        if let seconds = value(after: "--add-line").flatMap(Double.init) {
            model.seek(to: seconds)
            try? await Task.sleep(for: .milliseconds(300))
            model.addCaption()
        } else {
            model.seek(to: 4.5)
        }
        if let path = value(after: "--snapshot") {
            try? await Task.sleep(for: .seconds(1))
            if let window = NSApp.windows.first(where: { $0.isVisible }) {
                Self.snapshot(window, to: path)
            }
        }
    }

    @MainActor
    private static func snapshot(_ window: NSWindow, to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
