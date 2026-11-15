# The demo video

How `docs/assets/demo.mp4`, `demo-poster.jpg` and `demo.gif` (the website's demo and
the README's GIF) are made. Everything in it is original: the clip stars Subby (Bubble
Buddy, the mascot) as a deadpan New York wiseguy in a diner booth, talking to camera.

1. **The clip** (`subby-wiseguy.mp4`, 11 s): `python3 build.py`. It lays out the four
   voiced lines in `voice/` with short pauses, animates Subby to them (SVG frames drawn
   by `render.js` in headless Chrome; `npm install --prefix Resources/demo playwright-core`
   first), and muxes them with ffmpeg. The mouth follows the loudness; the acting (the
   eyebrow on "aren't you?", the shrug, the lean-in on "subtitles", the nod after
   "Capisce?") is timed from each line's start, end and longest pause, so other takes of
   the same lines work too: `VOICE_DIR=<folder> OUT=<clip.mp4> python3 build.py`.
   The lines were voiced by `openai/gpt-audio` (voice Ash) through OpenRouter with
   `voice.py`, then trimmed of silence and resampled to 44.1 kHz with ffmpeg
   (`t1.wav`…`t4.wav`); the results aren't deterministic, so the takes used are kept in
   `voice/`. Check the transcription:
   `build/Subya.app/Contents/Helpers/subya transcribe subby-wiseguy.mp4`. It should give
   the four lines ("aren't you?" and "I get it." as captions of their own) with
   "Capisce?" heard as "Capish.", which the tour then fixes.
2. **The recording**: `make sign`, compile the window recorder
   (`mkdir -p build && swiftc -O wincap.swift -o build/wincap`), then
   `./record-bg.sh "$PWD/subby-wiseguy.mp4" /tmp/take`. It runs the app's scripted tour
   (`--demo`, see `Sources/SubyaApp/DemoTour.swift`) behind your other windows and
   records just Subya's window with ScreenCaptureKit, so the Mac stays usable. The
   process running it needs Screen Recording permission.
3. **The edit**: `python3 edit.py /tmp/take` cuts the tour's steps (from `marks.txt`),
   lays the clip's audio under each playback, and writes `demo.mp4`, `demo-poster.jpg`
   and `demo.gif` into the take folder. `OFFSET` (recording vs tour clock, default
   0.33 s) and `LAG` (AVPlayer's start-up delay, 0.15 s) line the sound up; check the
   first speech lands as Subby's mouth opens. Copy the three files to `docs/assets/`.
