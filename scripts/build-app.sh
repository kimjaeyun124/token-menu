#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
app_name="Token Menu"
bundle_dir="$repo_dir/dist/$app_name.app"
contents_dir="$bundle_dir/Contents"
binary_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
login_item_dir="$contents_dir/Library/LoginItems/Token Menu Launcher.app"
login_item_contents="$login_item_dir/Contents"
login_item_binary_dir="$login_item_contents/MacOS"

cd "$repo_dir"
architecture="${ARCHITECTURE:-universal}"
case "$architecture" in
    universal) architectures=(arm64 x86_64) ;;
    arm64|x86_64) architectures=("$architecture") ;;
    *) print -u2 "ARCHITECTURE must be universal, arm64, or x86_64"; exit 1 ;;
esac
sandbox_args=()
if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    sandbox_args+=(--disable-sandbox)
fi
# Build each slice with SwiftPM's native build system so resource catalogs stay
# available to the app's existing localization loader, then merge executables.
app_binaries=()
launcher_binaries=()
for target_architecture in "${architectures[@]}"; do
    swift build -c "$configuration" --arch "$target_architecture" "${sandbox_args[@]}"
    bin_dir=$(swift build -c "$configuration" --arch "$target_architecture" "${sandbox_args[@]}" --show-bin-path)
    app_binaries+=("$bin_dir/CodexUsageMonitor")
    launcher_binaries+=("$bin_dir/CodexUsageLauncher")
done
zsh "$repo_dir/scripts/build-icon.sh"

mkdir -p "$binary_dir" "$resources_dir" "$login_item_binary_dir"
lipo -create "${app_binaries[@]}" -output "$binary_dir/CodexUsageMonitor"
resource_bundle="$bin_dir/CodexUsageMonitor_CodexUsageMonitor.bundle"
if [[ -d "$resource_bundle" ]]; then
    ditto "$resource_bundle" "$resources_dir/${resource_bundle:t}"
fi
cp "$repo_dir/support/Info.plist" "$contents_dir/Info.plist"
cp "$repo_dir/support/token-menu.icns" "$resources_dir/token-menu.icns"
lipo -create "${launcher_binaries[@]}" -output "$login_item_binary_dir/CodexUsageLauncher"
cp "$repo_dir/support/LoginItem-Info.plist" "$login_item_contents/Info.plist"
codesign --force --deep --sign - "$login_item_dir"
codesign --force --deep --sign - "$bundle_dir"
codesign --verify --deep --strict "$bundle_dir"

echo "$bundle_dir"
