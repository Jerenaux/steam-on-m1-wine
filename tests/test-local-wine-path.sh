#!/usr/bin/env bash
set -euo pipefail

unset WINE_APP WINE_BIN WINESERVER_BIN
source "$(dirname "$0")/../scripts/lib/common.sh"

expected_app="$HOME/Applications/Wine Stable SteamOnM1.app"
expected_wine="$expected_app/Contents/Resources/wine/bin/wine"
expected_wineserver="$expected_app/Contents/Resources/wine/bin/wineserver"

[[ "$WINE_APP" == "$expected_app" ]] || {
    printf 'expected WINE_APP=%s, got %s\n' "$expected_app" "$WINE_APP" >&2
    exit 1
}
[[ "$WINE_BIN" == "$expected_wine" ]] || {
    printf 'expected WINE_BIN=%s, got %s\n' "$expected_wine" "$WINE_BIN" >&2
    exit 1
}
[[ "$WINESERVER_BIN" == "$expected_wineserver" ]] || {
    printf 'expected WINESERVER_BIN=%s, got %s\n' "$expected_wineserver" "$WINESERVER_BIN" >&2
    exit 1
}
