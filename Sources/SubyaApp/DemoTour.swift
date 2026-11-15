import AppKit
import CaptionKit

/// `--demo <video> [--demo-out <mp4>]` (developer option): drives the app through a short
/// scripted tour for recording the website's demo video. It sizes and centres the window,
/// prints `DEMO-FRAME x,y,w,h` (screen points, top-left origin, for `screencapture -R`),
/// waits a moment for the recording to start, then opens the video, plays it, edits a
/// line, switches styles, moves the captions, crops and exports, printing `DEMO <t> <step>`
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
        func play(from time: Double = 0, for seconds: Double) async {
            model.seek(to: time)
            await wait(0.3)
            model.player?.play()
            await wait(seconds)
            model.player?.pause()
        }

        if let classic = style("Classic") { model.selectStyle(classic) }
        await wait(3)  // the recording starts; the empty window shows

        mark("open")
        model.open(video)
        await wait(0.5)
        while model.isBusy || model.player == nil { await wait(0.1) }
        mark("transcribed")
        await wait(1.2)

        mark("play")
        await play(for: model.duration + 0.2)
        await wait(0.6)

        // Type an extra word onto the last line, as if fixing it by hand.
        if let last = model.captions.last {
            mark("edit")
            model.select(last.id, at: max(last.start, last.end - 0.6))
            await wait(0.8)
            for character in " Oops." {
                if let i = model.captions.firstIndex(where: { $0.id == last.id }) {
                    model.captions[i].text.append(character)
                }
                await wait(0.12)
            }
            await wait(1)
        }

        mark("meme")
        if let meme = style("Meme") { model.selectStyle(meme) }
        await wait(0.6)
        await play(for: min(3.5, model.duration))
        await wait(0.4)

        mark("oneword")
        if let oneWord = style("One Word") { model.selectStyle(oneWord) }
        await wait(0.6)
        await play(for: model.duration + 0.2)

        // Slide the captions from the middle down towards the bottom, as a drag would.
        mark("move")
        model.seek(to: model.captions.first.map { ($0.start + $0.end) / 2 } ?? 1)
        await wait(0.6)
        let from = model.choice.vertical
        for step in 0...36 {
            let t = Double(step) / 36
            let eased = t * t * (3 - 2 * t)
            model.choice.vertical = CaptionStyle.snapped(from + (0.82 - from) * eased)
            await wait(1.0 / 30)
        }
        await wait(1)

        mark("crop")
        model.startCropping()
        await wait(1)
        model.setCropAspect(.portrait)
        await wait(1.4)
        model.finishCropping()
        await wait(0.8)
        await play(for: min(4, model.duration))

        mark("export")
        await model.export(to: output)
        await wait(2.5)
        mark("end")
        print("DEMO-DONE")
        fflush(stdout)
    }
}
