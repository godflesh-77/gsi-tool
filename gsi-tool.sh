#!/bin/bash
# ==============================================================================
# GSI FLASH & SERVICE TOOL 0.9.9 (Linux)
# Windows 10/11 is served by gsi-tool-0.9.9.ps1
# ==============================================================================

TOOL_VERSION="0.9.9"

# Build identifier: git short hash if .git exists, else timestamp
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
WAIT_ADB=15
WAIT_FASTBOOT=60
REBOOT_TIMEOUT=30
MARGIN_MB=256
UNPACK_TIMEOUT=3600

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
            echo "Usage: $0 [--lang=en|ru] [--serial=<serial>] [--version] [--help]"
            exit 0
            ;;
        --lang=*)   FORCE_LANG="${arg#--lang=}" ;;
        --serial=*) SERIAL="${arg#--serial=}" ;;
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

MSG_EN[Welcome]="Welcome to GSI Flash Tool"
MSG_EN[LogFile]="Log"
MSG_EN[FromAndroid]="Android  -> Fastbootd"
MSG_EN[FromRecovery]="Recovery -> Fastbootd"
MSG_EN[FromBootloader]="Bootloader -> Fastbootd"
MSG_EN[AlreadyFb]="Already in Fastbootd"
MSG_EN[ServiceMenu]="SERVICE MENU"
MSG_EN[Exit]="Exit"
MSG_EN[Input]="Input: "
MSG_EN[ActionUpdate]="Update system"
MSG_EN[ActionReset]="Reset and flash (Full Wipe)"
MSG_EN[ActionSlot]="Flash to specified slot (A/B)"
MSG_EN[ActionSwitch]="Switch active slot"
MSG_EN[ActionDirty]="Dirty flash"
MSG_EN[Back]="Back"
MSG_EN[CheckingBl]="Checking bootloader state..."
MSG_EN[BlUnlocked]="Bootloader: UNLOCKED"
MSG_EN[BlLocked]="CRITICAL: Bootloader is LOCKED!"
MSG_EN[WaitAdb]="Waiting for ADB device"
MSG_EN[WaitFastboot]="Waiting for Fastboot device"
MSG_EN[Timeout]="[TIMEOUT]"
MSG_EN[Ok]="[OK]"
MSG_EN[FoundImg]="Found system image"
MSG_EN[ChooseImg]="Found multiple images. Choose one"
MSG_EN[Cancel]="Cancelled."
MSG_EN[InvalidChoice]="Invalid choice."
MSG_EN[EnterSlot]="Enter slot (a/b): "
MSG_EN[EnterConfirm]="Continue? (y/N): "
MSG_EN[FlashOk]="Done."
MSG_EN[RebuildSuper]="SUPER RECONSTRUCTION"
MSG_EN[Backing]="Backup /data via ADB stream"
MSG_EN[FlashingGki]="Flash GKI kernels (boot + vendor_boot)"
MSG_EN[EmergencyFix]="Emergency dual-slot restore"
MSG_EN[PressKey]="Press Enter to continue..."
MSG_EN[Error]="ERROR"
MSG_EN[Warning]="WARNING"
MSG_EN[ToolCheck]="Tool version check"
MSG_EN[ToolMissing]="not found"

