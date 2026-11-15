"""Cuts the recorded demo tour into the site video (and the README GIF).

python3 edit.py <take-dir>    reads <take-dir>/screen.mov and marks.txt, buddy-biscuit.mp4
Writes <take-dir>/demo.mp4 (1280x800, sound), demo-poster.jpg and demo.gif.
"""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TAKE = sys.argv[1]
CLIP = os.path.join(HERE, "buddy-biscuit.mp4")
OFFSET = float(os.environ.get("OFFSET", "0.33"))   # recording time = tour time - OFFSET
LAG = float(os.environ.get("LAG", "0.15"))          # AVPlayer's start-up delay after play()

marks = {}
for line in open(os.path.join(TAKE, "marks.txt")):
    _, t, name = line.split()
    marks[name] = float(t)
m = marks
clip_len = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                          "-of", "csv=p=0", CLIP]).strip())

# (start, end) in tour time: what to keep, in order.
SEGMENTS = [
    (1.5, m["play"]),                          # empty window, then the clip arrives transcribed
    (m["play"], m["edit"]),                    # plays with Classic captions
    (m["edit"], m["meme"]),                    # types a fix into the last line
    (m["meme"], m["meme"] + 4.8),              # Meme style
    (m["oneword"], m["oneword"] + 9.4),        # One Word, through "Maybe two."
    (m["move"], m["crop"]),                    # slides the captions down
    (m["crop"], m["export"]),                  # 9:16 crop, plays
    (m["export"], m["end"] - 0.3),             # exports
]
# When the tour started the clip playing (tour time) and for how long: play() seeks, waits
# 0.3 s, then plays; style changes wait 0.6 s first, the crop 3.2 s.
PLAYS = [(m["play"] + 0.3, clip_len), (m["meme"] + 0.9, 3.5), (m["oneword"] + 0.9, clip_len),
         (m["crop"] + 3.5, 4.0)]

def run(*cmd):
    subprocess.run(cmd, check=True)

# 1. The audio for the whole recording: the clip's sound wherever the app was playing it.
total = m["end"] + 1
parts, inputs = [], []
for i, (start, length) in enumerate(PLAYS):
    inputs += ["-i", CLIP]
    delay = int((start - OFFSET + LAG) * 1000)
    parts.append(f"[{i}:a]atrim=0:{length},asetpts=PTS-STARTPTS,adelay={delay}:all=1[a{i}]")
mix = ";".join(parts) + ";" + "".join(f"[a{i}]" for i in range(len(PLAYS))) + \
      f"amix=inputs={len(PLAYS)}:normalize=0,apad,atrim=0:{total}[out]"
audio = os.path.join(TAKE, "audio.wav")
run("ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", mix, "-map", "[out]", "-ar", "44100", "-ac", "1", audio)

# 2. Cut the same segments from video and audio and join them.
screen = os.path.join(TAKE, "screen.mov")
f = []
for i, (a, b) in enumerate(SEGMENTS):
    a, b = a - OFFSET, b - OFFSET
    f.append(f"[0:v]trim={a:.3f}:{b:.3f},setpts=PTS-STARTPTS,fps=30,scale=1280:800:flags=lanczos[v{i}]")
    f.append(f"[1:a]atrim={a:.3f}:{b:.3f},asetpts=PTS-STARTPTS[a{i}]")
f.append("".join(f"[v{i}][a{i}]" for i in range(len(SEGMENTS))) + f"concat=n={len(SEGMENTS)}:v=1:a=1[v][a]")
demo = os.path.join(TAKE, "demo.mp4")
run("ffmpeg", "-v", "error", "-y", "-i", screen, "-i", audio, "-filter_complex", ";".join(f),
    "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset", "slow", "-crf", "23", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", demo)

# 3. A poster frame (the One Word style mid-line) and a short GIF for the README.
seg_starts, acc = [], 0.0
for a, b in SEGMENTS:
    seg_starts.append(acc); acc += b - a
poster_t = seg_starts[4] + 2.2
run("ffmpeg", "-v", "error", "-y", "-ss", f"{poster_t:.2f}", "-i", demo, "-frames:v", "1", "-q:v", "3",
    os.path.join(TAKE, "demo-poster.jpg"))
gif_parts = [(seg_starts[1] + 0.3, 4.2), (seg_starts[2], 2.6), (seg_starts[4] + 0.6, 4.2), (seg_starts[6] + 0.6, 6.0)]
g = []
for i, (a, length) in enumerate(gif_parts):
    g.append(f"[0:v]trim={a:.2f}:{a + length:.2f},setpts=PTS-STARTPTS[g{i}]")
g.append("".join(f"[g{i}]" for i in range(len(gif_parts))) + f"concat=n={len(gif_parts)}:v=1:a=0,fps=12,"
         "scale=800:-1:flags=lanczos,split[x][y];[x]palettegen=max_colors=128:stats_mode=diff[p];"
         "[y][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle")
run("ffmpeg", "-v", "error", "-y", "-i", demo, "-filter_complex", ";".join(g), "-loop", "0",
    os.path.join(TAKE, "demo.gif"))
print(f"demo.mp4 {acc:.1f} s; poster at {poster_t:.1f} s")
