# Roadmap

## Выполнено в 1.0.1 (2026-10-09)
- **Fix-релиз**: закрыты 6 багов, найденных при перечитывании 1.0.0:
  - `.ps1`: `Get-FastbootVar` / `Wait-Adb` / `Wait-Fastboot` не пробрасывали `-s Serial` — команды уходили на случайное устройство при нескольких подключённых
  - Обе платформы: `Test-ToolVersions` не увеличивал счётчик при «version unknown» — `-StrictVersions` не ловил этот случай
  - `.sh`: бэкап без `BACKUP_TIMEOUT` — при зависании `adb exec-out` пайплайн ждал вечно
  - `.sh`: probe `tar --exclude` не отличал «tar без поддержки» от «adb отвалился»
  - `.sh`: `resolve_system_image` не показывал ошибку распаковки пользователю
- **Унифицированные шапки** `.sh` / `.ps1` / `.cmd` — единый формат с репо и лицензией.
- **Предупреждение про IMEI / MAC / Widevine** при бэкапе `/data`.
- **Прогресс-бар распаковки через `pv`** в `.sh`.

## Выполнено в 1.0.0 (2026-10-09)
- **`Backup-DataStream` в PowerShell** — `adb exec-out` → буферный цикл 64 КБ → `7z -si` через stdin, прогресс `Write-Progress`, `-s Serial` пробрасывается, exceptions убивают оба процесса.
- **`Test-ToolVersions`** — проверка не только наличия, но и версии: `adb`/`fastboot` ≥ 33.0.0, 7-Zip ≥ 22.00, `zstd` ≥ 1.0.
- **`-StrictVersions` / `--strict-versions`** — hard-fail на любом problem.
- **`Pause()` через `[Console]::ReadKey($true)`** в PowerShell — реально «любая клавиша».
- **i18n: 90+ ключей EN/RU** в паритете между `.ps1` и `.sh`.
- **`fb_tolerant` / `-Tolerant`** — MTK-специфичный non-zero от `reboot fastboot` не считается ошибкой.
- **Отдельные таймауты flash / backup** — `FLASH_TIMEOUT=3600`, `BACKUP_TIMEOUT=3600`.
- **Фикс критического бага Linux-бэкапа** — `adb exec-out` вместо буферизующего `adb_()`, `set -o pipefail` + `PIPESTATUS[0]`.

## Выполнено в 0.9.9 (2026-09-17)
- PowerShell-порт Windows-версии: монолитный `gsi-tool.ps1` + launcher `.cmd` (5 строк)
- Упразднён `helper.ps1`
- Мультиязычность EN/RU (auto-detect + флаги `-Lang` / `--lang=`)
- Проверка наличия внешних утилит
- Architecture check (x86_64 / aarch64, 64-bit Windows)
- CLI-флаги: `-Serial`, `-Version`, `-Help` (PS) / `--serial=`, `--version`, `--help` (bash)
- Build identifier (`+build.<hash>`) в UI и логе
- Полное логирование с уровнями (INFO/WARN/ERROR)
- Раздельные таймауты (ADB / Fastboot / Reboot)
- SHA256-верификация образов
- Автоматическая распаковка `.img.xz/.gz/.zst`
- Реконструкция `super` с выравниванием и margin
- Прошивка GKI-ядер и экстренный откат
- Защита от `set_active` в fastbootd на MTK
- Size check при выборе системного образа

## 1.1.0
- **DSU Sideloader integration** — запуск второй GSI без изменения слотов.
- **Клон слота A → B** — дублирование `system`/`vendor`/`boot`/`dtbo` для безопасных экспериментов.
- **Auto-defragment super** — дефрагментация контейнера `super` через `lptools`.
- **`lpmake` on-device** — пересборка super на устройстве, если GSI не влезает после delete.
- **Унификация логики бэкапа** между `.sh` и `.ps1` (единый формат архива).
- **Mac-поддержка** (`uname -m` Darwin, `gtimeout`, `gstat`, `gdf`, `gsha256sum`).
- **Backup critical partitions** — nvram / persist / modemst через `dd` из recovery.
- **`set -u` в Linux** — после аудита всех переменных.
- **Объединение helper-вызовов** в `super_prep` (Linux).

## 2.0.0 (идеи)
- GUI-обёртка (Electron / Tauri) для Windows и Linux.
- Поддержка не-A/B устройств (A-only) с автоматическим определением.
- Интеграция с GitHub Releases для автоматической загрузки GSI.
- Экспорт отчёта о прошивке в JSON / HTML.
- Флаг `-Admin` для Windows (запуск с повышением прав).
- Автоматическая проверка обновлений скрипта через GitHub API.