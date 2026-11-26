#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
source "$repo_root/scripts/steam-watchdog.sh"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/steam-update-test.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT
REPO_ROOT="$tmp_dir/repo"
WINEPREFIX="$tmp_dir/prefix"
STEAM_EXE="$WINEPREFIX/drive_c/Program Files (x86)/Steam/Steam.exe"
STEAM_GAMEPROCESS_LOG="$WINEPREFIX/drive_c/Program Files (x86)/Steam/logs/gameprocess_log.txt"
bootstrap_log="$(dirname "$STEAM_GAMEPROCESS_LOG")/bootstrap_log.txt"
helper="$WINEPREFIX/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64/steamwebhelper.exe"
mkdir -p "$REPO_ROOT/wrapper" "$(dirname "$helper")" "$(dirname "$bootstrap_log")"
printf 'compatibility wrapper' > "$REPO_ROOT/wrapper/steamwebhelper.exe"
cp "$REPO_ROOT/wrapper/steamwebhelper.exe" "$helper"
if steam_wrapper_needs_repair; then echo 'Healthy wrapper reported broken' >&2; exit 1; fi
printf 'Valve update' > "$helper"
steam_wrapper_needs_repair

printf 'Installing update...\n' > "$bootstrap_log"
steam_update_in_progress "$bootstrap_log"
printf 'Update complete, launching Steam...\nStartup - Steam Client launched\n' >> "$bootstrap_log"
if steam_update_in_progress "$bootstrap_log"; then echo 'Completed update still blocked' >&2; exit 1; fi

# Identical Windows paths from another prefix must not match this session.
ps() {
    printf '%s\n' '10 00:05 /Applications/Steam.app/Contents/MacOS/steam_osx' \
        '20 00:05 C:\Program Files (x86)\Steam\steam.exe' \
        '30 00:05 C:\Program Files (x86)\Steam\steam.exe'
}
lsof() { [[ "$*" == "-a -p 30 -t $STEAM_EXE" ]]; }
[[ "$(find_steam_process)" == '30 00:05' ]]
unset -f ps lsof

# A helper in another Wine prefix must not count as this Steam UI.
helper_real="$(dirname "$helper")/steamwebhelper_real.exe"
touch "$helper_real"
lsof() { [[ "$*" == "-t $helper_real" ]]; }
steam_webhelper_running
lsof() { return 1; }
if steam_webhelper_running; then echo 'Missing interface reported healthy' >&2; exit 1; fi
unset -f lsof

# Exercise the watchdog's decisions without stopping or opening any real app.
find_steam_process() { printf '30 00:05\n'; }
steam_webhelper_running() { return 0; }
STEAM_WATCHDOG_LOCK="$tmp_dir/watchdog.lock"
STEAM_WATCHDOG_DRY_RUN=1
printf 'Client version: test\n' > "$STEAM_GAMEPROCESS_LOG"
( main ) 2> "$tmp_dir/decision"
grep -q 'dry run would refresh' "$tmp_dir/decision"

printf 'Installing update...\n' >> "$bootstrap_log"
( main ) 2> "$tmp_dir/decision"
grep -q 'deferred while Steam installs an update' "$tmp_dir/decision"
printf 'Update complete, launching Steam...\n' >> "$bootstrap_log"

printf 'AppID 123 adding PID 456 as a tracked process "game.exe"\n' >> "$STEAM_GAMEPROCESS_LOG"
( main ) 2> "$tmp_dir/decision"
grep -q 'deferred because a game is running' "$tmp_dir/decision"

: > "$STEAM_GAMEPROCESS_LOG"
( main ) 2> "$tmp_dir/decision"
grep -q 'deferred because game state is unknown' "$tmp_dir/decision"

printf 'Client version: test\n' > "$STEAM_GAMEPROCESS_LOG"
cp "$REPO_ROOT/wrapper/steamwebhelper.exe" "$helper"
( main ) 2> "$tmp_dir/decision"
[[ ! -s "$tmp_dir/decision" ]]

steam_webhelper_running() { return 1; }
( main ) 2> "$tmp_dir/decision"
[[ ! -s "$tmp_dir/decision" ]] # Do not interrupt a client that is still starting.
find_steam_process() { printf '30 02:00\n'; }
( main ) 2> "$tmp_dir/decision"
grep -q 'interface process is not running and idle; dry run would refresh' "$tmp_dir/decision"
printf 'AppID 123 adding PID 456 as a tracked process "game.exe"\n' >> "$STEAM_GAMEPROCESS_LOG"
( main ) 2> "$tmp_dir/decision"
grep -q 'deferred because a game is running' "$tmp_dir/decision"
echo 'Steam update recovery and prefix-isolation checks passed'
