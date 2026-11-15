"""Mascot options for Subya's app icon. Same canvas, frame, sunburst and caption as
Resources/art/make_icons.py; each option is an `app_icon()`-style function returning a
full SVG, so the chosen one can replace `app_icon` there (with the helpers it uses).

    python3 make_mascots.py        # writes option-A.svg ... option-F.svg here
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

INK = "#1F2329"
BURST_DARK = "#FFB400"
BURST_LIGHT = "#FFD84A"
BLOB = "#FF5D8F"
BLOB_SHADE = "#E23E77"
MOUTH = "#7A1F3D"
TONGUE = "#FF9DBB"
CAPTION_FONT = "Impact, Helvetica Neue Condensed Black, Arial Narrow, sans-serif"


# ---- shared with make_icons.py -------------------------------------------------------

def sunburst(cx, cy, radius, rays):
    """Alternate wedges of a comic-book burst, fanning out from (cx, cy)."""
    step = math.pi / rays
    wedges = []
    for i in range(rays):
        a, b = (2 * i + 0.5) * step, (2 * i + 1.5) * step
        wedges.append(f"M{cx},{cy} L{cx + radius * math.cos(a):.0f},{cy + radius * math.sin(a):.0f} "
                      f"L{cx + radius * math.cos(b):.0f},{cy + radius * math.sin(b):.0f} Z")
    return f'<path d="{" ".join(wedges)}" fill="{BURST_LIGHT}"/>'


def caption(x, y, size, text):
    """Meme caption text, drawn the way the app burns captions in: white, thick black outline."""
    return (f'<text x="{x}" y="{y}" text-anchor="middle" font-family="{CAPTION_FONT}" font-size="{size}" '
            f'fill="#FFF" stroke="{INK}" stroke-width="{size * 0.2:.0f}" stroke-linejoin="round" '
            f'paint-order="stroke">{text}</text>')


def icon(character, over_caption=""):
    """The icon frame: squircle, sunburst, `character` clipped to it, then the caption.
    `over_caption` is drawn in the caption's tilted space, on top of it (paws, say)."""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <clipPath id="frame"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
  </defs>
  <rect x="100" y="112" width="824" height="824" rx="185" fill="#000" fill-opacity="0.18"/>
  <g clip-path="url(#frame)">
    <rect x="100" y="100" width="824" height="824" fill="{BURST_DARK}"/>
    {sunburst(512, 540, 700, 11)}
    {character}
  </g>
  <g transform="rotate(-5 512 800)">
    {caption(512, 868, 222, "SUB YA")}
    {over_caption}
  </g>
