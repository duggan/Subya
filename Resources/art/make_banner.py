# Draws the README and social-card banner as SVG on stdout. Render with:
#   python3 Resources/art/make_banner.py > Resources/art/Banner.svg
#   inkscape Resources/art/Banner.svg -o docs/assets/banner.png -w 1280 -h 640 -b '#FFB400' -y 1
# (-b and -y keep the PNG opaque, so it looks the same on GitHub's light and dark themes.)
#
# Bubble Buddy, the sunburst and the colours come from make_icons.py, next to this file.
from make_icons import BURST_DARK, BURST_LIGHT, INK, PINK, bubble_buddy, sunburst

F = "Impact, Haettenschweiler, Arial Narrow, sans-serif"
print(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 640" width="1280" height="640">
<defs>
<pattern id="dots" width="22" height="22" patternUnits="userSpaceOnUse" patternTransform="rotate(30)"><circle cx="11" cy="11" r="5" fill="#E88A00"/></pattern>
<radialGradient id="fade" cx="1" cy="0" r="0.75"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></radialGradient>
<mask id="m"><rect width="1280" height="640" fill="url(#fade)"/></mask>
<radialGradient id="fade2" cx="0" cy="1" r="0.5"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></radialGradient>
<mask id="m2"><rect width="1280" height="640" fill="url(#fade2)"/></mask>
</defs>
<rect width="1280" height="640" fill="{BURST_DARK}"/>
{sunburst(300, 330, 1700, 13)}
<rect width="1280" height="640" fill="url(#dots)" mask="url(#m)" opacity=".55"/>
<rect width="1280" height="640" fill="url(#dots)" mask="url(#m2)" opacity=".45"/>
<g transform="translate(-104 -10) scale(0.75)">
{bubble_buddy()}
</g>
<g transform="rotate(-4 900 320)">
<text x="906" y="342" text-anchor="middle" font-family="{F}" font-size="250" fill="{INK}" stroke="{INK}" stroke-width="50" stroke-linejoin="round">SUBYA</text>
<text x="900" y="330" text-anchor="middle" font-family="{F}" font-size="250" fill="#FFF" stroke="{INK}" stroke-width="50" stroke-linejoin="round" paint-order="stroke">SUBYA</text>
<rect x="578" y="398" width="660" height="88" rx="20" fill="{INK}"/>
<rect x="570" y="390" width="660" height="88" rx="20" fill="{PINK}" stroke="{INK}" stroke-width="8"/>
<text x="900" y="453" text-anchor="middle" font-family="{F}" font-size="52" letter-spacing="1.5" fill="#FFF" stroke="{INK}" stroke-width="11" stroke-linejoin="round" paint-order="stroke">BIG CAPTIONS FOR YOUR MEMES</text>
</g>
<text x="915" y="566" text-anchor="middle" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="bold" font-size="28" fill="{INK}">Burned in, on your Mac. Free &amp; open source.</text>
</svg>''')
