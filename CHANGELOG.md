# Changelog

All notable changes to GSI Flash Tool are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/).

## [Unreleased]

_(nothing yet)_

## [1.1.2] — 2026-10-24

- **Hotfix.** CLI argument parsing parity between platforms. No new features.

### Fixed
- **Linux: unknown CLI flags were silently ignored.** A typo like
  `--strcit-versions` (or any unrecognized flag) was treated as "no flag"
  and the script ran in normal mode. Now an unknown flag prints an error
  and exits with code 1.
- **Linux: Windows-style flags were rejected.** `-Version`, `-Help`,
  `-Lang=`, `-Serial=`, `-StrictVersions` now work in bash just like in
  PowerShell (previously only the `--` / short forms were recognized,
  despite what README implied).
- **`--lang` / `--serial` parsing simplified.** Value extraction now
  uses `${arg#*=}` (works for both `-Flag=value` and `--flag=value`).

## [1.1.1] — 2026-10-23

- **Hotfix.** Review-driven safety and correctness fixes. No new features.

### Fixed
- **Slot selection broken on Linux.** `sanitize_choice` stripped non-digits, so
  "flash to specified slot" always fell back to the current slot.
- **`local` outside a function** in the Linux main loop (switch-slot menu
  printed an error every time).
- **Ctrl+C protection actually implemented (Linux).** `trap` on INT refuses
  interruption while `super` reconstruction (delete/create logical partitions)
  is in progress. README previously claimed this existed — it did not.
- **vbmeta flashed before any verification (Windows & Linux).** Split into
  prepare/flash stages: SHA256 verification and the user's final confirmation
  now run before vbmeta is touched. All confirmations moved into the
  bootloader (before the fastbootd reboot), since vbmeta is a physical
  partition.
- **tar `--exclude` probe never matched on Windows** (`$?` was interpolated
  into the probe string) and ran a full `/data` scan on both platforms. Now
  checked via `tar --help`.
- **7z unpacked into CWD instead of the image's folder** (`Resolve-SystemImage`).
- **Linux: images searched in CWD** while logs went to the script dir — the
  script now `cd`s to its own directory; build hash only taken from the tool's
  own repo.
- `erase cache` only on non-A/B devices; `set_active` result checked; `devices`
  propagates `-s <serial>`; `init_boot` excluded from GSI candidates;
  `Get-SlotCount` cast hardened.
- **`set_active` failure now aborts before `reboot`** (both platforms).
  Previously the device rebooted into a slot whose `system` had just been
  deleted — guaranteed bootloop on MTK.
- **`.cmd` pauses only on error.** Success paths already pause inside the
  script (no double pause); main-menu exit pauses once inside the script.
- **Linux slot prompt re-asks on invalid input** instead of silently falling
  back to the current slot.

## [1.1.0] — 2026-10-15

- **Minor release.** Two new features plus accumulated backlog cleanup.
  Codeberg is now the primary repository.

