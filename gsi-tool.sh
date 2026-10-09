#!/bin/bash
# ==============================================================================
# GSI FLASH & SERVICE TOOL 1.0.2 (Linux)
# Flash GSI, manage A/B slots, back up /data, service partitions.
#
# Repository: https://github.com/godflesh-77/gsi-tool
# License:    MIT
# ==============================================================================

TOOL_VERSION="1.0.2"

if command -v git >/dev/null 2>&1 && [ -d .git ]; then
    BUILD=$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d.%H%M)
else
    BUILD=$(date +%Y%m%d.%H%M)
fi
FULL_VERSION="${TOOL_VERSION}+build.${BUILD}"

# --------- defaults ---------
LANG_CODE="en"
FORCE_LANG=""
SERIAL=""
STRICT_VERSIONS="no"
WAIT_ADB=15
WAIT_FASTBOOT=60
REBOOT_TIMEOUT=30
FLASH_TIMEOUT=3600
BACKUP_TIMEOUT=3600
UNPACK_TIMEOUT=3600
MARGIN_MB=256

IS_AB_DEVICE="yes"
CURRENT_SLOT="a"
LOG=""
SELECTED_FILE=""
SYSTEM_IMG=""

# ==============================================================================
# CLI flags
# ==============================================================================
for arg in "$@"; do
    case "$arg" in
        --version|-v) echo "$TOOL_VERSION"; exit 0 ;;
        --help|-h)
            echo "GSI Flash Tool $TOOL_VERSION"
            echo "Build: $BUILD"
            echo "Usage: $0 [--lang=en|ru] [--serial=<serial>] [--strict-versions] [--version] [--help]"
            exit 0
            ;;
        --lang=*)          FORCE_LANG="${arg#--lang=}" ;;
        --serial=*)        SERIAL="${arg#--serial=}" ;;
        --strict-versions) STRICT_VERSIONS="yes" ;;
    esac
done

# ==============================================================================
# Architecture check
# ==============================================================================
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|aarch64) : ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        echo "Supported: x86_64, aarch64"
        exit 1
        ;;
esac

# ==============================================================================
# i18n
# ==============================================================================
declare -A MSG_EN MSG_RU

MSG_EN[MainMenuTitle]="GSI Flash Tool"
MSG_EN[LogFile]="Log"
MSG_EN[MenuCheckDev]="Check devices (ADB / Fastboot)"
MSG_EN[MenuFromAndroid]="Android  -> Fastbootd"
MSG_EN[MenuFromRecovery]="Recovery -> Fastbootd"
MSG_EN[MenuFromBoot]="Bootloader -> Fastbootd"
MSG_EN[MenuAlreadyFb]="Already in Fastbootd"
MSG_EN[ServiceMenu]="SERVICE MENU"
MSG_EN[Exit]="Exit"
MSG_EN[Input]="Input: "
MSG_EN[Back]="Back"
MSG_EN[ActiveSlotLine]="Active slot: %s  [A/B: %s]"

MSG_EN[ActionUpdate]="Update system"
MSG_EN[ActionReset]="Reset and flash (Full Wipe)"
MSG_EN[ActionSlot]="Flash to specified slot (A/B)"
MSG_EN[ActionSwitch]="Switch active slot"
MSG_EN[ActionDirty]="Dirty flash"

MSG_EN[Backing]="Backup /data via ADB stream"
MSG_EN[FlashingGki]="Flash GKI kernels (boot + vendor_boot)"
MSG_EN[EmergencyFix]="Emergency dual-slot restore"

MSG_EN[CheckingBl]="Checking bootloader state..."
MSG_EN[BlUnlocked]="Bootloader: UNLOCKED"
MSG_EN[BlLocked]="CRITICAL: Bootloader is LOCKED!"
MSG_EN[BlOemDisabled]="ERROR: OEM Unlock disabled in Android!"

MSG_EN[WaitAdb]="Waiting for ADB device"
MSG_EN[WaitFastboot]="Waiting for Fastboot device"
MSG_EN[Timeout]="[TIMEOUT]"
MSG_EN[Ok]="[OK]"

MSG_EN[Error]="ERROR"
MSG_EN[Warning]="WARNING"
MSG_EN[Cancel]="Cancelled."
MSG_EN[InvalidChoice]="Invalid choice."
MSG_EN[PressKey]="Press Enter to continue..."
MSG_EN[EnterConfirm]="Continue? (y/N): "
MSG_EN[EnterSlot]="Enter slot (a/b): "
MSG_EN[FlashOk]="Done."

MSG_EN[ToolCheck]="Tool version check"
MSG_EN[ToolMissing]="not found"
MSG_EN[VersionTooOld]="version too old (need >= %s)"
MSG_EN[VersionUnknown]="version unknown"
MSG_EN[ToolsWarn]="Some tools missing or too old. Basic operations may not work."
MSG_EN[StrictFail]="Strict version check enabled: aborting on version problems."

MSG_EN[FoundImg]="Found system image"
MSG_EN[NoSystemImg]="No system images found."
MSG_EN[ChooseImg]="Found multiple images. Choose one"
MSG_EN[ImgSuspect1]="WARNING: one or more images are suspiciously small (<100 MB)."
MSG_EN[ImgSuspect2]="         Typical GSI is 600 MB - 4 GB. File may be corrupted,"
MSG_EN[ImgSuspect3]="         incomplete, or not a system image at all."
MSG_EN[ContinueAnyway]="Continue anyway? (y/N): "

MSG_EN[Unpacking]="Unpacking: %s -> %s"
MSG_EN[UnpackFailed]="Unpack failed: %s"
MSG_EN[UnpackProgress]="unpack"
MSG_EN[Need7Zip]="Need 7-Zip for %s"

MSG_EN[RebuildSuper]="SUPER RECONSTRUCTION"
MSG_EN[RebootToFb]="Rebooting to Fastbootd..."
MSG_EN[NotInFbReboot]="Not in Fastbootd, reboot needed"
MSG_EN[TargetPart]="Target partition: %s"
MSG_EN[NewSize]="New size: %s bytes"
MSG_EN[NotTouching]="NOT touching: vendor / odm / vendor_dlkm / system_dlkm"
MSG_EN[SuperBigWarn]="WARNING: partition > 4 GB. MTK overflow possible."
MSG_EN[CreateFailed]="CRITICAL: create-logical-partition failed."
MSG_EN[CreateFailed2]="super left without system/product/system_ext. DO NOT REBOOT."

MSG_EN[ShaHeader]="SHA256 VERIFICATION:"
MSG_EN[ShaFileFound]="[INFO] Found .sha256 file."
MSG_EN[ShaPrompt]="Copy SHA256 hash from GitHub release and paste here (or Enter to skip)."
MSG_EN[ShaPromptShort]="Hash"
MSG_EN[ShaOk]="[SHA256] OK."
MSG_EN[ShaSkipNoHash]="[SHA256] Hash not recognized. Skipping."
MSG_EN[ShaSkipTooBig]="[SHA256] .sha256 too large. Skipping."
MSG_EN[ShaSkipErr]="[SHA256] Hash calculation error. Skipping."
MSG_EN[ShaSkipUser]="[SHA256] Check skipped by user."
MSG_EN[ShaMismatch]="SHA256 mismatch! Real: %s"
MSG_EN[ShaRiskPrompt]="Continue at your own risk? (y/N): "

MSG_EN[VbMissing]="WARNING: vbmeta.img not found. Bootloop possible."
MSG_EN[VbContinueNo]="Continue without vbmeta? (y/N): "
MSG_EN[VbInUserspace]="WARNING: You are in Fastbootd. vbmeta is a physical partition."
MSG_EN[VbFlashing]="Flashing vbmeta..."

