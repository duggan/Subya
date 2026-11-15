"""Turns a recorded demo tour into the site video and the README GIF.

python3 edit.py <take-dir> [clip.mp4]
Reads <take-dir>/screen.mov and marks.txt (from record-bg.sh) and the clip the tour
played (default: subby-wiseguy.mp4 here). Writes <take-dir>/demo.mp4 (1280x800, with the
clip's sound wherever the app played it), demo-poster.jpg and demo.gif.
"""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TAKE = sys.argv[1]
CLIP = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "subby-wiseguy.mp4")
# Recording time = tour time - OFFSET (the recorder starts just after the tour's clock).
OFFSET = float(os.environ.get("OFFSET", "0.33"))
# The tour marks a play when AVPlayer reports playing; frames show up a touch later.
LAG = float(os.environ.get("LAG", "0.12"))

marks, plays = {}, []
for line in open(os.path.join(TAKE, "marks.txt")):
    parts = line.split()
    t = float(parts[1])
    if parts[2] == "play":
        plays.append((t, float(parts[3]), float(parts[4])))   # (tour time, clip from, length)
    else:
        marks[parts[2]] = t

START = marks["open"] - 1.0   # a beat of the empty window first
END = marks["end"] - 0.2
LENGTH = END - START

def run(*cmd):
    subprocess.run(cmd, check=True)

# 1. Audio: the clip's sound from where each play started, for as long as it played.
inputs, parts = [], []
for i, (t, frm, length) in enumerate(plays):
    inputs += ["-i", CLIP]
    delay = max(int((t - START + LAG) * 1000), 0)
    parts.append(f"[{i}:a]atrim={frm:.3f}:{frm + length:.3f},asetpts=PTS-STARTPTS,"
                 f"afade=t=out:st={max(length - 0.08, 0):.3f}:d=0.08,adelay={delay}:all=1[a{i}]")
mix = ";".join(parts) + ";" + "".join(f"[a{i}]" for i in range(len(plays))) + \
      f"amix=inputs={len(plays)}:normalize=0,apad,atrim=0:{LENGTH:.3f}[out]"
audio = os.path.join(TAKE, "audio.wav")
run("ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", mix, "-map", "[out]", "-ar", "44100", "-ac", "1", audio)

# 2. Video: one continuous cut of the tour.
a = START - OFFSET
demo = os.path.join(TAKE, "demo.mp4")
run("ffmpeg", "-v", "error", "-y", "-i", os.path.join(TAKE, "screen.mov"), "-i", audio, "-filter_complex",
    f"[0:v]trim={a:.3f}:{a + LENGTH:.3f},setpts=PTS-STARTPTS,fps=30,scale=1280:800:flags=lanczos[v]",
    "-map", "[v]", "-map", "1:a", "-c:v", "libx264", "-preset", "slow", "-crf", "23", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", "-shortest", demo)

# 3. Poster (One Word style, mid-line) and the README GIF (the whole tour, smaller).
poster = marks["oneword"] - START + 1.6
run("ffmpeg", "-v", "error", "-y", "-ss", f"{poster:.2f}", "-i", demo, "-frames:v", "1", "-q:v", "3",
    os.path.join(TAKE, "demo-poster.jpg"))
run("ffmpeg", "-v", "error", "-y", "-i", demo, "-filter_complex",
    "fps=12,scale=800:-1:flags=lanczos,split[x][y];[x]palettegen=max_colors=128:stats_mode=diff[p];"
    "[y][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle", "-loop", "0", os.path.join(TAKE, "demo.gif"))
print(f"demo.mp4 {LENGTH:.1f} s, {len(plays)} plays; poster at {poster:.1f} s")
