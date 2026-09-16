## [Unreleased]

### Planned for 0.9.9
- **Полный порт Windows-версии с `cmd.exe` на PowerShell.** 
  Причины:
  - cmd.exe — legacy-наследие MS-DOS с крашами парсера на скобках
    внутри `if (...)`, drive-ref проблемами `$var:name`, 32-bit `set /a`,
    обязательным экранированием `^(`, `^<`, `^>` внутри блоков.
  - Кодировочный ад: CP866/CP1251/UTF-8-BOM → ANSI, `chcp`, BOM
    ломающий `@echo off`.
  - Нет встроенной криптографии → helper.ps1 в обход.
  - Pipe не пробрасывает exit code первого процесса.
  
  Архитектура после порта:
  - `gsi-tool.ps1` — вся логика (main menu, action menu, все функции).
  - `gsi-tool.cmd` — launcher в 5 строк: 
    `powershell -NoProfile -ExecutionPolicy Bypass -File gsi-tool.ps1 %*`
  - helper.ps1 упраздняется — код сливается в основной `.ps1`.
  - 7-Zip остаётся только для `.xz/.zst` (у PS нет встроенных для них).
  - UTF-8 без BOM — нативная поддержка.
  - `Write-Host -ForegroundColor` для цветного вывода.
  - `try/catch`, `$LASTEXITCODE`, `[int64]` — вместо костылей.
  
  Портировать функции:
  - `Main menu`, `Action menu`, `Service menu`
  - `select_system_img`, `resolve_system_img`
  - `check_and_flash_vbmeta`, `free_super_space`
  - `fb_flash`, `fb_reboot`, `fb_reboot_adb`
  - `check_bootloader_unlocked`, `detect_ab_device`
  - `backup_data_stream`, `flash_gki_cores`, `emergency_slot_fix`
  - `wait_for_adb`, `wait_for_fastboot`, `get_current_slot`, `get_userspace`
  - Все helper-режимы (`size`, `sparse_integrity`, `calculate_partition`,
    `verify_sha256`, `stream_backup`, `disk_free_mb`, `need_mb_x3/x4`,
    `reboot`, `adb_reboot`, `timestamp`)
- **PowerShell-порт (0.9.9)**: уберёт legacy-cmd костыли:
  `USER_HASH=file` magic string → явный параметр `-FromFile`;
  `dirty_flash` без SHA256 → опциональный pre-check;
  `$sha256.Dispose()` в catch-ветке (утечка);
  `set /p` внутри трёх уровней if → плоская структура;
  `Write-Error` в helper → `Write-Output` для `for /f` совместимости.
  Все эти пункты в PowerShell-версии решаются автоматически.
- **PowerShell-порт Windows-версии** (замена `.cmd` + helper.ps1 на монолитный `gsi-tool.ps1`).
  - Упраздняет cmd-hell: BOM, CP1251, `errorlevel` в pipe, `exit /b` в скобках, `set /a` overflow.
  - Launcher `.cmd` в 5 строк, только ASCII, `powershell -ExecutionPolicy Bypass -File`.
  - `[Console]::OutputEncoding` + `$OutputEncoding = UTF8` для корректного вывода.
  - Функции вместо меток: `Get-ImageSize`, `Test-SparseIntegrity`, `Invoke-FbFlash`,
    `Get-CurrentSlot`, `Invoke-VerifySha256`, `New-SuperPartition`, `Start-DataBackup`,
    `Install-GkiKernels`, `Restore-EmergencySlots`, `Show-MainMenu`, `Show-ActionMenu`,
    `Show-ServiceMenu`, `Select-SystemImage`, `Resolve-SystemImage`, `Confirm-Vbmeta`.
  - Прогресс-бар бэкапа через `Write-Progress` + `CopyToAsync`.
  - Автоматическое устранение spawn'ов helper'а (минус 200–500 мс на каждый вызов).
- **Мультиязычность EN/RU.**
  - Auto-detect: `$LANG`/`CurrentUICulture` в PS, `$LANG` в bash.
  - Override: `-Lang ru` (PS), `--lang=ru` (bash).
  - Тексты встроены (хеш-таблица `$MSG` в PS, `MSG_RU`/`MSG_EN` в bash).
  - Комментарии в коде — на английском.
- **Проверка версий внешних утилит** (до главного меню):
  - `adb` / `fastboot` ≥ 33.0.0 — warning.
  - `7z.exe` ≥ 22.00 — **hard fail** (нестабильный `.zst` и `-bsp1` на старых версиях).
  - `unxz` / `gunzip` / `zstd` (Linux) — warning.
  - Формат: таблица `[Tool Check]` с версиями и статусом `✓` / `⚠` / `✗`.
  - Флаг `--strict-versions` для жёсткого отказа на любом warning.
- **Только x86_64 / aarch64.**
  - Windows: `[Environment]::Is64BitOperatingSystem` + `Is64BitProcess` check.
  - Linux: `uname -m` ∈ {`x86_64`, `aarch64`}.
  - 32-bit Windows и i386/ARMv7 Linux — не поддерживаются.

### Planned for 1.0.0
- **Опциональная SHA256-верификация образов.** Отдельный режим
  `verify_sha256` в helper (regex `(?i)[a-f0-9]{64}`), локальная
  реализация на Linux с тем же regex. `ok` / `mismatch` / `missing` /
  `no_hash_in_file`.
- **Прогресс-бар декомпрессии** на Windows через 7-Zip `-bsp1`.
- **Прогресс-бар бэкапа** на Windows через `stream_backup` (счётчик
  переданных байт в helper).
- **Backup critical partitions** — nvram / persist / modemst через
  `dd` из recovery. Опциональный пункт сервисного меню.
- **Предупреждение про IMEI/MAC/Widevine** в шапке `backup_data_stream`:
  `/data`-бэкап их не содержит.
- **Опциональный `lpmake`** для случаев, когда GSI физически не влезает
  в super после удаления `product`/`system_ext`.
- **`-s <serial>`** — поддержка нескольких подключённых устройств.
- **Унификация шапок** всех скриптов (единый формат на `.sh` / `.cmd` /
  `.ps1`).
- **`set -u`** в Linux-версии (после аудита всех переменных).
- **Объединение PowerShell-вызовов** — один `super_prep` вместо
  четырёх (`size`, `sparse_integrity`, `calculate_partition`, `>4GB`).
- **`$args` → `$rebootArgs`** (сделано в 0.9.5, но пункт остаётся для
  аудита).
- **Финальный smoke-тест на живом GSI** (Lunaris с GitHub) + публикация.
- **Унификация шапок** уже после PowerShell-порта.
