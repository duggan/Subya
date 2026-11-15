"""Builds sheet.svg: every option large, and at 64 and 32 px on light and dark."""
import os
from make_mascots import OPTIONS, HERE

CW, CH, BIG = 660, 900, 600
out = [f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
       f'width="{3 * CW}" height="{2 * CH + 20}"><rect width="100%" height="100%" fill="#F3F1EC"/>']
for i, (letter, name, _) in enumerate(OPTIONS):
    x, y = (i % 3) * CW, (i // 3) * CH + 10
    def img(suffix, ix, iy, s):
        return (f'<image xlink:href="option-{letter}{suffix}.png" x="{ix}" y="{iy}" width="{s}" height="{s}" '
                f'style="image-rendering:pixelated"/>')
    out.append(img("", x + 30, y, BIG))
    out.append(f'<text x="{x + 60}" y="{y + 660}" font-family="Helvetica Neue, Helvetica, Arial" font-size="44" '
               f'font-weight="bold" fill="#1F2329">{letter}  {name}</text>')
    for j, bg in enumerate(("#E8E6E1", "#26282C")):
        bx = x + 60 + j * 270
        out.append(f'<rect x="{bx}" y="{y + 700}" width="240" height="110" rx="18" fill="{bg}"/>')
        out.append(img("-64", bx + 40, y + 723, 64))
        out.append(img("-32", bx + 150, y + 739, 32))
    out.append(f'<text x="{x + 60}" y="{y + 842}" font-family="Helvetica Neue, Helvetica, Arial" font-size="20" '
               f'fill="#1F2329" fill-opacity="0.6">64 px and 32 px, actual size</text>')
out.append("</svg>")
with open(os.path.join(HERE, "sheet.svg"), "w") as f:
    f.write("\n".join(out))