MSG_EN[NotAb]="Device is not A/B."
MSG_EN[SetActiveWarn]="WARNING: you are in Fastbootd. set_active may not work on MTK."
MSG_EN[SetActiveTry]="Try anyway? (y/N): "
MSG_EN[CurrentSlotMsg]="Current slot: %s"
MSG_EN[SetActiveFail]="ERROR: set_active failed. On MTK use bootloader, not fastbootd."

MSG_EN[SelectBoot]="Select BOOT (kernel):"
MSG_EN[SelectVendor]="Select VENDOR_BOOT:"
MSG_EN[SelectStableBoot]="Stable BOOT image:"
MSG_EN[SelectStableVb]="Stable VENDOR_BOOT image:"
MSG_EN[FlashToSlot]="Flash to slot _%s? (y/N): "

MSG_EN[BackupTitle]="BACKUP /DATA VIA ADB STREAM"
MSG_EN[BackupWarning]="Ensure device is in recovery (e.g. OrangeFox) and /data is decrypted."
MSG_EN[BackupCriticalWarn]="NOTE: /data backup does NOT include IMEI, Wi-Fi/BT MAC, or Widevine keys."
MSG_EN[BackupCriticalHint]="      Those live in /persist, /nvram, /modemst*, /misc. Back them up separately from recovery."
MSG_EN[BackupMountOk]="Mount check output written to log."
MSG_EN[BackupMountAsk]="Is /data mounted and decrypted? (y/N): "
MSG_EN[BackupNoExcl]="tar does not support --exclude, doing full backup"
MSG_EN[BackupProgress]="Backup /data"
MSG_EN[BackupDone]="Backup OK: %s"
MSG_EN[BackupFailed]="Backup FAILED. See log:"
MSG_EN[BackupNo7Zip]="Backup requires 7-Zip. Install 7-Zip 22.00+ and retry."

MSG_EN[ExitCodeMsg]="Exit code: %s"

MSG_RU[MainMenuTitle]="GSI Flash Tool"
MSG_RU[LogFile]="Лог"
MSG_RU[MenuCheckDev]="Проверить устройства (ADB / Fastboot)"
MSG_RU[MenuFromAndroid]="Android  -> Fastbootd"
MSG_RU[MenuFromRecovery]="Recovery -> Fastbootd"
MSG_RU[MenuFromBoot]="Bootloader -> Fastbootd"
MSG_RU[MenuAlreadyFb]="Уже в Fastbootd"
MSG_RU[ServiceMenu]="СЕРВИСНОЕ МЕНЮ"
MSG_RU[Exit]="Выход"
MSG_RU[Input]="Ввод: "
MSG_RU[Back]="Назад"
MSG_RU[ActiveSlotLine]="Активный слот: %s  [A/B: %s]"

MSG_RU[ActionUpdate]="Обновить систему"
MSG_RU[ActionReset]="Сброс и прошивка (Full Wipe)"
MSG_RU[ActionSlot]="Прошить в указанный слот (A/B)"
MSG_RU[ActionSwitch]="Переключить активный слот"
MSG_RU[ActionDirty]="Грязная прошивка"

MSG_RU[Backing]="Бэкап /data через ADB-стрим"
MSG_RU[FlashingGki]="Прошивка GKI-ядер (boot + vendor_boot)"
MSG_RU[EmergencyFix]="Экстренный откат (оба слота)"

MSG_RU[CheckingBl]="Проверка загрузчика..."
MSG_RU[BlUnlocked]="Загрузчик: РАЗБЛОКИРОВАН"
MSG_RU[BlLocked]="КРИТИЧЕСКАЯ ОШИБКА: Загрузчик заблокирован!"
MSG_RU[BlOemDisabled]="ОШИБКА: в Android выключен OEM Unlock!"

MSG_RU[WaitAdb]="Ожидание ADB-устройства"
MSG_RU[WaitFastboot]="Ожидание Fastboot-устройства"
MSG_RU[Timeout]="[ТАЙМ-АУТ]"
MSG_RU[Ok]="[OK]"

MSG_RU[Error]="ОШИБКА"
MSG_RU[Warning]="ВНИМАНИЕ"
MSG_RU[Cancel]="Отменено."
MSG_RU[InvalidChoice]="Неверный ввод."
MSG_RU[PressKey]="Нажмите Enter для продолжения..."
MSG_RU[EnterConfirm]="Выполнить? (y/N): "
MSG_RU[EnterSlot]="Слот (a/b): "
MSG_RU[FlashOk]="Готово."

MSG_RU[ToolCheck]="Проверка версий утилит"
MSG_RU[ToolMissing]="не найден"
MSG_RU[VersionTooOld]="версия устарела (нужно >= %s)"
MSG_RU[VersionUnknown]="версия не определена"
MSG_RU[ToolsWarn]="Часть утилит отсутствует или устарела. Базовые операции могут не работать."
MSG_RU[StrictFail]="Включён строгий режим проверки: отказ из-за проблем с версиями."

MSG_RU[FoundImg]="Найден образ системы"
MSG_RU[NoSystemImg]="Образы системы не найдены."
MSG_RU[ChooseImg]="Найдено несколько образов. Выберите"
MSG_RU[ImgSuspect1]="ВНИМАНИЕ: один или несколько образов подозрительно малы (<100 МБ)."
MSG_RU[ImgSuspect2]="         Типичный GSI весит 600 МБ - 4 ГБ. Файл может быть повреждён,"
MSG_RU[ImgSuspect3]="         недокачан, или это вовсе не образ системы."
MSG_RU[ContinueAnyway]="Всё равно продолжить? (y/N): "

MSG_RU[Unpacking]="Распаковка: %s -> %s"
MSG_RU[UnpackFailed]="Ошибка распаковки: %s"
MSG_RU[UnpackProgress]="распаковка"
MSG_RU[Need7Zip]="Для %s нужен 7-Zip"

MSG_RU[RebuildSuper]="РЕКОНСТРУКЦИЯ SUPER"
MSG_RU[RebootToFb]="Перезагрузка в Fastbootd..."
MSG_RU[NotInFbReboot]="Не в Fastbootd, нужна перезагрузка"
MSG_RU[TargetPart]="Целевой раздел: %s"
MSG_RU[NewSize]="Новый размер: %s байт"
MSG_RU[NotTouching]="НЕ трогаем: vendor / odm / vendor_dlkm / system_dlkm"
MSG_RU[SuperBigWarn]="ВНИМАНИЕ: раздел > 4 ГБ. Возможно переполнение на MTK."
MSG_RU[CreateFailed]="КРИТИЧНО: create-logical-partition не удалось."
MSG_RU[CreateFailed2]="super остался без system/product/system_ext. НЕ ПЕРЕЗАГРУЖАЙТЕ."

MSG_RU[ShaHeader]="ПРОВЕРКА SHA256:"
MSG_RU[ShaFileFound]="[INFO] Найден файл .sha256."
MSG_RU[ShaPrompt]="Скопируйте SHA256 из GitHub-релиза и вставьте сюда (или Enter — пропустить)."
MSG_RU[ShaPromptShort]="Hash"
MSG_RU[ShaOk]="[SHA256] OK."
MSG_RU[ShaSkipNoHash]="[SHA256] Хеш не распознан. Пропуск."
MSG_RU[ShaSkipTooBig]="[SHA256] Файл .sha256 слишком большой. Пропуск."
MSG_RU[ShaSkipErr]="[SHA256] Ошибка вычисления хеша. Пропуск."
MSG_RU[ShaSkipUser]="[SHA256] Проверка пропущена пользователем."
MSG_RU[ShaMismatch]="Несовпадение SHA256! Реальный: %s"
MSG_RU[ShaRiskPrompt]="Продолжить на свой риск? (y/N): "