MSG_RU[Welcome]="Добро пожаловать в GSI Flash Tool"
MSG_RU[LogFile]="Лог"
MSG_RU[FromAndroid]="Android  -> Fastbootd"
MSG_RU[FromRecovery]="Recovery -> Fastbootd"
MSG_RU[FromBootloader]="Bootloader -> Fastbootd"
MSG_RU[AlreadyFb]="Уже в Fastbootd"
MSG_RU[ServiceMenu]="СЕРВИСНОЕ МЕНЮ"
MSG_RU[Exit]="Выход"
MSG_RU[Input]="Ввод: "
MSG_RU[ActionUpdate]="Обновить систему"
MSG_RU[ActionReset]="Сброс и прошивка (Full Wipe)"
MSG_RU[ActionSlot]="Прошить в указанный слот (A/B)"
MSG_RU[ActionSwitch]="Переключить активный слот"
MSG_RU[ActionDirty]="Грязная прошивка"
MSG_RU[Back]="Назад"
MSG_RU[CheckingBl]="Проверка загрузчика..."
MSG_RU[BlUnlocked]="Загрузчик: РАЗБЛОКИРОВАН"
MSG_RU[BlLocked]="КРИТИЧЕСКАЯ ОШИБКА: Загрузчик заблокирован!"
MSG_RU[WaitAdb]="Ожидание ADB-устройства"
MSG_RU[WaitFastboot]="Ожидание Fastboot-устройства"
MSG_RU[Timeout]="[ТАЙМ-АУТ]"
MSG_RU[Ok]="[OK]"
MSG_RU[FoundImg]="Найден образ системы"
MSG_RU[ChooseImg]="Найдено несколько образов. Выберите"
MSG_RU[Cancel]="Отменено."
MSG_RU[InvalidChoice]="Неверный ввод."
MSG_RU[EnterSlot]="Слот (a/b): "
MSG_RU[EnterConfirm]="Выполнить? (y/N): "
MSG_RU[FlashOk]="Готово."
MSG_RU[RebuildSuper]="РЕКОНСТРУКЦИЯ SUPER"
MSG_RU[Backing]="Бэкап /data через ADB-стрим"
MSG_RU[FlashingGki]="Прошивка GKI-ядер (boot + vendor_boot)"
MSG_RU[EmergencyFix]="Экстренный откат (оба слота)"
MSG_RU[PressKey]="Нажмите Enter для продолжения..."
MSG_RU[Error]="ОШИБКА"
MSG_RU[Warning]="ВНИМАНИЕ"
MSG_RU[ToolCheck]="Проверка версий утилит"
MSG_RU[ToolMissing]="не найден"

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

# ==============================================================================
# Logging
# All log output goes to stderr — keeps stdout clean for function return values.
# ==============================================================================
LOG_DIR="logs"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/gsi-tool_${TOOL_VERSION}_$(date +%Y%m%d_%H%M%S).log"
echo "=== SESSION START $(date) ===" >> "$LOG"
echo "Version: $TOOL_VERSION" >> "$LOG"
echo "Build:   $BUILD" >> "$LOG"
echo "Arch: $ARCH" >> "$LOG"
echo "Lang: $LANG_CODE (LANG=${LANG:-unset})" >> "$LOG"
echo "PWD: $PWD" >> "$LOG"

log()      { local l="[$(date '+%H:%M:%S')] [INFO]  $*"; echo "$l" >&2; echo "$l" >> "$LOG"; }
log_warn() { local l="[$(date '+%H:%M:%S')] [WARN]  $*"; echo "$l" >&2; echo "$l" >> "$LOG"; }
log_err()  { local l="[$(date '+%H:%M:%S')] [ERROR] $*"; echo "$l" >&2; echo "$l" >> "$LOG"; }
log_raw()  { [ -n "$1" ] && echo "$1" >> "$LOG"; }

pause() { read -rp "$(t PressKey)"; }

confirm() {
    local prompt="${1:-$(t EnterConfirm)}"
    read -rp "$prompt " r
    local res=0
    [[ "$r" =~ ^[Yy]$ ]] && res=1
    log "Confirm '$prompt' -> $res"
    return $((1-res))
}

