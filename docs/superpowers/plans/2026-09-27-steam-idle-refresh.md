# Steam Idle Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Install a macOS user LaunchAgent that refreshes Wine Steam after 24 hours only when Steam has no tracked game process.

**Architecture:** A sourceable Bash watchdog contains the age and Steam-log state checks and performs the refresh only from its main entry point. A separate installer writes and loads a user LaunchAgent that runs the watchdog every five minutes.

**Tech Stack:** Bash 3.2, macOS `launchd`, `ps`, `awk`, Wine's `wineserver`, and shell fixture tests.

---

### Task 1: Watchdog decision logic

**Files:**
- Create: `scripts/steam-watchdog.sh`
- Create: `tests/test-steam-watchdog.sh`

- [x] **Step 1: Write the failing test**

Create fixtures for current Steam sessions with no game, an active tracked PID,
and a tracked PID that later exits. Assert that `elapsed_to_seconds` parses
`HH:MM:SS` and `D-HH:MM:SS`, and that `current_session_has_game` returns true
only for the active fixture.

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test-steam-watchdog.sh`
Expected: FAIL because `scripts/steam-watchdog.sh` does not exist.

- [x] **Step 3: Write minimal implementation**

Implement:

```bash
elapsed_to_seconds() { ...; }
current_session_has_game() { awk '...'; }
find_steam_process() { ps -axo pid=,etime=,command= | awk '...'; }
```

The main path exits for no Steam process, a session younger than
`${STEAM_WATCHDOG_MAX_AGE_SECONDS:-86400}`, or an active game. For an old idle
session it sends `Steam.exe -shutdown`, waits up to 30 seconds, calls the
prefix-specific `wineserver -k` only if needed, then runs
`open -na "$WINE_APP"`.

- [x] **Step 4: Run test to verify it passes**

Run: `bash tests/test-steam-watchdog.sh`
Expected: `Steam watchdog decision checks passed`.

### Task 2: LaunchAgent installer

**Files:**
- Create: `scripts/11-install-watchdog.sh`
- Extend: `tests/test-steam-watchdog.sh`
- Modify: `install.sh`

- [x] **Step 1: Add a failing installation test**

Run the installer with a temporary `HOME` and
`STEAM_WATCHDOG_SKIP_LOAD=1`, then assert that the property list exists,
contains a 300-second `StartInterval`, and passes `plutil -lint`.

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test-steam-watchdog.sh`
Expected: FAIL because `scripts/11-install-watchdog.sh` does not exist.

- [x] **Step 3: Implement and wire the installer**

Write `~/Library/LaunchAgents/com.jerome.steam-on-m1-watchdog.plist` with the
absolute watchdog path, `RunAtLoad`, `StartInterval=300`, and log paths under
`~/Library/Logs`. Reload an existing job using `launchctl bootout/bootstrap`.
Add the installer as the final `install.sh` step.

- [x] **Step 4: Run the focused and repository tests**

Run: `bash tests/test-steam-watchdog.sh && for t in tests/test-*.sh; do bash "$t"; done`
Expected: all checks exit zero.

### Task 3: Install and verify locally

**Files:**
- Install: `~/Library/LaunchAgents/com.jerome.steam-on-m1-watchdog.plist`

- [x] **Step 1: Install without restarting Steam**

Run: `bash scripts/11-install-watchdog.sh`
Expected: the agent bootstraps and its first check exits without refresh.

- [x] **Step 2: Verify the loaded schedule and live safety decision**

Run `launchctl print gui/$(id -u)/com.jerome.steam-on-m1-watchdog`, validate the
plist with `plutil`, and run the watchdog with a zero age threshold while the
current game is active.
Expected: LaunchAgent interval is 300 seconds and the forced-age check logs
that refresh was deferred because a game is running.

