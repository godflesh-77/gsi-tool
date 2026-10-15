# Roadmap

## Done in 1.0.3 (2026-10-10)
- **Hotfix (Linux)**: three defects found in 1.0.2:
  - menu input not matching due to ANSI escapes captured from `clear`
  - 7-Zip version unknown false warning (7z prints banner to stderr)
  - `logs/` and `backups/` created relative to CWD instead of script dir

## Done in 1.0.2 (2026-10-09)
- **Backup pipeline fixes** — 4 silent-failure defects closed:
  - `adb.ExitCode` validation on Windows (no more "Backup OK" on truncated archive)
  - `.Dispose()` for both processes on Windows (no more handle leaks)
  - Full `PIPESTATUS[]` validation on Linux (disk-full on PC caught)
  - Broken/truncated archives force-removed on any failure path

## Done in 1.0.1 (2026-10-09)
- **Unified headers** `.sh` / `.ps1` / `.cmd` — single format with repo and license.
- **IMEI / MAC / Widevine warning** during `/data` backup.
- **`pv` decompression progress** in `.sh`.
- **`.ps1` `-s Serial` propagation** in `Get-FastbootVar` / `Wait-Adb` / `Wait-Fastboot`.
- **`Test-ToolVersions` counts "version unknown"** as a problem (matters for `--strict-versions`).
- **`.sh` backup timeout** — `BACKUP_TIMEOUT=3600`.
- **`.sh` tar-exclude probe** distinguishes adb-fail from no-support.
- **`.sh` `resolve_system_image`** prints `UnpackFailed` to user.

## Done in 1.0.0 (2026-10-09)
- **`Backup-DataStream` in PowerShell** — `adb exec-out` → 64 KB buffered loop → `7z -si` via stdin, `Write-Progress`, `-s Serial` propagated, exceptions kill both processes.
- **`Test-ToolVersions`** — checks not only presence but version: `adb`/`fastboot` ≥ 33.0.0, 7-Zip ≥ 22.00, `zstd` ≥ 1.0.
- **`-StrictVersions` / `--strict-versions`** — hard-fail on any problem.
- **`Pause()` via `[Console]::ReadKey($true)`** in PowerShell — really "any key".
- **i18n: 90+ keys EN/RU** in parity between `.ps1` and `.sh`.
- **`fb_tolerant` / `-Tolerant`** — MTK-specific non-zero from `reboot fastboot` is not treated as an error.
- **Separate timeouts for flash / backup** — `FLASH_TIMEOUT=3600`, `BACKUP_TIMEOUT=3600`.
- **Critical Linux backup bug fix** — `adb exec-out` instead of buffering `adb_()`, `set -o pipefail` + `PIPESTATUS[0]`.

## Done in 0.9.9 (2026-09-17)
- PowerShell port of the Windows version: monolithic `gsi-tool.ps1` + 5-line `.cmd` launcher
- `helper.ps1` removed
- EN/RU multilingual UI (auto-detect + `-Lang` / `--lang=` flags)
- External tool presence check
- Architecture check (x86_64 / aarch64, 64-bit Windows)
- CLI flags: `-Serial`, `-Version`, `-Help` (PS) / `--serial=`, `--version`, `--help` (bash)
- Build identifier (`+build.<hash>`) in UI and log
- Full logging with levels (INFO/WARN/ERROR)
- Separate timeouts (ADB / Fastboot / Reboot)
- SHA256 image verification
- Automatic decompression of `.img.xz/.gz/.zst`
- `super` reconstruction with alignment and margin
- GKI kernel flashing and emergency restore
- `set_active` protection on MTK fastbootd
- Size check when selecting system image

## 1.1.0
- **DSU Sideloader integration** — launch a second GSI without changing slots.
- **Slot A → B clone** — duplicate `system`/`vendor`/`boot`/`dtbo` for safe experiments.
- **Auto-defragment super** — defragment the `super` container via `lptools`.
- **`lpmake` on-device** — rebuild super on the device if GSI doesn't fit after delete.
- **Unify backup logic** between `.sh` and `.ps1` (single archive format).
- **macOS support** (`uname -m` Darwin, `gtimeout`, `gstat`, `gdf`, `gsha256sum`).
- **Backup critical partitions** — nvram / persist / modemst via `dd` from recovery.
- **`set -u` in Linux** — after auditing all variables.
- **Merge helper calls** into `super_prep` (Linux).

## 2.0.0 (ideas)
- GUI wrapper (Electron / Tauri) for Windows and Linux.
- Support for non-A/B devices (A-only) with auto-detection.
- GitHub Releases integration for automatic GSI download.
- Export flash report to JSON / HTML.
- `-Admin` flag for Windows (run elevated).
- Automatic script update check via GitHub API.