MSG_RU[VbMissing]="ВНИМАНИЕ: vbmeta.img не найден. Возможен bootloop."
MSG_RU[VbContinueNo]="Продолжить без vbmeta? (y/N): "
MSG_RU[VbInUserspace]="ВНИМАНИЕ: вы в Fastbootd. vbmeta — физический раздел."
MSG_RU[VbFlashing]="Прошивка vbmeta..."

MSG_RU[NotAb]="Устройство не A/B."
MSG_RU[SetActiveWarn]="ВНИМАНИЕ: вы в Fastbootd. set_active может не работать на MTK."
MSG_RU[SetActiveTry]="Всё равно попробовать? (y/N): "
MSG_RU[CurrentSlotMsg]="Текущий слот: %s"
MSG_RU[SetActiveFail]="ОШИБКА: set_active не удалось. На MTK используйте bootloader, не fastbootd."

MSG_RU[SelectBoot]="Выберите BOOT (ядро):"
MSG_RU[SelectVendor]="Выберите VENDOR_BOOT:"
MSG_RU[SelectStableBoot]="Стабильный BOOT-образ:"
MSG_RU[SelectStableVb]="Стабильный VENDOR_BOOT-образ:"
MSG_RU[FlashToSlot]="Прошить в слот _%s? (y/N): "

MSG_RU[BackupTitle]="БЭКАП /DATA ЧЕРЕЗ ADB-СТРИМ"
MSG_RU[BackupWarning]="Убедитесь, что телефон в recovery (например, OrangeFox) и /data расшифрована."
MSG_RU[BackupCriticalWarn]="ВНИМАНИЕ: бэкап /data НЕ включает IMEI, MAC Wi-Fi/Bluetooth и ключи Widevine."
MSG_RU[BackupCriticalHint]="         Они лежат в /persist, /nvram, /modemst*, /misc. Бэкапьте их отдельно из recovery."
MSG_RU[BackupMountOk]="Вывод проверки mount записан в лог."
MSG_RU[BackupMountAsk]="/data смонтирована и расшифрована? (y/N): "
MSG_RU[BackupNoExcl]="tar не поддерживает --exclude, делаем полный бэкап"
MSG_RU[BackupProgress]="Бэкап /data"
MSG_RU[BackupDone]="Бэкап готов: %s"
MSG_RU[BackupFailed]="Бэкап НЕ УДАЛСЯ. См. лог:"
MSG_RU[BackupNo7Zip]="Для бэкапа нужен 7-Zip. Установите 7-Zip 22.00+ и повторите."

MSG_RU[ExitCodeMsg]="Код выхода: %s"

if [ -n "$FORCE_LANG" ]; then
    LANG_CODE="$FORCE_LANG"
elif [[ "${LANG:-}" =~ ^ru ]] || [[ "${LC_ALL:-}" =~ ^ru ]] || [[ "${LC_MESSAGES:-}" =~ ^ru ]]; then
    LANG_CODE="ru"
fi

t() {
    local key="$1"
    if [ "$LANG_CODE" = "ru" ]; then
        echo "${MSG_RU[$key]:-${MSG_EN[$key]:-$key}}"
    else
        echo "${MSG_EN[$key]:-$key}"
    fi
}

tf() {
    local key="$1"; shift
    local fmt
    fmt="$(t "$key")"
    printf "$fmt" "$@"
}

# ==============================================================================
# Logging — stderr for live output, file for archive
# ==============================================================================
LOG_DIR="logs"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/gsi-tool_${TOOL_VERSION}_$(date +%Y%m%d_%H%M%S).log"
{
    echo "=== SESSION START $(date) ==="
    echo "Version: $TOOL_VERSION"
    echo "Build:   $BUILD"
    echo "Arch: $ARCH"
    echo "Lang: $LANG_CODE (LANG=${LANG:-unset})"
    echo "StrictVersions: $STRICT_VERSIONS"
    echo "Serial: ${SERIAL:-(auto)}"
    echo "PWD: $PWD"
} >> "$LOG"

log()      { local l="[$(date '+%H:%M:%S')] [INFO]  $*"; echo "$l" >&2; echo "$l" >> "$LOG"; }
log_warn() { local l="[$(date '+%H:%M:%S')] [WARN]  $*"; echo "$l" >&2; echo "$l" >> "$LOG"; }
log_err()  { local l="[$(date '+%H:%M:%S')] [ERROR] $*"; echo "$l" >&2; echo "$l" >> "$LOG"; }
log_raw()  { [ -n "$1" ] && echo "$1" >> "$LOG"; }

pause() { read -rp "$(t PressKey)" _; }

confirm() {
    local prompt="${1:-$(t EnterConfirm)}"
    local r
    read -rp "$prompt " r
    local res=0
    [[ "$r" =~ ^[Yy]$ ]] && res=1
    log "Confirm '$prompt' -> $res"
    return $((1-res))
}

# ==============================================================================
# Version compare helper: version_ge A B → 0 if A >= B
# ==============================================================================
version_ge() {
    local a="$1" b="$2"
    while [ "$(printf '%s' "$a" | tr -cd '.' | wc -c)" -lt 2 ]; do a="${a}.0"; done
    while [ "$(printf '%s' "$b" | tr -cd '.' | wc -c)" -lt 2 ]; do b="${b}.0"; done
    local first
    first=$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)
    [ "$first" = "$b" ]
}

# ==============================================================================
# Decompression with pv progress
# ==============================================================================
decompress_with_progress() {
    local src="$1" out="$2"; shift 2
    local total rc
    total=$(stat -c%s "$src" 2>/dev/null || echo 0)
    if command -v pv >/dev/null 2>&1 && [ -t 2 ]; then
        set -o pipefail
        "$@" "$src" | pv -s "$total" -N "$(t UnpackProgress)" > "$out"
        rc=$?
        set +o pipefail
    else
        "$@" "$src" > "$out"
        rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        rm -f "$out"
        return "$rc"
    fi
    return 0
}

