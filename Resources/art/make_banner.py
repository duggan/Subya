import math,sys
# Draws the README and social-card banner as SVG on stdout. Render with:
#   python3 Resources/art/make_banner.py > Resources/art/Banner.svg
#   inkscape Resources/art/Banner.svg -o docs/assets/banner.png -w 1280 -h 640
INK="#1F2329"
def burst(cx,cy,r,rays):
    step=math.pi/rays; w=[]
    for i in range(rays):
        a,b=(2*i+0.5)*step,(2*i+1.5)*step
        w.append(f"M{cx},{cy} L{cx+r*math.cos(a):.0f},{cy+r*math.sin(a):.0f} L{cx+r*math.cos(b):.0f},{cy+r*math.sin(b):.0f} Z")
    return " ".join(w)
def eye(cx,cy,n):
    rx,ry=104,112
    return f'''<clipPath id="eye{n}"><ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}"/></clipPath>
<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#FFF"/>
<g clip-path="url(#eye{n})"><circle cx="{cx+52}" cy="{cy+22}" r="50" fill="{INK}"/><circle cx="{cx+34}" cy="{cy+2}" r="15" fill="#FFF"/>
<rect x="{cx-rx}" y="{cy-ry}" width="{2*rx}" height="{ry-34}" fill="#E23E77"/><path d="M{cx-rx},{cy-34} L{cx+rx},{cy-34}" stroke="{INK}" stroke-width="18"/></g>
<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="none" stroke="{INK}" stroke-width="18"/>'''
F="Impact, Haettenschweiler, Arial Narrow, sans-serif"
print(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 640" width="1280" height="640">
<defs>
<pattern id="dots" width="22" height="22" patternUnits="userSpaceOnUse" patternTransform="rotate(30)"><circle cx="11" cy="11" r="5" fill="#E88A00"/></pattern>
<radialGradient id="fade" cx="1" cy="0" r="0.75"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></radialGradient>
<mask id="m"><rect width="1280" height="640" fill="url(#fade)"/></mask>
<radialGradient id="fade2" cx="0" cy="1" r="0.5"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></radialGradient>
<mask id="m2"><rect width="1280" height="640" fill="url(#fade2)"/></mask>
</defs>
<rect width="1280" height="640" fill="#FFB400"/>
<path d="{burst(330,400,1700,13)}" fill="#FFD84A"/>
<rect width="1280" height="640" fill="url(#dots)" mask="url(#m)" opacity=".55"/>
<rect width="1280" height="640" fill="url(#dots)" mask="url(#m2)" opacity=".45"/>
<g transform="translate(-48 6) scale(0.74)">
<g stroke="{INK}" stroke-width="20" stroke-linejoin="round" stroke-linecap="round">
<path d="M440,262 L452,172 L512,232 L566,150 L596,262 Z" fill="#FF5D8F"/>
<path d="M172,960 C140,520 200,236 516,236 C832,236 884,520 852,960 Z" fill="#FF5D8F"/></g>
{eye(392,452,1)}{eye(636,452,2)}
<g fill="none" stroke="{INK}" stroke-width="24" stroke-linecap="round">
<path d="M322,322 L476,334"/><path d="M556,304 C606,262 684,262 730,302"/><path d="M452,636 C520,668 600,656 652,598"/><path d="M632,574 L676,612" stroke-width="18"/></g>
</g>
<g transform="rotate(-4 900 320)">
<text x="906" y="342" text-anchor="middle" font-family="{F}" font-size="250" fill="{INK}" stroke="{INK}" stroke-width="50" stroke-linejoin="round">SUBYA</text>
<text x="900" y="330" text-anchor="middle" font-family="{F}" font-size="250" fill="#FFF" stroke="{INK}" stroke-width="50" stroke-linejoin="round" paint-order="stroke">SUBYA</text>
<rect x="578" y="398" width="660" height="88" rx="20" fill="{INK}"/>
<rect x="570" y="390" width="660" height="88" rx="20" fill="#FF5D8F" stroke="{INK}" stroke-width="8"/>
<text x="900" y="453" text-anchor="middle" font-family="{F}" font-size="52" letter-spacing="1.5" fill="#FFF" stroke="{INK}" stroke-width="11" stroke-linejoin="round" paint-order="stroke">BIG CAPTIONS FOR YOUR MEMES</text>
</g>
<text x="915" y="566" text-anchor="middle" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="bold" font-size="28" fill="{INK}">Burned in, on your Mac. Free &amp; open source.</text>
</svg>''')
