# TODO

## Ideas (not urgent)
- [ ] `-Admin` flag for Windows (done in 1.1.0)
- [ ] Automatic script update check via Codeberg API
- [ ] Export flash report to JSON

## 1.2.0
- [ ] DSU Sideloader integration — launch a second GSI without changing slots
- [ ] Slot A → B clone — duplicate system/vendor/boot/dtbo
- [ ] Auto-defragment super — defragment the `super` container via lptools
- [ ] `lpmake` on-device — rebuild super on the device if GSI doesn't fit
- [ ] Unify backup logic between `.sh` and `.ps1` (single archive format)
- [ ] `set -u` in Linux (after auditing all variables)
- [ ] Merge helper calls into `super_prep` (Linux)
- [ ] Final smoke test on a live GSI (Lunaris)

## Done in 1.1.0 (2026-10-15)
- [x] `-Admin` flag (Windows) — UAC self-relaunch with argument forwarding
- [x] Windows Terminal detection in `.cmd` launcher
- [x] Critical partitions backup — nvram/persist/modemst/fsg/fsc/misc/bluetooth/oem via `adb exec-out dd | gzip`
- [x] README "Related documents" section with links to RU docs
- [x] macOS support removed from roadmap

## Done in 1.0.3 (2026-10-10)
- [x] Fix: `.sh` menu did not match input (ANSI escapes from `clear` captured into `$c`)
- [x] Fix: 7-Zip version unknown false warning on Linux (banner goes to stderr)
- [x] Fix: `logs/` and `backups/` created relative to CWD, not script dir (`SCRIPT_DIR`)

## Done in 1.0.2 (2026-10-09)
- [x] Fix: `.ps1` `Backup-DataStream` did not check `adb.ExitCode`
- [x] Fix: `.ps1` handle leak on backup failure (`.Dispose()` in catch)
- [x] Fix: `.sh` `PIPESTATUS[0]` checked only adb, not lz4/gzip
- [x] Fix: `.sh` 0-byte archive not removed

## Done in 1.0.1 (2026-10-09)
- [x] Fix: `.ps1` `Get-FastbootVar` did not pass `-s Serial`
- [x] Fix: `.ps1` `Wait-Adb` / `Wait-Fastboot` did not pass `-s Serial`
- [x] Fix: `Test-ToolVersions` did not count "version unknown" as a problem
- [x] Fix: `.sh` backup had no timeout (`BACKUP_TIMEOUT=3600` added)
- [x] Fix: `.sh` `tar --exclude` probe did not distinguish adb-fail from no-support
- [x] Fix: `.sh` `resolve_system_image` did not show `UnpackFailed` to user
- [x] Unified headers `.sh` / `.ps1` / `.cmd`
- [x] IMEI / MAC / Widevine warning during `/data` backup
- [x] `pv` decompression progress in `.sh`

## Done in 1.0.0 (2026-10-09)
- [x] `Backup-DataStream` port to PowerShell (Write-Progress + 64 KB buffered loop)
- [x] Tool version check (adb/fastboot ≥ 33.0.0, 7-Zip ≥ 22.00, zstd ≥ 1.0)
- [x] `--strict-versions` / `-StrictVersions` flag — hard-fail on any warning
- [x] Fix double message in Windows `free_super_space` on `fb_reboot error`
- [x] `Pause()` via `[Console]::ReadKey($true)` instead of `Read-Host`
- [x] i18n: remaining hardcoded strings in service functions moved
- [x] Critical Linux backup fix: `adb exec-out` instead of buffering `adb_()`
- [x] Separate timeouts for flash / backup (were 30 s for all calls)
- [x] `fb_tolerant` on MTK for `reboot fastboot`
- [x] CRLF-strip in wait helpers on Linux
- [x] `shopt -s nullglob` in file-select on Linux