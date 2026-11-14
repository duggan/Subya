<p align="center">
  <img src="docs/icon.png" width="140" alt="">
</p>

<h1 align="center">Subya</h1>

<p align="center">Big, readable captions for your memes and reaction clips, made on your Mac.</p>

Subya ("sub ya") is a small macOS app that burns captions into a video clip, so the line
lands even when your friends watch with the sound off, in WhatsApp, Messages or the
group chat.

Drop a video on the window. Subya transcribes it on your Mac and splits the speech
into short caption lines. Fix any wrong words or timings in the list, watch the preview,
then export. You get a new `<name>-captioned.mp4` next to the original, with bold white
captions outlined in black near the bottom of the frame.

Nothing is uploaded. Transcription uses the speech recognition built into macOS, and there
are no permissions to grant.

## Install

Download `Subya.dmg` from the latest release and drag Subya to Applications. It
needs macOS 26 or later.

## Use

1. Drag a video onto the window, or choose **File › Open Video…** (⌘O).
2. Wait a moment while it's transcribed. The first time, macOS may download its speech
   model for your language.
3. Edit the captions on the right. You can change the text, the start and end times
   (in seconds), or delete a line. Click ▶ next to a line to play from there. The line
   that's on screen is highlighted.
4. Use the size slider to make the text bigger or smaller.
5. Click **Export…** (⌘E).

## Command line

The `subya` tool does the same from Terminal:

```sh
swift run subya transcribe clip.mp4 --srt > clip.srt   # edit clip.srt if needed
swift run subya burn clip.mp4 clip-captioned.mp4 --captions clip.srt
```

Without `--captions`, `burn` transcribes first. `--scale 1.3` makes the text 30% bigger.

## Development

You need Xcode 26 or later and a Developer ID signing identity. `make dmg` also needs
`create-dmg`, and `make icons` needs Inkscape.

```sh
make run       # build a universal app, sign it, and launch it
make test      # unit tests
make release   # notarized DMG (run `make notary-setup` once first)
make help      # everything else
```

## License

GPL-3.0. See [LICENSE](LICENSE).
