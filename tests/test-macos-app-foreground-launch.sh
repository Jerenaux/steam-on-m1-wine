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

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/prefix/drive_c/windows" "$scratch/prefix/drive_c/Program Files (x86)/Steam"
touch "$scratch/prefix/drive_c/Program Files (x86)/Steam/Steam.exe"
chmod +x "$scratch/prefix/drive_c/Program Files (x86)/Steam/Steam.exe"
cat >"$scratch/wineserver" <<'SH'
#!/bin/bash
case "$1" in
    -k) exit "${STOP_STATUS:-1}" ;;
    -w) exit "${WAIT_STATUS:-0}" ;;
esac
SH
cat >"$scratch/wine" <<'SH'
#!/bin/bash
echo 'Steam launch reached'
SH
chmod +x "$scratch/wine" "$scratch/wineserver"

export WINE_BIN="$scratch/wine" WINESERVER_BIN="$scratch/wineserver"
export WINEPREFIX="$scratch/prefix" WINE_VIRTUAL_DESKTOP=""
export STEAM_LAUNCH_LOG="$scratch/steam.log"
for STOP_STATUS in 0 1; do
    export STOP_STATUS
    bash "$launch_script" --foreground >"$scratch/launcher.log" 2>&1
    grep -Fq 'Steam launch reached' "$STEAM_LAUNCH_LOG"
done
export STOP_STATUS=2
if bash "$launch_script" --foreground >"$scratch/launcher.log" 2>&1; then
    echo 'Launcher ignored an unexpected wineserver failure' >&2
    exit 1
fi
grep -Fq 'Could not stop the Steam Wine prefix' "$scratch/launcher.log"
export STOP_STATUS=1 WAIT_STATUS=1
if bash "$launch_script" --foreground >"$scratch/launcher.log" 2>&1; then
    echo 'Launcher ignored a wineserver wait failure' >&2
    exit 1
fi
grep -Fq 'Could not wait for the Steam Wine prefix to stop' "$scratch/launcher.log"

echo "macOS app foreground launch regression check passed"
