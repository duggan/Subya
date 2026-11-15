#!/usr/bin/env python3
"""Build subby-wiseguy.mp4: Subby, a deadpan New York wiseguy, talking to camera. A demo clip for Subya.

    python3 build.py            # audio -> frames -> mp4, all next to this file

Steps: the voiced lines (voice/t1.wav…, or VOICE_DIR; `say` if there are none) are laid
out with pauses into speech.wav; the loudness of each 1/30 s drives the mouth; every frame
is an SVG snippet (Subby's shapes are the ones in Resources/art/make_icons.py and
docs/index.html, in a 320x180 scene); render.js draws them in headless Chrome; ffmpeg
joins frames and speech. OUT=<path> writes the clip somewhere else.
"""
import json
import math
import os
import struct
import subprocess
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("OUT") or os.path.join(HERE, "subby-wiseguy.mp4")
BUILD = os.path.join(HERE, "build")
FPS = 30
RATE = 44100
VOICE = "Daniel"                    # only for `say`, when there are no voiced lines
LEAD, TAIL = 0.3, 0.6
# (text, pause after it)
LINES = [("You're watching this on mute, aren't you?", 0.5),
         ("That's fine. I get it.", 0.5),
         ("That's why I brought subtitles.", 0.7),
         ("Capisce?", 0.0)]

INK, PINK, MOUTH = "#1F2329", "#FF5D8F", "#7A1F3D"
BODY = ("M-35,-41 H35 A25,25 0 0 1 60,-16 V16 A25,25 0 0 1 35,41 H-11 L-43,64 L-35,41 "
        "A25,25 0 0 1 -60,16 V-16 A25,25 0 0 1 -35,-41 Z")          # p-round from the site
BX, BY, BS = 160, 60, 1.2           # Subby's centre and size in the 320x180 scene: close to camera
TABLE_Y = 130                       # the table's edge; below it stays plain for captions


# ---------------------------------------------------------------- audio

def run(*cmd):
    subprocess.run(cmd, check=True)


def read_wav(path):
    with wave.open(path) as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1 and w.getsampwidth() == 2
        return list(struct.unpack(f"<{w.getnframes()}h", w.readframes(w.getnframes())))


def trimmed(samples, floor=300):
    """Drop the silence `say` leaves at either end."""
    loud = [i for i, s in enumerate(samples) if abs(s) > floor]
    return samples[max(0, loud[0] - 400):loud[-1] + 2000]


