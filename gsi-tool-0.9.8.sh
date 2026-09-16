#!/bin/bash
# ==============================================================================
# GSI FLASH & SERVICE TOOL 0.9.8 // BY GODFLESH
# Safety-first, sparse-aware, aligned+256MB, unlock-check, A/B autodetect,
# auto-resolve .img.xz/.gz/.zst, safe-super, unified filter, universal timeouts.
# ==============================================================================

TOOL_VERSION="0.9.8"

if [ "$1" = "--version" ] || [ "$1" = "-v" ]; then echo "$TOOL_VERSION"; exit 0; fi
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "GSI Flash Tool $TOOL_VERSION"
    echo "Использование: $0 [опции]"
    echo "  -h, --help     Показать эту справку"
    echo "  -v, --version  Показать версию утилиты"
    exit 0
fi

set -o pipefail

for cmd in adb fastboot timeout od df awk; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Ошибка: $cmd не найден!"; exit 1; }
done

LOG_DIR="logs"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/gsi-tool_${TOOL_VERSION}_$(date +%Y%m%d_%H%M%S).log"
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
pause() { read -n 1 -r -p "Нажмите любую клавишу..."; echo; }

trap_destructive_on() {
    trap 'echo; echo "!!! ПРЕРЫВАНИЕ !!!"; echo "НЕ выключайте устройство и не отсоединяйте кабель!"; echo "Перезагрузите в fastboot вручную и попробуйте снова."; exit 130' INT TERM
}
trap_destructive_off() { trap - INT TERM; }

PARTITION_MARGIN_MB="${GSI_MARGIN_MB:-256}"
if [[ ! "$PARTITION_MARGIN_MB" =~ ^[0-9]+$ ]] || [ "$PARTITION_MARGIN_MB" -lt 16 ]; then
    echo "Некорректное GSI_MARGIN_MB='$PARTITION_MARGIN_MB', использую 256"
    PARTITION_MARGIN_MB=256
fi
PARTITION_MARGIN=$((PARTITION_MARGIN_MB * 1024 * 1024))
PARTITION_ALIGN=4096
PARTITION_WARN_BIG=$((4 * 1024 * 1024 * 1024))
WAIT_TIMEOUT=15
REBOOT_TIMEOUT=10
UNPACK_TIMEOUT=3600

IS_AB_DEVICE="yes"
CURRENT_SLOT="a"

sys_part() { [ "$IS_AB_DEVICE" = "yes" ] && echo "system_$1" || echo "system"; }

fb_flash() {
    if ! fastboot "$@" >> "$LOG" 2>&1; then
        echo "========================================================"
        echo "ОШИБКА: fastboot $* — ПРОВАЛ!"
        echo "Подробности в логе: $LOG"
        echo "НЕ ПЕРЕЗАГРУЖАЙТЕ устройство. Сначала разберитесь."
        echo "========================================================"
        return 1
    fi
    return 0
}

safe_reboot() {
    local rc
    timeout $REBOOT_TIMEOUT fastboot reboot >> "$LOG" 2>&1
    rc=$?
    if [ $rc -eq 124 ]; then
        echo "[ВНИМАНИЕ] fastboot reboot: timeout ($REBOOT_TIMEOUT сек)"
        echo "Устройство, скорее всего, всё равно перезагрузится."
        echo "Проверьте лог: $LOG"
    elif [ $rc -ne 0 ]; then
        echo "[ВНИМАНИЕ] fastboot reboot: ошибка (код $rc)"
        echo "Проверьте лог: $LOG"
    fi
}

calculate_partition_size() {
    local raw=$1
    if [[ ! "$raw" =~ ^[0-9]+$ ]] || [ "$raw" -le 0 ]; then
        echo 0; return 1
    fi
    local aligned=$(( (raw + PARTITION_ALIGN - 1) / PARTITION_ALIGN * PARTITION_ALIGN ))
    echo $((aligned + PARTITION_MARGIN))
}

