"""Generates Subya's artwork as SVG. `make icons` renders these into the files in
Resources/.

The icon is Bubble Buddy: a chubby white speech bubble with a face, beaming because it
has something to say, in front of a comic sunburst, with "SUB YA" burned in across the
bottom the way the app draws captions: white, with a thick black outline.

    python3 make_icons.py          # writes AppIcon.svg and DMGBackground.svg here
    python3 make_icons.py site     # the website's sticker icon, on stdout
    python3 make_icons.py touch    # the square, opaque apple-touch-icon, on stdout

The website's copies in docs/assets/ are made from those:

    cp Resources/art/AppIcon.svg docs/assets/icon.svg
    python3 Resources/art/make_icons.py site > site.svg
    inkscape site.svg -o docs/assets/icon-512.png -w 512 -h 512
    inkscape site.svg -o docs/assets/favicon.png -w 64 -h 64
    python3 Resources/art/make_icons.py touch > touch.svg
    inkscape touch.svg -o docs/assets/apple-touch-icon.png -w 180 -h 180 -b "#FFB400" -y 1

make_banner.py draws the README and social-card banner with the same character.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

PAPER = "#F3F1EC"
INK = "#1F2329"
BURST_DARK = "#FFB400"
BURST_LIGHT = "#FFD84A"
PINK = "#FF5D8F"
MOUTH = "#7A1F3D"
TONGUE = "#FF9DBB"
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


def caption(x, y, size, text):
    """Meme caption text, drawn the way the app burns captions in: white, thick black outline."""
    return (f'<text x="{x}" y="{y}" text-anchor="middle" font-family="{CAPTION_FONT}" font-size="{size}" '
            f'fill="#FFF" stroke="{INK}" stroke-width="{size * 0.2:.0f}" stroke-linejoin="round" '
            f'paint-order="stroke">{text}</text>')


def bubble_buddy():
    """Bubble Buddy, drawn in the icon's 1024 square: a chubby speech bubble, tilted a
    little, with a pink copy peeking out behind it like a sticker's shadow, dot eyes,
    pink cheeks and a wide-open smile. Everything is outlined in thick ink."""
    shape = ("M326,170 H698 A130,130 0 0 1 828,300 V470 A130,130 0 0 1 698,600 H452 "
             "L286,722 L330,600 H326 A130,130 0 0 1 196,470 V300 A130,130 0 0 1 326,170 Z")
    mouth = "M424,452 Q512,478 600,452 Q602,560 512,560 Q422,560 424,452 Z"

    def dot_eye(x):
        return (f'<ellipse cx="{x}" cy="352" rx="46" ry="66" fill="{INK}"/>'
                f'<circle cx="{x - 12}" cy="328" r="17" fill="#FFF"/>'
                f'<circle cx="{x + 14}" cy="380" r="8" fill="#FFF"/>')

    def cheek(x):
        return f'<ellipse cx="{x}" cy="446" rx="50" ry="30" fill="{PINK}"/>'

    return f'''<g transform="rotate(-4 512 420)">
      <path d="{shape}" transform="translate(22 24)" fill="{PINK}" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>
      <path d="{shape}" fill="#FFF" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>
      {cheek(306)}{cheek(718)}
      {dot_eye(408)}{dot_eye(616)}
      <clipPath id="mouth"><path d="{mouth}"/></clipPath>
      <path d="{mouth}" fill="{MOUTH}"/>
      <g clip-path="url(#mouth)"><ellipse cx="512" cy="560" rx="62" ry="40" fill="{TONGUE}"/></g>
      <path d="{mouth}" fill="none" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>
    </g>'''


def app_icon(look="app"):
    """Bubble Buddy in front of a comic sunburst, captioned "SUB YA". The caption sits
    slightly askew and overlaps the bubble's tail, as a burned-in caption would.

    `look` is "app" (the macOS icon: a squircle with a soft drop shadow), "site" (the
    website's sticker: an ink outline and a hard offset shadow, cropped close) or "touch"
    (the sunburst filling the whole square, opaque, for the apple-touch-icon)."""
    box, radius, shadow, outline = "0 0 1024 1024", 185, "", ""
    if look == "app":
        shadow = '<rect x="100" y="112" width="824" height="824" rx="185" fill="#000" fill-opacity="0.18"/>'
    elif look == "site":
        box = "82 82 864 864"
        shadow = f'<rect x="112" y="114" width="824" height="824" rx="185" fill="{INK}"/>'
        outline = f'<rect x="100" y="100" width="824" height="824" rx="185" fill="none" stroke="{INK}" stroke-width="20"/>'
    else:
        box, radius = "100 100 824 824", 0
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{box}" width="1024" height="1024">
  <defs>
    <clipPath id="frame"><rect x="100" y="100" width="824" height="824" rx="{radius}"/></clipPath>
  </defs>
  {shadow}
  <g clip-path="url(#frame)">
    <rect x="100" y="100" width="824" height="824" fill="{BURST_DARK}"/>
    {sunburst(512, 540, 700, 11)}
    {bubble_buddy()}
  </g>
  {outline}
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
    if len(sys.argv) > 1:
        sys.stdout.write(app_icon(sys.argv[1]))
        sys.exit()
    for name, svg in (("AppIcon.svg", app_icon()), ("DMGBackground.svg", dmg_background())):
        with open(os.path.join(HERE, name), "w") as f:
            f.write(svg)
        print("wrote", name)
