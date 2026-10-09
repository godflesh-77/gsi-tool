# gsi-tool

**GSI flash & service tool для Android-устройств с A/B-разметкой и динамическими разделами (Dynamic Partitions / Super).**

Кроссплатформенная утилита для прошивки Generic System Images (GSI), управления слотами, сервисного обслуживания и резервного копирования. Написана с приоритетом безопасности: скрипт делает максимум проверок до того, как коснётся разделов.

---

## Возможности

- **Прошивка GSI** в активный или указанный слот (`system_a` / `system_b`)
- **Автодетект A/B** через `fastboot getvar slot-count`
- **Проверка разблокировки загрузчика** до любых деструктивных операций
- **Sparse-aware** определение реального размера образа (raw vs sparse)
- **Автоматическая реконструкция `super`** — удаление `system`/`product`/`system_ext` в обоих слотах с пересозданием нужного раздела (+4096 align +256 МБ margin)
- **Не трогает** `vendor`, `odm`, `vendor_dlkm`, `system_dlkm` — критично для GKI-устройств
- **SHA256-верификация** образа перед прошивкой: из файла `<image>.sha256` или интерактивный ввод хеша из GitHub
- **Автоматическая распаковка** `.img.xz` / `.img.gz` / `.img.zst` (Linux — с прогресс-баром через `pv`, если установлен)
- **Бэкап `/data`** через ADB-стрим на обеих платформах:
  - Windows — `adb exec-out` → буферный цикл 64 КБ → `7z -si` (прогресс через `Write-Progress`)
  - Linux — `adb exec-out` → `pv` → `lz4`/`gzip` (при наличии `pv` и `lz4` — быстрый бэкап)
- **Предупреждение про IMEI / MAC / Widevine** при бэкапе `/data` — эти данные лежат в `/persist`, `/nvram`, `/modemst*`, `/misc`, и в `/data` их нет
- **Прошивка GKI-ядер** (`boot` + `vendor_boot`) в активный слот
- **Экстренный откат** — двойная запись ядер в оба слота + `set_active a`
- **Логирование** всех операций в `logs/`
- **Защита от Ctrl+C** в критических секциях (Linux)
- **Мультиязычность** EN/RU с автоопределением и флагами `-Lang` / `--lang=`
- **Проверка версий** внешних утилит (не только наличия): `adb`/`fastboot` ≥ 33.0.0, 7-Zip ≥ 22.00, `zstd` ≥ 1.0
- **Флаг `-StrictVersions` / `--strict-versions`** — hard-fail при любом version problem (включая случай «версия не распознана»)
- **Таргетинг конкретного устройства** через `-Serial` / `--serial=` — все `adb`/`fastboot` вызовы (включая `getvar`, `devices`, `wait`) пробрасывают `-s`
- **CLI-флаги** для автоматизации: `-Serial`, `-StrictVersions`, `-Version`, `-Help` (PS) / `--serial=`, `--strict-versions`, `--version`, `--help` (bash)
- **Build identifier** (`+build.<hash>`) в UI и логе для точной идентификации сборки

---

## Требования

| Компонент | Минимум |
|---|---|
| **Android platform-tools** (`adb`, `fastboot`) | 33.0.0 (Android 13) |
| **7-Zip** (Windows — обязателен для `.xz`/`.gz`/`.zst` и для бэкапа) | 22.00 |
| **Linux-утилиты** | `adb`, `fastboot`, `timeout`, `od`, `df`, `awk` (coreutils), `sha256sum`, `grep`, `tr` |
| **Опционально (Linux)** | `pv` + `lz4` — быстрый бэкап и прогресс распаковки; `unxz`, `gunzip`, `zstd` — распаковка образов |
| **ОС** | Windows 10/11 x64, Linux x86_64 / aarch64 |
| **Устройство** | A/B (или non-A/B) с разблокированным загрузчиком |

**Не поддерживается:** Windows 7/8/8.1, 32-bit Windows, 32-bit Linux (i386, ARMv7).

---

## Установка

### Windows

1. Скачайте релиз `gsi-tool-<version>.zip` со страницы [Releases](../../releases).
2. Распакуйте в любую папку.
3. Убедитесь, что `adb.exe` и `fastboot.exe` доступны либо в `PATH`, либо лежат в той же папке.
4. Скачайте [7-Zip 22.00+](https://www.7-zip.org/) и положите `7z.exe` + `7z.dll` рядом со скриптом (или установите 7-Zip в `Program Files`).
5. Запустите `gsi-tool.cmd`.

### Linux

1. Скачайте `gsi-tool.sh` из релиза.
2. Дайте права на исполнение:
   ```bash
   chmod +x gsi-tool.sh
Убедитесь, что adb / fastboot из platform-tools 33.0.0+ есть в PATH.

(Опционально, для быстрого бэкапа и прогресса распаковки) установите pv и lz4:

bash
sudo apt install pv lz4    # Debian/Ubuntu
sudo pacman -S pv lz4      # Arch
sudo dnf install pv lz4    # Fedora
Запустите:

bash
./gsi-tool.sh
CLI
Флаг (PS / bash)	Описание
-Lang en|ru / --lang=en|ru	Форсировать язык UI (по умолчанию — авто из $PSUICulture / $LANG)
-Serial <serial> / --serial=<serial>	Таргетинг конкретного устройства при нескольких подключённых
-StrictVersions / --strict-versions	Hard-fail при любом problem в версиях утилит, включая «версия не распознана»
-Version / --version / -v	Показать версию (1.0.1, без build-суффикса)
-Help / --help / -h	Показать справку
Примеры:

powershell
.\gsi-tool.cmd -Serial ABC123 -StrictVersions
bash
./gsi-tool.sh --serial=ABC123 --strict-versions
Безопасность
Скрипт никогда не форматирует раздел без явного подтверждения.

Перед fastboot flash проверяется результат каждой команды.

При провале create-logical-partition скрипт останавливается и печатает DO NOT REBOOT.

При SHA256-mismatch требуется дополнительный confirm.

При обнаружении подозрительно маленького образа (<100 МБ) — warning + confirm.

При бэкапе /data выводится предупреждение: IMEI, MAC Wi-Fi/Bluetooth и ключи Widevine не входят в этот бэкап — они в /persist, /nvram, /modemst*, /misc.

Известные особенности
MTK fastbootd: fastboot reboot fastboot часто возвращает ненулевой exit code, хотя устройство реально перезагружается (загрузчик рвёт USB до ACK). Скрипт использует tolerant-обёртку и полагается на wait_for_fastboot, а не на exit code.

MTK fastbootd: set_active обычно не работает — используйте bootloader (не fastbootd) для переключения слота. Скрипт предупреждает об этом перед попыткой.

MTK -w: fastboot -w иногда ругается на нестандартный layout. В Linux-версии rc игнорируется (продолжаем), в Windows-версии — предупреждение в лог.

Лицензия
MIT. См. LICENSE.