# ==============================================================================
# Tool version check
# ==============================================================================
check_tool_versions() {
    echo "$(t ToolCheck)" >&2
    log "Tool version check (strict=$STRICT_VERSIONS)"
    local problems=0

    if ! command -v adb >/dev/null 2>&1; then
        echo "  adb      : $(t ToolMissing)" >&2
        log_err "adb not found"
        problems=$((problems+1))
    else
        local adb_v
        adb_v=$(adb --version 2>/dev/null | grep -oE 'Version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $2}')
        if [ -z "$adb_v" ]; then
            echo "  adb      : $(t VersionUnknown)  ($(command -v adb))" >&2
            log_warn "adb version unknown"
            problems=$((problems+1))
        elif ! version_ge "$adb_v" "33.0.0"; then
            echo "  adb      : $adb_v  $(tf VersionTooOld 33.0.0)" >&2
            log_warn "adb version too old: $adb_v (need >= 33.0.0)"
            problems=$((problems+1))
        else
            echo "  adb      : $adb_v  ($(command -v adb))" >&2
            log "adb: $adb_v"
        fi
    fi

    if ! command -v fastboot >/dev/null 2>&1; then
        echo "  fastboot : $(t ToolMissing)" >&2
        log_err "fastboot not found"
        problems=$((problems+1))
    else
        local fb_v
        fb_v=$(fastboot --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -z "$fb_v" ]; then
            echo "  fastboot : $(t VersionUnknown)  ($(command -v fastboot))" >&2
            log_warn "fastboot version unknown"
            problems=$((problems+1))
        elif ! version_ge "$fb_v" "33.0.0"; then
            echo "  fastboot : $fb_v  $(tf VersionTooOld 33.0.0)" >&2
            log_warn "fastboot version too old: $fb_v (need >= 33.0.0)"
            problems=$((problems+1))
        else
            echo "  fastboot : $fb_v  ($(command -v fastboot))" >&2
            log "fastboot: $fb_v"
        fi
    fi

    if command -v 7z >/dev/null 2>&1; then
        local sz_v
        sz_v=$(7z 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [ -z "$sz_v" ]; then
            echo "  7-Zip    : $(t VersionUnknown)" >&2
            log_warn "7-Zip version unknown"
            problems=$((problems+1))
        elif ! version_ge "$sz_v" "22.00"; then
            echo "  7-Zip    : $sz_v  $(tf VersionTooOld 22.00)" >&2
            log_warn "7-Zip version too old: $sz_v (need >= 22.00)"
            problems=$((problems+1))
        else
            echo "  7-Zip    : $sz_v  ($(command -v 7z))" >&2
            log "7-Zip: $sz_v"
        fi
    else
        echo "  7-Zip    : $(t ToolMissing)  (not required on Linux)" >&2
        log "7-Zip not found (not required on Linux)"
    fi

    if command -v zstd >/dev/null 2>&1; then
        local z_v
        z_v=$(zstd --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | tr -d 'v')
        if [ -z "$z_v" ]; then
            echo "  zstd     : $(t VersionUnknown)  ($(command -v zstd))" >&2
            log_warn "zstd version unknown"
            problems=$((problems+1))
        elif ! version_ge "$z_v" "1.0"; then
            echo "  zstd     : $z_v  $(tf VersionTooOld 1.0)" >&2
            log_warn "zstd version too old: $z_v (need >= 1.0)"
            problems=$((problems+1))
        else
            echo "  zstd     : $z_v  ($(command -v zstd))" >&2
            log "zstd: $z_v"
        fi
    fi

    if ! command -v timeout >/dev/null 2>&1; then
        echo "  timeout  : $(t ToolMissing)" >&2
        log_err "timeout not found"
        problems=$((problems+1))
    fi
    if ! command -v od >/dev/null 2>&1; then
        echo "  od       : $(t ToolMissing)" >&2
        log_err "od not found"
        problems=$((problems+1))
    fi

    return "$problems"
}

# ==============================================================================
# Wait helpers
# ==============================================================================
wait_for_adb() {
    local tmo=${1:-$WAIT_ADB} c=0
    echo -n "$(t WaitAdb)" >&2
    while [ $c -lt $tmo ]; do
        local devs
        if [ -n "$SERIAL" ]; then
            devs=$(adb -s "$SERIAL" devices 2>/dev/null | tail -n +2 | tr -d '\r' | grep -E '\s(device|recovery)$' || true)
        else
            devs=$(adb devices 2>/dev/null | tail -n +2 | tr -d '\r' | grep -E '\s(device|recovery)$' || true)
        fi
        if [ -n "$devs" ]; then
            echo " $(t Ok)" >&2
            log "ADB found: $(echo "$devs" | awk '{print $1}' | tr '\n' ',')"
            return 0
        fi
        echo -n "." >&2; sleep 1; c=$((c+1))
    done
    echo " $(t Timeout)" >&2
    log_err "Wait-Adb TIMEOUT ($tmo s)"
    return 1
}

wait_for_fastboot() {
    local tmo=${1:-$WAIT_FASTBOOT} c=0
    echo -n "$(t WaitFastboot)" >&2
    while [ $c -lt $tmo ]; do
        local devs
        if [ -n "$SERIAL" ]; then
            devs=$(fastboot -s "$SERIAL" devices 2>/dev/null | tr -d '\r' | grep 'fastboot$' || true)
        else
            devs=$(fastboot devices 2>/dev/null | tr -d '\r' | grep 'fastboot$' || true)
        fi
        if [ -n "$devs" ]; then
            echo " $(t Ok)" >&2
            log "Fastboot found: $(echo "$devs" | awk '{print $1}' | tr '\n' ',')"
            return 0
        fi
        echo -n "." >&2; sleep 1; c=$((c+1))
    done
    echo " $(t Timeout)" >&2
    log_err "Wait-Fastboot TIMEOUT ($tmo s)"
    return 1
}

# ==============================================================================
# Fastboot / ADB wrappers
# ==============================================================================
fb() {
    local args=()
    [ -n "$SERIAL" ] && args+=("-s" "$SERIAL")
    args+=("$@")
    log "fastboot ${*}"
    local out
    out=$(timeout "$REBOOT_TIMEOUT" fastboot "${args[@]}" 2>&1)
    local rc=$?
    [ -n "$out" ] && log_raw "  fb: $out"
    if [ $rc -eq 124 ]; then log_err "fastboot TIMEOUT after ${REBOOT_TIMEOUT}s"; return 1; fi
    if [ $rc -ne 0 ]; then log_warn "fastboot exit: $rc"; return 1; fi
    return 0
}

fb_tolerant() {
    local args=()
    [ -n "$SERIAL" ] && args+=("-s" "$SERIAL")
    args+=("$@")
    log "fastboot (tolerant) ${*}"
    local out
    out=$(timeout "$REBOOT_TIMEOUT" fastboot "${args[@]}" 2>&1)
    local rc=$?
    [ -n "$out" ] && log_raw "  fb: $out"
    if [ $rc -eq 124 ]; then log_err "fastboot TIMEOUT after ${REBOOT_TIMEOUT}s"; return 1; fi
    log "fastboot (tolerant) exit=$rc (ignored)"
    return 0
}

adb_() {
    local args=()
    [ -n "$SERIAL" ] && args+=("-s" "$SERIAL")
    args+=("$@")
    log "adb ${*}"
    local out
    out=$(adb "${args[@]}" 2>&1)
    local rc=$?
    [ -n "$out" ] && log_raw "  adb: $out"
    [ $rc -ne 0 ] && { log_warn "adb exit: $rc"; return 1; }
    return 0
}

fb_flash() {
    local args=()
    [ -n "$SERIAL" ] && args+=("-s" "$SERIAL")
    args+=("$@")
    log "fastboot (flash) ${*}"
    local out
    out=$(timeout "$FLASH_TIMEOUT" fastboot "${args[@]}" 2>&1)
    local rc=$?
    [ -n "$out" ] && log_raw "  fb: $out"
    if [ $rc -eq 124 ]; then
        log_err "fb_flash TIMEOUT after ${FLASH_TIMEOUT}s"
        echo "========================================================" >&2
        echo "$(t Error): fastboot $* -- TIMEOUT" >&2
        echo "See log: $LOG" >&2
        echo "DO NOT REBOOT the device." >&2
        echo "========================================================" >&2
        return 1
    fi
    if [ $rc -ne 0 ]; then
        log_err "fb_flash FAILED: fastboot $*"
        echo "========================================================" >&2
        echo "$(t Error): fastboot $* -- FAILED" >&2
        echo "See log: $LOG" >&2
        echo "DO NOT REBOOT the device." >&2
        echo "========================================================" >&2
        return 1
    fi
    log "fb_flash OK: fastboot $*"
    return 0
}

# ==============================================================================
# Fastboot var helpers
# ==============================================================================
fb_getvar() {
    local name="$1"
    local raw
    if [ -n "$SERIAL" ]; then
        raw=$(fastboot -s "$SERIAL" getvar "$name" 2>&1)
    else
        raw=$(fastboot getvar "$name" 2>&1)
    fi
    if [[ "$raw" =~ $name:[[:space:]]*([^[:space:]]+) ]]; then
        echo "${BASH_REMATCH[1]}" | tr -d '\r'
    fi
}

get_current_slot() {
    local v
    v=$(fb_getvar current-slot)
    log "current-slot = $v"
    if [[ "$v" =~ ^[ab] ]]; then echo "${v:0:1}"; return; fi
    log_warn "current-slot not detected, fallback 'a'"
    echo "a"
}

get_slot_count() {
    local v
    v=$(fb_getvar slot-count)
    log "slot-count = $v"
    echo "${v:-2}"
}

is_userspace() {
    local v
    v=$(fb_getvar is-userspace)
    log "is-userspace = $v"
    [ "$v" = "yes" ]
}

check_bootloader_unlocked() {
    echo "$(t CheckingBl)" >&2
    local u s a
    u=$(fb_getvar unlocked)
    s=$(fb_getvar secure)
    a=$(fb_getvar get_unlock_ability)
    log "Bootloader: unlocked=$u secure=$s get_unlock_ability=$a"
    if [ "$u" = "yes" ] || [ "$s" = "no" ]; then
        echo "  $(t BlUnlocked)" >&2
        log "Bootloader UNLOCKED"
        return 0
    fi
    if [ "$a" = "0" ]; then
        echo "  $(t BlOemDisabled)" >&2
        log_err "OEM Unlock disabled"
        return 1
    fi
    echo "  $(t BlLocked)" >&2
    log_err "Bootloader LOCKED"
    return 1
}

sys_part() {
    if [ "$IS_AB_DEVICE" = "yes" ]; then echo "system_$1"; else echo "system"; fi
}

# ==============================================================================
# Image helpers (sparse-aware)
# ==============================================================================
get_image_size() {
    local img="$1"
    [ -f "$img" ] || { echo 0; return 1; }
    local magic
    magic=$(od -An -tx1 -N4 "$img" 2>/dev/null | tr -d ' \n')
    if [ "$magic" = "3aff26ed" ]; then
        local bs tb
        bs=$(od -An -tu4 -j12 -N4 "$img" 2>/dev/null | tr -d ' ')
        tb=$(od -An -tu4 -j16 -N4 "$img" 2>/dev/null | tr -d ' ')
        if [[ "$bs" =~ ^[0-9]+$ ]] && [[ "$tb" =~ ^[0-9]+$ ]]; then
            echo $((bs * tb)); return
        fi
    fi
    stat -c%s "$img"
}

test_sparse_integrity() {
    local img="$1"
    [ -f "$img" ] || { echo missing; return; }
    local magic
    magic=$(od -An -tx1 -N4 "$img" 2>/dev/null | tr -d ' \n')
    [ "$magic" != "3aff26ed" ] && { echo raw; return; }
    local bs tb actual expected min
    bs=$(od -An -tu4 -j12 -N4 "$img" 2>/dev/null | tr -d ' ')
    tb=$(od -An -tu4 -j16 -N4 "$img" 2>/dev/null | tr -d ' ')
    [[ ! "$bs" =~ ^[0-9]+$ ]] && { echo raw; return; }
    [[ ! "$tb" =~ ^[0-9]+$ ]] && { echo raw; return; }
    expected=$((bs * tb)); actual=$(stat -c%s "$img"); min=$((expected / 4))
    if [ "$actual" -lt "$min" ]; then echo "suspect:${actual}:${expected}"; else echo ok; fi
}

calc_partition_size() {
    local raw="$1"
    [[ ! "$raw" =~ ^[0-9]+$ ]] && { echo 0; return; }
    local align=4096 margin=$((MARGIN_MB * 1024 * 1024))
    local aligned=$(( (raw + align - 1) / align * align ))
    echo $((aligned + margin))
}

verify_sha256() {
    local path="$1" hash_arg="$2"
    local src="none"
    [ "$hash_arg" = "file" ] && src=file
    [ -n "$hash_arg" ] && [ "$hash_arg" != "file" ] && src=inline
    log "Verify SHA256: Path=$path HashSource=$src"
    [ -f "$path" ] || { log_err "Image not found: $path"; echo missing_img; return; }
    local want="" got=""
    if [ -n "$hash_arg" ] && [[ "$hash_arg" =~ ([a-fA-F0-9]{64}) ]]; then
        want=$(echo "${BASH_REMATCH[1]}" | tr 'A-F' 'a-f')
    elif [ -f "${path}.sha256" ]; then
        local sz
        sz=$(stat -c%s "${path}.sha256")
        if [ "$sz" -gt 4096 ]; then log_warn ".sha256 too large"; echo error_file_too_large; return; fi
        local content
        content=$(tr -d '\r\n ' < "${path}.sha256" 2>/dev/null)
        if [[ "$content" =~ ([a-fA-F0-9]{64}) ]]; then
            want=$(echo "${BASH_REMATCH[1]}" | tr 'A-F' 'a-f')
        fi
    fi
    if [ -z "$want" ]; then log_warn "No SHA256 hash available"; echo missing; return; fi
    if command -v pv >/dev/null 2>&1 && [ -t 1 ]; then
        got=$(pv -N "SHA256" "$path" 2>/dev/null | sha256sum | awk '{print $1}')
    else
        got=$(sha256sum "$path" | awk '{print $1}')
    fi
    got=$(echo "$got" | tr 'A-F' 'a-f')
    if [ "$got" = "$want" ]; then
        log "SHA256 OK ($got)"; echo ok
    else
        log_err "SHA256 mismatch: want=$want got=$got"
        echo "mismatch:$got"
    fi
}

# ==============================================================================
# Interactive file select (glob) — uses global SELECTED_FILE
# ==============================================================================
interactive_file_select() {
    local mask="$1"
    local prompt="$2"
    local old; old=$(shopt -p nullglob 2>/dev/null)
    shopt -s nullglob
    local files=($mask)
    [ ${#files[@]} -eq 0 ] && { eval "$old"; return 1; }
    if [ ${#files[@]} -eq 1 ]; then
        SELECTED_FILE="${files[0]}"
        log "Auto-selected: $SELECTED_FILE"
        echo "Found: $SELECTED_FILE" >&2
        eval "$old"; return 0
    fi
    echo "$prompt" >&2
    local c=1
    for f in "${files[@]}"; do echo "   $c) $f" >&2; c=$((c+1)); done
    local choice
    while true; do
        read -rp "$(t Input)" choice
        [ "$choice" = "0" ] && { eval "$old"; return 1; }
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#files[@]} ]; then
            SELECTED_FILE="${files[$((choice-1))]}"
            log "Selected: $SELECTED_FILE"
            eval "$old"; return 0
        fi
        echo "$(t InvalidChoice)" >&2
    done
}

# ==============================================================================
# Select system image
# ==============================================================================
select_system_image() {
    local all=()
    shopt -s nullglob
    all=(*.img *.img.xz *.img.gz *.img.zst)
    shopt -u nullglob
    local sys=()
    for f in "${all[@]}"; do
        case "$f" in
            vbmeta*|boot*|vendor*|recovery*|super*|dtbo*|userdata*|metadata*|system_dlkm*) continue ;;
        esac
        [ -f "$f" ] && sys+=("$f")
    done
    log "Select-SystemImage: found ${#sys[@]} candidate(s)"
    for f in "${sys[@]}"; do log "  candidate: $f"; done
    if [ ${#sys[@]} -eq 0 ]; then
        log_warn "No system images found"
        echo "$(t NoSystemImg)" >&2
        return 1
    fi

    local size_warn=0
    for f in "${sys[@]}"; do
        local fsz fmb
        fsz=$(stat -c%s "$f" 2>/dev/null || echo 0)
        fmb=$((fsz / 1024 / 1024))
        if [ "$fmb" -lt 100 ]; then
            log_warn "Suspicious small image: $f ($fmb MB) — not a valid GSI?"
            size_warn=1
        elif [ "$fmb" -lt 300 ]; then
            log_warn "Unusually small image: $f ($fmb MB) — typical GSI is 600 MB - 4 GB"
        fi
    done
    if [ $size_warn -eq 1 ]; then
        echo "$(t ImgSuspect1)" >&2
        echo "$(t ImgSuspect2)" >&2
        echo "$(t ImgSuspect3)" >&2
        confirm "$(t ContinueAnyway)" || { log "Aborted due to size check"; return 1; }
    fi

    if [ ${#sys[@]} -eq 1 ]; then
        log "Auto-selected: ${sys[0]}"
        echo "$(t FoundImg): ${sys[0]}" >&2
        echo "${sys[0]}"; return 0
    fi
    echo "$(t ChooseImg)" >&2
    local i=1
    for f in "${sys[@]}"; do
        local fsz fmb
        fsz=$(stat -c%s "$f" 2>/dev/null || echo 0)
        fmb=$((fsz / 1024 / 1024))
        local mark=" [${fmb} MB]"
        [ "$fmb" -lt 100 ] && mark=" [${fmb} MB] SUSPICIOUS"
        [ "$fmb" -ge 100 ] && [ "$fmb" -lt 300 ] && mark=" [${fmb} MB] small"
        echo "   $i) $f$mark" >&2
        i=$((i+1))
    done
    local choice
    while true; do
        read -rp "$(t Input)" choice
        if [ "$choice" = "0" ]; then log "cancelled"; return 1; fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#sys[@]} ]; then
            log "User selected: ${sys[$((choice-1))]}"
            echo "${sys[$((choice-1))]}"; return 0
        fi
        echo "$(t InvalidChoice)" >&2
    done
}

# ==============================================================================
# Resolve system image (decompress .xz/.gz/.zst) with pv progress
# ==============================================================================
resolve_system_image() {
    local img="$1"
    local out
    case "$img" in
        *.img.xz)
            if ! command -v unxz >/dev/null 2>&1; then
                log_err "unxz not found"
                tf Need7Zip ".xz (unxz)" >&2
                return 1
            fi
            out="${img%.xz}"
            if [ ! -f "$out" ]; then
                log "Unpacking .xz: $img -> $out"
                tf Unpacking "$img" "$out" >&2
                if ! timeout "$UNPACK_TIMEOUT" bash -c "$(declare -f decompress_with_progress); decompress_with_progress \"\$1\" \"\$2\" unxz -T0 -c" _ "$img" "$out"; then
                    log_err "unxz failed"
                    tf UnpackFailed ".xz" >&2
                    return 1
                fi
            fi
            echo "$out" ;;
        *.img.gz)
            if ! command -v gunzip >/dev/null 2>&1; then
                log_err "gunzip not found"
                tf Need7Zip ".gz (gunzip)" >&2
                return 1
            fi
            out="${img%.gz}"
            if [ ! -f "$out" ]; then
                log "Unpacking .gz: $img -> $out"
                tf Unpacking "$img" "$out" >&2
                if ! timeout "$UNPACK_TIMEOUT" bash -c "$(declare -f decompress_with_progress); decompress_with_progress \"\$1\" \"\$2\" gunzip -c" _ "$img" "$out"; then
                    log_err "gunzip failed"
                    tf UnpackFailed ".gz" >&2
                    return 1
                fi
            fi
            echo "$out" ;;
        *.img.zst)
            if ! command -v zstd >/dev/null 2>&1; then
                log_err "zstd not found"
                tf Need7Zip ".zst (zstd)" >&2
                return 1
            fi
            out="${img%.zst}"
            if [ ! -f "$out" ]; then
                log "Unpacking .zst: $img -> $out"
                tf Unpacking "$img" "$out" >&2
                if ! timeout "$UNPACK_TIMEOUT" bash -c "$(declare -f decompress_with_progress); decompress_with_progress \"\$1\" \"\$2\" zstd -d -c" _ "$img" "$out"; then
                    log_err "zstd failed"
                    tf UnpackFailed ".zst" >&2
                    return 1
                fi
            fi
            echo "$out" ;;
        *) echo "$img" ;;
    esac
}

# ==============================================================================
# vbmeta
# ==============================================================================
confirm_vbmeta() {
    if [ ! -f "vbmeta.img" ]; then
        log_warn "vbmeta.img not found"
        echo "$(t VbMissing)" >&2
        confirm "$(t VbContinueNo)"; return $?
    fi
    if is_userspace; then
        log_warn "in fastbootd, vbmeta is physical"
        echo "$(t VbInUserspace)" >&2
    fi
    log "Flashing vbmeta"
    echo "$(t VbFlashing)" >&2
    if ! fb_flash --disable-verity --disable-verification flash vbmeta vbmeta.img; then
        confirm "$(t VbContinueNo)"; return $?
    fi
    log "vbmeta flashed OK"; return 0
}

# ==============================================================================
# Free super space
# ==============================================================================
free_super_space() {
    local slot="${1:-$CURRENT_SLOT}"
    log "=== free_super_space slot=$slot ==="
    [ -n "$SYSTEM_IMG" ] && [ -f "$SYSTEM_IMG" ] || { log_err "SYSTEM_IMG not set"; return 1; }

    local integrity
    integrity=$(test_sparse_integrity "$SYSTEM_IMG")
    log "Sparse integrity: $integrity"
    if [[ "$integrity" =~ ^suspect: ]]; then
        echo "Sparse image looks suspicious: $integrity" >&2
        confirm "$(t ContinueAnyway)" || return 1
    fi

    local raw part
    raw=$(get_image_size "$SYSTEM_IMG")
    [ "$raw" -le 0 ] && { log_err "Cannot detect image size"; return 1; }
    part=$(calc_partition_size "$raw")
    log "raw=$raw part=$part (margin=${MARGIN_MB}MB)"
    echo "raw=$raw, part=$part (margin=${MARGIN_MB}MB)" >&2

    echo "--------------------------------------------------------" >&2
    echo "$(t ShaHeader)" >&2
    local user_hash=""
    if [ -f "${SYSTEM_IMG}.sha256" ]; then
        echo "$(t ShaFileFound)" >&2
        log "Found .sha256 file"
        user_hash="file"
    else
        echo "$(t ShaPrompt)" >&2
        read -rp "$(t ShaPromptShort): " user_hash
        log "SHA256 input: $( [ -n "$user_hash" ] && echo provided || echo skipped )"
    fi
    if [ -n "$user_hash" ]; then
        local res
        res=$(verify_sha256 "$SYSTEM_IMG" "$user_hash")
        case "$res" in
            mismatch:*)
                log_err "SHA256 mismatch: $res"
                echo "$(t Error): $(tf ShaMismatch "$res")" >&2
                confirm "$(t ShaRiskPrompt)" || return 1 ;;
            ok)                   echo "$(t ShaOk)" >&2 ;;
            missing)              echo "$(t ShaSkipNoHash)" >&2 ;;
            error_file_too_large) echo "$(t ShaSkipTooBig)" >&2 ;;
            error)                echo "$(t ShaSkipErr)" >&2 ;;
        esac
    else
        echo "$(t ShaSkipUser)" >&2
    fi
    echo "--------------------------------------------------------" >&2

    local tpart opp
    tpart=$(sys_part "$slot")
    opp=$([ "$slot" = "a" ] && echo b || echo a)

    if ! is_userspace; then
        echo "$(t RebootToFb)" >&2
        log "$(t NotInFbReboot)"
        fb_tolerant reboot fastboot || true
        wait_for_fastboot || return 1
    fi

    echo "--------------------------------------------------------" >&2
    echo "$(t RebuildSuper)" >&2
    tf TargetPart "$tpart" >&2
    tf NewSize "$part" >&2
    echo "  $(t NotTouching)" >&2
    echo "--------------------------------------------------------" >&2
    confirm || { log "Rebuild cancelled by user"; return 1; }

    if [ "$part" -gt $((4 * 1024 * 1024 * 1024)) ]; then
        echo "$(t SuperBigWarn)" >&2
        confirm || return 1
    fi

    log "Deleting system/product/system_ext in slots $slot/$opp"
    if [ "$IS_AB_DEVICE" = "yes" ]; then
        for s in "$slot" "$opp"; do
            for p in system product system_ext; do
                fb delete-logical-partition "${p}_${s}" || true
            done
        done
    else
        for p in system product system_ext; do
            fb delete-logical-partition "$p" || true
        done
    fi

    log "Creating $tpart size=$part"
    echo "Creating $tpart ($part bytes)..." >&2
    if ! fb create-logical-partition "$tpart" "$part"; then
        log_err "create-logical-partition failed"
        echo "$(t CreateFailed)" >&2
        echo "$(t CreateFailed2)" >&2
        return 1
    fi
    log "Partition $tpart recreated: $part bytes"
    return 0
}

