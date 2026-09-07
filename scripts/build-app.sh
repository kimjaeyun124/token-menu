#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
app_name="Codex Usage"
bundle_dir="$repo_dir/dist/$app_name.app"
contents_dir="$bundle_dir/Contents"
binary_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
login_item_dir="$contents_dir/Library/LoginItems/Codex Usage Launcher.app"
login_item_contents="$login_item_dir/Contents"
login_item_binary_dir="$login_item_contents/MacOS"

cd "$repo_dir"
swift build -c "$configuration"
bin_dir=$(swift build -c "$configuration" --show-bin-path)

mkdir -p "$binary_dir" "$resources_dir" "$login_item_binary_dir"
cp "$bin_dir/CodexUsageMonitor" "$binary_dir/CodexUsageMonitor"
cp "$repo_dir/support/Info.plist" "$contents_dir/Info.plist"
cp "$bin_dir/CodexUsageLauncher" "$login_item_binary_dir/CodexUsageLauncher"
cp "$repo_dir/support/LoginItem-Info.plist" "$login_item_contents/Info.plist"
codesign --force --deep --sign - "$login_item_dir"
codesign --force --deep --sign - "$bundle_dir"

echo "$bundle_dir"
