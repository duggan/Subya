import AppKit
import CaptionKit

/// `--demo <video> [--demo-out <mp4>]` (developer option): drives the app through a short
/// scripted tour for recording the website's demo video. It sizes and centres the window,
/// prints `DEMO-FRAME x,y,w,h` (screen points, top-left origin, for `screencapture -R`),
/// waits a moment for the recording to start, then opens the video, plays the first line,
/// fixes a misheard word, switches styles, moves the captions, crops and exports, printing
/// `DEMO <t> <step>` (and `DEMO <t> play <from> <for>` when playback starts)
/// marks (seconds since the frame line) for editing the recording, and `DEMO-DONE` at the end.
/// With `--demo-background` it leaves the window behind whatever's in front and doesn't
/// touch the pointer, so the Mac stays usable while a window recorder captures it.
@MainActor
enum DemoTour {
    static func run(model: AppModel, video: URL, output: URL, background: Bool = false) async {
        // Keep timers on time while the app is in the background (no App Nap).
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical], reason: "Recording the demo tour")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        // Launched in the background (open -g), the window may not be on screen yet.
        var found: NSWindow?
        for _ in 0..<50 {
            found = NSApp.windows.first { $0.isVisible } ?? NSApp.windows.first { $0.canBecomeMain }
            if found != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let window = found, let screen = window.screen ?? NSScreen.main else {
            print("DEMO-ERROR no window")
            fflush(stdout)
            return
        }
        let size = CGSize(width: 1280, height: 800)
        let visible = screen.visibleFrame
        window.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                               width: size.width, height: size.height), display: true)
        let frame = window.frame
        if background {
            window.orderBack(nil)
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            // Park the pointer just outside the window, so no hover state or tooltip shows.
            CGWarpMouseCursorPosition(CGPoint(x: min(frame.maxX + 40, screen.frame.maxX - 40),
                                              y: screen.frame.maxY - frame.midY))
        }
        print(String(format: "DEMO-FRAME %.0f,%.0f,%.0f,%.0f", frame.minX, screen.frame.maxY - frame.maxY,
                     frame.width, frame.height))
        fflush(stdout)
        let start = Date()
        func mark(_ step: String) {
            print(String(format: "DEMO %.2f %@", Date().timeIntervalSince(start), step))
            fflush(stdout)
        }
        func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        func style(_ name: String) -> CaptionStyle.ID? { CaptionStyle.builtIns.first { $0.name == name }?.id }
        /// Plays from `time` for `seconds`, marking `play <from> <for>` (clip seconds) when
        /// playback actually starts, so the edit can lay the clip's sound under it.
        func play(from time: Double = 0, for seconds: Double) async {
            model.seek(to: time)
            await wait(0.3)
            model.player?.play()
            while model.player?.timeControlStatus != .playing { await wait(0.01) }
            mark(String(format: "play %.3f %.3f", time, seconds))
            await wait(seconds)
            model.player?.pause()
        }
        func captionStart(_ i: Int) -> Double {
            model.captions.indices.contains(i) ? max(model.captions[i].start - 0.15, 0) : 0
        }

        if let classic = style("Classic") { model.selectStyle(classic) }
        await wait(2)  // the recording starts; the empty window shows

        mark("open")
        model.open(video)
        await wait(0.3)
        while model.isBusy || model.player == nil { await wait(0.05) }
        mark("transcribed")
        await wait(0.5)

        // The first line, in the default style.
        mark("classic")
        await play(for: min(captionStart(2), model.duration))

        // Fix a word the transcriber got wrong, if it did ("Capisce" tends to come out as
        // "Capish"), then show the fixed line.
        if let i = model.captions.lastIndex(where: { $0.text.lowercased().hasPrefix("cap") || $0.text.lowercased().hasPrefix("gab") }),
           model.captions[i].text != "Capisce?" {
            let id = model.captions[i].id
            mark("edit")
            model.select(id, at: model.captions[i].start + 0.1)
            await wait(0.5)
            while let j = model.captions.firstIndex(where: { $0.id == id }), !model.captions[j].text.isEmpty {
                model.captions[j].text.removeLast()
                await wait(0.05)
            }
            for character in "Capisce?" {
                if let j = model.captions.firstIndex(where: { $0.id == id }) { model.captions[j].text.append(character) }
                await wait(0.08)
            }
            await wait(0.4)
            if let j = model.captions.firstIndex(where: { $0.id == id }) {
                await play(from: max(model.captions[j].start - 0.1, 0), for: model.captions[j].end - model.captions[j].start + 0.2)
            }
        }

        mark("meme")
        if let meme = style("Meme") { model.selectStyle(meme) }
        await wait(0.3)
        await play(from: captionStart(model.captions.count - 2), for: 2.8)

        mark("oneword")
        if let oneWord = style("One Word") { model.selectStyle(oneWord) }
        await wait(0.3)
        await play(for: min(captionStart(2), model.duration))

        // Slide the captions from the middle down towards the bottom, as a drag would.
        mark("move")
        model.seek(to: model.captions.first.map { ($0.start + $0.end) / 2 } ?? 1)
        await wait(0.3)
        let from = model.choice.vertical
        for step in 0...30 {
            let t = Double(step) / 30
            let eased = t * t * (3 - 2 * t)
            model.choice.vertical = CaptionStyle.snapped(from + (0.82 - from) * eased)
            await wait(1.0 / 30)
        }
        await wait(0.5)

        mark("crop")
        model.startCropping()
        await wait(0.6)
        model.setCropAspect(.portrait)
        await wait(0.9)
        model.finishCropping()
        await wait(0.5)
        await play(from: captionStart(model.captions.count - 2), for: 2.6)

        mark("export")
        await model.export(to: output)
        await wait(1.5)
        mark("end")
        print("DEMO-DONE")
        fflush(stdout)
    }
}
