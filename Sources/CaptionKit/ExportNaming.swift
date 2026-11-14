import CoreGraphics
import Foundation

/// File names and frame sizes for exports.
public enum ExportNaming {
    /// `<folder>/<video name><suffix>.mp4`, or with " 2", " 3" and so on added if that
    /// file exists. Never returns an existing file.
    public static func url(for video: URL, in folder: URL, suffix: String,
                           fileManager: FileManager = .default) -> URL {
        let base = video.deletingPathExtension().lastPathComponent + suffix
        var candidate = folder.appending(path: base + ".mp4")
        var n = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(base) \(n).mp4")
            n += 1
        }
        return candidate
    }

    /// The frame size for an export: unchanged, or scaled down so the longer side is at
    /// most `maxLongSide`. Both sides are even, as H.264 requires.
    public static func exportSize(for natural: CGSize, maxLongSide: CGFloat?) -> CGSize {
        func even(_ x: CGFloat) -> CGFloat { max(2, floor(x / 2) * 2) }
        let long = max(natural.width, natural.height)
        guard let maxLongSide, long > maxLongSide else { return natural }
        let scale = maxLongSide / long
        return CGSize(width: even(natural.width * scale), height: even(natural.height * scale))
    }
}