wait_for_adb() {
    local t=${1:-$WAIT_TIMEOUT} c=0
    echo -n "Ожидание ADB-устройства"
    while [ $c -lt $t ]; do
        adb devices 2>/dev/null | grep -qE "device$|recovery$" && { echo " [OK]"; return 0; }
        echo -n "."; sleep 1; c=$((c+1))
    done
    echo " [ТАЙМ-АУТ]"; return 1
}

wait_for_fastboot() {
    local t=${1:-$WAIT_TIMEOUT} c=0
    echo -n "Ожидание Fastboot-устройства"
    while [ $c -lt $t ]; do
        fastboot devices 2>/dev/null | grep -q "fastboot" && { echo " [OK]"; return 0; }
        echo -n "."; sleep 1; c=$((c+1))
    done
    echo " [ТАЙМ-АУТ]"; return 1
}

detect_image_size() {
    local img=$1
    [ -f "$img" ] || { echo 0; return 1; }
    local magic
    magic=$(od -An -tx1 -N4 "$img" 2>/dev/null | tr -d ' \n')
    if [ "$magic" = "3aff26ed" ]; then
        local blk_sz total_blks
        blk_sz=$(od -An -tu4 -j12 -N4 "$img" 2>/dev/null | tr -d ' ')
        total_blks=$(od -An -tu4 -j16 -N4 "$img" 2>/dev/null | tr -d ' ')
        if [[ "$blk_sz" =~ ^[0-9]+$ ]] && [[ "$total_blks" =~ ^[0-9]+$ ]]; then
            echo $((blk_sz * total_blks)); return 0
        fi
    fi
    stat -c%s "$img"
}

verify_sparse_integrity() {
    local img=$1
    local magic; magic=$(od -An -tx1 -N4 "$img" 2>/dev/null | tr -d ' \n')
    [ "$magic" != "3aff26ed" ] && return 0

    local blk_sz total_blks
    blk_sz=$(od -An -tu4 -j12 -N4 "$img" 2>/dev/null | tr -d ' ')
    total_blks=$(od -An -tu4 -j16 -N4 "$img" 2>/dev/null | tr -d ' ')
    [[ ! "$blk_sz" =~ ^[0-9]+$ ]] && return 0
    [[ ! "$total_blks" =~ ^[0-9]+$ ]] && return 0

    local expected=$((blk_sz * total_blks))
    local actual; actual=$(stat -c%s "$img")
    local min_size=$((expected / 4))

    if [ "$actual" -lt "$min_size" ]; then
        echo "--------------------------------------------------------"
        echo "ВНИМАНИЕ: sparse-образ подозрительно мал."
        echo "  actual=$actual, min_expected=$min_size, raw=$expected"
        echo "Возможно, файл недокачан или повреждён."
        echo "--------------------------------------------------------"
        read -p "Продолжить прошивку? (y/N): " c
        [[ "$c" =~ ^[Yy]$ ]] || return 1
    fi
    return 0
}

