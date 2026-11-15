# The demo video

How `docs/assets/demo.mp4`, `demo-poster.jpg` and `demo.gif` (the website's demo and
the README's GIF) are made. Everything in it is original: the clip stars Bubble Buddy.

1. **The clip** (`buddy-biscuit.mp4`, 12 s): `python3 build.py`. It lays out the four
   voiced lines in `voice/` with pauses, animates Bubble Buddy to them (SVG frames drawn
   by `render.js` in headless Chrome; `npm install --prefix Resources/demo playwright-core`
   first), and muxes them with ffmpeg. The lines were voiced by `openai/gpt-audio`
   (voice Coral) through OpenRouter with `voice.py`, then trimmed of silence with
   ffmpeg; the results aren't deterministic, so the takes used are kept in `voice/`.
   Check the transcription splits into the four lines:
   `build/Subya.app/Contents/Helpers/subya transcribe buddy-biscuit.mp4`.
2. **The recording**: `make sign`, compile the window recorder
   (`mkdir -p build && swiftc -O wincap.swift -o build/wincap`), then
   `./record-bg.sh "$PWD/buddy-biscuit.mp4" /tmp/take`. It runs the app's scripted tour
   (`--demo`, see `Sources/SubyaApp/DemoTour.swift`) behind your other windows and
   records just Subya's window with ScreenCaptureKit, so the Mac stays usable. The
   process running it needs Screen Recording permission.
3. **The edit**: `python3 edit.py /tmp/take` cuts the tour's steps (from `marks.txt`),
   lays the clip's audio under each playback, and writes `demo.mp4`, `demo-poster.jpg`
   and `demo.gif` into the take folder. `OFFSET` (recording vs tour clock, default
   0.33 s) and `LAG` (AVPlayer's start-up delay, 0.15 s) line the sound up; check the
   first speech lands as Buddy's mouth opens. Copy the three files to `docs/assets/`.
