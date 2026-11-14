// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Subya",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "CaptionKit", targets: ["CaptionKit"]),
        .executable(name: "subya", targets: ["subya"]),
    ],
    targets: [
        // Transcription, caption grouping, SRT files, and burning captions into video.
        .target(name: "CaptionKit"),

        // The app. `make bundle` wraps this binary in Subya.app.
        // AVKit is linked explicitly: SwiftPM doesn't autolink it, and AVPlayerView needs it.
        .executableTarget(
            name: "SubyaApp",
            dependencies: ["CaptionKit"],
            linkerSettings: [.linkedFramework("AVKit")]
        ),

        // Developer CLI: transcribe and burn captions without the UI.
        .executableTarget(name: "subya", dependencies: ["CaptionKit"]),

        .testTarget(name: "CaptionKitTests", dependencies: ["CaptionKit"]),
    ],
    swiftLanguageModes: [.v5]
)
