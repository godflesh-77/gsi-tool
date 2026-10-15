# gsi-tool

**GSI flash & service tool for Android devices with A/B slots and dynamic partitions (Dynamic Partitions / Super).**

Cross-platform utility for flashing Generic System Images (GSI), managing slots, servicing partitions, and backing up data. Built safety-first: the script performs every reasonable check before it touches a partition.

[English](README.md) | [Русский](README.ru.md)

> **Development repository:** [codeberg.org/godflesh-77/gsi-tool](https://codeberg.org/godflesh-77/gsi-tool)
> GitHub ([godflesh-77/gsi-tool](https://github.com/godflesh-77/gsi-tool)) is a read-only mirror.

---

## Features

- **GSI flashing** into the active or a specific slot (`system_a` / `system_b`)
- **A/B auto-detection** via `fastboot getvar slot-count`
- **Bootloader unlock check** before any destructive operation
- **Sparse-aware** image size detection (raw vs sparse)
- **Automatic `super` reconstruction** — deletes `system`/`product`/`system_ext` in both slots and recreates the target partition (4096-align + 256 MB margin)
- **Never touches** `vendor`, `odm`, `vendor_dlkm`, `system_dlkm` — critical for GKI devices
- **SHA256 verification** before flashing: from `<image>.sha256` file or interactive hash input from the release page
- **Automatic decompression** of `.img.xz` / `.img.gz` / `.img.zst` (Linux: with `pv` progress bar if available)
- **`/data` backup** via ADB stream on both platforms:
  - Windows — `adb exec-out` → 64 KB buffered loop → `7z -si` (progress via `Write-Progress`)
  - Linux — `adb exec-out` → `pv` → `lz4`/`gzip` (fast path with `pv` + `lz4` if installed)
- **IMEI / MAC / Widevine warning** during `/data` backup — those live in `/persist`, `/nvram`, `/modemst*`, `/misc`, not in `/data`
- **GKI kernel flashing** (`boot` + `vendor_boot`) into the active slot
- **Emergency restore** — dual-write kernels into both slots + `set_active a`
- **Full logging** of every operation into `logs/`
- **Ctrl+C protection** in critical sections (Linux)
- **Multilingual UI** EN/RU with auto-detect and `-Lang` / `--lang=` flags
- **Tool version check** (not just presence): `adb`/`fastboot` ≥ 33.0.0, 7-Zip ≥ 22.00, `zstd` ≥ 1.0
- **`-StrictVersions` / `--strict-versions`** flag — hard-fail on any version problem (including "version unparseable")
- **Device targeting** via `-Serial` / `--serial=` — all `adb`/`fastboot` calls (including `getvar`, `devices`, `wait`) propagate `-s`
- **CLI flags** for automation: `-Serial`, `-StrictVersions`, `-Version`, `-Help` (PS) / `--serial=`, `--strict-versions`, `--version`, `--help` (bash)
- **Build identifier** (`+build.<hash>`) in UI and log for precise build identification

---

## Requirements

| Component | Minimum |
|---|---|
| **Android platform-tools** (`adb`, `fastboot`) | 33.0.0 (Android 13) |
| **7-Zip** (Windows — required for `.xz`/`.gz`/`.zst` and for backup) | 22.00 |
| **Linux utilities** | `adb`, `fastboot`, `timeout`, `od`, `df`, `awk` (coreutils), `sha256sum`, `grep`, `tr` |
| **Optional (Linux)** | `pv` + `lz4` — fast backup and decompression progress; `unxz`, `gunzip`, `zstd` — image decompression |
| **OS** | Windows 10/11 x64, Linux x86_64 / aarch64 |
| **Device** | A/B (or non-A/B) with unlocked bootloader |

**Not supported:** Windows 7/8/8.1, 32-bit Windows, 32-bit Linux (i386, ARMv7).

---

## Usage

### Windows

1. Download `gsi-tool-<version>.zip` from the [Releases](https://codeberg.org/godflesh-77/gsi-tool/releases) page.
2. Extract to any folder.
3. Make sure `adb.exe` and `fastboot.exe` are either in `PATH` or in the same folder as the script.
4. Download [7-Zip 22.00+](https://www.7-zip.org/) and put `7z.exe` + `7z.dll` next to the script (or install 7-Zip to `Program Files`).
5. Run `gsi-tool.cmd`.

### Linux

1. Download `gsi-tool.sh` from the release.
2. Make it executable: `chmod +x gsi-tool.sh`
3. Make sure `adb` / `fastboot` from platform-tools 33.0.0+ are in `PATH`.
4. (Optional, for fast backup and decompression progress) install `pv` and `lz4`:

   Debian/Ubuntu: `sudo apt install pv lz4`
   Arch: `sudo pacman -S pv lz4`
   Fedora: `sudo dnf install pv lz4`

5. Run: `./gsi-tool.sh`

---

## CLI

| Flag (PS / bash) | Description |
|---|---|
| `-Lang en\|ru` / `--lang=en\|ru` | Force UI language (default: auto from `$PSUICulture` / `$LANG`) |
| `-Serial <serial>` / `--serial=<serial>` | Target a specific device when multiple are connected |
| `-StrictVersions` / `--strict-versions` | Hard-fail on any version problem, including "version unparseable" |
| `-Version` / `--version` / `-v` | Print version (`1.0.3`, without build suffix) |
| `-Help` / `--help` / `-h` | Print help |

**Examples:**

PowerShell: `.\gsi-tool.cmd -Serial ABC123 -StrictVersions`

Bash: `./gsi-tool.sh --serial=ABC123 --strict-versions`

---

## Safety

- The script **never** formats a partition without explicit confirmation.
- Every `fastboot flash` result is checked before proceeding.
- On `create-logical-partition` failure, the script stops and prints **DO NOT REBOOT**.
- On SHA256 mismatch, an additional confirm is required.
- On suspiciously small image (<100 MB), a warning + confirm is shown.
- During `/data` backup, a warning is printed: IMEI, Wi-Fi/Bluetooth MAC, and Widevine keys are **not** included — they live in `/persist`, `/nvram`, `/modemst*`, `/misc`.

---

## Known quirks

- **MTK fastbootd:** `fastboot reboot fastboot` often returns a non-zero exit code even though the device really reboots (bootloader drops USB before ACK). The script uses a tolerant wrapper and relies on `wait_for_fastboot` instead of the exit code.
- **MTK fastbootd:** `set_active` usually fails — use `bootloader` (not fastbootd) to switch slots. The script warns about this before attempting.
- **MTK `-w`:** `fastboot -w` sometimes complains about non-standard layout. In the Linux version the rc is ignored (continue); in the Windows version a warning is written to the log.

---

## License

MIT. See `LICENSE`.
