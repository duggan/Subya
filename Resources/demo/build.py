#!/usr/bin/env python3
"""Build buddy-biscuit.mp4: Bubble Buddy and the biscuit packet, a demo clip for Subya.

    python3 build.py            # audio -> frames -> mp4, all next to this file

Steps: `say` renders each line; the lines are laid out with pauses into speech.wav; the
loudness of each 1/30 s drives the mouth; every frame is an SVG snippet (Buddy's shapes
are the ones in Resources/art/make_icons.py and docs/index.html, at the site's 320x180
scene size); render.js draws them in headless Chrome; ffmpeg joins frames and speech.
"""
import json
import math
import os
import random
import struct
import subprocess
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "buddy-biscuit.mp4")
BUILD = os.path.join(HERE, "build")
FPS = 30
RATE = 44100
VOICE = "Sandy (English (UK))"
LEAD, TAIL = 0.7, 0.9
# (text, pause after it)
LINES = [("I'm just going to have one biscuit.", 0.95),
         ("Just one.", 0.95),
         ("Maybe two.", 1.15),
         ("The whole packet is gone.", 0.0)]

INK, PINK, MOUTH, TONGUE = "#1F2329", "#FF5D8F", "#7A1F3D", "#FF9DBB"
BISCUIT, BISCUIT_DARK = "#F2B45A", "#C98531"
BODY = ("M-35,-41 H35 A25,25 0 0 1 60,-16 V16 A25,25 0 0 1 35,41 H-11 L-43,64 L-35,41 "
        "A25,25 0 0 1 -60,16 V-16 A25,25 0 0 1 -35,-41 Z")          # p-round from the site
HAPPY_MOUTH = "M-17,13 Q0,18 17,13 Q17.4,33.5 0,33.5 Q-17.4,33.5 -17,13 Z"
BX, BY, BS = 180, 68, 1.05          # Buddy's centre and size in the 320x180 scene
MOUTH_AT = (BX, BY + 24)            # where biscuits fly to
SHELF_Y = 112
SLOT_X0, SLOT_DX, N_BISCUITS = 56, 8.5, 6


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


def backdrop():
    """bg-room from the site (wall, floor, framed picture, plant) plus a shelf for the packet."""
    return f'''<rect width="320" height="180" fill="#7CCBFF"/><rect y="132" width="320" height="48" fill="#4FA3DD"/>
<rect x="22" y="24" width="64" height="50" rx="4" fill="#FFF6DF" stroke="{INK}" stroke-width="4"/><path d="M30,66 L48,44 L60,58 L68,50 L80,66 Z" fill="#6EE7C8" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>
<g stroke="{INK}" stroke-width="4" stroke-linejoin="round"><path d="M262,132 L268,96 H292 L298,132 Z" fill="#FFB400"/><path d="M280,96 C262,74 262,56 272,50 C284,60 284,78 280,96 C294,74 304,70 310,76 C308,88 294,96 280,96" fill="#6EE7C8"/></g>
<g stroke="{INK}" stroke-width="3" stroke-linejoin="round"><path d="M34,{SHELF_Y + 5} v10 l8,-10 Z M96,{SHELF_Y + 5} v10 l-8,-10 Z" fill="#FFB400"/><rect x="18" y="{SHELF_Y}" width="96" height="6" rx="2" fill="#FFF6DF"/></g>'''


def biscuit_round(x, y, r, angle):
    dots = "".join(f'<circle cx="{dx}" cy="{dy}" r="0.9" fill="{BISCUIT_DARK}"/>'
                   for dx, dy in [(-3, -2), (2.5, -3), (0, 1), (-2.5, 3.5), (3.5, 2.5)])
    return (f'<g transform="translate({x:.2f} {y:.2f}) rotate({angle:.1f}) scale({r / 8:.3f})">'
            f'<circle r="8" fill="{BISCUIT}" stroke="{INK}" stroke-width="2.6"/>{dots}</g>')


