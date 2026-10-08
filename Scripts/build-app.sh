#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
dist_dir="$project_dir/dist"
app_bundle="$dist_dir/LLMmonitor.app"

"$project_dir/Scripts/create-icon.sh"
swift build -c release --package-path "$project_dir"
bin_dir="$(swift build -c release --show-bin-path --package-path "$project_dir")"

rm -rf "$app_bundle"
mkdir -p "$dist_dir"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$project_dir/App/Info.plist" "$app_bundle/Contents/Info.plist"
build_timestamp="$(date '+%y%m%d-%H%M')"
/usr/libexec/PlistBuddy -c "Add :LLMmonitorBuildTimestamp string $build_timestamp" "$app_bundle/Contents/Info.plist"
cp "$project_dir/App/Icon.icns" "$app_bundle/Contents/Resources/Icon.icns"
cp "$bin_dir/LLMmonitor" "$app_bundle/Contents/MacOS/LLMmonitor"
xattr -cr "$app_bundle"
xattr -rd com.apple.macl "$app_bundle" >/dev/null 2>&1 || true
xattr -rd com.apple.provenance "$app_bundle" >/dev/null 2>&1 || true
xattr -d com.apple.FinderInfo "$app_bundle" >/dev/null 2>&1 || true
codesign --force --sign - "$app_bundle"

print "Built $app_bundle"
