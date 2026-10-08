#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
iconset="$project_dir/App/Icon.iconset"
output="$project_dir/App/Icon.icns"

rm -rf "$iconset"
mkdir -p "$iconset"

for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
  read size name <<< "$spec"
  sips -s format png -z "$size" "$size" "$project_dir/App/Icon.png" --out "$iconset/$name.png" >/dev/null
done

iconutil -c icns "$iconset" -o "$output"
rm -rf "$iconset"