# ==============================================================================
# Backup /data via ADB stream
# 1.0.2: check entire PIPESTATUS, drop broken archive on any failure.
# ==============================================================================
backup_data_stream() {
    clear
    log "=== Backup-DataStream ==="
    echo "$(t BackupTitle)" >&2

    wait_for_adb || { pause; return 1; }
    echo "$(t BackupWarning)" >&2
    echo "$(t BackupCriticalWarn)" >&2
    echo "$(t BackupCriticalHint)" >&2

    # --- mount check ---
    log "Mount check: /data"
    local marr=()
    [ -n "$SERIAL" ] && marr+=("-s" "$SERIAL")
    marr+=("shell" "mount | grep -E '/data|f2fs|ext4' || true")
    local mout
    mout=$(timeout 15 adb "${marr[@]}" 2>&1 | tr -d '\r' || true)
    [ -n "$mout" ] && log_raw "mount: $mout"
    echo "$(t BackupMountOk)" >&2
    confirm "$(t BackupMountAsk)" || { log "Backup cancelled at mount prompt"; return 1; }

    # --- probe: adb alive AND tar --exclude supported ---
    local excludes="--exclude=media --exclude=dalvik-cache --exclude=tombstones --exclude=dropbox"
    local parr=()
    [ -n "$SERIAL" ] && parr+=("-s" "$SERIAL")
    parr+=("shell" "echo ADB_OK; tar $excludes -cf /dev/null -C /data . >/dev/null 2>&1; echo RC=\$?")
    local pout
    pout=$(timeout 20 adb "${parr[@]}" 2>&1 | tr -d '\r' || true)
    if [[ ! "$pout" =~ ADB_OK ]]; then
        log_err "adb shell probe failed (adb lost connection?)"
        echo "$(t BackupFailed) $LOG" >&2
        pause; return 1
    fi
    if [[ ! "$pout" =~ RC=0 ]]; then
        log_warn "tar --exclude not supported, full backup"
        echo "$(t BackupNoExcl)" >&2
        excludes=""
    fi

    # --- output path ---
    local bdir="backups/data_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bdir"
    local bfile="$bdir/userdata_backup"
    local remote_tar="tar -c -C /data $excludes ."

    local sarr=()
    [ -n "$SERIAL" ] && sarr+=("-s" "$SERIAL")
    sarr+=("exec-out" "$remote_tar")

    log "Backup stream start (timeout ${BACKUP_TIMEOUT}s): $remote_tar"

    if command -v pv >/dev/null 2>&1 && command -v lz4 >/dev/null 2>&1; then
        # ===== fast path: pv + lz4 =====
        set -o pipefail
        timeout "$BACKUP_TIMEOUT" adb "${sarr[@]}" 2>>"$LOG" | pv -N "$(t BackupProgress)" | lz4 -9 > "${bfile}.tar.lz4"
        # Capture PIPESTATUS IMMEDIATELY — must be a bare assignment, not `local`.
        rc_array=("${PIPESTATUS[@]}")
        set +o pipefail
        local adb_rc=${rc_array[0]}
        local pv_rc=${rc_array[1]}
        local lz4_rc=${rc_array[2]}

        if [ "$adb_rc" -eq 124 ]; then
            log_err "backup TIMEOUT after ${BACKUP_TIMEOUT}s (adb killed by timeout)"
            rm -f "${bfile}.tar.lz4"
            echo "$(t BackupFailed) $LOG" >&2
            pause; return 1
        fi
        if [ "$adb_rc" -ne 0 ] || [ "$lz4_rc" -ne 0 ]; then
            log_err "backup failed (adb=$adb_rc pv=$pv_rc lz4=$lz4_rc)"
            rm -f "${bfile}.tar.lz4"
            echo "$(t BackupFailed) $LOG" >&2
            pause; return 1
        fi
        local sz
        sz=$(stat -c%s "${bfile}.tar.lz4" 2>/dev/null || echo 0)
        if [ "$sz" -eq 0 ]; then
            log_err "backup produced 0-byte archive"
            rm -f "${bfile}.tar.lz4"
            echo "$(t BackupFailed) $LOG" >&2
            pause; return 1
        fi
        log "Backup OK: ${bfile}.tar.lz4 ($sz bytes)"
        tf BackupDone "${bfile}.tar.lz4" >&2
    else
        # ===== fallback: gzip =====
        set -o pipefail
        timeout "$BACKUP_TIMEOUT" adb "${sarr[@]}" 2>>"$LOG" | gzip -9 > "${bfile}.tar.gz"
        rc_array=("${PIPESTATUS[@]}")
        set +o pipefail
        local adb_rc=${rc_array[0]}
        local gz_rc=${rc_array[1]}

        if [ "$adb_rc" -eq 124 ]; then
            log_err "backup TIMEOUT after ${BACKUP_TIMEOUT}s (adb killed by timeout)"
            rm -f "${bfile}.tar.gz"
            echo "$(t BackupFailed) $LOG" >&2
            pause; return 1
        fi
        if [ "$adb_rc" -ne 0 ] || [ "$gz_rc" -ne 0 ]; then
            log_err "backup failed (adb=$adb_rc gzip=$gz_rc)"
            rm -f "${bfile}.tar.gz"
            echo "$(t BackupFailed) $LOG" >&2
            pause; return 1
        fi
        local sz
        sz=$(stat -c%s "${bfile}.tar.gz" 2>/dev/null || echo 0)
        if [ "$sz" -eq 0 ]; then
            log_err "backup produced 0-byte archive"
            rm -f "${bfile}.tar.gz"
            echo "$(t BackupFailed) $LOG" >&2
            pause; return 1
        fi
        log "Backup OK: ${bfile}.tar.gz ($sz bytes)"
        tf BackupDone "${bfile}.tar.gz" >&2
    fi
    ls -lh "$bdir" >&2
    pause
}