def make_audio():
    """Returns ([(text, start, end)], samples) and writes build/speech.wav."""
    os.makedirs(BUILD, exist_ok=True)
    # VOICE_DIR: pre-recorded lines (t1.wav…, 44.1 kHz mono 16-bit, e.g. from voice.py
    # trimmed with ffmpeg) instead of `say`.
    voice_dir = os.environ.get("VOICE_DIR") or (os.path.join(HERE, "voice") if os.path.isdir(os.path.join(HERE, "voice")) else None)
    if not voice_dir:
        voices = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
        assert any(line.startswith(VOICE + " ") for line in voices.splitlines()), f"voice {VOICE} not installed"
    track, timings = [0] * int(LEAD * RATE), []
    for i, (text, pause) in enumerate(LINES):
        path = os.path.join(BUILD, f"line{i + 1}.wav")
        if voice_dir:
            run("cp", os.path.join(voice_dir, f"t{i + 1}.wav"), path)
        else:
            run("say", "-v", VOICE, "-o", path, f"--data-format=LEI16@{RATE}", text)
        s = trimmed(read_wav(path))
        timings.append((text, len(track) / RATE, (len(track) + len(s)) / RATE))
        track += s + [0] * int(pause * RATE)
    track += [0] * int(TAIL * RATE)
    track += [0] * (-len(track) % (RATE // FPS))            # whole frames
    with wave.open(os.path.join(BUILD, "speech.wav"), "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(struct.pack(f"<{len(track)}h", *track))
    return timings, track


def split_at(track, start, end, fallback):
    """Where the longest pause inside a line starts and ends (the next phrase begins), in
    seconds; `fallback` (a fraction of the line) twice if it has no pause of 0.1 s or more."""
    n = RATE // 100
    quiet = [max(abs(s) for s in track[i:i + n]) < 500 for i in range(int(start * RATE), int(end * RATE) - n, n)]
    best, run_start = (0, 0, 0), None
    for i, q in enumerate(quiet + [False]):
        if q and run_start is None:
            run_start = i
        elif not q and run_start is not None:
            if run_start > 15 and i < len(quiet) - 15:       # not the line's own ends
                best = max(best, (i - run_start, run_start, i))
            run_start = None
    if best[0] < 10:
        return (start + fallback * (end - start),) * 2
    return start + best[1] / 100, start + best[2] / 100


def mouth_levels(track):
    """How open the mouth is in each frame, 0-1, from the speech's loudness."""
    n = RATE // FPS
    rms = [math.sqrt(sum(s * s for s in track[i:i + n]) / n) for i in range(0, len(track), n)]
    top = sorted(rms)[int(len(rms) * 0.93)]
    levels, prev = [], 0.0
    for r in rms:
        v = min(1.0, r / top)
        v = 0.0 if v < 0.08 else v ** 0.7
        prev = max(v, prev * 0.45)                          # close a little slower than it opens
        levels.append(prev)
    return levels


# ---------------------------------------------------------------- drawing

def ease(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def pulse(t, on, off, rise, fall):
    """0 -> 1 from `on` (taking `rise`), back to 0 from `off` (taking `fall`)."""
    return ease((t - on) / rise) * (1 - ease((t - off) / fall))


def backdrop():
    """A diner booth at night: dim wall, a pool of lamplight, a window with city lights, the seat back."""
    lights = "".join(f'<rect x="{x}" y="{y}" width="3" height="3" fill="#FFD466"/>'
                     for x, y in [(23, 52), (23, 62), (29, 57), (39, 44), (45, 44), (39, 56), (45, 64),
                                  (56, 60), (62, 54), (62, 66), (56, 70)])
    return f'''<rect width="320" height="180" fill="#3B2A45"/>
<circle cx="278" cy="46" r="112" fill="#47314B"/><circle cx="278" cy="46" r="70" fill="#573A50"/>
<g stroke="{INK}" stroke-width="4" stroke-linejoin="round"><rect x="16" y="24" width="58" height="56" rx="4" fill="#22335C"/></g>
<path d="M18,80 V50 H34 V80 Z M34,80 V38 H52 V80 Z M52,80 V48 H72 V80 Z" fill="#16213F"/>{lights}
<g stroke="{INK}" stroke-linejoin="round" fill="none"><path d="M45,24 V80 M16,52 H74" stroke-width="3"/><rect x="16" y="24" width="58" height="56" rx="4" stroke-width="4"/>
<rect x="11" y="79" width="68" height="6" rx="2" fill="#FFF6DF" stroke-width="3"/></g>
<g stroke="{INK}" stroke-width="4" stroke-linejoin="round"><rect x="28" y="66" width="264" height="90" rx="14" fill="#A8323F"/>
<path d="M28,84 H292" fill="none" stroke-width="3"/></g>'''


def foreground():
    """The lamp over the booth and the table's edge, seen from a little below; plain underneath."""
    return f'''<g stroke="{INK}" stroke-width="4" stroke-linejoin="round"><path d="M278,0 V16" fill="none" stroke-width="3"/>
<path d="M262,34 Q264,16 278,16 Q292,16 294,34 Z" fill="#FFB400"/><path d="M271,34 Q278,42 285,34 Z" fill="#FFF6DF" stroke-width="3"/></g>
<rect y="{TABLE_Y + 4}" width="320" height="{180 - TABLE_Y - 4}" fill="#241A2C"/>
<rect x="-4" y="{TABLE_Y}" width="328" height="8" rx="3" fill="#E9D9B8" stroke="{INK}" stroke-width="3.5"/>'''


def face(level, lid=0.5, brows=(0.0, 0.0), glance=(0.0, 0.0), pleased=0.0):
    """Subby's face around 0,0. `level` 0-1 opens the mouth; `lid` is how far the eyelids
    are down (0.5 half-lidded, 1 shut); `brows` raises the left and right eyebrow, 0-1;
    `pleased` 0-1 lifts one corner of the shut mouth a little."""
    gx, gy = glance
    rx, ry = 8.5, 12.5
    out = [f'<g fill="{PINK}"><ellipse cx="-39" cy="11.5" rx="9.5" ry="5.7"/><ellipse cx="39" cy="11.5" rx="9.5" ry="5.7"/></g>']
    for side, x in (("l", -20), ("r", 20)):
        ex, ey = x + gx, -6 + gy
        y = ey - ry + 2 * ry * min(lid, 1.0)                 # the eyelid's edge
        whole = f'<ellipse cx="{ex:.2f}" cy="{ey:.2f}" rx="{rx}" ry="{ry}"'
        if lid < 0.88:                                       # the eye below a heavy, flat lid
            out.append(f'<clipPath id="eye{side}"><rect x="{ex - 12:.2f}" y="{y:.2f}" width="24" height="30"/></clipPath>'
                       f'<g clip-path="url(#eye{side})">{whole} fill="{INK}"/>'
                       f'<circle cx="{ex - 2.3 + gx * 0.2:.2f}" cy="{max(ey - 4.5, y + 4.4):.2f}" r="3.1" fill="#fff"/>'
                       f'<circle cx="{ex + 2.8:.2f}" cy="{ey + 6.4:.2f}" r="1.5" fill="#fff"/></g>')
            w = rx * math.sqrt(max(0.0, 1 - ((y - ey) / ry) ** 2)) + 0.6
            out.append(f'<path d="M{ex - w:.2f},{y:.2f} H{ex + w:.2f}" stroke="{INK}" stroke-width="3.6" stroke-linecap="round"/>')
        else:                                                # shut
            out.append(f'<path d="M{ex - rx - 0.5:.2f},{ey + 1:.2f} Q{ex:.2f},{ey + 5:.2f} {ex + rx + 0.5:.2f},{ey + 1:.2f}" '
                       f'fill="none" stroke="{INK}" stroke-width="3.6" stroke-linecap="round"/>')
    for (x0, x1), r in zip(((-31, -11), (11, 31)), brows):
        y = -18 - 9 * r
        out.append(f'<path d="M{x0},{y:.2f} Q{(x0 + x1) / 2},{y - 4.5 * r:.2f} {x1},{y:.2f}" fill="none" stroke="{INK}" '
                   f'stroke-width="4" stroke-linecap="round"/>')
    if level < 0.12:                                         # shut: a flat line, a shade off-centre
        out.append(f'<path d="M-8,22 H7 Q11,22 12.5,{22 - 2.6 * pleased:.2f}" fill="none" stroke="{INK}" stroke-width="3.8" '
                   f'stroke-linecap="round" stroke-linejoin="round"/>')
    else:                                                    # talking out of the side of his mouth
        out.append(f'<ellipse cx="3" cy="22.5" rx="{7.5 * (0.75 + 0.25 * level):.2f}" ry="{max(2.2, 6.2 * level):.2f}" '
                   f'fill="{MOUTH}" stroke="{INK}" stroke-width="3.4"/>')
    return f'<g transform="translate(0 -2)">{"".join(out)}</g>'   # features a touch high: seen from below


def subby(dx, dy, tilt, sx, sy, zoom, face_svg):
    foot = 41 * BS
    return (f'<g transform="translate({BX + dx:.2f} {BY + dy:.2f}) translate(0 {foot:.2f}) scale({sx:.4f} {sy:.4f}) '
            f'translate(0 {-foot:.2f}) rotate({tilt:.2f}) scale({BS * zoom:.4f})">'
            f'<g stroke="{INK}" stroke-width="4" stroke-linejoin="round"><path d="{BODY}" transform="translate(4.5 5)" fill="{PINK}"/>'
            f'<path d="{BODY}" fill="#fff"/></g>{face_svg}</g>')


# ---------------------------------------------------------------- the acting

def make_frames(timings, levels, track):
    (_, a1, b1), (_, a2, b2), (_, a3, b3), (_, a4, b4) = timings
    total = len(levels) / FPS
    _, tag = split_at(track, a1, b1, 0.7)                 # "…aren't you?"
    fine_end, second = split_at(track, a2, b2, 0.5)       # "That's fine." | "I get it."
    word = a3 + 0.55 * (b3 - a3)                          # "subtitles"
    blinks = [a3 - 0.3, a4 - 0.5]                         # few: he stares

    frames = []
    for f in range(len(levels)):
        t = f / FPS
        level = levels[f]
        raise_ = pulse(t, tag - 0.1, b1 + 0.3, 0.5, 0.3)             # a slow eyebrow on "aren't you?"
        shrug = pulse(t, a2 - 0.08, min(fine_end, a2 + 0.75) - 0.1, 0.2, 0.3)         # "That's fine."
        nod2 = pulse(t, second + 0.05, second + 0.22, 0.12, 0.22)    # "I get it."
        lean = pulse(t, word - 0.15, b3 + 0.45, 0.3, 0.4)            # in on "subtitles"
        aside = pulse(t, b3 + 0.02, b3 + 0.3, 0.1, 0.12)             # a glance down at them
        cock = ease((t - a4 + 0.3) / 0.4)                            # head to one side for "Capisce?"
        ask = pulse(t, a4 - 0.1, b4 + 0.2, 0.3, 0.45)
        nod4 = pulse(t, b4 + 0.05, b4 + 0.3, 0.3, 0.4)               # one slow nod, then hold
        still = 1 - ease((t - b4) / 0.3)

        lid = 0.5 - 0.1 * lean + 0.06 * cock
        lid += (0.95 - lid) * shrug                                  # eyes shut through the shrug
        for tb in blinks:
            if 0 <= t - tb <= 0.2:
                lid += (1.0 - lid) * math.sin((t - tb) / 0.2 * math.pi)
        brows = (0.55 * shrug + 0.15 * raise_, 0.55 * shrug + raise_ + 0.75 * ask)
        glance = (3.2 * aside, 3.4 * aside)

        dy = 0.7 * math.sin(t * 2 * math.pi * 0.4) * still + 2.4 * nod2 + 2.2 * lean + 3.6 * nod4
        tilt = -2 + 0.5 * math.sin(t * 2 * math.pi * 0.23) * still + 2.5 * raise_ - 5.5 * shrug + 5 * cock
        sy = (1 + 0.02 * level) * (1 - 0.065 * shrug) * (1 - 0.02 * nod4)
        sx = 1 + (1 - sy) * 0.7
        parts = [backdrop(), subby(0, dy, tilt, sx, sy, 1 + 0.07 * lean,
                                   face(level, lid, brows, glance, pleased=0.7 * lean)), foreground()]
        frames.append("".join(parts))
    return frames, {"arent_you": round(tag, 2), "i_get_it": round(second, 2), "subtitles": round(word, 2), "total": round(total, 2)}


def main():
    timings, track = make_audio()
    frames, notes = make_frames(timings, mouth_levels(track), track)
    with open(os.path.join(BUILD, "frames.json"), "w") as f:
        json.dump(frames, f)
    with open(os.path.join(BUILD, "timings.json"), "w") as f:
        json.dump({"lines": [{"text": t, "start": round(a, 2), "end": round(b, 2)} for t, a, b in timings], **notes}, f, indent=1)
    print(open(os.path.join(BUILD, "timings.json")).read())
    run("node", os.path.join(HERE, "render.js"), os.path.join(BUILD, "frames.json"), os.path.join(BUILD, "frames"))
    run("ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(BUILD, "frames", "%04d.png"),
        "-i", os.path.join(BUILD, "speech.wav"), "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p",
        "-r", str(FPS), "-c:a", "aac", "-b:a", "160k", "-ar", "44100", "-ac", "2", "-movflags", "+faststart", "-shortest", OUT)
    print(OUT)


if __name__ == "__main__":
    main()