resolve_system_img() {
    local img="$SYSTEM_IMG"
    local sz free_mb need_mb out target_dir

    case "$img" in
        *.img.xz)
            command -v unxz >/dev/null || { echo "Нет unxz (пакет xz)"; return 1; }
            out="${img%.xz}"
            if [ ! -f "$out" ]; then
                target_dir=$(dirname "$out")
                sz=$(stat -c%s "$img"); need_mb=$(( sz * 3 / 1024 / 1024 ))
                free_mb=$(( $(df -P -B1 "$target_dir" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
                if [ "$free_mb" -lt "$need_mb" ]; then
                    echo "ОШИБКА: мало места в $target_dir (нужно ~${need_mb} МБ, свободно ${free_mb} МБ)"
                    return 1
                fi
                echo "Распаковка $img → $out (нужно ~${need_mb} МБ, свободно ${free_mb} МБ)"
                read -p "Продолжить? (y/N): " c
                [[ "$c" =~ ^[Yy]$ ]] || return 1
                timeout $UNPACK_TIMEOUT unxz -k -T0 "$img" || return 1
            fi
            SYSTEM_IMG="$out" ;;
        *.img.gz)
            command -v gunzip >/dev/null || { echo "Нет gunzip"; return 1; }
            out="${img%.gz}"
            if [ ! -f "$out" ]; then
                target_dir=$(dirname "$out")
                sz=$(stat -c%s "$img"); need_mb=$(( sz * 4 / 1024 / 1024 ))
                free_mb=$(( $(df -P -B1 "$target_dir" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
                if [ "$free_mb" -lt "$need_mb" ]; then
                    echo "ОШИБКА: мало места в $target_dir (нужно ~${need_mb} МБ, свободно ${free_mb} МБ)"
                    return 1
                fi
                echo "Распаковка $img → $out (нужно ~${need_mb} МБ)"
                read -p "Продолжить? (y/N): " c
                [[ "$c" =~ ^[Yy]$ ]] || return 1
                timeout $UNPACK_TIMEOUT gunzip -k "$img" || return 1
            fi
            SYSTEM_IMG="$out" ;;
        *.img.zst)
            command -v zstd >/dev/null || { echo "Нет zstd"; return 1; }
            out="${img%.zst}"
            if [ ! -f "$out" ]; then
                target_dir=$(dirname "$out")
                sz=$(stat -c%s "$img"); need_mb=$(( sz * 4 / 1024 / 1024 ))
                free_mb=$(( $(df -P -B1 "$target_dir" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
                if [ "$free_mb" -lt "$need_mb" ]; then
                    echo "ОШИБКА: мало места в $target_dir (нужно ~${need_mb} МБ, свободно ${free_mb} МБ)"
                    return 1
                fi
                echo "Распаковка $img → $out (нужно ~${need_mb} МБ)"
                read -p "Продолжить? (y/N): " c
                [[ "$c" =~ ^[Yy]$ ]] || return 1
                timeout $UNPACK_TIMEOUT zstd -d -k "$img" || return 1
            fi
            SYSTEM_IMG="$out" ;;
        *.img) : ;;
        *) echo "Неизвестный формат: $img"; return 1 ;;
    esac
    [ -f "$SYSTEM_IMG" ] || return 1
    return 0
}

check_bootloader_unlocked() {
    local raw
    raw=$(fastboot getvar unlocked 2>&1)
    [[ "$raw" =~ unlocked:[[:space:]]*yes ]] && { log "unlocked: yes"; return 0; }

    raw=$(fastboot getvar secure 2>&1)
    [[ "$raw" =~ secure:[[:space:]]*no ]] && { log "secure: no"; return 0; }

    raw=$(fastboot flashing get_unlock_ability 2>&1)
    if [[ "$raw" =~ get_unlock_ability:[[:space:]]*0 ]]; then
        echo "========================================================"
        echo "ОШИБКА: OEM Unlock выключен в Android!"
        echo "Включите 'OEM unlocking' в настройках разработчика."
        echo "========================================================"
        return 1
    fi

    echo "========================================================"
    echo "КРИТИЧЕСКАЯ ОШИБКА: Загрузчик заблокирован!"
    echo "Прошивка dynamic partitions невозможна."
    echo "========================================================"
    return 1
}

detect_ab_device() {
    local raw; raw=$(fastboot getvar slot-count 2>&1)
    if [[ "$raw" =~ slot-count:[[:space:]]*2 ]]; then
        IS_AB_DEVICE="yes"; log "A/B: yes (slot-count=2)"
    elif [[ "$raw" =~ slot-count:[[:space:]]*1 ]]; then
        IS_AB_DEVICE="no";  log "A/B: no (slot-count=1)"
    else
        IS_AB_DEVICE="yes"; log "slot-count не определён, предполагаем A/B"
    fi
}

parse_slot() {
    local raw; raw=$(fastboot getvar current-slot 2>&1)
    if [[ "$raw" =~ current-slot:[[:space:]]*([ab]) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "[WARN] не удалось определить текущий слот, использую 'a'" >&2
        echo "a"
    fi
}

parse_userspace() {
    local raw; raw=$(fastboot getvar is-userspace 2>&1)
    [[ "$raw" =~ is-userspace:[[:space:]]*yes ]] && echo "yes" || echo "no"
}

get_current_slot() { parse_slot; }

interactive_file_select() {
    local mask=$1 prompt_text=$2
    local old; old=$(shopt -p nullglob 2>/dev/null)
    shopt -u nullglob
    local files=($mask)
    if [ ! -e "${files[0]}" ]; then
        echo "Файлы по маске [$mask] не найдены!"
        eval "$old"; return 1
    fi
    if [ ${#files[@]} -eq 1 ]; then
        SELECTED_FILE="${files[0]}"
        echo "Найден единственный файл: $SELECTED_FILE"
        eval "$old"; return 0
    fi
    echo "$prompt_text"
    local c=1
    for f in "${files[@]}"; do echo "   $c) $f"; c=$((c+1)); done
    local choice
    while true; do
        read -p "Номер (0 = отмена): " choice
        [ "$choice" = "0" ] && { eval "$old"; return 1; }
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#files[@]} ]; then
            SELECTED_FILE="${files[$((choice-1))]}"
            eval "$old"; return 0
        fi
        echo "Неверный ввод."
    done
}

backup_data_stream() {
    clear; log "=== BACKUP START ==="
    echo "Лог: $LOG"
    echo "Убедитесь, что телефон в OrangeFox и Data расшифрована."
    wait_for_adb || { echo "ADB не отвечает."; pause; return 1; }

    local use_pv="" use_lz4=""
    command -v pv  >/dev/null 2>&1 && use_pv="yes"
    command -v lz4 >/dev/null 2>&1 && use_lz4="yes"

    adb shell "mount | grep -E '/data|/mnt|f2fs|ext4' || true" | tee -a "$LOG"
    read -rp "Раздел /data смонтирован? (y/N): " m
    [[ ! "$m" =~ ^[Yy]$ ]] && { pause; return 1; }
    read -rp "Запустить поток? (y/N): " s
    [[ ! "$s" =~ ^[Yy]$ ]] && return 1

    # Проверка поддержки --exclude (BusyBox tar может не понимать длинный синтаксис)
    local excludes="--exclude='media' --exclude='dalvik-cache' --exclude='tombstones' --exclude='dropbox'"
    if ! adb shell "tar $excludes -cf /dev/null -C /data ." >/dev/null 2>&1; then
        echo "[ВНИМАНИЕ] tar на устройстве не поддерживает --exclude — бэкап пойдёт полностью."
        excludes=""
        read -rp "Продолжить полный бэкап (включая /data/media, может быть очень долго)? (y/N): " c
        [[ "$c" =~ ^[Yy]$ ]] || { pause; return 1; }
    fi

    local bdir="backups/data_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bdir"
    local bfile="${bdir}/userdata_backup"

    if [ "$use_pv" = "yes" ] && [ "$use_lz4" = "yes" ]; then
        if ! { adb shell "tar -c -C /data $excludes ." 2>>"$LOG" \
              | pv -N "Поток /data -> ПК" \
              | lz4 -9 > "${bfile}.tar.lz4"; }; then
            echo "ОШИБКА: бэкап провалился. Архив может быть повреждён."
            pause; return 1
        fi
        log "Бэкап завершён: ${bfile}.tar.lz4"
    else
        if ! adb shell "tar -cz -C /data $excludes ." 2>>"$LOG" > "${bfile}.tar.gz"; then
            echo "ОШИБКА: бэкап провалился. Архив может быть повреждён."
            pause; return 1
        fi
        log "Бэкап завершён: ${bfile}.tar.gz"
    fi
    ls -lh "$bdir" | tee -a "$LOG"
    pause
}

flash_gki_cores() {
    clear; log "=== GKI FLASH ==="
    interactive_file_select "boot*.img" "Выберите BOOT:" || { pause; return 1; }
    local boot_file=$SELECTED_FILE
    interactive_file_select "vendor_boot*.img" "Выберите VENDOR_BOOT:" || { pause; return 1; }
    local vendor_file=$SELECTED_FILE

    wait_for_adb || { echo "ADB недоступен."; pause; return 1; }
    timeout $REBOOT_TIMEOUT adb reboot bootloader >> "$LOG" 2>&1 || true
    wait_for_fastboot || { echo "Fastboot не появился."; pause; return 1; }
    check_bootloader_unlocked || { pause; return 1; }

    local slot; slot=$(parse_slot)
    read -p "Прошить в слот _$slot? (y/N): " c
    if [[ "$c" =~ ^[Yy]$ ]]; then
        fb_flash flash boot_"$slot"        "$boot_file"   || { pause; return 1; }
        fb_flash flash vendor_boot_"$slot" "$vendor_file" || { pause; return 1; }
        fastboot erase cache >> "$LOG" 2>&1 || true
        log "Ядра прошиты."
    fi
    pause
}

emergency_slot_fix() {
    clear; log "=== EMERGENCY DUAL-SLOT ==="
    interactive_file_select "boot*.img" "Стабильный BOOT:" || { pause; return 1; }
    local b=$SELECTED_FILE
    interactive_file_select "vendor_boot*.img" "Стабильный VENDOR_BOOT:" || { pause; return 1; }
    local v=$SELECTED_FILE
    wait_for_fastboot || { echo "Нет fastboot."; pause; return 1; }
    check_bootloader_unlocked || { pause; return 1; }

    trap_destructive_on
    fb_flash flash boot_a        "$b" || { trap_destructive_off; pause; return 1; }
    fb_flash flash vendor_boot_a "$v" || { trap_destructive_off; pause; return 1; }
    fb_flash flash boot_b        "$b" || { trap_destructive_off; pause; return 1; }
    fb_flash flash vendor_boot_b "$v" || { trap_destructive_off; pause; return 1; }
    trap_destructive_off

    fastboot set_active a >> "$LOG" 2>&1
    log "Разметка стабилизирована."
    safe_reboot
    exit 0
}

service_menu() {
    while true; do
        clear
        echo "==== СЕРВИСНЫЙ МОДУЛЬ ===="
        echo "  1. ADB-Stream бэкап /data"
        echo "  2. GKI-ядра в активный слот"
        echo "  3. Экстренный откат (оба слота + A)"
        echo "  0. Назад"
        read -p "Ввод: " s
        case "$s" in
            1) backup_data_stream ;;
            2) flash_gki_cores ;;
            3) emergency_slot_fix ;;
            0) return 0 ;;
        esac
    done
}

select_system_img() {
    local all=()
    shopt -s nullglob
    all=(*.img *.img.xz *.img.gz *.img.zst)
    shopt -u nullglob

    local sys_imgs=()
    for img in "${all[@]}"; do
        case "$img" in
            vbmeta*.img*|boot*.img*|vendor*.img*|recovery*.img*|super*.img*|dtbo*.img*|userdata*.img*|metadata*.img*|system_dlkm*.img*)
                continue ;;
        esac
        [ -f "$img" ] && sys_imgs+=("$img")
    done

    if [ ${#sys_imgs[@]} -eq 0 ]; then echo "Образы системы не найдены!"; return 1; fi
    if [ ${#sys_imgs[@]} -eq 1 ]; then
        SYSTEM_IMG="${sys_imgs[0]}"
        echo "Найден: $SYSTEM_IMG"
        resolve_system_img || return 1
        return 0
    fi

    echo "Найдено несколько образов:"
    PS3="Ваш выбор (0 = отмена): "
    select f in "${sys_imgs[@]}" "Ввести имя вручную"; do
        [ -z "$f" ] && { echo "Отменено."; return 1; }
        if [ "$f" = "Ввести имя вручную" ]; then
            read -p "Имя файла: " custom
            [ -f "$custom" ] || { echo "Не найден."; return 1; }
            SYSTEM_IMG="$custom"
        else
            SYSTEM_IMG="$f"
        fi
        resolve_system_img || return 1
        return 0
    done
}

check_and_flash_vbmeta() {
    if [ ! -f "vbmeta.img" ]; then
        echo "ВНИМАНИЕ: vbmeta.img не найден! Возможен bootloop из-за AVB."
        read -p "Продолжить без vbmeta? (y/N): " c
        [[ "$c" =~ ^[Yy]$ ]] && return 0 || return 1
    fi

    if [ "$(parse_userspace)" = "yes" ]; then
        echo "ВНИМАНИЕ: вы в Fastbootd. Прошивка vbmeta (физический раздел)"
        echo "может не работать на некоторых устройствах. Если упадёт —"
        echo "вернитесь в Bootloader и повторите."
    fi

    echo "Прошиваю vbmeta с --disable-verity --disable-verification..."
    if ! fb_flash --disable-verity --disable-verification flash vbmeta vbmeta.img; then
        read -p "Продолжить без vbmeta? (y/N): " c
        [[ "$c" =~ ^[Yy]$ ]] || return 1
    else
        log "vbmeta прошит."
    fi
    return 0
}

free_super_space() {
    local slot=$1
    [ -z "$slot" ] && slot="$CURRENT_SLOT"

    if [ -z "$SYSTEM_IMG" ] || [ ! -f "$SYSTEM_IMG" ] || [ ! -r "$SYSTEM_IMG" ]; then
        echo "ОШИБКА: файл образа не задан или недоступен: '$SYSTEM_IMG'"
        return 1
    fi

    verify_sparse_integrity "$SYSTEM_IMG" || return 1

    local real_size; real_size=$(detect_image_size "$SYSTEM_IMG")
    if [[ ! "$real_size" =~ ^[0-9]+$ ]] || [ "$real_size" -le 0 ]; then
        echo "Не удалось определить размер образа."; return 1
    fi

    local part_size; part_size=$(calculate_partition_size "$real_size")
    log "raw=$real_size, part=$part_size (margin=${PARTITION_MARGIN_MB}MB)"

    # --- SHA256 verification (0.9.8) ---
    echo "--------------------------------------------------------"
    echo "ВЕРИФИКАЦИЯ ЦЕЛОСТНОСТИ ОБРАЗА (SHA256):"
    local user_hash="" raw_content=""
    if [ -f "${SYSTEM_IMG}.sha256" ]; then
        if [ "$(stat -c%s "${SYSTEM_IMG}.sha256" 2>/dev/null || echo 0)" -gt 4096 ]; then
            echo "[ВНИМАНИЕ] Файл .sha256 больше 4 КБ. Проверка пропущена."
        else
            echo "[INFO] Найден локальный файл контрольной суммы."
            raw_content=$(cat "${SYSTEM_IMG}.sha256" 2>/dev/null)
        fi
    else
        echo "Скопируйте хеш SHA256 со страницы GitHub / 4PDA."
        read -p "Вставьте хеш (или Enter для пропуска): " user_hash
        raw_content="$user_hash"
    fi

    if [[ "$raw_content" =~ ([a-fA-F0-9]{64}) ]]; then
        local want got
        want=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
        echo "Вычисляю SHA256 образа, подождите..."
        if command -v pv >/dev/null 2>&1 && [ -t 1 ]; then
            got=$(pv -N "SHA256" "$SYSTEM_IMG" | sha256sum | awk '{print $1}')
        else
            got=$(sha256sum "$SYSTEM_IMG" | awk '{print $1}')
        fi
        got=$(echo "$got" | tr '[:upper:]' '[:lower:]')
        if [ "$got" != "$want" ]; then
            echo "========================================================"
            echo "КРИТИЧЕСКАЯ ОШИБКА: Контрольная сумма SHA256 НЕ СОВПАДАЕТ!"
            echo "  В файле/вводе: $want"
            echo "  Реальный хеш:  $got"
            echo "========================================================"
            read -p "Образ поврежден. Продолжить на свой риск? (y/N): " c
            [[ "$c" =~ ^[Yy]$ ]] || return 1
        else
            log "[SHA256] Контрольная сумма совпадает (OK)."
        fi
    else
        echo "[SHA256] Проверка пропущена (нет валидного хеша)."
    fi
    echo "--------------------------------------------------------"

    local tpart; tpart=$(sys_part "$slot")
    local opp; [ "$slot" = "a" ] && opp="b" || opp="a"

    if [ "$(parse_userspace)" != "yes" ]; then
        echo "Перезагрузка в Fastbootd..."
        timeout $REBOOT_TIMEOUT fastboot reboot fastboot 2>/dev/null || true
        wait_for_fastboot || { echo "Fastbootd не поднялся."; return 1; }
    fi

    echo "--------------------------------------------------------"
    echo "РЕКОНСТРУКЦИЯ SUPER:"
    echo "  Тип устройства: $([ "$IS_AB_DEVICE" = yes ] && echo "A/B" || echo "Non-A/B")"
    echo "  Целевой раздел: $tpart"
    echo "  Raw образ:      $real_size байт"
    echo "  Партиция:       $part_size байт (align $PARTITION_ALIGN + ${PARTITION_MARGIN_MB} MB)"
    echo "  НЕ трогаем:     vendor / odm / vendor_dlkm / system_dlkm"
    echo "--------------------------------------------------------"
    read -p "Выполнить? (y/N): " c
    if [[ ! "$c" =~ ^[Yy]$ ]]; then
        echo "Реконструкция отменена пользователем."
        return 1
    fi

    if [ "$part_size" -gt "$PARTITION_WARN_BIG" ]; then
        echo "ВНИМАНИЕ: партиция >4 ГБ. Возможен overflow 32-bit на MTK fastbootd."
        read -p "Продолжить? (y/N): " big_ok
        [[ "$big_ok" =~ ^[Yy]$ ]] || return 1
    fi

    trap_destructive_on

    if [ "$IS_AB_DEVICE" = "yes" ]; then
        for s in "$slot" "$opp"; do
            for p in system product system_ext; do
                fastboot delete-logical-partition "${p}_${s}" >> "$LOG" 2>&1 || true
            done
        done
    else
        for p in system product system_ext; do
            fastboot delete-logical-partition "$p" >> "$LOG" 2>&1 || true
        done
    fi

    if ! fastboot create-logical-partition "$tpart" "$part_size" >> "$LOG" 2>&1; then
        trap_destructive_off
        echo "========================================================"
        echo "КРИТИЧЕСКАЯ ОШИБКА: create-logical-partition $tpart провалился."
        echo "super остался без system/product/system_ext на обоих слотах."
        echo ""
        echo "Пути восстановления:"
        echo "  1. НЕ перезагружайте устройство."
        echo "  2. Если активный слот другой — переключитесь: fastboot set_active <slot>"
        echo "  3. Попробуйте меньший GSI или lpmake на устройстве."
        echo "========================================================"
        return 1
    fi

    trap_destructive_off
    log "Раздел $tpart создан: $part_size байт."
    return 0
}

# ============================================================
# MAIN MENU
# ============================================================
while true; do
    clear
    echo "GSI Flash Tool $TOOL_VERSION (Linux)"
    echo "Лог: $LOG"
    echo "========================================================"
    echo "   1. Проверить устройства (ADB / Fastboot)"
    echo "   2. Android → Fastbootd"
    echo "   3. Recovery → Fastbootd"
    echo "   4. Bootloader → Fastbootd"
    echo "   5. Уже в Fastbootd"
    echo "   6. СЕРВИСНОЕ МЕНЮ"
    echo "   0. Выход"
    echo "========================================================"
    read -p "Ввод: " cs
    case "$cs" in
        0) exit 0 ;;
        6) service_menu; continue ;;
        5) wait_for_fastboot || { pause; continue; }; break ;;
        4)
            wait_for_fastboot || { echo "Не в Bootloader!"; pause; continue; }
            timeout $REBOOT_TIMEOUT fastboot reboot fastboot 2>/dev/null || true
            wait_for_fastboot || { pause; continue; }
            break ;;
        3|2)
            wait_for_adb || { echo "ADB не отвечает."; pause; continue; }
            timeout $REBOOT_TIMEOUT adb reboot fastboot 2>/dev/null || true
            wait_for_fastboot || { pause; continue; }
            break ;;
        1) adb devices; fastboot devices; pause; continue ;;
        *) continue ;;
    esac
