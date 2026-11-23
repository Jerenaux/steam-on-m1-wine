#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
launch_script="$repo_root/scripts/launch-steam.sh"
app_installer="$repo_root/scripts/09-install-macos-app.sh"

grep -Fq '"${1:-}" == "--foreground"' "$launch_script"
grep -Fq 'nohup /usr/bin/script -q /dev/null /usr/bin/arch -x86_64 "$WINE_BIN"' "$launch_script"
grep -Fq 'wait "$steam_host_pid"' "$launch_script"
grep -Fq 'scripts/launch-steam.sh" --foreground' "$app_installer"
grep -Fq 'WINEPREFIX="$WINEPREFIX" "$WINESERVER_BIN" -k' "$launch_script"
grep -Fq -- '-iname "*.lock"' "$launch_script"

echo "macOS app foreground launch regression check passed"
