// Records one window with ScreenCaptureKit, even when it's covered by other windows.
// swiftc -O wincap.swift -o wincap
// wincap <app name> <out.mov> <stop-file>   (records until <stop-file> exists, max 180 s)
import AVFoundation
import AppKit
import Foundation
import ScreenCaptureKit

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: wincap <app> <out.mov> <stop-file>"); exit(2) }
let appName = args[1], out = URL(fileURLWithPath: args[2]), stopFile = args[3]

final class Delegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    func recordingOutputDidStartRecording(_ r: SCRecordingOutput) { print("WINCAP-STARTED"); fflush(stdout) }
    func recordingOutput(_ r: SCRecordingOutput, didFailWithError e: Error) { print("WINCAP-ERROR \(e)"); fflush(stdout) }
    func stream(_ s: SCStream, didStopWithError e: Error) { print("WINCAP-STOPPED \(e)"); fflush(stdout) }
}

_ = NSApplication.shared  // connects to the window server, which ScreenCaptureKit needs
let delegate = Delegate()
Task {
    do {
        var window: SCWindow?
        for _ in 0..<100 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            window = content.windows.first {
                $0.owningApplication?.applicationName == appName && $0.title == appName && $0.frame.width > 400
            }
            if window != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let window else { print("WINCAP-ERROR no window"); exit(1) }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: config, delegate: delegate)
        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = out
        recConfig.outputFileType = .mov
        recConfig.videoCodecType = .h264
        let recording = SCRecordingOutput(configuration: recConfig, delegate: delegate)
        try stream.addRecordingOutput(recording)
        try await stream.startCapture()
        print("WINCAP-FRAME \(Int(window.frame.width))x\(Int(window.frame.height)) @\(scale)x")
        fflush(stdout)
        let deadline = Date().addingTimeInterval(180)
        while !FileManager.default.fileExists(atPath: stopFile) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await stream.stopCapture()
        try await Task.sleep(for: .milliseconds(500))
        print("WINCAP-DONE")
        exit(0)
    } catch {
        print("WINCAP-ERROR \(error)")
        exit(1)
    }
}
RunLoop.main.run()
