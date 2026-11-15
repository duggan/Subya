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
  rounded box behind the text (colour with opacity), a vertical position, a size,
  all caps, and `display`: whole lines (default) or one
  word at a time. Text is centred and wraps at 90% of the width. Font size is 9.6% of the frame's shorter side times `scale`. Eight built-ins
  (Classic, Meme, Rounded, Marker, Typewriter, Poster, Boxed, Highlight) have fixed
  UUIDs (`5B0BA000-…-00000000000N`) and per-face scales so they look the same size.
  Users duplicate one to make their own in Settings. An unknown font falls back to
  the heavy system font. `CaptionStyle` decodes every field with a default, so styles
  saved before a field existed still load; keep that when adding fields.
- **One word at a time**: `Caption.wordStarts` keeps the transcript's word start
  times (set by `Chunker`). `Caption.timedWords` uses them while they still fit the
  text (same word count, in order, inside the caption), so a typo fix keeps them;
  otherwise, and for lines from SRT or "+ Line", it shares the caption's time out by
  word length (+2 characters each, so short words don't flash). The first word shows
  from the caption's start, the last until its end. Moving a caption shifts its word
  times; retiming an edge stretches them; `setWordStart` retimes one word. `CaptionOverlay` then draws only the
  current word (cached per word). The built-in One Word style (SF Rounded, caps,
  middle, large) uses it, and the main window has a quick toggle.
- **Vertical position** (`CaptionStyle.vertical`): 0 is the Top position and 1 the
  Bottom one (each with a 7% margin from the frame's edge), interpolated in between;
  0.5 is exactly Middle for any text height. `position` is a computed view of it:
  the snap point it's at, or nil in between (pickers then show nothing selected).
  `CaptionStyle.snapped` pulls values within 0.04 onto Top, Middle or Bottom. Styles
  saved with only `position` still load, and `position` is still written.
- **Style choice in the main window** (`AppModel.StyleChoice`, saved as `styleChoice`):
  the chosen style's id plus quick adjustments (vertical position, size, caps, one
  word). Picking a style
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
  `CaptionOverlay`. Captions are rendered tightly around the text
  (`CaptionRenderer.textBlock`: the image, its rect in the frame, and how far it
  travels from the Top position to the Bottom one) on first use and cached by text,
  frame size and look, without the vertical position: moving captions up or down
  just offsets the cached image. Edits update the overlay; the paused frame is redrawn
  by reassigning the item's `videoComposition`. Seeking to the current time does
  not redraw (AVPlayer treats it as a no-op), which made the preview lag behind
  style changes.
- **Responsiveness** (`AppModel`): seeks chase (one in flight; when it lands, jump to
  the latest target), and while one is in flight the time observer doesn't move the
  playhead back. Redraws of the paused frame are coalesced to one per run-loop turn
  and skipped when a seek will redraw anyway. `currentTime` changes 30 times a
  second, so only `TransportBar` and `TimelinePlayhead` read it; everything else
  reads `currentCaptionID` and `currentWordIndex`, which are assigned only when they
  change (observers fire on every set). Keep it that way when adding views.
- The source video is never modified. Export uses `AVAssetExportPresetHighestQuality`
  (H.264, fast start) with its own `CaptionOverlay` at the export's frame size. Where
  it goes is a setting: next to the original (default), a chosen folder, or ask.
  `ExportNaming.url` adds the suffix (default `-captioned`) and " 2", " 3" so nothing
  is overwritten. "Smaller for messaging" scales frames so the long side is 1280
  (`ExportNaming.exportSize`, even sides for H.264), done in the Core Image handler.
  Changing the render size needs the deprecated `AVMutableVideoComposition` (the macOS
  26 `Configuration` API can't hold a CI filter handler); it's called through a
  protocol so the build stays warning-free.
- **Crop** (`Crop`): a rectangle in fractions of the frame, origin top left as on
  screen. `pixelRect` turns it into an even-sided pixel rect in Core Image
  coordinates (origin bottom left). The composition's CI handler crops, moves to the
  origin, then scales (for 720p), and the render size becomes the cropped (scaled)
  size, so captions are laid out in the cropped frame and the preview matches the
  export. Shapes: Free, Original, 1:1, 9:16, 4:5, 16:9; picking one snaps to the
  largest centred crop of that shape, and corner drags keep it. The crop belongs to
  the open video and isn't saved.
- **Trim** (`Trim`): the part of the video kept, in source seconds (at least 0.5 s).
  Captions keep source times; `CaptionRenderer.export(trim:)` sets the export session's
  `timeRange`, and the CI handler still sees source times (checked: output starts at 0
  with the right captions), so nothing is shifted. In the app (`AppModel`), Trim (⌘T, or the `TrimButton` beside Crop, yellow while editing)
  shows the whole video on the timeline with the kept part framed in yellow (grips at
  its ends, outside dimmed, captions dimmed and inert); otherwise the timeline,
  scrubber, ruler, times and caption list show only `timelineRange` (the trim), with
  times counted from its start, and playback stops at its end
  (`forwardPlaybackEndTime`). The trim belongs to the open video and isn't saved.
  Transcription runs as a cancellable task: finishing a trim while it runs cancels it
  and transcribes just the trim (`Transcriber.words(range:)` exports only that audio
  and offsets word times), which matters for big videos (20 min: 21 s whole, 1.3 s
  for a 20 s trim). `transcribed` lists the parts done; a wider trim later transcribes
  only `Trim.missing(from:)` and `merge`s the new captions in. Re-split rebuilds per
  transcribed part. `startTranscription` keeps `isBusy`/`isTranscribing` set until the
  newest task finishes, so a restart doesn't flicker them off.
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
  - `Crop.swift`: the crop rectangle, shape presets, moving and resizing.
  - `Trim.swift`: the trim range, edge rules, parsing `1:05-1:20`, and the parts not
    yet transcribed.
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
  - `CaptionTimeline.swift`: the track under the video, modelled on Photos' trim bar:
    a filmstrip (`Filmstrip`: `AVAssetImageGenerator` frames made only for the visible
    tiles, with time tolerance for speed, the newest request cancelling older ones,
    and the nearest made frame standing in meanwhile), see-through caption blocks, and
    a white playhead with a knob. Clicking a caption selects it
    (`AppModel.selectedCaptionID`): a yellow frame with chevron grips; other blocks'
    edges are invisible but still draggable. Drag a block to move it, its edges to
    retime it, click it to jump there and focus its text, click or drag the filmstrip
    or ruler to scrub. Drags are measured in the timeline's named coordinate space
    ("timeline"), not the dragged view's: the view moves as the caption changes, so
    local coordinates made grips lag behind the pointer (each step partly undid the
    last). The crop editor's drags use its "crop" space for the same reason. While dragging, the preview seeks
    to the edge being moved (the end edge shows the caption's last frame). In one-word
    display, blocks split into their words (labels when there's room): drag a divider
    to change when that word appears (`setWordStart`, which first fixes spread-out
    timings in place, keeps words at least 0.08 s and inside the caption), and click a
    word to jump to it.
    The timeline zooms (`AppModel.timelineZoom`, 1 = whole video in view, up to about
    400 points per second): −/+ and a log-scale slider in the transport bar, pinch, and
    View › Zoom In/Out Timeline (⌘= ⌘−) and Fit Timeline (⌘0). Zoomed, it scrolls
    sideways (`ScrollPosition`), follows the playhead when it leaves the view (not
    while dragging), and zooming keeps the playhead's place on screen. A ruler above
    the blocks labels times, spaced at least 60 points apart.
  - `Preferences.swift`: `Pref` keys and defaults, `ExportLocation`, `ExportQuality`,
    and `StyleStore` (the custom styles, saved as they change).
  - `SettingsView.swift`: Settings (⌘,). General: language (from
    `SpeechTranscriber.supportedLocales`), splitting, export. Styles: built-in and
    custom styles with +/−, and an editor with a live preview on a stand-in frame;
    built-ins are read-only ("Duplicate to Edit"). The font picker is family then
    face; switching family picks its heaviest face.
  - `VideoControls.swift`: caption placement, drawn on the preview when not cropping:
    drag the band where the caption sits, or the chunky yellow handle on the position
    track at the right edge (shown on hover), up or down, snapping at Top, Middle and
    Bottom. Drags are measured in the "video" coordinate space. While dragging
    (`AppModel.isPlacingCaption`), the video shows no captions and the view draws the
    caption's `TextBlock` (rendered once at the start) at the new place, which is
    smooth where redrawing the video each step was jerky; the video takes over on
    release, with the copy kept up 250 ms so it doesn't blink. Clicking the video
    plays and pauses. The track's ends are estimated from the font size; drags work
    on changes, so the estimate only affects where the handle is drawn. `CropButton`
    (same file) is pinned to the top-left corner of the video panel and shows the crop
    once one is set; `TrimButton` sits beside it, shows the clip's length once trimmed,
    and is yellow while the trim is being edited (clicking it then finishes).
  - `CropOverlay.swift`: the crop editor drawn over the preview (dimmed outside the
    crop, thirds grid, drag inside to move, corners to resize) and its toolbar
    (shapes, Reset, Cancel, Done). While editing, the preview shows the whole frame
    without captions; Done rebuilds the composition with the crop.
  - `PlayerView.swift`: wraps `AVPlayerView` with its own controls off. Don't switch
    to SwiftUI's `VideoPlayer`: it crashed this SwiftPM-built app at first display
    (`getSuperclassMetadata` in `_AVKit_SwiftUI`). AVKit is also linked explicitly in
    `Package.swift` for the same reason.
  - The window opens at 1280×820 (within 90% of the screen) the first time, via
    `InitialWindowSize` in `ContentView.swift`, which sets the size through AppKit when
    there's no saved frame. SwiftUI's `defaultSize` and `defaultWindowPlacement` were
    both ignored (the window opened at its minimum, 900×560), so don't swap back
    without checking the real window size.
  - The bars are stacked in a `VStack`, not added with `safeAreaInset`, because
    `HSplitView` ignores safe-area insets and the bar would cover the transport row.
  - Developer launch options: `--open <video>` loads a file as if dropped,
    `--add-line <seconds>` then adds a line there, `--zoom <n>` zooms the timeline,
    `--crop <shape>` crops (with `--crop-edit`, leaves the editor open),
    `--trim <from-to>` trims as soon as the video is in, while it's still transcribing
    (with `--trim-edit`, leaves the editor open; put value-less options like this last,
    as a run with `--trim-edit --snapshot <png>` never ran the launch handler); after
    loading, the app prints `loaded in … s: n captions, first–last s`,
    `--hover-controls` shows the position track as if hovered,
    `--simulate-drag <s>` moves the second caption back and forth 60 times a second
    through the drag path and prints how far the run loop fell behind (run the binary
    directly to see it; pair with `sample Subya` to profile), `--settings general|styles` opens
    Settings on that tab (via `openSettings`; the old `showSettingsWindow:` action no
    longer works), and `--snapshot <png>` saves an image of the main window, or of
    Settings with `--settings`. The snapshot draws native controls poorly and
    shows the layout, not the video (frames come out black), and needs no
    screen-recording permission.
- `Sources/subya/`: a developer CLI. `subya transcribe <video> [--srt]` prints
  the captions; `subya burn <video> <out.mp4> [--captions file.srt]` exports, with
  `--style <name>` (built-in or the user's own), `--position` (top, middle, bottom,
  or 0–1), `--caps`/`--no-caps`,
  `--scale`, `--words`/`--lines`, `--crop 1:1|9:16|4:5|16:9` (centred), `--trim
  <from-to>` (transcribes and exports only that part) and `--small` (720p). Both take `--language <id>`. `subya styles` lists
  style names. Transcribe to SRT, edit it, then burn with `--captions` to script fixes.
- `Tests/CaptionKitTests/`: unit tests for grouping, inserting lines, timeline moves and
  resizes, word-at-a-time timing, SRT, word splitting, styles (built-ins, saving, lookup, font fallback),
  export naming and sizes, trims (edges, parsing, missing parts, merging), crop presets, moves, resizes and pixel rects, and the renderer (positions, colours, outline, box, caps,
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
- `Resources/art/make_icons.py` draws the artwork as SVG. The mascot is Bubble Buddy
  (`bubble_buddy()`): a chubby white speech bubble with a pink sticker shadow, dot
  eyes, pink cheeks and a beaming open smile, on a yellow comic sunburst, with "SUB YA"
  burned across the bottom in Impact, white with a black outline, the app's caption
  style. It's drawn like a sticker, all thick ink outlines. Keep it cheerful (the
  mascot before it, a blob giving smug side-eye, came across as smarmy) and keep it an
  original character, not an existing meme, emoji or mascot. `make icons` (Inkscape)
  renders `Subya.icns` and the DMG background (an arrow and a line of text, no
  character) into `Resources/`. Commit them.
- The website's icons in `docs/assets/` come from the same script (the commands are in
  its docstring): `icon.svg` is a copy of `AppIcon.svg`; `make_icons.py site` draws
  the sticker version (ink outline, hard shadow) for `icon-512.png` and `favicon.png`;
  `make_icons.py touch` the square opaque one for `apple-touch-icon.png`.
- `Resources/art/make_banner.py` draws the README and social-card banner
  (`Banner.svg`, rendered to `docs/assets/banner.png` at 1280×640, opaque), importing
  Bubble Buddy from `make_icons.py`; how to render is in the comment at its top.
- `Resources/art/mascot-options/` keeps the six mascots Bubble Buddy was picked from
  (`options.png` and the scripts that drew them), for reference only.
- `docs/index.html` is the website. Its illustrated clips star Bubble Buddy's
  family: speech-bubble characters in the same sticker style (round, oval, box, cloud
  thought bubble, spiky shout bubble, dashed whisper bubble), built from shared
  `b-*` bodies (`-r` mirrors the tail) and `f-*` faces drawn around 0,0, coloured with
  `--fill`, `--shade` and `--cheek`. Bubble Buddy himself (white, pink shadow) stars in
  the hero. None of them is smug, and none sits over a caption.

## Testing

- `swift test` for the library.
- End to end without the UI: `swift run subya burn <video> /tmp/out.mp4`, then
  pull frames with `ffmpeg -ss 2 -i /tmp/out.mp4 -frames:v 1 /tmp/f.jpg`.
- The window: `make run`, or
  `open build/Subya.app --args --open <video> --snapshot /tmp/window.png`.
- Settings: `open build/Subya.app --args --settings styles --snapshot /tmp/settings.png`.
- Styles and sizes end to end: `subya burn clip.mp4 out.mp4 --style Boxed --small`,
  then check `ffprobe` for 1280-long frames.
