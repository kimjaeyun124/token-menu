#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
app_path="$repo_dir/dist/Token Menu.app"
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    zsh "$repo_dir/scripts/build-app.sh"
fi
[[ -d "$app_path" ]] || { print -u2 "Build dist/Token Menu.app first."; exit 1; }
codesign --verify --deep --strict "$app_path"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
binary_archs=$(lipo -archs "$app_path/Contents/MacOS/CodexUsageMonitor")
case "$binary_archs" in
    *arm64*x86_64*|*x86_64*arm64*) architecture=universal ;;
    arm64) architecture=arm64 ;;
    x86_64) architecture=x86_64 ;;
    *) print -u2 "Unsupported app architectures: $binary_archs"; exit 1 ;;
esac

mkdir -p "$repo_dir/dist"
dmg_work=$(mktemp -d "$repo_dir/dist/.token-menu-dmg.XXXXXX")
trap 'rm -rf "$dmg_work"' EXIT
mkdir -p "$dmg_work/volume"
ditto "$app_path" "$dmg_work/volume/Token Menu.app"
ln -s /Applications "$dmg_work/volume/Applications"
cp "$repo_dir/docs/INSTALL.txt" "$dmg_work/volume/INSTALL.txt"

filename="token-menu-${version}-macOS-${architecture}.dmg"
hdiutil create -volname "Token Menu $version" -srcfolder "$dmg_work/volume" -fs HFS+ -format UDZO "$dmg_work/$filename"
hdiutil verify "$dmg_work/$filename"
mv -f "$dmg_work/$filename" "$repo_dir/dist/$filename"
(
    cd "$repo_dir/dist"
    shasum -a 256 "$filename" > "$filename.sha256"
)
echo "$repo_dir/dist/$filename"
