#!/bin/sh
# Claude Code status-line bridge for Token Menu.
# The status-line JSON contains rate limits but no credentials.
set -eu

destination="${TOKEN_MENU_CLAUDE_USAGE_PATH:-$HOME/.claude/token-menu-statusline.json}"
directory=$(dirname "$destination")
mkdir -p "$directory"
temporary="$destination.tmp.$$"
trap 'rm -f "$temporary"' EXIT HUP INT TERM
cat > "$temporary"
mv "$temporary" "$destination"
printf ''
