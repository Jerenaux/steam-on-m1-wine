#!/usr/bin/env bash
# Install the per-user LaunchAgent for update recovery and idle refresh.

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

label="com.jerome.steam-on-m1-watchdog"
agent_dir="$HOME/Library/LaunchAgents"
log_dir="$HOME/Library/Logs"
plist="$agent_dir/$label.plist"
watchdog="$REPO_ROOT/scripts/steam-watchdog.sh"
log_file="$log_dir/steam-on-m1-watchdog.log"

[[ -x "$watchdog" ]] || die "Watchdog is not executable: $watchdog"
mkdir -p "$agent_dir" "$log_dir"

cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$watchdog</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$log_file</string>
    <key>StandardErrorPath</key>
    <string>$log_file</string>
</dict>
</plist>
EOF

/usr/bin/plutil -lint "$plist" >/dev/null || die "Invalid LaunchAgent plist: $plist"

if [[ "${STEAM_WATCHDOG_SKIP_LOAD:-0}" != "1" ]]; then
    domain="gui/$(id -u)"
    /bin/launchctl bootout "$domain/$label" 2>/dev/null || true
    /bin/launchctl bootstrap "$domain" "$plist" \
        || die "Could not load LaunchAgent: $plist"
fi

log_ok "Installed Steam update-recovery watchdog (30-second interval) at $plist"