def packet(left, wobble=0.0):
    """The packet on the shelf: a wrapper with a torn end and `left` biscuits standing in a row."""
    top, bottom = SHELF_Y - 21, SHELF_Y - 1.5
    out = []
    if left > 0:
        for i in range(left):
            x = SLOT_X0 + SLOT_DX * i
            out.append(f'<rect x="{x:.1f}" y="{top + 1}" width="7" height="{bottom - top - 1}" rx="3" '
                       f'fill="{BISCUIT}" stroke="{INK}" stroke-width="2.6"/>')
        out.append(f'<path d="M26,{top} H52 l4,5 l-4,5 l4,5 l-4,4.5 H26 Q22,{(top + bottom) / 2} 26,{top} Z" '
                   f'fill="#B79CFF" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'
                   f'<path d="M33,{top + 1.5} V{bottom - 1.5} M41,{top + 1.5} V{bottom - 1.5}" stroke="#7D5BE0" stroke-width="3"/>')
    else:                                                    # flat, empty wrapper and what's left
        out.append(f'<g transform="rotate({wobble:.1f} 44 {bottom})"><path d="M24,{bottom} l5,-6 l9,2 l8,-4 l9,3 l8,-2 l5,7 Z" '
                   f'fill="#B79CFF" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'
                   f'<path d="M36,{bottom - 1} l1,-4 M48,{bottom - 1} l1,-5" stroke="#7D5BE0" stroke-width="2.4" stroke-linecap="round"/></g>')
        for x, r in [(72, 1.8), (79, 1.2), (86, 2.0), (93, 1.3), (100, 1.6), (66, 1.1)]:
            out.append(f'<circle cx="{x}" cy="{SHELF_Y - r - 0.6}" r="{r}" fill="{BISCUIT}" stroke="{INK}" stroke-width="1.2"/>')
    return "".join(out)


FACE_CRUMBS = [(-11, 36, 1.8), (13, 35, 1.5), (-24, 27, 1.4), (22, 30, 1.9), (3, 39, 1.3),
               (-31, 20, 1.2), (30, 22, 1.5), (-17, 33, 1.2), (36, 31, 1.2), (-38, 30, 1.4)]


def face(look, level, blink=0.0, glance=(0.0, 0.0), crumbs=0, chew=0.0):
    """Buddy's face around 0,0. `look` is happy, flat, shifty or shock (the site's f-happy,
    f-flat, f-pout and f-shock); `level` 0-1 opens the mouth; `blink` 0-1 shuts the eyes."""
    gx, gy = glance
    rx, ry = (10, 13.5) if look == "shock" else (8.5, 12.5)
    out = [f'<g fill="{PINK}"><ellipse cx="-39" cy="11.5" rx="9.5" ry="5.7"/><ellipse cx="39" cy="11.5" rx="9.5" ry="5.7"/></g>']
    lid = 0.55 if look == "flat" else 1.0                    # deadpan: half-shut eyes
    open_ = max(0.08, (1 - blink) * lid)
    for x in (-20, 20):
        ex, ey = x + gx, -6 + gy + (ry * (1 - open_) * 0.5 if look == "flat" else 0)
        out.append(f'<ellipse cx="{ex:.2f}" cy="{ey:.2f}" rx="{rx}" ry="{ry * open_:.2f}" fill="{INK}"/>')
        if open_ > 0.4:
            out.append(f'<circle cx="{ex - 2.3 + gx * 0.2:.2f}" cy="{ey - 4.5 * open_:.2f}" r="{3.3 * min(1, open_ + 0.2):.2f}" fill="#fff"/>'
                       f'<circle cx="{ex + 2.6:.2f}" cy="{ey + 5.2 * open_:.2f}" r="1.5" fill="#fff"/>')
    brows = {"flat": "M-29,-21 H-12 M12,-21 H29",
             "shifty": "M-29,-27 L-13,-24 M13,-27 L29,-24",
             "shock": "M-31,-27 Q-21,-34 -11,-29 M11,-29 Q21,-34 31,-27"}.get(look)
    if brows:
        out.append(f'<path d="{brows}" fill="none" stroke="{INK}" stroke-width="3.6" stroke-linecap="round"/>')

    line = f'fill="none" stroke="{INK}" stroke-width="3.8" stroke-linecap="round" stroke-linejoin="round"'
    if chew > 0:                                             # mouth shut, munching
        w = 8 + 2 * chew
        out.append(f'<path d="M{-w:.1f},{20 - chew:.1f} Q0,{24 + 3 * chew:.1f} {w:.1f},{20 - chew:.1f}" {line}/>')
    elif look == "happy":
        if level < 0.12:
            out.append(f'<path d="M-13,16 Q0,27 13,16" {line}/>')
        else:
            k = 0.35 + 0.65 * level
            out.append(f'<g transform="translate(0 13) scale({0.8 + 0.2 * level:.3f} {k:.3f}) translate(0 -13)">'
                       f'<clipPath id="m"><path d="{HAPPY_MOUTH}"/></clipPath><path d="{HAPPY_MOUTH}" fill="{MOUTH}"/>'
                       f'<g clip-path="url(#m)"><ellipse cx="0" cy="33.5" rx="12" ry="7.6" fill="{TONGUE}"/></g></g>'
                       f'<path d="{HAPPY_MOUTH}" transform="translate(0 13) scale({0.8 + 0.2 * level:.3f} {k:.3f}) translate(0 -13)" '
                       f'fill="none" stroke="{INK}" stroke-width="3.8" stroke-linejoin="round" vector-effect="non-scaling-stroke"/>')
    else:
        shut = {"flat": "M-10,20 H10", "shifty": "M-7,22 Q0,16.5 7,22", "shock": None}[look]
        w, h, y = {"flat": (7.5, 6, 21.5), "shifty": (6, 6.5, 21.5), "shock": (7.5, 10.5, 23)}[look]
        floor = 0.45 if look == "shock" else 0.0             # shocked: never quite shut
        if level < 0.12 and shut:
            out.append(f'<path d="{shut}" {line}/>')
        else:
            k = floor + (1 - floor) * level
            out.append(f'<ellipse cx="0" cy="{y}" rx="{w * (0.75 + 0.25 * k):.2f}" ry="{max(2.2, h * k):.2f}" '
                       f'fill="{MOUTH}" stroke="{INK}" stroke-width="3.4"/>')
    for x, y, r in FACE_CRUMBS[:crumbs]:
        out.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{BISCUIT}" stroke="{INK}" stroke-width="1.1"/>')
    return "".join(out)


