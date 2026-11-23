#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
watchdog="$repo_root/scripts/steam-watchdog.sh"

[[ -f "$watchdog" ]] || {
    printf 'missing watchdog: %s\n' "$watchdog" >&2
    exit 1
}

# shellcheck source=../scripts/steam-watchdog.sh
source "$watchdog"

[[ "$(elapsed_to_seconds 03:04)" == "184" ]]
[[ "$(elapsed_to_seconds 02:03:04)" == "7384" ]]
[[ "$(elapsed_to_seconds 2-02:03:04)" == "180184" ]]

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/steam-watchdog-test.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

idle_log="$tmp_dir/idle.log"
active_log="$tmp_dir/active.log"
exited_log="$tmp_dir/exited.log"
multi_log="$tmp_dir/multi.log"

cat >"$idle_log" <<'EOF'
[2026-09-27 14:09:38] Client version: 1788652215
[2026-09-27 14:09:38] SSGL: UI mode (0->7)
EOF

cat >"$active_log" <<'EOF'
[2026-09-25 16:52:05] AppID 1709900 no longer tracking PID 1680, exit code 0
[2026-09-27 14:09:38] Client version: 1788652215
[2026-09-27 14:11:03] AppID 1709900 adding PID 1020 as a tracked process "game.exe"
EOF

cat >"$exited_log" <<'EOF'
[2026-09-27 14:09:38] Client version: 1788652215
[2026-09-27 14:11:03] AppID 1709900 adding PID 1020 as a tracked process "game.exe"
[2026-09-27 15:11:03] AppID 1709900 no longer tracking PID 1020, exit code 0
EOF

cat >"$multi_log" <<'EOF'
[2026-09-27 14:09:38] Client version: 1788652215
[2026-09-27 14:11:03] AppID 1709900 adding PID 1020 as a tracked process "game.exe"
[2026-09-27 14:12:03] AppID 1709900 adding PID 1021 as a tracked process "helper.exe"
[2026-09-27 15:11:03] AppID 1709900 no longer tracking PID 1020, exit code 0
EOF

if current_session_has_game "$idle_log"; then
    printf 'idle session was incorrectly reported active\n' >&2
    exit 1
fi
current_session_has_game "$active_log"
if current_session_has_game "$exited_log"; then
    printf 'exited game was incorrectly reported active\n' >&2
    exit 1
fi
current_session_has_game "$multi_log"

printf 'Steam watchdog decision checks passed\n'

install_home="$tmp_dir/home"
mkdir -p "$install_home"
HOME="$install_home" STEAM_WATCHDOG_SKIP_LOAD=1 \
    bash "$repo_root/scripts/11-install-watchdog.sh"

plist="$install_home/Library/LaunchAgents/com.jerome.steam-on-m1-watchdog.plist"
[[ -f "$plist" ]]
/usr/bin/plutil -lint "$plist" >/dev/null
grep -Fq '<integer>30</integer>' "$plist"
grep -Fq "$repo_root/scripts/steam-watchdog.sh" "$plist"

printf 'Steam watchdog installation checks passed\n'
