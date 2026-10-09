# Changelog

Все значимые изменения в GSI Flash Tool документируются в этом файле.
Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).
Версионирование: [SemVer](https://semver.org/lang/ru/).

## [1.0.2] — 2026-10-09

**Fix-релиз.** Закрыты 4 дефекта в подсистеме бэкапа `/data`, найденные
при аудите 1.0.1. Ошибки тихие — скрипт сообщал «Backup OK» на обрезанных
архивах. Никаких новых фич.

### Fixed
- **Критично (PowerShell): `Backup-DataStream` не проверял `adb.ExitCode`.**
  Сценарий: телефон отваливается на середине стрима → `adb exec-out`
  умирает → `.Read()` возвращает 0 → `7z` получает EOF, упаковывает
  что успел и возвращает `ExitCode = 0`. Скрипт печатал
  `Backup OK` на обрезанном архиве. Fix: `if ($adbRc -ne 0 -or
  $szRc -ne 0)` → `BackupFailed` + удаление битого архива
  (`Remove-Item -Force`).
- **Критично (PowerShell): утечка handle'ов при сбое бэкапа.**
  В `catch` вызывался `.Kill()` без `.Dispose()`. При многократных
  сбоях — накопление неосвобождённых handle'ов процессов. Fix:
  `.Dispose()` вызывается в success-ветке (сразу после чтения
  `ExitCode`) и в `catch` (после `Kill`, независимо от его успеха).
- **Критично (Linux): `PIPESTATUS[0]` проверял только `adb`, не `lz4`/`gzip`.**
  Сценарий: на ПК закончилось место → `lz4` падает → `PIPESTATUS[1]
  -ne 0` игнорируется, скрипт читает `PIPESTATUS[0]` (`adb`, OK)
  и печатает `Backup OK` на пустом/битом файле. Fix: захват всего
  массива `PIPESTATUS` **сразу после пайпа** (голое присваивание,
  без `local`, чтобы не сбросить значения), проверка обоих rc;
  `rm -f` битого архива при любом провале.
- **Средне (Linux): не удалялся 0-byte архив.** Если `adb` успешно
  завершился, но `tar` на устройстве вернул пустой поток — оставался
  файл нулевого размера. Fix: явная проверка `stat -c%s` и `rm -f`
  при нуле. Плюс паритет с Windows-версией (там эта проверка тоже
  добавлена defencive).

### Changed
- **Версия поднята 1.0.1 → 1.0.2.** `TOOL_VERSION` в `.sh` / `.ps1`,
  заголовок `.cmd`, `title`.
- **`.ps1`: `Invoke-Fb` / `Invoke-Adb` — `.Dispose()` после чтения
  `ExitCode`** (не только в timeout-ветке). Освобождает handle'ы
  в штатном пути.
- **`.sh`: `rc_array` вместо одиночного `rc`** — для сохранения
  полного `PIPESTATUS` между двумя ветками (lz4/gzip).

## [1.0.1] — 2026-10-09

**Fix-релиз.** Закрыты баги, найденные при перечитывании 1.0.0. Плюс
тривиальные улучшения, отложенные ранее: унификация шапок, IMEI/MAC/
Widevine warning, `pv`-прогресс распаковки. Никаких новых крупных фич.

### Added
- **Унифицированные шапки `.sh` / `.ps1` / `.cmd`.** Единый формат:
  имя, версия, платформа, назначение, ссылка на репозиторий, лицензия.
- **Предупреждение про IMEI / MAC / Widevine при бэкапе `/data`**
  (обе платформы). После основного `BackupWarning` выводятся две
  строки: бэкап `/data` НЕ включает IMEI, MAC Wi-Fi/BT, ключи
  Widevine — они лежат в `/persist`, `/nvram`, `/modemst*`, `/misc`.
  Новые i18n-ключи: `BackupCriticalWarn`, `BackupCriticalHint`.
- **Прогресс-бар распаковки через `pv` на Linux.** Новый хелпер
  `decompress_with_progress` оборачивает `unxz` / `gunzip` / `zstd`
  в пайп с `pv -s <size>` (процент + ETA + скорость). Показывается
  только если `pv` установлен и `stderr` — терминал. При отказе
  декомпрессора временный файл удаляется (`rm -f "$out"`), чтобы не
  осталось гигабайтных обрубков образов. Новый ключ `UnpackProgress`.

### Fixed
- **Критично (PowerShell): `Get-FastbootVar` не пробрасывал `-s Serial`.**
  При двух подключённых устройствах `current-slot`, `slot-count`,
  `unlocked`, `secure`, `get_unlock_ability`, `is-userspace` уходили
  на случайное устройство. `Test-BootloaderUnlocked`, `Get-CurrentSlot`,
  `Get-SlotCount`, `Test-Userspace` работали по чужому девайсу.
  Fix: собирать `@('-s', $Serial, 'getvar', $name)` и вызывать через
  array splatting.
- **Критично (PowerShell): `Wait-Adb` / `Wait-Fastboot` не пробрасывали
  `-s Serial`.** Цикл ожидания мог увидеть чужое устройство и вернуть
  `$true` преждевременно — все последующие команды уходили не туда.
  Fix: общие хелперы `Get-AdbDevices` / `Get-FastbootDevices`,
  собирающие аргументы с `-s`.
- **Важно (обе): `Test-ToolVersions` не увеличивал счётчик проблем при
  «version unknown».** Из-за этого `-StrictVersions` / `--strict-versions`
  не ловил случай «adb есть, но версия не парсится» (новая нумерация,
  локализованный вывод, кастомная сборка). Fix: `$problems++` в обеих
  ветках «unknown» (adb, fastboot, 7-Zip, zstd на Linux).
- **Важно (Linux): `backup_data_stream` без таймаута.** В `.ps1`
  `BACKUP_TIMEOUT=3600` был, в `.sh` — нет. При зависании `adb exec-out`
  на середине потока (USB-драйвер, флешка отвалилась) `pv` и `lz4`
  ждали вечно. Fix: `BACKUP_TIMEOUT=3600` + `timeout` вокруг `adb`;
  различаем rc=124 (timeout) и прочие ненулевые.
- **Важно (Linux): probe `tar --exclude` не отличал «tar не поддерживает»
  от «adb отвалился».** При потере adb probe возвращал пустой `pout`,
  скрипт уходил в «full backup», который падал с невнятной ошибкой.
  Fix: эхо-маркер `ADB_OK` в probe, отдельный hard-fail на потерю adb.
- **Средне (Linux): `resolve_system_image` логировал ошибки распаковки
  только в файл (`log_err`), но не выводил пользователю.** В `.ps1`
  ветки уже показывали `Say 'UnpackFailed'`, в `.sh` — нет. Fix:
  `tf UnpackFailed ... >&2` в каждой ветке (нет утилиты / утилита упала).

### Changed
- **Версия поднята 1.0.0 → 1.0.1.** `TOOL_VERSION` в `.sh` / `.ps1`,
  заголовок `.cmd`, `title`.
- **`.ps1`: добавлены хелперы `Get-AdbDevices` / `Get-FastbootDevices`** —
  единая точка сбора аргументов `devices` с учётом `-s`.
- **Лог-шапка:** в SESSION START добавлена строка `Serial: ...` (или
  `(auto)`), чтобы в логе было видно, был ли задан `-Serial`.

## [1.0.0] — 2026-10-09

**Первый стабильный релиз.** Полный паритет Windows/Linux по функциям
бэкапа и проверки версий, строгий режим, фикс критического бага стриминга
в Linux-версии, унификация i18n и Pause-поведения.

### Added
- **`Backup-DataStream` в PowerShell.** Полный порт Linux-версии:
  `adb exec-out tar` → буферный цикл 64 КБ → `7z -si` через stdin.
  Прогресс через `Write-Progress` каждые 500 мс (`MB @ MB/s`).
  - `stderr` от `adb` идёт в консоль (без 4-КБ-deadlock).
  - `WaitForExit()` без таймаута после закрытия stdin 7z.
  - Exceptions принудительно убивают оба процесса (без orphaned 7z).
  - `-s Serial` пробрасывается в `adb exec-out`.
  - Логирование mount-операций и probe `tar --exclude`.
- **`Test-ToolVersions` (обе платформы).** Проверяет не только наличие,
  но и версию: `adb ≥ 33.0.0`, `fastboot ≥ 33.0.0`, `7-Zip ≥ 22.00`
  (Windows — обязательный; Linux — опционально), `zstd ≥ 1.0` (если
  установлен). Три исхода: «не найден» / «версия не определена» /
  «версия устарела».
- **`-StrictVersions` / `--strict-versions`.** Hard-fail на любом
  version problem. Пробрасывается через `.cmd` без изменений (`%*`).
- **`Pause()` через `[Console]::ReadKey($true)`** в PowerShell — реально
  «любая клавиша», а не Enter. Fallback на `Read-Host` в non-interactive.
- **i18n: 90+ ключей EN/RU** в паритете между `.ps1` и `.sh`. Хелпер
  `tf KEY arg1 ...` в bash (аналог `-f` в PowerShell) для
  параметризованных строк.
- **`fb_tolerant` (bash) / `-Tolerant` (PS)** — non-zero exit от
  `fastboot reboot fastboot` на MTK не считается ошибкой. Убирает
  двойное сообщение `[WARN] fastboot exit` + `[ERROR] TIMEOUT`.
- **Отдельные таймауты для flash и backup.** `FLASH_TIMEOUT=3600`,
  `BACKUP_TIMEOUT=3600`. Раньше использовался общий `REBOOT_TIMEOUT=30`,
  что убивало прошивку 2 ГБ GSI через USB 2.0 на ~90-й секунде.

### Fixed
- **Критично (Linux): `backup_data_stream` писал пустой файл.**
  Функция вызывала `adb_ shell "tar -c ..."`, а `adb_()` использует
  `out=$(...)` и **не отдаёт вывод в stdout** — пайп `| pv | lz4`
  получал пустоту. При этом `rc` брался от `lz4` (0), а не от `adb`.
  Плюс `tar`-probe страдал тем же.
  Фикс: прямой `adb exec-out` (без CRLF-конверсии `adb shell`),
  `set -o pipefail` + `PIPESTATUS[0]` для корректного `rc`.
- **Критично (PowerShell): `Invoke-Fb` использовал `REBOOT_TIMEOUT`
  (30 с) для всех вызовов, включая `fastboot flash`.** Прошивка
  реального GSI на 2 ГБ стабильно убивалась `Kill()` по таймауту.
  Фикс: параметр `-TimeoutSec` (default 30), для flash — 3600.
- **Windows: `Select-SystemImage` мог вернуть `.img.xz`, но
  `Resolve-SystemImage` не находил `7z.exe`** и возвращал `$null`
  без явного указания причины. Теперь — понятное сообщение
  `Need 7-Zip for .xz` через i18n.
- **Linux: `interactive_file_select` / `select_system_image` —
  ложное «файл найден» при отсутствии масок.** Из-за
  `shopt -u nullglob` массив содержал литерал `*.img`.
  Фикс: `shopt -s nullglob` + проверка `${#files[@]} -eq 0`.
- **Linux: `wait_for_adb` / `wait_for_fastboot` — CRLF в выводе
  `adb devices` / `fastboot devices` на MTK.** Добавлен `tr -d '\r'`
  перед `grep` (паритет с фиксом `.ps1` от 0.9.9).
- **Обе: `free_super_space` / `Invoke-FreeSuperSpace` — двойное
  сообщение при MTK-специфичном non-zero exit `fastboot reboot fastboot`.**
  Теперь через tolerant-обёртку.

### Changed
- **Версия поднята 0.9.9 → 1.0.0.** `TOOL_VERSION` в `.sh` / `.ps1`,
  заголовок `.cmd`, `title`.
- **`check_tool_versions` (bash)** — переписан с `version_ge` через
  `sort -V` (семантическое сравнение, не лексикографическое).
- **`gsi-tool.cmd`** — структурно без изменений (`%*` уже пробрасывает
  новые флаги), только версия в `title`.
- **Все строки на русском/английском в `.sh` и `.ps1`** вынесены в
  i18n-таблицы. Добавлены ключи для: SHA256-блока, vbmeta, backup,
  tool check, size check, super reconstruction, slot ops, GKI, emergency.

## [0.9.9] — 2026-09-17

**PowerShell rewrite (Windows) + i18n + tool version checks.**
Крупный архитектурный релиз: Windows-версия переведена с `cmd.exe` +
`helper.ps1` на монолитный `gsi-tool.ps1`. Добавлены мультиязычность
и проверки окружения. Логика flash синхронизирована с Linux-версией.

### Added
- **PowerShell-порт Windows-версии.** Замена `.cmd` + `helper.ps1`
  на монолитный `gsi-tool-0.9.9.ps1`.
  - Launcher `.cmd` сокращён до 5 строк: только `powershell -File`.
  - Упразднён `helper.ps1` — все функции внутри основного скрипта.
  - Ноль spawn'ов PowerShell на каждый чих — все операции в одном
    процессе.
  - `System.Diagnostics.Process` + `ReadToEndAsync()` для захвата
    stdout/stderr fastboot — надёжный `ExitCode`, никаких deadlock'ов.
- **Мультиязычность EN/RU (обе платформы).**
  - Auto-detect из `$PSUICulture` / `$LANG` / `CurrentUICulture` /
    `InstalledUICulture`.
  - Override: `-Lang en|ru` (PS), `--lang=en|ru` (bash).
  - Тексты встроены в скрипт (хеш-таблица в PS, ассоциативные
    массивы в bash). Комментарии в коде — английские.
- **Проверка версий и наличия внешних утилит.**
  - `adb` / `fastboot` — обязательно наличие, печатается версия.
  - `timeout`, `od` (Linux) — обязательно наличие.
  - 7-Zip — печатается путь; отсутствие = warning.
- **Architecture check.**
  - Linux: только `x86_64` / `aarch64`, иначе hard fail.
  - Windows: `Is64BitOperatingSystem` + `Is64BitProcess`.
- **CLI-флаги.**
  - PS: `-Lang`, `-Serial`, `-Version`, `-Help`.
  - Bash: `--lang=`, `--serial=`, `--version`, `--help`.
- **`-Serial` / `--serial` — таргетинг конкретного устройства** при
  нескольких подключённых (пробрасывается во все `adb`/`fastboot`).
- **Build identifier (`+build.<hash>`) в UI и логе.** Не накручивает
  SemVer, даёт уникальную метку для каждой сборки. Источник:
  `git rev-parse --short HEAD` если есть `.git`, иначе timestamp
  `YYYYMMDD.HHmm`.
- **Полное логирование с уровнями.**
  - `[INFO]` / `[WARN]` / `[ERROR]` с таймстемпом.
  - Каждое действие меню, каждая команда fastboot/adb, каждый
    confirm, каждый выбор файла — попадают в лог.
  - Сырой вывод внешних утилит пишется через `LogRaw`.
- **Раздельные таймауты.** `WAIT_ADB=15s`, `WAIT_FASTBOOT=60s`
  (MTK reboot в fastbootd реально занимает ~35 сек), `REBOOT_TIMEOUT=30s`.
- **`backup_data_stream` — полный порт на Linux.** Исключения
  `media`, `dalvik-cache`, `tombstones`, `dropbox`, fallback на
  GNU tar если BusyBox не поддерживает `--exclude`.
- **`flash_gki_cores` / `emergency_slot_fix` — портированы на обе
  платформы.** Выбор `boot*.img` / `vendor_boot*.img` через
  интерактивный файловый селектор.
- **Warning про `set_active` в fastbootd на MTK.** Перед попыткой
  смены слота проверяется `is-userspace`; если `yes` — предупреждение
  и confirm, потому что MTK fastbootd обычно отказывает.
- **Size check при выборе системного образа.** Рядом с именем каждого
  кандидата показывается размер (`[1.55 GB]`), подозрительно маленькие
  помечаются `[N MB] SUSPICIOUS` (<100 MB) или `[N MB] small`
  (100–300 MB). При наличии «подозрительных» — warning + confirm перед
  продолжением. Защищает от прошивки недокачанного или обрезанного GSI.
- **Убран номер версии из имён файлов.** Файлы называются
  `gsi-tool.sh`, `gsi-tool.ps1`, `gsi-tool.cmd` — версия живёт
  только внутри (`TOOL_VERSION`) и в имени релизного архива.
  Упрощает обновление: пользователь перезаписывает файлы,
  а не копирует рядом с старыми.

### Fixed
- **Windows: `Start-Process -RedirectStandardOutput` не заполнял
  `ExitCode`.** Симптом: `fastboot` успешно отрабатывал, но
  скрипт показывал `FAILED`. Причина: `WaitForExit(ms)` возвращает
  управление до слива потоков, `ExitCode` пустой.
  Фикс: `System.Diagnostics.Process` + асинхронный `ReadToEndAsync()`
  для stdout/stderr + `WaitForExit()` без таймаута после слива.
- **Windows: `\r` в `adb devices` / `fastboot devices` ломал regex.**
  Фильтр `-match '\sdevice$'` не матчил `device\r`.
  Фикс: `ForEach-Object { $_.Trim() }` перед regex.
- **Windows: `set_active` не проверял результат.** При провале
  (`Unable to set slot` на MTK) `CURRENT_SLOT` всё равно
  переключался, и следующая команда шла в никуда.
  Фикс: переключение `CURRENT_SLOT` только при success.
- **Windows: двойной `Pause` после пунктов меню.** `Pause` был
  и в `switch`, и после него.
- **Windows: `Action menu → 0` завершал скрипт, а не возвращал в
  главное меню.** `break` внутри `switch` в PowerShell выходит
  только из `switch`. Фикс: внешний цикл + флаг `$Script:BackToMain`.
- **Linux: `Get-FastbootVar` мог захватить `\r` в значение.**
  Regex `\S+` → `[^\s\r\n]+`.
- **Обе: `.Trim()` значений из `getvar` перед использованием.**
- **Windows: окно cmd закрывалось сразу после успешной прошивки.**
  `exit 0` в конце `Do-Flash` возвращал в `.cmd` код 0, блок
  `if %errorlevel% neq 0 ( pause )` не срабатывал, окно закрывалось
  мгновенно — пользователь не успевал увидеть «Готово.» и лог.
  Добавлен `Pause` перед `exit 0` во всех финальных ветках
  (`slot`/`update`/`reset`/`dirty`) и в `Restore-EmergencySlots`.
- **Windows: `Invoke-FreeSuperSpace` игнорировал результат `fastboot
  reboot fastboot`.** При провале команды скрипт всё равно запускал
  60-секундный `Wait-Fastboot` впустую. Теперь результат проверяется,
  при провале — немедленный выход с понятной ошибкой.
- **Windows: `$LASTEXITCODE` после `7z ... | Out-Null` мог терять
  реальный код возврата.** Заменено на `> $null` во всех трёх
  распаковках (`.xz/.gz/.zst`) — гарантирует правильную обработку
  ошибок 7-Zip (кончилось место, битый архив).
- **Windows: `fastboot reboot fastboot` на MTK рвёт USB до ACK.**
  Загрузчик уходит в ребут быстрее, чем `fastboot.exe` получает
  подтверждение → `ExitCode = 1` или `-1 (Connection reset)`, хотя
  ребут реально произошёл. Проверка кода возврата убрана —
  полагаемся на `Wait-Fastboot`, как и в главном меню.
- **Linux: `${var,,}` (Bash 4.0+) → `tr 'A-F' 'a-f'`.** Приведение
  регистра хеша через POSIX-совместимый конвейер. Синтаксис Bash 4.x
  работал, но `tr` надёжнее в embed-окружениях с урезанным bash.

### Changed
- Windows: `gsi-tool-0.9.8.cmd` + `gsi-tool-helper-0.9.8.ps1` →
  `gsi-tool-0.9.9.ps1` (монолит) + `gsi-tool-0.9.9.cmd` (launcher 5 строк).
- Linux: `gsi-tool-0.9.8.sh` → `gsi-tool-0.9.9.sh` (рефакторинг под
  общий стиль i18n + логирование + CLI-флаги).
- Все строки на русском в коде вынесены в i18n-таблицу.
- Комментарии в коде переведены на английский.
- Версия в меню и логе показывается как `0.9.9+build.<hash>`;
  `--version` возвращает чистый `0.9.9` (SemVer для скриптов/CI).

### Removed
- `gsi-tool-helper-0.9.8.ps1` — упразднён, код слит в `gsi-tool-0.9.9.ps1`.
- Множественные `spawn powershell.exe` из `.cmd` (ныне один процесс).
- Дублирующие таймауты `WAIT_TIMEOUT` (разделены на ADB / Fastboot).

## [0.9.8] — 2026-09-15

**Interactive SHA256 verification + decompression progress.**
Первая функциональная фича после серии «safety-first» ревизий.

### Added
- **Интерактивная SHA256-верификация образов.** Перед `free_super_space`
  скрипт запрашивает эталонный хеш:
  1. Если рядом лежит `${SYSTEM_IMG}.sha256` — берётся оттуда.
  2. Иначе — предложение вставить хеш вручную (например, из UI GitHub).
     Парсится regex `[a-f0-9]{64}`, пробелы и мусор игнорируются.
  3. Enter → silent skip.
  Реализовано:
  - `helper.ps1`: режим `verify_sha256`, параметр `-Hash`
  - `.cmd`: блок в `:free_super_space`
  - `.sh`: тот же блок на bash + `sha256sum` + `pv` (если есть)
- **Прогресс-бар декомпрессии на Windows.** 7-Zip вызывается с
  `-bso0 -bsp1` — виден прогресс распаковки `.xz/.gz/.zst`.
- **Симметрия `fb_reboot` в action menu.** После `call :fb_reboot`
  в каждом блоке (flash/update/reset/dirty/emergency) добавлено
  короткое сообщение, если reboot не удался.

### Fixed
- **Helper `verify_sha256` — совместимость с PowerShell 7.**
  `SHA256Managed` устарел в .NET Core, используем
  `[System.Security.Cryptography.SHA256]::Create()`.
- **Helper `verify_sha256` — защита от больших `.sha256`.**
  Файл >4 КБ игнорируется (`error_file_too_large`).
- **Regex групповой захват** — используем `$Matches[1]` /
  `${BASH_REMATCH[1]}`, а не `[0]`.
- **CHANGELOG 0.9.7 formulation** — «вызывающие проверяют» относилось
  только к критичным местам; в action menu проверка не критична.

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
- Linux `.sh`: обновлена шапка файла `0.9.5 → 0.9.6`.

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
  Фикс: stderr направляется в консоль (`RedirectStandardError = $false`).
- **Критично (Windows): отсутствие таймаута в `stream_backup`.**
  Добавлен `-StreamTimeout 3600` (1 час).
- **Важно (Windows): `ADB_CMD` с одинарными кавычками.**
  В цепочке `cmd → PowerShell → .NET → adb → shell` одинарные кавычки
  вокруг `--exclude='media'` могут теряться или искажаться. Для имён без
  пробелов они не нужны — убраны.
- **Важно (Windows): `adb reboot bootloader` / `adb reboot fastboot` без
  таймаута и логирования.** Теперь через helper `-Mode adb_reboot`.
- **Профилактика (Windows): `calculate_partition` — try/catch на cast.**
  Если кто-то передаст нечисловой `-Path`, ловим `InvalidCastException`.
- **Проверка (helper): `${actual}:${expected}` вместо `$actual:$expected`.**
  В PowerShell `$var:name` — drive-qualified reference. Не экранированное
  двоеточие вызывало `ParserError: InvalidVariableReferenceWithDrive`.

### Changed
- Linux `.sh`: обновлена шапка `0.9.4 → 0.9.5`.
- Windows `.cmd`: `HELPER` путь → `gsi-tool-helper-0.9.5.ps1`.
- Windows helper: новый режим `adb_reboot`.
- Windows helper: параметр `-StreamTimeout`.

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
- **Профилактика (Windows): `calculate_partition` теперь целочисленный.**
  `[Math]::Ceiling($raw / $align)` через `[Double]` заменён на
  `[Math]::DivRem` с `[UInt64]`. Плюс short-circuit на `$raw = 0`.
- **Linux: fallback для BusyBox tar без `--exclude`.**
  Проверка поддержки через пробный вызов `tar -cf /dev/null`.

## [0.9.3] — 2026-09-15

**Safety-first release, revision 3.** Три фикса по итогам второго аудита.

### Fixed
- **`flash_slot` (обе платформы): не было reboot.** После прошивки в
  указанный слот устройство оставалось в fastbootd.
- **Windows `fb_reboot`: результат `error` молча игнорировался.**
  Теперь `error` обрабатывается с явным предупреждением.
- **Кроссплатформенная унификация фильтра `select_system_img`.**
  Linux и Windows по-разному отсеивали не-системные образы:
  `boot.img.xz` / `vendor.img.gz` проходили на Linux, `vendor_dlkm.img`
  на Windows. Теперь единый superset-подход.

### Changed
- Linux `safe_reboot` теперь различает timeout (124) и error.

## [0.9.2] — 2026-09-15

**Safety-first release, revision 2.** Дочищены дефекты второго аудита 0.9.1.

### Fixed
- **Критично (Windows): `set /a` overflow при расчёте `need_mb`** для
  `.img.xz` >2 ГБ. Batch `set /a` работает с 32-битным signed int.
  Заменено на PowerShell через `helper.ps1 -Mode need_mb_x3 / need_mb_x4`.
- **Критично (Windows): `fallback_backup` без проверок errorlevel.**
  Три команды (`adb shell tar`, `adb pull`, `adb shell rm`).
- **Критично (Linux): `fastboot -w || true` маскировал провал wipe.**
- **Windows: `check_bootloader_unlocked` без проверки `get_unlock_ability`.**
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
- Sparse-aware определение размера образа (magic `3aff26ed`,
  `blk_sz × total_blks`).
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