# ==============================================================================
# Tool version check
# ==============================================================================
check_tool_versions() {
    echo "$(t ToolCheck)" >&2
    log "Tool version check"
    local problems=0

    if ! command -v adb >/dev/null 2>&1; then
        echo "  adb      : $(t ToolMissing)" >&2; log_err "adb not found"; problems=$((problems+1))
    else
        local adb_v=$(adb --version 2>/dev/null | grep -oE 'Version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $2}')
        echo "  adb      : ${adb_v:-?}  ($(command -v adb))" >&2
        log "adb: ${adb_v:-?}"
    fi

    if ! command -v fastboot >/dev/null 2>&1; then
        echo "  fastboot : $(t ToolMissing)" >&2; log_err "fastboot not found"; problems=$((problems+1))
    else
        local fb_v=$(fastboot --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        echo "  fastboot : ${fb_v:-?}  ($(command -v fastboot))" >&2
        log "fastboot: ${fb_v:-?}"
    fi

    if ! command -v timeout >/dev/null 2>&1; then
        echo "  timeout  : $(t ToolMissing)" >&2; log_err "timeout not found"; problems=$((problems+1))
    fi
    if ! command -v od >/dev/null 2>&1; then
        echo "  od       : $(t ToolMissing)" >&2; log_err "od not found"; problems=$((problems+1))
    fi

    return $problems
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
            devs=$(adb -s "$SERIAL" devices 2>/dev/null | tail -n +2 | grep -E '\s(device|recovery)$' || true)
        else
            devs=$(adb devices 2>/dev/null | tail -n +2 | grep -E '\s(device|recovery)$' || true)
        fi
        if [ -n "$devs" ]; then
            echo " $(t Ok)" >&2; log "ADB found: $(echo "$devs" | awk '{print $1}' | tr '\n' ',')"
            return 0
        fi
        echo -n "." >&2; sleep 1; c=$((c+1))
    done
    echo " $(t Timeout)" >&2; log_err "Wait-Adb TIMEOUT ($tmo s)"
    return 1
}

wait_for_fastboot() {
    local tmo=${1:-$WAIT_FASTBOOT} c=0
    echo -n "$(t WaitFastboot)" >&2
    while [ $c -lt $tmo ]; do
        local devs
        if [ -n "$SERIAL" ]; then
            devs=$(fastboot -s "$SERIAL" devices 2>/dev/null | grep 'fastboot$' || true)
        else
            devs=$(fastboot devices 2>/dev/null | grep 'fastboot$' || true)
        fi
        if [ -n "$devs" ]; then
            echo " $(t Ok)" >&2; log "Fastboot found: $(echo "$devs" | awk '{print $1}' | tr '\n' ',')"
            return 0
        fi
        echo -n "." >&2; sleep 1; c=$((c+1))
    done
    echo " $(t Timeout)" >&2; log_err "Wait-Fastboot TIMEOUT ($tmo s)"
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
    out=$(timeout $REBOOT_TIMEOUT fastboot "${args[@]}" 2>&1)
    local rc=$?
    [ -n "$out" ] && log_raw "  fb: $out"
    if [ $rc -eq 124 ]; then log_err "fastboot TIMEOUT after ${REBOOT_TIMEOUT}s"; return 1; fi
    if [ $rc -ne 0 ]; then log_warn "fastboot exit: $rc"; return 1; fi
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
    if ! fb "$@"; then
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
    [[ "$raw" =~ $name:[[:space:]]*([^[:space:]]+) ]] && echo "${BASH_REMATCH[1]}" | tr -d '\r'
}

get_current_slot() {
    local v=$(fb_getvar current-slot)
    log "current-slot = $v"
    [[ "$v" =~ ^[ab] ]] && echo "${v:0:1}" && return
    log_warn "current-slot not detected, fallback 'a'"
    echo "a"
}

get_slot_count() {
    local v=$(fb_getvar slot-count)
    log "slot-count = $v"
    echo "${v:-2}"
}

is_userspace() {
    local v=$(fb_getvar is-userspace)
    log "is-userspace = $v"
    [ "$v" = "yes" ]
}

check_bootloader_unlocked() {
    echo "$(t CheckingBl)" >&2
    local u=$(fb_getvar unlocked)
    local s=$(fb_getvar secure)
    local a=$(fb_getvar get_unlock_ability)
    log "Bootloader: unlocked=$u secure=$s get_unlock_ability=$a"
    if [ "$u" = "yes" ] || [ "$s" = "no" ]; then
        echo "  $(t BlUnlocked)" >&2; log "Bootloader UNLOCKED"; return 0
    fi
    if [ "$a" = "0" ]; then
        echo "  ERROR: OEM Unlock disabled in Android!" >&2
        log_err "OEM Unlock disabled"; return 1
    fi
    echo "  $(t BlLocked)" >&2; log_err "Bootloader LOCKED"
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
        want="${BASH_REMATCH[1],,}"
    elif [ -f "${path}.sha256" ]; then
        local sz=$(stat -c%s "${path}.sha256")
        if [ "$sz" -gt 4096 ]; then log_warn ".sha256 too large"; echo error_file_too_large; return; fi
        local content
        content=$(cat "${path}.sha256" 2>/dev/null | tr -d '\r\n ')
        if [[ "$content" =~ ([a-fA-F0-9]{64}) ]]; then want="${BASH_REMATCH[1],,}"; fi
    fi
    if [ -z "$want" ]; then log_warn "No SHA256 hash available"; echo missing; return; fi
    if command -v pv >/dev/null 2>&1 && [ -t 1 ]; then
        got=$(pv -N "SHA256" "$path" 2>/dev/null | sha256sum | awk '{print $1}')
    else
        got=$(sha256sum "$path" | awk '{print $1}')
    fi
    got="${got,,}"
    if [ "$got" = "$want" ]; then log "SHA256 OK ($got)"; echo ok
    else log_err "SHA256 mismatch: want=$want got=$got"; echo "mismatch:$got"; fi
}

# ==============================================================================
# Interactive file select (glob) — uses global SELECTED_FILE
# ==============================================================================
interactive_file_select() {
    local mask="$1"
    local prompt="$2"
    local old; old=$(shopt -p nullglob 2>/dev/null)
    shopt -u nullglob
    local files=($mask)
    if [ ! -e "${files[0]}" ]; then
        echo "Files by mask [$mask] not found!" >&2
        log_warn "Files by mask [$mask] not found"
        eval "$old"; return 1
    fi
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
# Select system image — returns path via stdout, all UI on stderr
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
    if [ ${#sys[@]} -eq 0 ]; then log_warn "No system images found"; echo "No system images found." >&2; return 1; fi

    # Size check — GSI normally weighs 600 MB - 4 GB
    local size_warn=0
    for f in "${sys[@]}"; do
        local fsz=$(stat -c%s "$f" 2>/dev/null || echo 0)
        local fmb=$((fsz / 1024 / 1024))
        if [ "$fmb" -lt 100 ]; then
            log_warn "Suspicious small image: $f ($fmb MB) — not a valid GSI?"
            size_warn=1
        elif [ "$fmb" -lt 300 ]; then
            log_warn "Unusually small image: $f ($fmb MB) — typical GSI is 600 MB - 4 GB"
        fi
    done
    if [ $size_warn -eq 1 ]; then
        echo "WARNING: one or more images are suspiciously small (<100 MB)." >&2
        echo "         Typical GSI is 600 MB - 4 GB. File may be corrupted," >&2
        echo "         incomplete, or not a system image at all." >&2
        confirm "Continue anyway? (y/N): " || { log "Aborted due to size check"; return 1; }
    fi

    if [ ${#sys[@]} -eq 1 ]; then
        log "Auto-selected: ${sys[0]}"
        echo "$(t FoundImg): ${sys[0]}" >&2
        echo "${sys[0]}"; return 0
    fi
    echo "$(t ChooseImg)" >&2
    local i=1
    for f in "${sys[@]}"; do
        local fsz=$(stat -c%s "$f" 2>/dev/null || echo 0)
        local fmb=$((fsz / 1024 / 1024))
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

resolve_system_image() {
    local img="$1"
    case "$img" in
        *.img.xz)
            command -v unxz >/dev/null || { log_err "unxz not found"; return 1; }
            local out="${img%.xz}"
            if [ ! -f "$out" ]; then
                log "Unpacking .xz: $img -> $out"
                timeout $UNPACK_TIMEOUT unxz -k -T0 "$img" || { log_err "unxz failed"; return 1; }
            fi
            echo "$out" ;;
        *.img.gz)
            command -v gunzip >/dev/null || { log_err "gunzip not found"; return 1; }
            local out="${img%.gz}"
            if [ ! -f "$out" ]; then
                timeout $UNPACK_TIMEOUT gunzip -k "$img" || { log_err "gunzip failed"; return 1; }
            fi
            echo "$out" ;;
        *.img.zst)
            command -v zstd >/dev/null || { log_err "zstd not found"; return 1; }
            local out="${img%.zst}"
            if [ ! -f "$out" ]; then
                timeout $UNPACK_TIMEOUT zstd -d -k "$img" || { log_err "zstd failed"; return 1; }
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
        echo "WARNING: vbmeta.img not found. Bootloop possible." >&2
        confirm "Continue without vbmeta? (y/N): "; return $?
    fi
    if is_userspace; then
        log_warn "in fastbootd, vbmeta is physical"
        echo "WARNING: you are in Fastbootd. vbmeta flash may not work." >&2
    fi
    log "Flashing vbmeta"
    if ! fb_flash --disable-verity --disable-verification flash vbmeta vbmeta.img; then
        confirm "Continue without vbmeta? (y/N): "; return $?
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

    local integrity=$(test_sparse_integrity "$SYSTEM_IMG")
    log "Sparse integrity: $integrity"
    if [[ "$integrity" =~ ^suspect: ]]; then
        echo "Sparse image looks suspicious: $integrity" >&2
        confirm "Continue anyway? (y/N): " || return 1
    fi

    local raw=$(get_image_size "$SYSTEM_IMG")
    [ "$raw" -le 0 ] && { log_err "Cannot detect image size"; return 1; }
    local part=$(calc_partition_size "$raw")
    log "raw=$raw part=$part (margin=${MARGIN_MB}MB)"
    echo "raw=$raw, part=$part (margin=${MARGIN_MB}MB)" >&2

    echo "--------------------------------------------------------" >&2
    echo "SHA256 VERIFICATION:" >&2
    local user_hash=""
    if [ -f "${SYSTEM_IMG}.sha256" ]; then
        echo "[INFO] Found .sha256 file." >&2
        log "Found .sha256 file"
        user_hash="file"
    else
        echo "Copy SHA256 hash from GitHub release and paste here (or Enter to skip)." >&2
        read -rp "Hash: " user_hash
        log "SHA256 input: $( [ -n "$user_hash" ] && echo provided || echo skipped )"
    fi
    if [ -n "$user_hash" ]; then
        local res=$(verify_sha256 "$SYSTEM_IMG" "$user_hash")
        case "$res" in
            mismatch:*)
                log_err "SHA256 mismatch: $res"
                echo "ERROR: SHA256 mismatch! Real: $res" >&2
                confirm "Continue at your own risk? (y/N): " || return 1 ;;
            ok)      echo "[SHA256] OK." >&2 ;;
            missing) echo "[SHA256] Hash not recognized. Skipping." >&2 ;;
            error_file_too_large) echo "[SHA256] .sha256 too large. Skipping." >&2 ;;
            error)   echo "[SHA256] Hash calculation error. Skipping." >&2 ;;
        esac
    else
        echo "[SHA256] Check skipped by user." >&2
    fi
    echo "--------------------------------------------------------" >&2

    local tpart=$(sys_part "$slot")
    local opp=$([ "$slot" = "a" ] && echo b || echo a)

    if ! is_userspace; then
        echo "Rebooting to Fastbootd..." >&2
        log "Not in Fastbootd, reboot needed"
        fb reboot fastboot || true
        wait_for_fastboot || return 1
    fi

    echo "--------------------------------------------------------" >&2
    echo "$(t RebuildSuper)" >&2
    echo "  Target: $tpart" >&2
    echo "  Size:   $part bytes" >&2
    echo "  NOT touching: vendor / odm / vendor_dlkm / system_dlkm" >&2
    echo "--------------------------------------------------------" >&2
    confirm || { log "Rebuild cancelled by user"; return 1; }

    if [ "$part" -gt $((4 * 1024 * 1024 * 1024)) ]; then
        echo "WARNING: partition > 4 GB. MTK overflow possible." >&2
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
    if ! fb create-logical-partition "$tpart" "$part"; then
        log_err "create-logical-partition failed"
        echo "CRITICAL: create-logical-partition FAILED." >&2
        echo "DO NOT REBOOT." >&2
        return 1
    fi
    log "Partition $tpart recreated: $part bytes"
    return 0
}

