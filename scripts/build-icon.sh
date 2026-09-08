#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
source_icon="$repo_dir/assets/token-menu-icon.png"
icon_work=$(mktemp -d "${TMPDIR:-/tmp}/token-menu-icon.XXXXXX")
trap 'rm -rf "$icon_work"' EXIT
iconset="$icon_work/token-menu.iconset"
mkdir -p "$iconset"

for size in 16 32 64 128 256 512 1024; do
    sips -s format png -z "$size" "$size" "$source_icon" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
done

# macOS 26's iconutil rejects even iconsets exported by iconutil itself. Build
# the standard PNG-backed ICNS container directly so the release stays
# reproducible on current and earlier macOS toolchains.
swiftc -module-cache-path "$icon_work/module-cache" \
    "$repo_dir/scripts/make-icns.swift" -o "$icon_work/make-icns"
"$icon_work/make-icns" "$repo_dir/support/token-menu.icns" \
    icp4 "$iconset/icon_16x16.png" \
    icp5 "$iconset/icon_32x32.png" \
    icp6 "$iconset/icon_64x64.png" \
    ic07 "$iconset/icon_128x128.png" \
    ic08 "$iconset/icon_256x256.png" \
    ic09 "$iconset/icon_512x512.png" \
    ic10 "$iconset/icon_1024x1024.png"
echo "$repo_dir/support/token-menu.icns"
