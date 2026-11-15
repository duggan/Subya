#!/bin/sh
# Renders every option with Inkscape (1024, 64, 32 px) and builds options.png.
cd "$(dirname "$0")" || exit 1
python3 make_mascots.py || exit 1
for l in A B C D E F; do
  inkscape option-$l.svg -w 1024 -h 1024 -o option-$l.png 2>/dev/null
  inkscape option-$l.svg -w 64 -h 64 -o option-$l-64.png 2>/dev/null
  inkscape option-$l.svg -w 32 -h 32 -o option-$l-32.png 2>/dev/null
done
python3 make_sheet.py && inkscape sheet.svg -o options.png 2>/dev/null && echo "wrote $(pwd)/options.png"