# ==============================================================================
# Backup /data
# ==============================================================================
backup_data_stream() {
    clear; log "=== BACKUP ==="
    wait_for_adb || { pause; return 1; }
    echo "Убедитесь, что телефон в OrangeFox и Data расшифрована." >&2
    adb_ shell "mount | grep -E '/data|/mnt|f2fs|ext4' || true"
    read -rp "Раздел /data смонтирован? (y/N): " m
    [[ ! "$m" =~ ^[Yy]$ ]] && { pause; return 1; }

    local excludes="--exclude=media --exclude=dalvik-cache --exclude=tombstones --exclude=dropbox"
    if ! adb_ shell "tar $excludes -cf /dev/null -C /data ." >/dev/null 2>&1; then
        echo "[WARN] tar does not support --exclude, doing full backup" >&2
        excludes=""
    fi

    local bdir="backups/data_$(date +%Y%m%d_%H%M%S)"; mkdir -p "$bdir"
    local bfile="$bdir/userdata_backup"

    if command -v pv >/dev/null 2>&1 && command -v lz4 >/dev/null 2>&1; then
        if ! { adb_ shell "tar -c -C /data $excludes ." 2>>"$LOG" | pv -N "backup" | lz4 -9 > "${bfile}.tar.lz4"; }; then
            log_err "backup failed"; pause; return 1
        fi
        log "Backup OK: ${bfile}.tar.lz4"
    else
        if ! adb_ shell "tar -cz -C /data $excludes ." 2>>"$LOG" > "${bfile}.tar.gz"; then
            log_err "backup failed"; pause; return 1
        fi
        log "Backup OK: ${bfile}.tar.gz"
    fi
    ls -lh "$bdir" >&2
    pause
}

