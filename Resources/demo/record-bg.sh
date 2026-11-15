#!/bin/zsh
# Records Subya's demo tour without taking over the Mac: record-bg.sh <input.mp4> <out-dir>
# The app opens behind other windows (open -g) and wincap records just its window.
set -u
DEMO=${0:A:h}
IN="$1"; OUT="$2"
mkdir -p "$OUT"; rm -f "$OUT/screen.mov" "$OUT/marks.txt" "$OUT/export.mp4" "$OUT/app.log" "$OUT/stop"
pkill -x Subya; sleep 1
open -g -n /Users/ross/Projects/Subya/build/Subya.app --stdout "$OUT/app.log" --stderr /dev/null --args \
  --demo "$IN" --demo-out "$OUT/export.mp4" \
  -ApplePersistenceIgnoreState YES -revealAfterExport NO --demo-background
# Value-less flags go last: one followed by a -key value default stops the app's launch handler.
for i in {1..150}; do grep -q "^DEMO-FRAME" "$OUT/app.log" 2>/dev/null && break; sleep 0.1; done
grep -q "^DEMO-FRAME" "$OUT/app.log" || { echo "no frame"; pkill -x Subya; exit 1; }
"$DEMO/build/wincap" Subya "$OUT/screen.mov" "$OUT/stop" > "$OUT/wincap.log" 2>&1 &
CAP=$!
for i in {1..1500}; do grep -q "^DEMO-DONE" "$OUT/app.log" && break; sleep 0.1; done
sleep 0.5; touch "$OUT/stop"; wait $CAP
pkill -x Subya
grep "^DEMO " "$OUT/app.log" > "$OUT/marks.txt"
cat "$OUT/wincap.log" "$OUT/marks.txt"
