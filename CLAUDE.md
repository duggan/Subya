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
- **Caption styles** (`CaptionStyle`, drawn by `CaptionRenderer.image`): a saveable
  style is a name, a font (any PostScript name, or `system-rounded` for SF Rounded),
  text colour, an outline (colour and width as a fraction of the font size, 0 for
  none, with round joins or Impact grows spikes), an optional soft shadow, an optional
  rounded box behind the text (colour with opacity), a position (top, middle or
  bottom, 7% margin), a size and all caps. Text is centred and wraps at 90% of the
  width. Font size is 9.6% of the frame's shorter side times `scale`. Eight built-ins
  (Classic, Meme, Rounded, Marker, Typewriter, Poster, Boxed, Highlight) have fixed
  UUIDs (`5B0BA000-…-00000000000N`) and per-face scales so they look the same size.
  Users duplicate one to make their own in Settings. An unknown font falls back to
  the heavy system font.
- **Style choice in the main window** (`AppModel.StyleChoice`, saved as `styleChoice`):
  the chosen style's id plus quick adjustments (position, size, caps). Picking a style
  resets them to the style's own. Editing the chosen style in Settings shows at once
  (its values replace the adjustments); deleting it falls back to Classic.
- **Grouping** (`Chunker`): a new caption starts after a pause, after a word ending in
  `.,?!;:`, or when the line would pass the longest line. Each caption stays up a
  little after its last word, without overlapping the next. The defaults are 0.6 s,
  40 characters and 0.6 s; Settings › General changes them for the next video, and
  Captions › Re-split Captions applies them to the open one (from the kept words,
  replacing edits, after asking).
- **The preview is the export.** The player and the exporter share one
  `AVVideoComposition` whose Core Image handler draws the current caption from a
  `CaptionOverlay`, which renders each caption image on first use and caches it by
  text, frame size and style. Edits update the overlay; the paused frame is redrawn
  by reassigning the item's `videoComposition`. Seeking to the current time does
  not redraw (AVPlayer treats it as a no-op), which made the preview lag behind
  style changes.