# ==============================================================================
# GKI kernels
# ==============================================================================
flash_gki_cores() {
    clear; log "=== GKI FLASH ==="
    local boot_file="" vendor_file=""
    interactive_file_select "boot*.img" "Select BOOT (kernel):" || { pause; return 1; }
    boot_file="$SELECTED_FILE"
    interactive_file_select "vendor_boot*.img" "Select VENDOR_BOOT:" || { pause; return 1; }
    vendor_file="$SELECTED_FILE"
    log "boot file: $boot_file"
    log "vendor_boot file: $vendor_file"

    wait_for_adb || { echo "ADB not available." >&2; pause; return 1; }
    log "adb reboot bootloader"
    adb_ reboot bootloader || true
    wait_for_fastboot || { echo "Fastboot not found." >&2; pause; return 1; }
    check_bootloader_unlocked || { pause; return 1; }

    local slot=$(get_current_slot)
    log "Target slot: $slot"
    read -rp "Flash to slot _$slot? (y/N): " c
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
    clear; log "=== EMERGENCY RESTORE ==="
    local b="" v=""
    interactive_file_select "boot*.img" "Stable BOOT image:" || { pause; return 1; }
    b="$SELECTED_FILE"
    interactive_file_select "vendor_boot*.img" "Stable VENDOR_BOOT image:" || { pause; return 1; }
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
# Menus — all UI on stderr, only final choice echoed to stdout
# ==============================================================================
show_main_menu() {
    clear
    echo "GSI Flash Tool $FULL_VERSION (Linux)" >&2
    echo "$(t LogFile): $LOG" >&2
    echo "========================================================" >&2
    echo "  1. Проверить устройства (ADB / Fastboot)" >&2
    echo "  2. $(t FromAndroid)" >&2
    echo "  3. $(t FromRecovery)" >&2
    echo "  4. $(t FromBootloader)" >&2
    echo "  5. $(t AlreadyFb)" >&2
    echo "  6. $(t ServiceMenu)" >&2
    echo "  0. $(t Exit)" >&2
    echo "========================================================" >&2
    local c; read -rp "$(t Input)" c
    log "Main menu: choice=$c"
    echo "$c"
}

show_action_menu() {
    clear
    echo "Active slot: $CURRENT_SLOT  [A/B: $IS_AB_DEVICE]" >&2
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
            local sc; read -rp "$(t EnterSlot)" sc
            [[ ! "$sc" =~ ^[ab]$ ]] && sc="$CURRENT_SLOT"
            log "Target slot: $sc"
            confirm_vbmeta || return
            free_super_space "$sc" || return
            fb_flash flash "$(sys_part "$sc")" "$SYSTEM_IMG" || return
            fb erase cache || true
            [ "$IS_AB_DEVICE" = "yes" ] && fb set_active "$sc" || true
            fb reboot
            log "Flash OK (slot). Exiting."
            echo "$(t FlashOk)"; exit 0
            ;;
        update)
            confirm_vbmeta || return
            free_super_space "$CURRENT_SLOT" || return
            fb_flash flash "$(sys_part "$CURRENT_SLOT")" "$SYSTEM_IMG" || return
            fb erase cache || true
            fb reboot
            log "Flash OK (update). Exiting."
            echo "$(t FlashOk)"; exit 0
            ;;
        reset)
            confirm_vbmeta || return
            free_super_space "$CURRENT_SLOT" || return
            fb -w || true
            fb_flash flash "$(sys_part "$CURRENT_SLOT")" "$SYSTEM_IMG" || return
            fb reboot
            log "Flash OK (reset). Exiting."
            echo "$(t FlashOk)"; exit 0
            ;;
        dirty)
            check_bootloader_unlocked || return
            fb_flash flash "$(sys_part "$CURRENT_SLOT")" "$SYSTEM_IMG" || return
            fb reboot
            log "Flash OK (dirty). Exiting."
            echo "$(t FlashOk)"; exit 0
            ;;
    esac
}

