#!/bin/bash
# Re-render the DMG background from SVG at the correct Retina DPI.
# The 144 DPI tag is essential: it makes Finder treat the 1200x800px image
# as a 600x400-POINT window. Without it (72 DPI) the window doubles in size
# and the icons land in the top-left quarter, away from the artwork.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
rsvg-convert -w 1200 -h 800 dmg-background.svg -o dmg-background.png
sips -s dpiWidth 144 -s dpiHeight 144 dmg-background.png >/dev/null
echo "Rendered dmg-background.png at 1200x800 @ 144 DPI (= 600x400 pt)."