done

check_bootloader_unlocked || exit 1
detect_ab_device

CURRENT_SLOT=$(get_current_slot)
echo "Активный слот: $CURRENT_SLOT"

# ============================================================
# ACTION MENU
# ============================================================
while true; do
    clear
    echo "========================================================"
    echo " Активный слот: $CURRENT_SLOT   [A/B: $IS_AB_DEVICE]"
    echo "========================================================"
    echo "   1. Обновить систему (Erase Cache)"
    echo "   2. Сброс и прошивка (Full Wipe)"
    echo "   3. Прошить в указанный слот (A/B)"
    echo "   4. Переключить активный слот"
    echo "   5. Грязная прошивка (Dirty Flash)"
    echo "   0. Назад"
    echo "========================================================"
    read -p "Ввод: " ca

    case "$ca" in
        0) exec "$0" "$@" ;;
        4)
            if [ "$IS_AB_DEVICE" != "yes" ]; then
                echo "Устройство не A/B. Переключение недоступно."
                pause; continue
            fi
            ns=$([ "$CURRENT_SLOT" = "a" ] && echo "b" || echo "a")
            fastboot set_active "$ns"
            CURRENT_SLOT="$ns"
            echo "Текущий слот: $CURRENT_SLOT"
            pause; continue ;;
        3)
            select_system_img || continue
            read -p "Слот (a/b): " sc
            [[ ! "$sc" =~ ^[ab]$ ]] && sc=$CURRENT_SLOT
            check_and_flash_vbmeta || continue
            free_super_space "$sc" || continue
            if ! fb_flash flash "$(sys_part "$sc")" "$SYSTEM_IMG"; then
                pause; continue
            fi
            fastboot erase cache >> "$LOG" 2>&1 || true
            [ "$IS_AB_DEVICE" = "yes" ] && fastboot set_active "$sc" >> "$LOG" 2>&1
            safe_reboot
            echo "Готово."
            pause; exit 0 ;;
        2)
            select_system_img || continue
            check_and_flash_vbmeta || continue
            free_super_space "$CURRENT_SLOT" || continue
            if ! fastboot -w >> "$LOG" 2>&1; then
                echo "ВНИМАНИЕ: fastboot -w (wipe) провалился."
                read -p "Продолжить без wipe? (y/N): " c
                [[ "$c" =~ ^[Yy]$ ]] || continue
            fi
            if ! fb_flash flash "$(sys_part "$CURRENT_SLOT")" "$SYSTEM_IMG"; then
                pause; continue
            fi
            safe_reboot
            pause; exit 0 ;;
        1)
            select_system_img || continue
            check_and_flash_vbmeta || continue
            free_super_space "$CURRENT_SLOT" || continue
            if ! fb_flash flash "$(sys_part "$CURRENT_SLOT")" "$SYSTEM_IMG"; then
                pause; continue
            fi
            fastboot erase cache >> "$LOG" 2>&1 || true
            safe_reboot
            pause; exit 0 ;;
        5)
            select_system_img || continue
            check_bootloader_unlocked || { pause; continue; }
            if ! fb_flash flash "$(sys_part "$CURRENT_SLOT")" "$SYSTEM_IMG"; then
                pause; continue
            fi
            safe_reboot
            pause; exit 0 ;;
        *) continue ;;
    esac
done