# ==============================================================================
# GKI kernels
# ==============================================================================
flash_gki_cores() {
    clear
    log "=== Install-GkiKernels ==="
    local boot_file="" vendor_file=""
    interactive_file_select "boot*.img" "$(t SelectBoot)" || { pause; return 1; }
    boot_file="$SELECTED_FILE"
    interactive_file_select "vendor_boot*.img" "$(t SelectVendor)" || { pause; return 1; }
    vendor_file="$SELECTED_FILE"
    log "boot file: $boot_file"
    log "vendor_boot file: $vendor_file"

    wait_for_adb || { echo "ADB not available." >&2; pause; return 1; }
    log "adb reboot bootloader"
    adb_ reboot bootloader || true
    wait_for_fastboot || { echo "Fastboot not found." >&2; pause; return 1; }
    check_bootloader_unlocked || { pause; return 1; }

    local slot
    slot=$(get_current_slot)
    log "Target slot: $slot"
    local c
    read -rp "$(tf FlashToSlot "$slot") " c
    if [[ "$c" =~ ^[Yy]$ ]]; then
        fb_flash flash "boot_$slot"        "$boot_file"   || { pause; return 1; }
        fb_flash flash "vendor_boot_$slot" "$vendor_file" || { pause; return 1; }
        fb erase cache || true
        log "GKI kernels flashed OK"
    fi
    pause
}

