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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video…") { model.chooseFile() }.keyboardShortcut("o")
            }
        }
    }

    /// Developer options:
    ///   --open <video>       load a video at launch (the same path as a drop)
    ///   --snapshot <png>     after loading, save an image of the window (for checking layout
    ///                        without screen-recording permission; video frames come out black)
    @MainActor
    private func handleLaunchArguments() async {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.count > i + 1 else { return nil }
            return args[i + 1]
        }
        if let path = value(after: "--open") {
            model.open(URL(fileURLWithPath: path))
        }
        if let path = value(after: "--snapshot") {
            try? await Task.sleep(for: .seconds(8))
            model.seek(to: 4.5)
            try? await Task.sleep(for: .seconds(1))
            if let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
