# Subya

Subya is a macOS app that burns easy-to-read captions into a video, mostly for memes
and reaction clips sent over WhatsApp, Messages and the like. Drop a video in, it's
transcribed on the Mac, you fix any wrong words, and it exports a copy with the
captions drawn into the frames. The name is "sub ya" (subtitle you); keep the tone
playful rather than slick.

## Design rules

- **Everything stays on the Mac.** Transcription uses Apple's on-device
  `SpeechAnalyzer` / `SpeechTranscriber` (macOS 26). The first use of a language
  downloads its model through `AssetInventory`. No network calls of our own.
- **No permissions.** `SpeechTranscriber` doesn't need speech-recognition
  authorization (unlike `SFSpeechRecognizer`, which crashes a process whose
  responsible app has no `NSSpeechRecognitionUsageDescription`). So the app asks for
  nothing, and the CLI works from Terminal. Don't add an `SFSpeechRecognizer` call.
- **Captions are burned in**, not a subtitle track. Messaging apps drop or hide soft
  subtitles, and the point is that the text is always readable.
- **Caption style** (`CaptionRenderer.image`): Helvetica Neue Bold, white, with a black
  outline and a soft drop shadow, centred, about 7% of the height above the bottom.
  Font size is 9.6% of the frame's shorter side, times the text-size slider. Lines
  wrap at 90% of the width.
- **Grouping** (`Chunker`): a new caption starts after a pause over 0.6 s, after a
  word ending in `.,?!;:`, or when the line would pass 40 characters. Each caption
  stays up to 0.6 s after its last word, without overlapping the next.
- **The preview is the export.** The player and the exporter share one
  `AVVideoComposition` whose Core Image handler draws the current caption from a
  `CaptionOverlay`. Edits update the overlay; the paused frame is redrawn by seeking
  to the current time.
- The source video is never modified. Export writes `<name>-captioned.mp4` with
  `AVAssetExportPresetHighestQuality` (H.264, fast start). Messaging apps recompress
  anyway, so file size isn't worth trading quality for.

## Layout

- `Sources/CaptionKit/`: the library.
  - `Caption.swift`: `Word`, `Caption` and `Chunker`.
  - `Transcriber.swift`: extracts the audio to a temporary m4a and runs
    `SpeechTranscriber` with `audioTimeRange`. `words(from:)` turns each result's
    attributed runs into timed words; punctuation-only runs attach to the previous
    word.
  - `SRT.swift`: reads and writes SubRip files.
  - `CaptionRenderer.swift`: caption images, `CaptionOverlay` (lock-protected,
    read on the compositor's thread), the video composition, and export.
- `Sources/SubyaApp/`: the SwiftUI app, one window.
  - `AppModel.swift`: loading, transcription, playback state and export.
  - `ContentView.swift`: the drop zone, the preview with its transport bar, the
    editable caption list, and the bottom bar.
  - `PlayerView.swift`: wraps `AVPlayerView` with its own controls off. Don't switch
    to SwiftUI's `VideoPlayer`: it crashed this SwiftPM-built app at first display
    (`getSuperclassMetadata` in `_AVKit_SwiftUI`). AVKit is also linked explicitly in
    `Package.swift` for the same reason.
  - The bars are stacked in a `VStack`, not added with `safeAreaInset`, because
    `HSplitView` ignores safe-area insets and the bar would cover the transport row.
  - Developer launch options: `--open <video>` loads a file as if dropped, and
    `--snapshot <png>` saves an image of the window after loading. The snapshot
    shows the layout, not the video (frames come out black), and needs no
    screen-recording permission.
- `Sources/subya/`: a developer CLI. `subya transcribe <video> [--srt]` prints
  the captions; `subya burn <video> <out.mp4> [--captions file.srt] [--scale n]`
  exports. Transcribe to SRT, edit it, then burn with `--captions` to script fixes.
- `Tests/CaptionKitTests/`: unit tests for grouping, SRT, word splitting and the
  renderer (`swift test`). They don't need a speech model.
- `Makefile`: `make run`, `test`, `icons`, `dmg` and `release`. It builds a
  universal app with a Developer ID signature and hardened runtime, not sandboxed,
  with bundle ID `ie.duggan.Subya`. Notarization uses the keychain profile
  `subya` (see `make notary-setup`). DMGs need `create-dmg`.
- `.github/workflows/release.yml` runs `make release` on GitHub, signing with a
  temporary keychain built from the `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`,
  `NOTARY_APPLE_ID` and `NOTARY_PASSWORD` secrets. A `v1.2.3` tag makes a release,
  `v1.2.3-rc1` a pre-release, and a push to `test/**` a `test-<branch>-<sha>`
  pre-release. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
  `Resources/App-Info.plist` before tagging. Both workflows run on `macos-26`, since
  the code needs the macOS 26 SDK.
- `Resources/art/make_icons.py` draws the artwork as SVG: an original pink blob
  character giving smug side-eye on a comic sunburst, with "SUB YA" burned across the
  bottom in Impact, white with a black outline, the app's caption style. It's drawn
  like a sticker, all thick ink outlines. Keep it an original character, not an
  existing meme or mascot. `make icons` (Inkscape) renders `Subya.icns` and the DMG
  background into `Resources/`. Commit them.

## Testing

- `swift test` for the library.
- End to end without the UI: `swift run subya burn <video> /tmp/out.mp4`, then
  pull frames with `ffmpeg -ss 2 -i /tmp/out.mp4 -frames:v 1 /tmp/f.jpg`.
- The window: `make run`, or
  `open build/Subya.app --args --open <video> --snapshot /tmp/window.png`.
