# Steam idle refresh watchdog

## Goal

Prevent the Wine Steam client from reaching the multi-day state where its
single-process CEF web helper stops forwarding Play actions. Refresh Steam
after 24 hours, but never while a game is running.

## Design

A user LaunchAgent runs a small shell watchdog every five minutes. The
watchdog finds the Steam process belonging to the `~/.wine-steam` setup and
exits unless that process is at least 24 hours old.

Before restarting Steam, the watchdog reads the current session in Steam's
`gameprocess_log.txt`. It tracks `adding PID` and `no longer tracking PID`
events. Any unmatched tracked process means a game is active, so the refresh
is deferred until a later check.

When Steam is old and idle, the watchdog asks the existing client to shut
down, waits for it to exit, and falls back to stopping the Wine session if it
does not. It then opens `Wine Stable SteamOnM1.app`, letting the existing app
launcher recreate the Wine and Steam processes with their required
environment and Chromium-lock cleanup.

The LaunchAgent lives in `~/Library/LaunchAgents` and starts at login. It logs
only decisions and restart results to
`~/Library/Logs/steam-on-m1-watchdog.log`. Installing or updating the agent
does not restart an existing Steam session.

## Safety and failure handling

- Exact process and prefix matching prevents interference with other Wine
  applications.
- A running game always postpones the refresh.
- A lock prevents overlapping watchdog executions.
- Failed shutdown or relaunch attempts are logged and retried at the next
  scheduled check.
- The 24-hour threshold is configurable through an environment variable for
  tests and troubleshooting; the installed default remains 24 hours.

## Verification

Shell tests use temporary fixture logs and injected process metadata. They
cover a young Steam session, an old idle session, an old session with one or
more active games, and a later game-exit event that permits refresh. An
installation check validates the generated property list with `plutil`.