</svg>
'''


# ---- parts ---------------------------------------------------------------------------

def blob(top=206, tuft=True):
    """The pink blob's body, its head reaching up to `top`, with its tuft of hair."""
    hair = (f'<path transform="translate(0 {top - 236})" d="M440,262 L452,172 L512,232 L566,150 L596,262 Z" '
            f'fill="{BLOB}"/>') if tuft else ""
    return f'''<g stroke="{INK}" stroke-width="20" stroke-linejoin="round" stroke-linecap="round">
      {hair}
      <path d="M172,960 C140,{top + 284} 200,{top} 516,{top} C832,{top} 884,{top + 284} 852,960 Z" fill="{BLOB}"/>
    </g>'''


def eye(n, cx, cy, rx, ry, pupil, shines=(), prx=None):
    """A wide-open eye. `pupil` is (dx, dy, r); `shines` are (dx, dy, r) highlights;
    `prx` narrows the pupil into an oval."""
    px, py, pr = pupil
    dots = "".join(f'<circle cx="{cx + dx}" cy="{cy + dy}" r="{r}" fill="#FFF"/>' for dx, dy, r in shines)
    return f'''<clipPath id="eye{n}"><ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}"/></clipPath>
    <ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#FFF"/>
    <g clip-path="url(#eye{n})">
      <ellipse cx="{cx + px}" cy="{cy + py}" rx="{prx or pr}" ry="{pr}" fill="{INK}"/>{dots}
    </g>
    <ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="none" stroke="{INK}" stroke-width="18"/>'''


def open_mouth(n, d, inside):
    """A mouth with outline path `d`; `inside` (teeth, tongue) is clipped to it."""
    return f'''<clipPath id="mouth{n}"><path d="{d}"/></clipPath>
    <path d="{d}" fill="{MOUTH}"/>
    <g clip-path="url(#mouth{n})">{inside}</g>
    <path d="{d}" fill="none" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>'''


def lines(*ds, width=24):
    paths = "".join(f'<path d="{d}"/>' for d in ds)
    return f'<g fill="none" stroke="{INK}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round">{paths}</g>'


def blush(*centres, rx=46, ry=28, fill=BLOB_SHADE):
    return "".join(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}"/>' for x, y in centres)


# ---- the options ---------------------------------------------------------------------

def gobsmacked():
    """A. The blob, jaw dropped at whatever it just watched: saucer eyes, tiny pupils,
    eyebrows up in its hair, mouth a perfect O."""
    return icon(f'''{blob()}
    {eye(1, 388, 420, 102, 106, (4, 8, 36), [(-10, -6, 12)])}
    {eye(2, 640, 420, 102, 106, (-4, 8, 36), [(-18, -6, 12)])}
    {lines("M318,300 Q386,252 450,284", "M578,284 Q642,252 710,300")}
    {open_mouth(1, "M514,544 C566,544 580,580 580,608 C580,642 556,668 514,668 C472,668 448,642 448,608 C448,580 462,544 514,544 Z",
                f'<ellipse cx="514" cy="676" rx="50" ry="34" fill="{TONGUE}"/>')}''')


def big_grin():
    """B. The blob, thrilled to be here: big shiny eyes, rosy cheeks and a huge toothy grin."""
    grin = "M366,548 Q514,590 662,548 Q664,676 514,676 Q364,676 366,548 Z"
    return icon(f'''{blob()}
    {blush((276, 548), (752, 548))}
    {eye(1, 388, 412, 100, 106, (6, 6, 68), [(-20, -22, 24), (30, 30, 11)])}
    {eye(2, 640, 412, 100, 106, (-6, 6, 68), [(-32, -22, 24), (18, 30, 11)])}
    {lines("M322,272 Q386,236 446,262", "M582,262 Q642,236 706,272")}
    <clipPath id="grin"><path d="{grin}"/></clipPath>
    <path d="{grin}" fill="#FFF"/>
    <g clip-path="url(#grin)" fill="none" stroke="{INK}" stroke-width="10">
      <path d="M360,606 Q514,646 668,606"/>
      <path d="M440,540 V690 M514,540 V690 M588,540 V690"/>
    </g>
    <path d="{grin}" fill="none" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>''')


def shouty():
    """C. The blob yelling the caption at the top of its lungs, eyes scrunched with joy."""
    def shout(*segs):
        d = " ".join(segs)
        return (f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="40" stroke-linecap="round"/>'
                f'<path d="{d}" fill="none" stroke="#FFF" stroke-width="16" stroke-linecap="round"/>')
    mouth = "M384,486 Q514,452 644,486 Q672,676 514,680 Q356,676 384,486 Z"
    return icon(f'''{shout("M236,316 L176,262", "M196,410 L130,392", "M304,236 L262,170",
                          "M788,316 L848,262", "M828,410 L894,392", "M720,236 L762,170")}
    {blob()}
    {lines("M316,412 Q388,316 460,412", "M568,412 Q640,316 712,412", width=28)}
    {open_mouth(1, mouth, f'<path d="M350,440 H680 V520 Q514,496 350,520 Z" fill="#FFF" stroke="{INK}" stroke-width="10"/>'
                          f'<ellipse cx="514" cy="672" rx="92" ry="58" fill="{TONGUE}"/>')}''')


def bubble_buddy():
    """D. A new character: a chubby speech bubble with a face, beaming because it has
    something to say."""
    shape = ("M326,170 H698 A130,130 0 0 1 828,300 V470 A130,130 0 0 1 698,600 H452 "
             "L286,722 L330,600 H326 A130,130 0 0 1 196,470 V300 A130,130 0 0 1 326,170 Z")
    def dot_eye(x):
        return (f'<ellipse cx="{x}" cy="352" rx="46" ry="66" fill="{INK}"/>'
                f'<circle cx="{x - 12}" cy="328" r="17" fill="#FFF"/>'
                f'<circle cx="{x + 14}" cy="380" r="8" fill="#FFF"/>')
    return icon(f'''<g transform="rotate(-4 512 420)">
      <path d="{shape}" transform="translate(22 24)" fill="{BLOB}" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>
      <path d="{shape}" fill="#FFF" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>
      {blush((306, 446), (718, 446), rx=50, ry=30, fill=BLOB)}
      {dot_eye(408)}{dot_eye(616)}
      {open_mouth(1, "M424,452 Q512,478 600,452 Q602,560 512,560 Q422,560 424,452 Z",
                  f'<ellipse cx="512" cy="560" rx="62" ry="40" fill="{TONGUE}"/>')}
    </g>''')


def clapper():
    """E. A new character: a chunky pink clapperboard, clapper flung open like a quiff,
    grinning and ready for its take."""
    def bar(n, y, transform=""):
        stripes = "".join(f'<path d="M{x},{y - 4} h62 l-44,72 h-62 Z" fill="{INK}"/>' for x in range(270, 860, 124))
        return f'''<g transform="{transform}">
        <clipPath id="bar{n}"><rect x="236" y="{y}" width="552" height="64" rx="14"/></clipPath>
        <rect x="236" y="{y}" width="552" height="64" rx="14" fill="#FFF"/>
        <g clip-path="url(#bar{n})">{stripes}</g>
        <rect x="236" y="{y}" width="552" height="64" rx="14" fill="none" stroke="{INK}" stroke-width="20"/></g>'''
    return icon(f'''<rect x="236" y="372" width="552" height="640" rx="70" fill="{BLOB}" stroke="{INK}" stroke-width="20"/>
    {bar(1, 318)}
    {bar(2, 244, "rotate(-13 250 318)")}
    <circle cx="262" cy="330" r="20" fill="{BURST_LIGHT}" stroke="{INK}" stroke-width="14"/>
    {blush((302, 566), (722, 566), rx=40, ry=24)}
    {eye(1, 414, 482, 78, 80, (6, 4, 50), [(-14, -18, 18)])}
    {eye(2, 610, 482, 78, 80, (-6, 4, 50), [(-26, -18, 18)])}
    {open_mouth(1, "M430,584 Q512,606 594,584 Q592,668 512,668 Q432,668 430,584 Z",
                f'<ellipse cx="512" cy="678" rx="58" ry="40" fill="{TONGUE}"/>')}''')


def caption_cat():
    """F. A new character: a round pink cat peeking over the caption, paws hooked on the
    letters, very pleased with what it wrote."""
    def ear(d, inner):
        return (f'<path d="{d}" fill="{BLOB}" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>'
                f'<path d="{inner}" fill="{BLOB_SHADE}"/>')
    def paw(x):
        return f'''<ellipse cx="{x}" cy="664" rx="62" ry="40" fill="{BLOB}" stroke="{INK}" stroke-width="20"/>
        <path d="M{x - 20},652 v26 M{x + 20},652 v26" fill="none" stroke="{INK}" stroke-width="12" stroke-linecap="round"/>'''
    return icon(f'''{ear("M216,430 L210,178 L430,268 Z", "M252,330 L250,236 L340,274 Z")}
    {ear("M812,430 L818,178 L598,268 Z", "M776,330 L778,236 L688,274 Z")}
    {blob(top=236, tuft=False)}
    {lines("M262,532 L176,512", "M266,574 L180,588", "M766,532 L852,512", "M762,574 L848,588", width=14)}
    {eye(1, 388, 432, 96, 102, (6, 4, 72), [(-16, -26, 20), (22, 30, 9)], prx=50)}
    {eye(2, 640, 432, 96, 102, (-6, 4, 72), [(-28, -26, 20), (10, 30, 9)], prx=50)}
    <path d="M486,556 H542 L514,588 Z" fill="{BLOB_SHADE}" stroke="{INK}" stroke-width="16" stroke-linejoin="round"/>
    {lines("M448,604 Q482,650 514,598 Q546,650 580,604", width=20)}''',
                over_caption=f"{paw(300)}{paw(736)}")


OPTIONS = [
    ("A", "Gobsmacked Blob", gobsmacked),
    ("B", "Big Grin Blob", big_grin),
    ("C", "Shouty Blob", shouty),
    ("D", "Bubble Buddy", bubble_buddy),
    ("E", "Clapper Critter", clapper),
    ("F", "Caption Cat", caption_cat),
]

if __name__ == "__main__":
    for letter, name, draw in OPTIONS:
        path = os.path.join(HERE, f"option-{letter}.svg")
        with open(path, "w") as f:
            f.write(draw())
        print("wrote", path)