# ==============================================================================
# Emergency restore
# ==============================================================================
emergency_slot_fix() {
    clear
    log "=== Restore-EmergencySlots ==="
    local b="" v=""
    interactive_file_select "boot*.img" "$(t SelectStableBoot)" || { pause; return 1; }
    b="$SELECTED_FILE"
    interactive_file_select "vendor_boot*.img" "$(t SelectStableVb)" || { pause; return 1; }
    v="$SELECTED_FILE"
    log "boot: $b"
    log "vendor_boot: $v"

    wait_for_fastboot || { echo "No fastboot." >&2; pause; return 1; }
    check_bootloader_unlocked || { pause; return 1; }

    log "Writing to both slots"
    fb_flash flash boot_a        "$b" || { pause; return 1; }
    fb_flash flash vendor_boot_a "$v" || { pause; return 1; }
    fb_flash flash boot_b        "$b" || { pause; return 1; }
    fb_flash flash vendor_boot_b "$v" || { pause; return 1; }
    fb set_active a || true
    log "Dual-slot restore OK"
    fb reboot
    exit 0
}

# ==============================================================================
# Menus
# ==============================================================================
show_main_menu() {
    clear
    echo "$(t MainMenuTitle) $FULL_VERSION (Linux)" >&2
    echo "$(t LogFile): $LOG" >&2
    echo "========================================================" >&2
    echo "  1. $(t MenuCheckDev)" >&2
    echo "  2. $(t MenuFromAndroid)" >&2
    echo "  3. $(t MenuFromRecovery)" >&2
    echo "  4. $(t MenuFromBoot)" >&2
    echo "  5. $(t MenuAlreadyFb)" >&2
    echo "  6. $(t ServiceMenu)" >&2
    echo "  0. $(t Exit)" >&2
    echo "========================================================" >&2
    local c; read -rp "$(t Input)" c
    log "Main menu: choice=$c"
    echo "$c"
}