### Added
- **`-Admin` flag (Windows).** `gsi-tool.ps1 -Admin` (or `gsi-tool.cmd -Admin`)
  self-relaunches via UAC if not already elevated. Useful when `logs/` needs
  admin rights (e.g. script placed under `C:\Program Files\`). All other
  CLI flags (`-Lang`, `-Serial`, `-StrictVersions`) are forwarded to the
  elevated instance.
- **Windows Terminal detection in `.cmd`.** If `wt.exe` is present, the
  launcher runs the script inside Windows Terminal (nicer resize, tabs,
  Unicode). Falls back to plain `powershell.exe` otherwise.
- **Critical partitions backup (both platforms).** New service menu item:
  reads `nvram`, `persist`, `modemst1`, `modemst2`, `fsg`, `fsc`, `misc`,
  `bluetooth`, `oem` via `adb exec-out dd | gzip`. Requires root
  (`adb shell id` → `uid=0`). Output:
  `backups/partitions_YYYYMMDD_HHMMSS/<name>.img.gz` + `metadata.txt`
  with sizes and SHA256 hashes. Missing partitions are skipped with a
  warning; zero-byte or failed reads are cleaned up.

### Changed
- **Version bumped 1.0.3 → 1.1.0.**
- **Primary repository moved to Codeberg** (https://codeberg.org/godflesh-77/gsi-tool).
  GitHub (`godflesh-77/gsi-tool`) is now a read-only push-mirror.
- **README: new "Related documents" section** with links to localised
  CHANGELOG / ROADMAP / TODO.
- **macOS support removed from roadmap** — no practical demand.

## [1.0.3] — 2026-10-10

- **Hotfix (Linux).** Found in 1.0.2: the menu did not respond to input —
  items 0-6 fell through `case` without matching, and the script looped on
  redrawing the menu. Also a spurious 7-Zip warning and relative-path logs.

### Fixed
- **Critical (Linux): menu did not match user choice.**
  Cause: `c=$(show_main_menu)` captured stdout of `show_main_menu`, which
  started with `clear`. `clear` writes ANSI escape sequences (`\e[H\e[2J`)
  to stdout → they landed in `$c` before the digit. `case` saw
  `"\e[H\e[2J...1"` instead of `"1"` and matched **no** branch. Item 0
  did not exit, item 6 did not open the service menu, item 1 did not
  print devices.
  Fix: menus no longer captured via `$( )` — they write choice into global
  `MENU_CHOICE`, caller reads it. Plus helper `sanitize_choice` strips
  CR/ESC/non-printables and keeps the first digit (defends against CRLF
  terminals and dirty input). Same fix applied to `show_action_menu` and
  `show_service_menu`.
- **Medium (Linux): 7-Zip version unknown = spurious warning.**
  `check_tool_versions` parsed 7z version via `7z 2>/dev/null | ...`, but
  many 7z builds print the banner to **stderr**. Result: version not
  recognized, script showed a warning + required confirm. Fix: `2>&1`.
  Also — on Linux 7z is **optional**, so "version unknown" no longer
  counts as a problem (does not affect `--strict-versions`).
- **Medium (Linux): `logs/` and `backups/` were created relative to CWD.**
  Running `bash /path/to/gsi-tool.sh` from another directory sent the log
  to `./logs/` of the **current** folder instead of next to the script.
  Windows version has no such problem (`$PSScriptRoot` is absolute).
  Fix: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` at the
  top of the script; `LOG_DIR` and `backup_dir` are now anchored to it.

### Changed
- **Version bumped 1.0.2 → 1.0.3.** `TOOL_VERSION` in `.sh` / `.ps1`,
  `.cmd` header, `title`.
- **`.sh`: new helper `sanitize_choice`** — single point for cleaning user
  input across all menus and file-selects.
- **`.sh`: global `MENU_CHOICE`** — instead of capturing function output
  via `$( )`.

## [1.0.2] — 2026-10-09

- **Patch release.** Closes 4 defects in the `/data` backup pipeline found
  during the 1.0.1 audit. Errors were silent — the script reported
  "Backup OK" on truncated archives. No new features.

### Fixed
- **Critical (PowerShell): `Backup-DataStream` did not check `adb.ExitCode`.**
  Scenario: phone disconnects mid-stream → `adb exec-out` dies → `.Read()`
  returns 0 → `7z` receives EOF, packs what it got and returns
  `ExitCode = 0`. Script printed `Backup OK` on a truncated archive.
  Fix: `if ($adbRc -ne 0 -or $szRc -ne 0)` → `BackupFailed` + remove the
  broken archive (`Remove-Item -Force`).
- **Critical (PowerShell): handle leak on backup failure.**
  In `catch`, `.Kill()` was called without `.Dispose()`. Repeated failures
  accumulated unreleased process handles. Fix: `.Dispose()` called in the
  success branch (right after reading `ExitCode`) and in `catch` (after
  `Kill`, regardless of its success).
- **Critical (Linux): `PIPESTATUS[0]` checked only `adb`, not `lz4`/`gzip`.**
  Scenario: PC runs out of space → `lz4` fails → `PIPESTATUS[1] -ne 0` is
  ignored, script reads `PIPESTATUS[0]` (`adb`, OK) and prints `Backup OK`
  on an empty/broken file. Fix: capture the full `PIPESTATUS` array
  **immediately after the pipe** (bare assignment, no `local`, so it does
  not reset the values), check both rcs; `rm -f` the broken archive on any
  failure.
- **Medium (Linux): 0-byte archive was not removed.** If `adb` finished
  fine but `tar` on the device returned an empty stream, a zero-size file
  remained. Fix: explicit `stat -c%s` check and `rm -f` on zero. Plus
  parity with the Windows version (same defensive check added there).

### Changed
- **Version bumped 1.0.1 → 1.0.2.** `TOOL_VERSION` in `.sh` / `.ps1`,
  `.cmd` header, `title`.
- **`.ps1`: `Invoke-Fb` / `Invoke-Adb` — `.Dispose()` after reading
  `ExitCode`** (not only in the timeout branch). Releases handles on the
  normal path.
- **`.sh`: `rc_array` instead of a single `rc`** — to preserve the full
  `PIPESTATUS` across both branches (lz4/gzip).

## [1.0.1] — 2026-10-09

- **Fix release.** Closes bugs found while re-reading 1.0.0. Plus trivial
  improvements deferred earlier: unified headers, IMEI/MAC/Widevine warning,
  `pv` decompression progress. No new major features.

### Added
- **Unified headers for `.sh` / `.ps1` / `.cmd`.** Single format: name,
  version, platform, purpose, repository URL, license.
- **IMEI / MAC / Widevine warning during `/data` backup** (both
  platforms). After the main `BackupWarning`, two lines are printed:
  `/data` backup does NOT include IMEI, Wi-Fi/BT MAC, or Widevine keys —
  they live in `/persist`, `/nvram`, `/modemst*`, `/misc`. New i18n
  keys: `BackupCriticalWarn`, `BackupCriticalHint`.
- **`pv` decompression progress bar on Linux.** New helper
  `decompress_with_progress` wraps `unxz` / `gunzip` / `zstd` in a pipe
  with `pv -s <size>` (percent + ETA + speed). Shown only if `pv` is
  installed and `stderr` is a terminal. On decompressor failure the
  temporary file is removed (`rm -f "$out"`), so no gigabyte-sized
  fragments are left behind. New key `UnpackProgress`.

### Fixed
- **Critical (PowerShell): `Get-FastbootVar` did not pass `-s Serial`.**
  With two connected devices, `current-slot`, `slot-count`, `unlocked`,
  `secure`, `get_unlock_ability`, `is-userspace` went to a random device.
  `Test-BootloaderUnlocked`, `Get-CurrentSlot`, `Get-SlotCount`,
  `Test-Userspace` worked on the wrong device.
  Fix: build `@('-s', $Serial, 'getvar', $name)` and invoke via array
  splatting.
- **Critical (PowerShell): `Wait-Adb` / `Wait-Fastboot` did not pass `-s Serial`.**
  The wait loop could see a foreign device and return `$true` prematurely
  — all subsequent commands went to the wrong target.
  Fix: shared helpers `Get-AdbDevices` / `Get-FastbootDevices` that build
  arguments with `-s`.
- **Important (both): `Test-ToolVersions` did not increment the problem
  counter on "version unknown".** As a result, `-StrictVersions` /
  `--strict-versions` missed the case "adb present but version unparsable"
  (new numbering, localized output, custom build). Fix: `$problems++` in
  both "unknown" branches (adb, fastboot, 7-Zip, zstd on Linux).
- **Important (Linux): `backup_data_stream` had no timeout.** In `.ps1`
  `BACKUP_TIMEOUT=3600` existed; in `.sh` — not. If `adb exec-out` hung
  mid-stream (USB driver, drive disconnected), `pv` and `lz4` waited
  forever. Fix: `BACKUP_TIMEOUT=3600` + `timeout` around `adb`;
  distinguish rc=124 (timeout) from other non-zeros.
- **Important (Linux): `tar --exclude` probe could not distinguish "tar
  doesn't support it" from "adb died".** On adb loss, the probe returned
  empty `pout`, script went to "full backup", which failed with an unclear
  error. Fix: echo-marker `ADB_OK` in the probe, separate hard-fail on adb
  loss.
- **Medium (Linux): `resolve_system_image` logged decompression errors
  only to the file (`log_err`), did not show them to the user.** In `.ps1`
  the branches already showed `Say 'UnpackFailed'`; in `.sh` — not. Fix:
  `tf UnpackFailed ... >&2` in every branch.

### Changed
- **Version bumped 1.0.0 → 1.0.1.** `TOOL_VERSION` in `.sh` / `.ps1`,
  `.cmd` header, `title`.
- **`.ps1`: added helpers `Get-AdbDevices` / `Get-FastbootDevices`** —
  single point for building `devices` args with `-s`.
- **Log header:** `Serial: ...` (or `(auto)`) added to SESSION START, so
  the log shows whether `-Serial` was given.

## [1.0.0] — 2026-10-09

- **First stable release.** Full Windows/Linux parity for backup and
  version-check features, strict mode, critical fix for Linux streaming bug,
  unified i18n and Pause behavior.

### Added
- **`Backup-DataStream` in PowerShell.** Full port of the Linux version:
  `adb exec-out tar` → 64 KB buffered loop → `7z -si` via stdin.
  Progress via `Write-Progress` every 500 ms (`MB @ MB/s`).
  - `stderr` from `adb` goes to the console (no 4-KB deadlock).
  - `WaitForExit()` without timeout after closing 7z stdin.
  - Exceptions force-kill both processes (no orphaned 7z).
  - `-s Serial` propagated into `adb exec-out`.
  - Logging of mount operations and `tar --exclude` probe.
- **`Test-ToolVersions` (both platforms).** Checks not only presence but
  version: `adb ≥ 33.0.0`, `fastboot ≥ 33.0.0`, `7-Zip ≥ 22.00`
  (Windows — required; Linux — optional), `zstd ≥ 1.0` (if installed).
  Three outcomes: "not found" / "version unknown" / "version too old".
- **`-StrictVersions` / `--strict-versions`.** Hard-fail on any version
  problem. Propagated through `.cmd` unchanged (`%*`).
- **`Pause()` via `[Console]::ReadKey($true)`** in PowerShell — really
  "any key", not just Enter. Fallback to `Read-Host` in non-interactive
  environments.
- **i18n: 90+ keys EN/RU** in parity between `.ps1` and `.sh`. Helper
  `tf KEY arg1 ...` in bash (analogous to `-f` in PowerShell) for
  parameterized strings.
- **`fb_tolerant` (bash) / `-Tolerant` (PS)** — non-zero exit from
  `fastboot reboot fastboot` on MTK is not treated as an error. Removes
  the double message `[WARN] fastboot exit` + `[ERROR] TIMEOUT`.
- **Separate timeouts for flash and backup.** `FLASH_TIMEOUT=3600`,
  `BACKUP_TIMEOUT=3600`. Previously `REBOOT_TIMEOUT=30` was used for
  everything, killing 2 GB GSI flashes over USB 2.0 at ~90 s.

### Fixed
- **Critical (Linux): `backup_data_stream` wrote an empty file.**
  The function called `adb_ shell "tar -c ..."`, but `adb_()` uses
  `out=$(...)` and **does not emit to stdout** — the pipe `| pv | lz4`
  received nothing. Meanwhile `rc` was taken from `lz4` (0), not from
  `adb`. The `tar` probe suffered from the same.
  Fix: direct `adb exec-out` (no CRLF conversion of `adb shell`),
  `set -o pipefail` + `PIPESTATUS[0]` for correct `rc`.
- **Critical (PowerShell): `Invoke-Fb` used `REBOOT_TIMEOUT` (30 s) for
  every call, including `fastboot flash`.** A real 2 GB GSI flash was
  consistently killed by the timeout. Fix: `-TimeoutSec` parameter
  (default 30); for flash — 3600.
- **Windows: `Select-SystemImage` could return `.img.xz`, but
  `Resolve-SystemImage` couldn't find `7z.exe`** and returned `$null`
  without a clear reason. Now — a clear `Need 7-Zip for .xz` message
  via i18n.
- **Linux: `interactive_file_select` / `select_system_image` — false
  "file found" when no mask matched.** Due to `shopt -u nullglob` the
  array held a literal `*.img`. Fix: `shopt -s nullglob` + check
  `${#files[@]} -eq 0`.
- **Linux: `wait_for_adb` / `wait_for_fastboot` — CRLF in `adb devices` /
  `fastboot devices` output on MTK.** Added `tr -d '\r'` before `grep`
  (parity with the `.ps1` fix from 0.9.9).
- **Both: `free_super_space` / `Invoke-FreeSuperSpace` — double message on
  MTK-specific non-zero exit of `fastboot reboot fastboot`.** Now via the
  tolerant wrapper.

### Changed
- **Version bumped 0.9.9 → 1.0.0.** `TOOL_VERSION` in `.sh` / `.ps1`,
  `.cmd` header, `title`.
- **`check_tool_versions` (bash)** — rewritten with `version_ge` via
  `sort -V` (semantic comparison, not lexicographic).
- **`gsi-tool.cmd`** — structurally unchanged (`%*` already propagates
  new flags); only version in `title`.
- **All Russian/English strings in `.sh` and `.ps1`** moved into i18n
  tables. Added keys for: SHA256 block, vbmeta, backup, tool check, size
  check, super reconstruction, slot ops, GKI, emergency.

---

## Historical releases (0.9.x)

Earlier versions are documented in Russian. See the repo history for
tags `v0.9.0` through `v0.9.9`. Summary:

- **0.9.9** — PowerShell rewrite (Windows): monolithic `gsi-tool.ps1`,
  EN/RU i18n, tool version check, architecture check, CLI flags
  (`-Lang`, `-Serial`, `-Version`, `-Help`), build identifier
  (`+build.<hash>`), full logging with levels, separate timeouts.
- **0.9.8** — interactive SHA256 verification, decompression progress
  (`-bso0 -bsp1` for 7-Zip).
- **0.9.7 … 0.9.2** — safety-first revisions: fixed `stream_backup`
  deadlock, `set /a` overflow, `check_bootloader_unlocked` gaps,
  fallback backup errorlevel checks.
- **0.9.1 / 0.9.0** — pre-1.0 baseline: sparse-aware size detection,
  4096-align + margin, MTK `set_active` warning, log rotation.
