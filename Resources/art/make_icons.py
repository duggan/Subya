"""Generates Subya's artwork as SVG. `make icons` renders these into the files in
Resources/.

The icon is a reaction shot: a pink blob giving side-eye in front of a comic sunburst,
with "SUB YA" burned in across the bottom the way the app draws captions: white, with a
thick black outline.
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

PAPER = "#F3F1EC"
INK = "#1F2329"
BURST_DARK = "#FFB400"
BURST_LIGHT = "#FFD84A"
BLOB = "#FF5D8F"
BLOB_SHADE = "#E23E77"
CAPTION_FONT = "Impact, Helvetica Neue Condensed Black, Arial Narrow, sans-serif"


def sunburst(cx, cy, radius, rays):
    """Alternate wedges of a comic-book burst, fanning out from (cx, cy)."""
    step = math.pi / rays
    wedges = []
    for i in range(rays):
        a, b = (2 * i + 0.5) * step, (2 * i + 1.5) * step
        wedges.append(f"M{cx},{cy} L{cx + radius * math.cos(a):.0f},{cy + radius * math.sin(a):.0f} "
                      f"L{cx + radius * math.cos(b):.0f},{cy + radius * math.sin(b):.0f} Z")
    return f'<path d="{" ".join(wedges)}" fill="{BURST_LIGHT}"/>'


def side_eye(cx, cy, n):
    """One half-lidded eye, pupil shoved into the corner. `n` keeps the clip id unique."""
    rx, ry = 104, 112
    return f'''<clipPath id="eye{n}"><ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}"/></clipPath>
    <ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#FFF"/>
    <g clip-path="url(#eye{n})">
      <circle cx="{cx + 52}" cy="{cy + 22}" r="50" fill="{INK}"/>
      <circle cx="{cx + 34}" cy="{cy + 2}" r="15" fill="#FFF"/>
      <rect x="{cx - rx}" y="{cy - ry}" width="{2 * rx}" height="{ry - 34}" fill="{BLOB_SHADE}"/>
      <path d="M{cx - rx},{cy - 34} L{cx + rx},{cy - 34}" stroke="{INK}" stroke-width="18"/>
    </g>
    <ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="none" stroke="{INK}" stroke-width="18"/>'''


def caption(x, y, size, text):
    """Meme caption text, drawn the way the app burns captions in: white, thick black outline."""
    return (f'<text x="{x}" y="{y}" text-anchor="middle" font-family="{CAPTION_FONT}" font-size="{size}" '
            f'fill="#FFF" stroke="{INK}" stroke-width="{size * 0.2:.0f}" stroke-linejoin="round" '
            f'paint-order="stroke">{text}</text>')


def app_icon():
    """A pink blob giving the viewer side-eye in front of a comic sunburst, captioned "SUB YA".

    Everything is outlined in thick ink, like a sticker; the caption sits slightly askew and
    overlaps the blob's chin, as a burned-in caption would.
    """
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <clipPath id="frame"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
  </defs>
  <rect x="100" y="112" width="824" height="824" rx="185" fill="#000" fill-opacity="0.18"/>
  <g clip-path="url(#frame)">
    <rect x="100" y="100" width="824" height="824" fill="{BURST_DARK}"/>
    {sunburst(512, 540, 700, 11)}
    <g stroke="{INK}" stroke-width="20" stroke-linejoin="round" stroke-linecap="round">
      <path d="M440,262 L452,172 L512,232 L566,150 L596,262 Z" fill="{BLOB}"/>
      <path d="M172,960 C140,520 200,236 516,236 C832,236 884,520 852,960 Z" fill="{BLOB}"/>
    </g>
    {side_eye(392, 452, 1)}
    {side_eye(636, 452, 2)}
    <g fill="none" stroke="{INK}" stroke-width="24" stroke-linecap="round">
      <path d="M322,322 L476,334"/>
      <path d="M556,304 C606,262 684,262 730,302"/>
      <path d="M452,636 C520,668 600,656 652,598"/>
      <path d="M632,574 L676,612" stroke-width="18"/>
    </g>
  </g>
  <g transform="rotate(-5 512 800)">
    {caption(512, 868, 222, "SUB YA")}
  </g>
</svg>
'''


def dmg_background():
    """660x420 window, with an arrow from the app (175, 215) to Applications (485, 215)."""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 660 420" width="660" height="420">
  <rect width="660" height="420" fill="{PAPER}"/>
  <g fill="none" stroke="{INK}" stroke-opacity="0.55" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">
    <path d="M268,215 L392,215"/>
    <path d="M372,197 L392,215 L372,233"/>
  </g>
  <text x="330" y="335" text-anchor="middle" font-family="-apple-system, Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="17" fill="{INK}" fill-opacity="0.7">Drag Subya to your Applications folder</text>
</svg>
'''


if __name__ == "__main__":
    for name, svg in (("AppIcon.svg", app_icon()), ("DMGBackground.svg", dmg_background())):
        with open(os.path.join(HERE, name), "w") as f:
            f.write(svg)
        print("wrote", name)