# ==============================================================================
# MAIN FLOW
# ==============================================================================
check_tool_versions
problems=$?
if [ $problems -gt 0 ]; then
    echo "Some tools missing. Basic operations may not work." >&2
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
            4) wait_for_fastboot && { fb reboot fastboot; wait_for_fastboot && PROCEED=1; } ;;
            3) wait_for_adb && { adb_ reboot fastboot; wait_for_fastboot && PROCEED=1; } ;;
            2) wait_for_adb && { adb_ reboot fastboot; wait_for_fastboot && PROCEED=1; } ;;
            1) adb devices; fastboot devices ;;
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
                if [ "$IS_AB_DEVICE" != "yes" ]; then echo "Device is not A/B." >&2; pause; continue; fi
                new=$([ "$CURRENT_SLOT" = "a" ] && echo b || echo a)
                if is_userspace; then
                    log_warn "set_active in fastbootd: may fail on MTK"
                    echo "WARNING: you are in Fastbootd. set_active may not work on MTK." >&2
                    confirm "Try anyway? (y/N): " || continue
                fi
                if fb set_active "$new"; then
                    CURRENT_SLOT="$new"
                    log "Switched active slot to $CURRENT_SLOT"
                    echo "Current slot: $CURRENT_SLOT" >&2
                else
                    log_err "set_active $new FAILED"
                    echo "ERROR: set_active failed. On MTK use bootloader, not fastbootd." >&2
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