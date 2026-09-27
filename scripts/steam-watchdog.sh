#!/usr/bin/env bash
# Refresh a stale Wine Steam session once it is old and no game is running.

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

STEAM_WATCHDOG_MAX_AGE_SECONDS=${STEAM_WATCHDOG_MAX_AGE_SECONDS:-86400}
STEAM_GAMEPROCESS_LOG=${STEAM_GAMEPROCESS_LOG:-$WINEPREFIX/drive_c/Program Files (x86)/Steam/logs/gameprocess_log.txt}
STEAM_EXE="$WINEPREFIX/drive_c/Program Files (x86)/Steam/Steam.exe"
STEAM_WATCHDOG_LOCK=${STEAM_WATCHDOG_LOCK:-${TMPDIR:-/tmp}/steam-on-m1-watchdog.lock}

elapsed_to_seconds() {
    local elapsed=$1 days=0 hours=0 minutes=0 seconds=0
    if [[ "$elapsed" == *-* ]]; then
        days=${elapsed%%-*}
        elapsed=${elapsed#*-}
    fi

    local first second third
    IFS=: read -r first second third <<<"$elapsed"
    if [[ -n "${third:-}" ]]; then
        hours=$first
        minutes=$second
        seconds=$third
    else
        minutes=$first
        seconds=$second
    fi

    printf '%s\n' $((10#$days * 86400 + 10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds))
}

# Return 0 when the current Steam client session has a tracked game process,
# 1 when it is known to be idle, and 2 when the log cannot establish state.
current_session_has_game() {
    local log_file=$1
    [[ -r "$log_file" ]] || return 2

    awk '
        /Client version:/ {
            for (key in active) delete active[key]
            saw_session = 1
            next
        }
        saw_session && /AppID [0-9]+ adding PID [0-9]+/ {
            line = $0
            sub(/^.*AppID /, "", line)
            split(line, fields, " ")
            active[fields[1] ":" fields[4]] = 1
            next
        }
        saw_session && /AppID [0-9]+ no longer tracking PID [0-9]+/ {
            line = $0
            sub(/^.*AppID /, "", line)
            split(line, fields, " ")
            sub(/[^0-9].*$/, "", fields[6])
            delete active[fields[1] ":" fields[6]]
            next
        }
        END {
            if (!saw_session) exit 2
            for (key in active) exit 0
            exit 1
        }
    ' "$log_file"
}

find_steam_process() {
    local pid elapsed command
    while read -r pid elapsed command; do
        case "$command" in
            'C:\Program Files (x86)\Steam\Steam.exe'*)
                printf '%s %s\n' "$pid" "$elapsed"
                return 0
                ;;
        esac
    done < <(ps -axo pid=,etime=,command=)
    return 1
}

watchdog_log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >&2
}

main() {
    local process_info steam_pid elapsed age game_state=0

    if ! /usr/bin/shlock -f "$STEAM_WATCHDOG_LOCK" -p $$; then
        return 0
    fi
    trap 'rm -f "$STEAM_WATCHDOG_LOCK"' EXIT

    process_info=$(find_steam_process || true)
    [[ -n "$process_info" ]] || return 0
    read -r steam_pid elapsed <<<"$process_info"
    age=$(elapsed_to_seconds "$elapsed")
    (( age >= STEAM_WATCHDOG_MAX_AGE_SECONDS )) || return 0

    current_session_has_game "$STEAM_GAMEPROCESS_LOG" || game_state=$?
    case "$game_state" in
        0)
            watchdog_log "Steam is ${age}s old; refresh deferred because a game is running"
            return 0
            ;;
        1) ;;
        *)
            watchdog_log "Steam is ${age}s old; refresh deferred because game state is unknown"
            return 0
            ;;
    esac

    if [[ "${STEAM_WATCHDOG_DRY_RUN:-0}" == "1" ]]; then
        watchdog_log "Steam is ${age}s old and idle; dry run would refresh it"
        return 0
    fi

    watchdog_log "Steam is ${age}s old and idle; refreshing the session"
    WINEPREFIX="$WINEPREFIX" WINEDEBUG=-all /usr/bin/arch -x86_64 \
        "$WINE_BIN" "$STEAM_EXE" -shutdown >/dev/null 2>&1 &

    local attempts=0
    while kill -0 "$steam_pid" 2>/dev/null && (( attempts < 30 )); do
        sleep 1
        attempts=$((attempts + 1))
    done

    if kill -0 "$steam_pid" 2>/dev/null; then
        watchdog_log "Steam did not exit cleanly; stopping this Wine prefix"
        WINEPREFIX="$WINEPREFIX" "$WINESERVER_BIN" -k >/dev/null 2>&1 || true
        sleep 3
    fi

    if kill -0 "$steam_pid" 2>/dev/null; then
        watchdog_log "Steam still has not exited; refresh will retry later"
        return 1
    fi

    /usr/bin/open -na "$WINE_APP"
    watchdog_log "Steam relaunch requested"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