show_action_menu() {
    clear
    tf ActiveSlotLine "$CURRENT_SLOT" "$IS_AB_DEVICE" >&2
    echo "========================================================" >&2
    echo "  1. $(t ActionUpdate)" >&2
    echo "  2. $(t ActionReset)" >&2
    echo "  3. $(t ActionSlot)" >&2
    echo "  4. $(t ActionSwitch)" >&2
    echo "  5. $(t ActionDirty)" >&2
    echo "  0. $(t Back)" >&2
    echo "========================================================" >&2
    local c; read -rp "$(t Input)" c
    log "Action menu: choice=$c"
    echo "$c"
}

show_service_menu() {
    clear
    echo "==== $(t ServiceMenu) ====" >&2
    echo "  1. $(t Backing)" >&2
    echo "  2. $(t FlashingGki)" >&2
    echo "  3. $(t EmergencyFix)" >&2
    echo "  0. $(t Back)" >&2
    local c; read -rp "$(t Input)" c
    log "Service menu: choice=$c"
    echo "$c"
}

# ==============================================================================
# Do-Flash
# ==============================================================================
do_flash() {
    local mode="$1"
    log "=== Do-Flash mode=$mode ==="
    SYSTEM_IMG=""
    SYSTEM_IMG=$(select_system_image) || return
    log "Selected image: $SYSTEM_IMG"
    SYSTEM_IMG=$(resolve_system_image "$SYSTEM_IMG") || { log_err "resolve failed"; return; }
    log "Resolved image: $SYSTEM_IMG"

    case "$mode" in
        slot)
            local sc
            read -rp "$(t EnterSlot)" sc
            [[ ! "$sc" =~ ^[ab]$ ]] && sc="$CURRENT_SLOT"
            log "Target slot: $sc"
            confirm_vbmeta || return
            free_super_space "$sc" || return
            fb_flash flash "$(sys_part "$sc")" "$SYSTEM_IMG" || return
            fb erase cache || true
            [ "$IS_AB_DEVICE" = "yes" ] && fb set_active "$sc" || true
            fb reboot
            log "Flash OK (slot). Exiting."
            echo "$(t FlashOk)"; pause; exit 0
            ;;
        update)
            confirm_vbmeta || return
            free_super_space "$CURRENT_SLOT" || return
            fb_flash flash "$(sys_part "$CURRENT_SLOT")" "$SYSTEM_IMG" || return
            fb erase cache || true
            fb reboot
            log "Flash OK (update). Exiting."
            echo "$(t FlashOk)"; pause; exit 0
            ;;
        reset)
            confirm_vbmeta || return
            free_super_space "$CURRENT_SLOT" || return
            fb -w || true
            fb_flash flash "$(sys_part "$CURRENT_SLOT")" "$SYSTEM_IMG" || return
            fb reboot
            log "Flash OK (reset). Exiting."
            echo "$(t FlashOk)"; pause; exit 0
            ;;
        dirty)
            check_bootloader_unlocked || return
            fb_flash flash "$(sys_part "$CURRENT_SLOT")" "$SYSTEM_IMG" || return
            fb reboot
            log "Flash OK (dirty). Exiting."
            echo "$(t FlashOk)"; pause; exit 0
            ;;
    esac
}

# ==============================================================================
# MAIN FLOW
# ==============================================================================
check_tool_versions
problems=$?
if [ "$problems" -gt 0 ]; then
    if [ "$STRICT_VERSIONS" = "yes" ]; then
        echo "$(t StrictFail)" >&2
        log_err "Strict version check failed ($problems problem(s)); aborting"
        exit 1
    fi
    echo "$(t ToolsWarn)" >&2
    confirm || exit 1
fi

while true; do
    PROCEED=0
    while [ $PROCEED -eq 0 ]; do
        c=$(show_main_menu)
        case "$c" in
            0) log "Exit from main menu"; exit 0 ;;
            6)
                while true; do
                    s=$(show_service_menu)
                    [ "$s" = "0" ] && break
                    case "$s" in
                        1) backup_data_stream ;;
                        2) flash_gki_cores ;;
                        3) emergency_slot_fix ;;
                        *) log "Unknown service choice: $s" ;;
                    esac
                done
                ;;
            5) wait_for_fastboot && PROCEED=1 ;;
            4) wait_for_fastboot && { fb_tolerant reboot fastboot; wait_for_fastboot && PROCEED=1; } ;;
            3) wait_for_adb && { adb_ reboot fastboot; wait_for_fastboot && PROCEED=1; } ;;
            2) wait_for_adb && { adb_ reboot fastboot; wait_for_fastboot && PROCEED=1; } ;;
            1) echo "-- ADB --" >&2; adb devices; echo "-- Fastboot --" >&2; fastboot devices ;;
        esac
        [ $PROCEED -eq 0 ] && pause
    done

    check_bootloader_unlocked || { pause; continue; }
    [ "$(get_slot_count)" = "1" ] && IS_AB_DEVICE="no" || IS_AB_DEVICE="yes"
    CURRENT_SLOT=$(get_current_slot)
    log "A/B=$IS_AB_DEVICE CURRENT_SLOT=$CURRENT_SLOT"

    BACK=0
    while [ $BACK -eq 0 ]; do
        a=$(show_action_menu)
        case "$a" in
            0) log "Back to main menu"; BACK=1 ;;
            4)
                if [ "$IS_AB_DEVICE" != "yes" ]; then echo "$(t NotAb)" >&2; pause; continue; fi
                local new
                new=$([ "$CURRENT_SLOT" = "a" ] && echo b || echo a)
                if is_userspace; then
                    log_warn "set_active in fastbootd: may fail on MTK"
                    echo "$(t SetActiveWarn)" >&2
                    confirm "$(t SetActiveTry)" || continue
                fi
                if fb set_active "$new"; then
                    CURRENT_SLOT="$new"
                    log "Switched active slot to $CURRENT_SLOT"
                    tf CurrentSlotMsg "$CURRENT_SLOT" >&2
                else
                    log_err "set_active $new FAILED"
                    echo "$(t SetActiveFail)" >&2
                fi
                pause
                ;;
            1) do_flash update ;;
            2) do_flash reset ;;
            3) do_flash slot ;;
            5) do_flash dirty ;;
        esac
    done
done