
---

## `TODO.md` — v1.0.1

```markdown
# TODO

## Идеи (не срочно)
- [ ] Флаг `-Admin` для Windows (запуск с повышением прав)
- [ ] Автоматическая проверка обновлений скрипта через GitHub API
- [ ] Экспорт отчёта о прошивке в JSON

## 1.1.0
- [ ] DSU Sideloader integration — запуск второй GSI без изменения слотов
- [ ] Клон слота A → B — дублирование system/vendor/boot/dtbo
- [ ] Auto-defragment super — дефрагментация контейнера super через lptools
- [ ] `lpmake` on-device — пересборка super на устройстве, если GSI не влезает
- [ ] Унификация логики бэкапа между `.sh` и `.ps1` (единый формат архива)
- [ ] Mac-поддержка (Darwin, gtimeout, gstat, gdf, gsha256sum) или отдельная ветка
- [ ] Backup critical partitions (nvram / persist / modemst) через dd из recovery
- [ ] `set -u` в Linux (после аудита всех переменных)
- [ ] Объединение helper-вызовов в `super_prep` (Linux)
- [ ] Финальный smoke-тест на живом GSI (Lunaris) + публикация репо

## Выполнено в 1.0.1 (2026-10-09)
- [x] Fix: `Get-FastbootVar` в `.ps1` не пробрасывал `-s Serial` → `getvar` уходил на случайное устройство
- [x] Fix: `Wait-Adb` / `Wait-Fastboot` в `.ps1` не пробрасывали `-s Serial`
- [x] Fix: `Test-ToolVersions` (обе платформы) не увеличивал счётчик проблем при «version unknown»
- [x] Fix: `.sh` бэкап без таймаута — добавлен `BACKUP_TIMEOUT=3600` + `timeout` вокруг `adb exec-out`
- [x] Fix: `.sh` probe `tar --exclude` не отличал «tar без --exclude» от «adb отвалился»
- [x] Fix: `.sh` `resolve_system_image` не показывал `UnpackFailed` пользователю
- [x] Унифицированные шапки `.sh` / `.ps1` / `.cmd` (репо, лицензия, назначение)
- [x] Предупреждение про IMEI / MAC / Widevine при бэкапе `/data`
- [x] Прогресс-бар распаковки через `pv` в `.sh`

## Выполнено в 1.0.0 (2026-10-09)
- [x] Порт `backup_data_stream` в PowerShell (Write-Progress + буферный цикл 64 КБ)
- [x] Проверка версий утилит (adb/fastboot ≥ 33.0.0, 7-Zip ≥ 22.00, zstd ≥ 1.0)
- [x] Флаг `--strict-versions` / `-StrictVersions` — жёсткий отказ на любом warning
- [x] Фикс двойного сообщения в Windows `free_super_space` при `fb_reboot error`
- [x] `Pause()` через `[Console]::ReadKey($true)` вместо `Read-Host`
- [x] i18n: добить оставшиеся хардкодные строки в service-функциях
- [x] Критический фикс Linux-бэкапа: `adb exec-out` вместо буферизующего `adb_()`
- [x] Отдельные таймауты flash / backup (были 30 с для всех вызовов)
- [x] `fb_tolerant` на MTK для `reboot fastboot`
- [x] CRLF-strip в wait-хелперах на Linux
- [x] `shopt -s nullglob` в file-select на Linux