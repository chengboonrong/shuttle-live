#!/bin/sh
# Renders icon.svg into the iOS and Android launcher icons.
# Needs Google Chrome (headless render) and python3 with Pillow (resize, drop alpha).
set -e
cd "$(dirname "$0")"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
tmp=$(mktemp -d)

render() {
  "$chrome" --headless --disable-gpu --hide-scrollbars --window-size=1024,1024 \
    --default-background-color=00000000 --screenshot="$2" "file://$1" >/dev/null 2>&1
}

render "$PWD/icon.svg" "$tmp/full.png"
# Android adaptive foreground: the art alone, shrunk to fit the 66 dp safe circle of the 108 dp canvas.
sed -e '/id="ground"/d' -e 's/viewBox="0 0 1024 1024"/viewBox="-278 -278 1580 1580"/' icon.svg > "$tmp/fg.svg"
render "$tmp/fg.svg" "$tmp/fg.png"

python3 - "$tmp" <<'EOF'
import json, sys
from PIL import Image

tmp = sys.argv[1]
full = Image.open(f"{tmp}/full.png").convert("RGB")  # App Store icons must not carry alpha
fg = Image.open(f"{tmp}/fg.png").convert("RGBA")
assert full.size == fg.size == (1024, 1024), (full.size, fg.size)

ios = "../ios/Runner/Assets.xcassets/AppIcon.appiconset"
for entry in json.load(open(f"{ios}/Contents.json"))["images"]:
    px = round(float(entry["size"].split("x")[0]) * int(entry["scale"][:-1]))
    full.resize((px, px), Image.LANCZOS).save(f"{ios}/{entry['filename']}")

res = "../android/app/src/main/res"
for density, scale in [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]:
    legacy, adaptive = round(48 * scale), round(108 * scale)
    full.resize((legacy, legacy), Image.LANCZOS).save(f"{res}/mipmap-{density}/ic_launcher.png")
    fg.resize((adaptive, adaptive), Image.LANCZOS).save(f"{res}/mipmap-{density}/ic_launcher_foreground.png")
EOF
rm -r "$tmp"
echo "icons written"