- The source video is never modified. Export uses `AVAssetExportPresetHighestQuality`
  (H.264, fast start) with its own `CaptionOverlay` at the export's frame size. Where
  it goes is a setting: next to the original (default), a chosen folder, or ask.
  `ExportNaming.url` adds the suffix (default `-captioned`) and " 2", " 3" so nothing
  is overwritten. "Smaller for messaging" scales frames so the long side is 1280
  (`ExportNaming.exportSize`, even sides for H.264), done in the Core Image handler.
  Changing the render size needs the deprecated `AVMutableVideoComposition` (the macOS
  26 `Configuration` API can't hold a CI filter handler); it's called through a
  protocol so the build stays warning-free.
- **Preferences** (`Pref` in `Preferences.swift`): UserDefaults keys with registered
  defaults, read where they're used: `transcriptionLanguage` ("" = system),
  `maxLineLength`, `splitPause`, `linger`, `exportLocation`, `exportFolder`,
  `exportSuffix`, `exportQuality`, `revealAfterExport`. Custom styles are JSON under
  `customStyles` (`StyleLibrary`), in the app's domain `ie.duggan.Subya`, which the
  CLI reads too.

## Layout

- `Sources/CaptionKit/`: the library.
  - `Caption.swift`: `Word`, `Caption`, `Chunker`, and `insertCaption(at:videoEnd:)`
    for lines added by hand: the caption showing at that time ends there, and the new
    one runs 2 s or until the next caption (at least 0.2 s), kept sorted.
    `moveCaption` and `setEdge` are the timeline's drag rules: a caption keeps clear of
    its neighbours and the video's ends, and stays at least 0.2 s long.
  - `Transcriber.swift`: extracts the audio to a temporary m4a and runs
    `SpeechTranscriber` with `audioTimeRange`. `words(from:)` turns each result's
    attributed runs into timed words; punctuation-only runs attach to the previous
    word.
  - `SRT.swift`: reads and writes SubRip files.
  - `CaptionStyle.swift`: `CaptionStyle`, `RGBA` and the built-in styles.
  - `StyleLibrary.swift`: loading and saving custom styles, lookup by name.
  - `ExportNaming.swift`: export file names and the scaled-down export size.
  - `CaptionRenderer.swift`: caption images, `CaptionOverlay` (lock-protected,
    read and rendered on the compositor's thread), the video composition, and export.
- `Sources/SubyaApp/`: the SwiftUI app: the main window and Settings.
  - `AppModel.swift`: loading, transcription, playback state, the style choice,
    adding lines at the playhead, re-splitting, and export. A video with no audio track loads with
    no captions (memes are often silent) instead of failing.
  - `ContentView.swift`: the drop zone, the preview with its transport bar, the
    style bar (style picker, a brush button that opens Settings, position, caps,
    size) above the editable caption list, and the
    bottom bar. "+ Line" in the transport bar and Captions › Add Line at Playhead (⌘N)
    add a line; the new row scrolls into view and its text field takes focus.
  - `CaptionTimeline.swift`: the track under the video. One block per caption; drag
    a block to move it, its edges to retime it, click it to jump there and focus its
    text, click or drag the empty track to scrub. While dragging, the preview seeks
    to the edge being moved (the end edge shows the caption's last frame).
  - `Preferences.swift`: `Pref` keys and defaults, `ExportLocation`, `ExportQuality`,
    and `StyleStore` (the custom styles, saved as they change).
  - `SettingsView.swift`: Settings (⌘,). General: language (from
    `SpeechTranscriber.supportedLocales`), splitting, export. Styles: built-in and
    custom styles with +/−, and an editor with a live preview on a stand-in frame;
    built-ins are read-only ("Duplicate to Edit"). The font picker is family then
    face; switching family picks its heaviest face.
  - `PlayerView.swift`: wraps `AVPlayerView` with its own controls off. Don't switch
    to SwiftUI's `VideoPlayer`: it crashed this SwiftPM-built app at first display
    (`getSuperclassMetadata` in `_AVKit_SwiftUI`). AVKit is also linked explicitly in
    `Package.swift` for the same reason.
  - The bars are stacked in a `VStack`, not added with `safeAreaInset`, because
    `HSplitView` ignores safe-area insets and the bar would cover the transport row.
  - Developer launch options: `--open <video>` loads a file as if dropped,
    `--add-line <seconds>` then adds a line there, `--settings general|styles` opens
    Settings on that tab (via `openSettings`; the old `showSettingsWindow:` action no
    longer works), and `--snapshot <png>` saves an image of the main window, or of
    Settings with `--settings`. The snapshot draws native controls poorly and
    shows the layout, not the video (frames come out black), and needs no
    screen-recording permission.
- `Sources/subya/`: a developer CLI. `subya transcribe <video> [--srt]` prints
  the captions; `subya burn <video> <out.mp4> [--captions file.srt]` exports, with
  `--style <name>` (built-in or the user's own), `--position`, `--caps`/`--no-caps`,
  `--scale` and `--small` (720p). Both take `--language <id>`. `subya styles` lists
  style names. Transcribe to SRT, edit it, then burn with `--captions` to script fixes.
- `Tests/CaptionKitTests/`: unit tests for grouping, inserting lines, timeline moves and
  resizes, SRT, word splitting, styles (built-ins, saving, lookup, font fallback),
  export naming and sizes, and the renderer (positions, colours, outline, box, caps,
  every built-in, style changes) (`swift test`). They don't need a speech model.
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
- Settings: `open build/Subya.app --args --settings styles --snapshot /tmp/settings.png`.
- Styles and sizes end to end: `subya burn clip.mp4 out.mp4 --style Boxed --small`,
  then check `ffprobe` for 1280-long frames.