def buddy(dx, dy, tilt, sx, sy, face_svg):
    foot = 41 * BS
    return (f'<g transform="translate({BX + dx:.2f} {BY + dy:.2f}) translate(0 {foot:.2f}) scale({sx:.4f} {sy:.4f}) '
            f'translate(0 {-foot:.2f}) rotate({tilt:.2f}) scale({BS})">'
            f'<g stroke="{INK}" stroke-width="4" stroke-linejoin="round"><path d="{BODY}" transform="translate(4.5 5)" fill="{PINK}"/>'
            f'<path d="{BODY}" fill="#fff"/></g>{face_svg}</g>')


# ---------------------------------------------------------------- the story

def make_frames(timings, levels):
    (_, a1, b1), (_, a2, b2), (_, a3, b3), (_, a4, b4) = timings
    total = len(levels) / FPS
    FLIGHT = 0.34
    # Biscuits leave the packet from the open end: (take-off time, slot it leaves).
    bites = [(b1 + 0.22, 5)]                                             # "one"
    bites += [(b2 + 0.18, 4), (b2 + 0.40, 3)]                            # "just one"... two more
    bites += [(b3 + 0.10 + 0.17 * i, 2 - i) for i in range(3)]           # and the rest
    gone = bites[-1][0] + FLIGHT                                         # the moment it's all gone
    blinks = [0.3, a2 - 0.3, b3 + 0.05, b4 + 0.35]
    rng = random.Random(7)
    sprays = []                                                          # crumbs flying off each bite
    for k, (t0, _) in enumerate(bites):
        for _ in range(4 if k < 3 else 7):
            sprays.append((t0 + FLIGHT, rng.uniform(-38, 38), rng.uniform(-50, -12), rng.uniform(1.0, 2.0)))

    frames = []
    for f in range(len(levels)):
        t = f / FPS
        level = levels[f]
        eaten = sum(1 for t0, _ in bites if t >= t0)
        landed = [t0 + FLIGHT for t0, _ in bites if t >= t0 + FLIGHT]
        chewing = bool(landed) and t - landed[-1] < 0.42 and t < gone + 0.1
        chew = 0.5 + 0.5 * math.sin((t - landed[-1]) * 2 * math.pi * 5.5) if chewing else 0.0

        # which face
        if t < a2 - 0.42:
            look = "happy"
        elif t < b2 + 0.12:
            look = "flat"
        elif t < a3 - 0.3:
            look = "happy"
        elif t < gone - 0.05:
            look = "shifty"
        else:
            look = "shock"

        # where the eyes go
        glance = (0.0, 0.0)
        for t0, _ in bites:                                              # watch each biscuit come in
            if t0 - 0.2 < t < t0 + FLIGHT:
                glance = (-4.0 * (1 - ease((t - t0) / FLIGHT)), 1.0)
        if look == "shifty" and t < b3 + 0.05:
            glance = (4.5 * ease((t - (a3 - 0.3)) / 0.2), -0.5)          # looking anywhere but the packet
        if look == "shock" and b4 + 0.25 < t:
            glance = (-4.5 * ease((t - b4 - 0.25) / 0.15), 1.5)          # ...and back at the scene of the crime
        blink = max((1 - abs((t - tb) / 0.07 - 1) for tb in blinks if 0 <= t - tb <= 0.14), default=0.0)

        incoming = any(t0 + FLIGHT * 0.45 < t < t0 + FLIGHT for t0, _ in bites)
        if incoming:
            level, chew = 1.0, 0.0
            if look in ("flat", "shifty"):
                look = "happy"

        # body: idle bob, a dip into each line, a munch wobble, a jump when it sinks in
        dy = 1.6 * math.sin(t * 2 * math.pi * 0.55)
        sy = 1 + 0.035 * level
        tilt = -4 + 1.2 * math.sin(t * 2 * math.pi * 0.31)
        for a in (a1, a2, a3, a4):
            x = (t - a + 0.08) / 0.3
            if 0 <= x <= 1:
                sy *= 1 - 0.07 * math.sin(x * math.pi) * (1 - x)
        if t < 0.5:                                                      # hello hop
            x = t / 0.5
            dy -= 9 * math.sin(x * math.pi)
        if chewing:
            sy *= 1 - 0.035 * chew
        x = (t - gone) / 0.36
        if 0 <= x <= 1:
            dy -= 13 * math.sin(x * math.pi)
            sy *= 1 + 0.07 * math.sin(x * math.pi)
        if look == "flat":
            tilt = -1 + 2.5 * (1 - ease((t - a2 + 0.42) / 0.2))
        if look == "shifty":
            tilt = 3
        if look == "shock":
            tilt = -6 + 2.5 * math.sin((t - gone) * 2 * math.pi * 9) * math.exp(-(t - gone) * 6)
        sx = 1 + (1 - sy) * 0.6

        crumbs = {0: 0, 1: 2, 2: 3, 3: 5}.get(len(landed), 5 if t < gone else 10)
        parts = [backdrop(), packet(N_BISCUITS - eaten, wobble=-6 * math.exp(-(t - gone) * 5) * math.cos((t - gone) * 22) if t > gone else 0)]
        parts.append(buddy(0, dy, tilt, sx, sy, face(look, level, blink, glance, crumbs, chew)))
        for t0, slot in bites:                                           # biscuits in the air
            x = (t - t0) / FLIGHT
            if 0 <= x < 1:
                x0, y0 = SLOT_X0 + SLOT_DX * slot + 3.5, SHELF_Y - 12
                px = x0 + (MOUTH_AT[0] - x0) * x
                py = y0 + (MOUTH_AT[1] + dy - y0) * x - 46 * math.sin(x * math.pi)
                parts.append(biscuit_round(px, py, 8.5 - 2.5 * x * x, 540 * x))
        for t0, vx, vy, r in sprays:                                     # crumbs, gone before the caption area
            x = t - t0
            if 0 <= x < 0.55:
                px, py = MOUTH_AT[0] + vx * x, MOUTH_AT[1] + vy * x + 170 * x * x
                if py < 128:
                    parts.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{r:.1f}" fill="{BISCUIT}" stroke="{INK}" '
                                 f'stroke-width="1" opacity="{1 - ease((x - 0.35) / 0.2):.2f}"/>')
        frames.append("".join(parts))
    return frames, {"bites": [round(b[0], 2) for b in bites], "gone": round(gone, 2), "total": round(total, 2)}


def main():
    timings, track = make_audio()
    frames, notes = make_frames(timings, mouth_levels(track))
    with open(os.path.join(BUILD, "frames.json"), "w") as f:
        json.dump(frames, f)
    with open(os.path.join(BUILD, "timings.json"), "w") as f:
        json.dump({"voice": VOICE, "lines": [{"text": t, "start": round(a, 2), "end": round(b, 2)} for t, a, b in timings], **notes}, f, indent=1)
    print(open(os.path.join(BUILD, "timings.json")).read())
    run("node", os.path.join(HERE, "render.js"), os.path.join(BUILD, "frames.json"), os.path.join(BUILD, "frames"))
    run("ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(BUILD, "frames", "%04d.png"),
        "-i", os.path.join(BUILD, "speech.wav"), "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p",
        "-r", str(FPS), "-c:a", "aac", "-b:a", "160k", "-ar", "44100", "-ac", "2", "-movflags", "+faststart", "-shortest", OUT)
    print(OUT)


if __name__ == "__main__":
    main()
