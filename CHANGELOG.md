# Changelog

Все значимые изменения в GSI Flash Tool документируются в этом файле.
Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).
Версионирование: [SemVer](https://semver.org/lang/ru/).

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

## [0.9.8] — 2026-09-15

**Interactive SHA256 verification + decompression progress.**
Первая функциональная фича после серии «safety-first» ревизий.

### Added
- **Интерактивная SHA256-верификация образов.** Перед `free_super_space`
  скрипт запрашивает эталонный хеш. Логика:
  1. Если рядом лежит `${SYSTEM_IMG}.sha256` — берётся оттуда.
  2. Иначе — предложение **вставить хеш** (например, скопированный
     из UI GitHub / темы 4PDA). Парсится regex `[a-f0-9]{64}`, любые
     пробелы/имя файла/мусор вокруг игнорируются.
  3. Enter → silent skip (это осознанный UX-выбор: пользователь сам
     решает, проверять или нет).
  Реализовано:
  - helper.ps1: режим `verify_sha256`, параметр `-Hash`
  - `.cmd`: блок в `:free_super_space` (интерактив + вывод)
  - `.sh`: тот же блок на bash + `sha256sum` + `pv` (если есть)
- **Прогресс-бар декомпрессии на Windows.** 7-Zip вызывается с
  `-bso0 -bsp1` — виден прогресс распаковки `.xz/.gz/.zst`.
- **Симметрия `fb_reboot` в action menu.** После `call :fb_reboot`
  в каждом блоке (flash/update/reset/dirty/emergency) добавлено
  короткое сообщение, если reboot не удался — чтобы пользователь
  видел, что «Готово» не означает «устройство перезагружено».

### Fixed
- **Helper `verify_sha256` — совместимость с PowerShell 7.**
  `SHA256Managed` устарел в .NET Core, используем
  `[System.Security.Cryptography.SHA256]::Create()` — работает
  и в PS 5.1, и в PS 7.
- **Helper `verify_sha256` — защита от больших `.sha256`.**
  Файл >4 КБ игнорируется (`error_file_too_large`). Защита от
  случайного или намеренного OOM.
- **Regex групповой захват** — используем `$Matches[1]` /
  `${BASH_REMATCH[1]}`, а не `[0]` (последний захватил бы всю
  строку совпадения с границами).
- **CHANGELOG 0.9.7 formulation** — «вызывающие проверяют» относилось
  только к критичным местам (`free_super_space`, `reboot_to_fastbootd`);
  в action menu проверка не критична (после успешного flash).
  В 0.9.8 симметрия добавлена.

### Changed
- Linux `.sh`: обновлена шапка `0.9.7 → 0.9.8`.
- Windows `.cmd`: `HELPER` путь → `gsi-tool-helper-0.9.8.ps1`.
- Windows `.cmd`: `7z x` теперь с `-bso0 -bsp1` вместо `>nul`.

## [0.9.7] — 2026-09-15

**Safety-first release, revision 7.** Дочистка двух дефектов ревью 0.9.6.

### Fixed
- **Критично (Windows): `stream_backup` orphaned 7z при нечистом сбое adb.**
  Если `CopyToAsync` бросал исключение (повреждённый pipe, I/O error USB-
  драйвера), внешний `catch` выводил `exception:...`, но **не убивал**
  процессы `adb` и `7z`. 7z оставался висеть в ожидании stdin, держал
  lock на выходной файл → следующий запуск `stream_backup` падал с
  «файл занят». Теперь в `catch` оба процесса принудительно убиваются.
- **Windows: `fb_reboot` (fastboot) всегда возвращал 0 на `error`.**
  Асимметрия с `fb_reboot_adb` (починен в 0.9.6). Если fastboot.exe
  отсутствовал — вызывающий код (`reboot_to_fastbootd`, `free_super_space`)
  всё равно шёл в `wait_for_fastboot` и висел 15 сек. Теперь `fb_reboot`
  возвращает 1 на `error`, вызывающие проверяют и выходят сразу.

### Changed
- Linux `.sh`: обновлена шапка файла `0.9.6 → 0.9.7`.
- Windows `.cmd`: `HELPER` путь → `gsi-tool-helper-0.9.7.ps1`.

## [0.9.6] — 2026-09-15

**Safety-first release, revision 6.** Дочистка после ревью 0.9.5.

### Fixed
- **Критично (Windows): `stream_backup` timeout не покрывал `CopyTo`.**
  CHANGELOG 0.9.5 заявлял «при зависании adb — timeout сработает», но
  `CopyTo` — синхронный вызов, и при зависании adb на уровне USB-драйвера
  он не возвращался, а до `WaitForExit` управление не доходило. Фикс:
  `CopyToAsync` + `Task.Wait($StreamTimeout * 1000)`. Теперь таймаут
  реально покрывает весь сценарий потока, включая зависание источника.
- **Windows: `fb_reboot_adb` всегда возвращал 0** — при `error` (adb.exe
  не найден) вызывающий код (`reboot_via_adb`, `flash_gki_cores`) всё
  равно шёл в `wait_for_fastboot`, крутился 15 сек и выдавал второе
  сообщение об ошибке. Теперь `fb_reboot_adb` возвращает 1 на `error`,
  вызывающие проверяют и выходят сразу.
- **Windows: `fallback_backup` — `rm -f` без проверки.**
  Формально CHANGELOG 0.9.2 обещал «проверку всех трёх команд».
  Теперь проверяется и `rm` — с мягким предупреждением, поскольку
  провал `rm` некритичен (файл просто останется в `/data/local/tmp`).

### Changed
- Linux `.sh`: обновлена шапка файла `0.9.5 → 0.9.6` (`TOOL_VERSION`
  был обновлён ещё в 0.9.5, но комментарий-шапка отставал).

## [0.9.5] — 2026-09-15

**Safety-first release, revision 5.** Закрыт реальный deadlock в Windows-бэкапе
и устранена проблема экранирования аргументов tar.

### Fixed
- **Критично (Windows): deadlock в `stream_backup` на stderr.**
  `RedirectStandardError = $true` без читателя → при заполнении буфера
  (4 КБ) `adb` блокировался на записи в stderr, `CopyTo()` никогда не
  завершался, скрипт висел навсегда. Реальный сценарий: `tar` пишет
  «permission denied» на десятки файлов из `/data/system` — буфер
  заполняется за секунды.
  Фикс: stderr направляется в консоль (`RedirectStandardError = $false`),
  процесс не блокируется.
- **Критично (Windows): отсутствие таймаута в `stream_backup`.**
  Если `adb` завис — PowerShell висел вечно. Добавлен `-StreamTimeout 3600`
  (1 час). При превышении — оба процесса убиваются, `.cmd` получает
  `timeout` и корректно завершается.
- **Важно (Windows): `ADB_CMD` с одинарными кавычками.**
  В цепочке `cmd → PowerShell → .NET → adb → shell` одинарные кавычки
  вокруг `--exclude='media'` могут теряться или искажаться. Для имён без
  пробелов они не нужны — убраны.
- **Важно (Windows): `adb reboot bootloader` / `adb reboot fastboot` без
  таймаута и логирования.** Теперь через helper `-Mode adb_reboot` —
  с таймаутом 10 сек и обработкой `ok` / `timeout` / `error`.
- **Профилактика (Windows): `calculate_partition` — try/catch на cast.**
  Если кто-то передаст нечисловой `-Path`, ловим `InvalidCastException`
  и возвращаем `0` вместо падения helper.
- **Проверка (helper): `${actual}:${expected}` вместо `$actual:$expected`.**
  В PowerShell `$var:name` — drive-qualified reference. Не экранированное
  двоеточие вызывало `ParserError: InvalidVariableReferenceWithDrive`.
  Ловилось только при реальном `suspect:` пути.

### Changed
- Linux `.sh`: обновлена шапка `0.9.4 → 0.9.5`.
- Windows `.cmd`: `HELPER` путь → `gsi-tool-helper-0.9.5.ps1`.
- Windows helper: новый режим `adb_reboot` (`adb reboot bootloader` /
  `adb reboot fastboot` с таймаутом).
- Windows helper: параметр `-StreamTimeout` (по умолчанию 3600 сек).

## [0.9.4] — 2026-09-15

**Safety-first release, revision 4.** Закрыт критический баг Windows-бэкапа
и добавлена защита от BusyBox tar.

### Fixed
- **Критично (Windows): batch-pipe не возвращает exit code `adb exec-out`.**
  В `cmd.exe` `errorlevel` после `|` = код последней команды (7z). Если
  `adb exec-out` умирал на середине потока, 7z получал обрезанный stdin,
  упаковывал что успел и возвращал 0. Скрипт показывал «Готово», пользователь
  получал битый `.tar.7z` на 500 МБ вместо 15 ГБ.
  Заменено на новый режим `stream_backup` в helper.ps1 — через
  `System.Diagnostics.Process` с `RedirectStandardOutput`/`Input`.
  Оба процесса контролируются, оба `ExitCode` проверяются.
- **Профилактика (Windows): `calculate_partition` теперь целочисленный.**
  `[Math]::Ceiling($raw / $align)` через `[Double]` заменён на
  `[Math]::DivRem` с `[UInt64]`. Плюс short-circuit на `$raw = 0`.
- **Linux: fallback для BusyBox tar без `--exclude`.**
  Проверка поддержки `--exclude` через пробный вызов `tar -cf /dev/null`.
  Если не поддерживается — предупреждение и предложение бэкапить `/data`
  целиком (без исключений), а не тихий провал.

## [0.9.3] — 2026-09-15

**Safety-first release, revision 3.** Три фикса по итогам второго аудита.

### Fixed
- **`flash_slot` (обе платформы): не было reboot.** После прошивки в
  указанный слот устройство оставалось в fastbootd — пользователь ждал,
  что скрипт перезагрузит его автоматически (как в опциях 1, 2, 5).
  Добавлен `safe_reboot` / `:fb_reboot`.
- **Windows `fb_reboot`: результат `error` молча игнорировался.**
  Helper возвращает три значения — `ok`, `timeout`, `error`. `.cmd`
  проверял только `timeout`. Если `Start-Process` падал — скрипт
  показывал «Готово.» и закрывался, хотя устройство НЕ перезагружено.
  Теперь `error` обрабатывается с явным предупреждением.
- **Кроссплатформенная унификация фильтра `select_system_img`.**
  Linux и Windows по-разному отсеивали не-системные образы:
  `boot.img.xz` / `vendor.img.gz` проходили на Linux, `vendor_dlkm.img`
  на Windows. Теперь единый superset-подход (glob + подстроки).

### Changed
- Linux `safe_reboot` теперь различает timeout (124) и error — разные
  сообщения для пользователя.

## [0.9.2] — 2026-09-15

**Safety-first release, revision 2.** Дочищены дефекты второго аудита 0.9.1.

### Fixed
- **Критично (Windows): `set /a` overflow при расчёте `need_mb`** для
  `.img.xz` >2 ГБ. Batch `set /a` работает с 32-битным signed int — файл
  2.5 ГБ давал отрицательный `need_mb`, проверка места всегда «проходила».
  Заменено на PowerShell через `helper.ps1 -Mode need_mb_x3 / need_mb_x4`.
- **Критично (Windows): `fallback_backup` без проверок errorlevel.**
  Три команды (`adb shell tar`, `adb pull`, `adb shell rm`) выполнялись
  без контроля. Теперь при провале любой из них — ошибка и выход.
  Добавлена проверка, что скачанный архив не пустой.
- **Критично (Linux): `fastboot -w || true` маскировал провал wipe.**
  Пользователь выбирал «Full Wipe», wipe молча не срабатывал, flash шёл
  поверх старых данных. Теперь при провале — предупреждение с возможностью
  отмены.
- **Windows: `check_bootloader_unlocked` без проверки `get_unlock_ability`.**
  Расхождение с Linux-версией.
- **Windows: `.gz` и `.zst` без проверки места на диске.**
- **Linux: хрупкая логика `[ -z "$real_size" ] || [ "$real_size" -le 0 ] &&`**
  в `free_super_space` → regex-проверка `^[0-9]+$`.
- **Linux: `trap` на Ctrl+C был глобальным** — теперь локально вокруг
  `free_super_space` и `emergency_slot_fix`.
- **Обе платформы: `REBOOT_TIMEOUT` не использовался для финальных reboot.**
- **Windows: `iloop`/`sloop` без проверки на нечисловой ввод.**
- **Windows: `free_super_space` вызывал `fastboot reboot fastboot` без
  таймаута.**

### Changed
- Windows helper: добавлены режимы `need_mb_x3`, `need_mb_x4`, `reboot`.
- Windows helper: параметр `Timeout` (по умолчанию 10 сек).

## [0.9.1] — 2026-09-15

*(Не деплоился — правки внесены сразу в 0.9.2.)*

**Safety-first release.** Закрыты критические дефекты аудита 0.9.0.

### Added
- `fb_flash()` / `:fb_flash` — безопасная обёртка над `fastboot flash`.
- Проверка `check_bootloader_unlocked` в `dirty_flash`.
- Проверка дискового пространства на Windows перед распаковкой.

### Fixed
- Проверка результата `fastboot flash` (10+ вызовов).
- `free_super_space` возвращал 0 при отказе пользователя.
- Windows: `check_bootloader_unlocked` вызывался ДО `wait_for_fastboot`.
- Linux: `check_and_flash_vbmeta` без проверки результата.
- Windows: `secure: not supported` false positive.
- Windows: `:.xz=` заменял все вхождения `.xz` в пути.
- Windows: `*boot*.img` матчил `vendor_boot.img`.
- Windows: `set /p` сохранял предыдущее значение.
- Linux: `df -P -B1 .` проверял не ту ФС.
- Linux: `parse_slot` молча возвращал «a».
- Linux: `--exclude='media'` расширен.
- Windows: `sparse_integrity` без outer try/catch.
- Windows: `MARGIN_MB` не пробрасывался в helper.

## [0.9.0] — 2026-09-14

**Pre-1.0 baseline.** Первый релиз под строгим SemVer.

### Added
- Sparse-aware определение размера образа (magic `3aff26ed`, `blk_sz × total_blks`).
- Sparse integrity check (warning).
- Выравнивание партиции до 4096 + margin 256 МБ (`GSI_MARGIN_MB`).
- Warn >4 ГБ для MTK fastbootd.
- Auto-resolve `.img.xz/.gz/.zst` (Linux: `df` + `timeout`; Windows: 7-Zip).
- Bootloader unlock check (`unlocked`, `secure`, `get_unlock_ability`).
- A/B autodetect через `fastboot getvar slot-count`.
- Log rotation: `logs/gsi-tool_<version>_YYYYMMDD_HHMMSS.log`.
- Windows helper.ps1 — изолированный PowerShell-движок.
- Флаги CLI: `--version`, `-v`, `--help`, `-h`.
- Universal 15s ADB/Fastboot timeout + `timeout`-обёртки.

### Fixed
- taskkill race condition (Windows).
- ReadAllBytes OOM на больших образах → `FileStream`.
- UInt32 × UInt32 overflow в PowerShell → `[UInt64]` cast.
- `awk '{print $2}'` fragile parsing → regex.
- `return 1` вне функции в batch → `exit /b` внутри `call :label`.
- `detect_ab_device` через findstr-токены → строгий regex.
- `check_bootloader_unlocked` обходился через сервисное меню.
- Windows fastboot flash в сервисах не писался в лог.
- `df -B1` → `df -P -B1`.

### Changed
- Сброс нумерации `V1…V6.3.1` → SemVer `0.9.0`.
- Убран суффикс `-final`.
- Версия в шапке, меню, логе, имени хелпера.
