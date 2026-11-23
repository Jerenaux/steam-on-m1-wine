#!/usr/bin/env bash
# Recover an overwritten web helper or refresh an old, idle Wine Steam session.

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

STEAM_WATCHDOG_MAX_AGE_SECONDS=${STEAM_WATCHDOG_MAX_AGE_SECONDS:-86400}
STEAM_GAMEPROCESS_LOG=${STEAM_GAMEPROCESS_LOG:-$WINEPREFIX/drive_c/Program Files (x86)/Steam/logs/gameprocess_log.txt}
STEAM_EXE="$WINEPREFIX/drive_c/Program Files (x86)/Steam/Steam.exe"
STEAM_WATCHDOG_LOCK=${STEAM_WATCHDOG_LOCK:-${TMPDIR:-/tmp}/steam-on-m1-watchdog.lock}

steam_wrapper_needs_repair() {
    local reference="$REPO_ROOT/wrapper/steamwebhelper.exe" helper
    [[ -f "$reference" ]] || return 1
    for helper in "$WINEPREFIX/drive_c/Program Files (x86)/Steam/bin/cef/"cef.win*/steamwebhelper.exe; do
        [[ -f "$helper" ]] || continue
        cmp -s "$reference" "$helper" || return 0
    done
    return 1
}

steam_update_in_progress() {
    local log_file=$1
    [[ -r "$log_file" ]] || return 1
    awk '
        /Installing update\.\.\./ { updating = 1 }
        /Update complete, launching Steam|Startup - Steam Client launched/ { updating = 0 }
        END { exit !updating }
    ' "$log_file"
}

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
            'C:\Program Files (x86)\Steam\Steam.exe'*|'C:\Program Files (x86)\Steam\steam.exe'*)
                # Wine command lines look identical across prefixes; check the mapped executable.
                lsof -a -p "$pid" -t "$STEAM_EXE" >/dev/null 2>&1 || continue
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
    local process_info steam_pid elapsed age game_state=0 reason

    if ! /usr/bin/shlock -f "$STEAM_WATCHDOG_LOCK" -p $$; then
        return 0
    fi
    trap 'rm -f "$STEAM_WATCHDOG_LOCK"' EXIT

    process_info=$(find_steam_process || true)
    [[ -n "$process_info" ]] || return 0
    read -r steam_pid elapsed <<<"$process_info"
    age=$(elapsed_to_seconds "$elapsed")
    if steam_wrapper_needs_repair; then
        reason="Steam update replaced the compatibility web helper"
    elif (( age >= STEAM_WATCHDOG_MAX_AGE_SECONDS )); then
        reason="Steam session is ${age}s old"
    else
        return 0
    fi

    if steam_update_in_progress "$WINEPREFIX/drive_c/Program Files (x86)/Steam/logs/bootstrap_log.txt"; then
        watchdog_log "$reason; recovery deferred while Steam installs an update"
        return 0
    fi

    current_session_has_game "$STEAM_GAMEPROCESS_LOG" || game_state=$?
    case "$game_state" in
        0)
            watchdog_log "$reason; recovery deferred because a game is running"
            return 0
            ;;
        1) ;;
        *)
            watchdog_log "$reason; recovery deferred because game state is unknown"
            return 0
            ;;
    esac

    if [[ "${STEAM_WATCHDOG_DRY_RUN:-0}" == "1" ]]; then
        watchdog_log "$reason and idle; dry run would refresh it"
        return 0
    fi

    local launcher="${INSTALL_APP_DIR:-$HOME/Applications}/Steam on M1 Wine.app"
    [[ -d "$launcher" ]] || { watchdog_log "Steam launcher is missing: $launcher"; return 1; }
    watchdog_log "$reason and idle; restarting through the compatibility launcher"
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

    /usr/bin/open -n "$launcher"
    watchdog_log "Steam relaunch requested"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
