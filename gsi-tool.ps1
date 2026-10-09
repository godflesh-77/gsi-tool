# ==============================================================================
# GSI FLASH & SERVICE TOOL 1.0.1 (PowerShell edition)
# Flash GSI, manage A/B slots, back up /data, service partitions.
#
# Repository: https://github.com/godflesh-77/gsi-tool
# License:    MIT
# ==============================================================================

[CmdletBinding()]
param(
    [ValidateSet('en','ru')][string]$Lang,
    [switch]$Version,
    [switch]$Help,
    [switch]$StrictVersions,
    [string]$Serial
)

$null = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

$Script:TOOL_VERSION = '1.0.1'

$buildHash = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    Push-Location $PSScriptRoot
    try { $buildHash = & git rev-parse --short HEAD 2>$null } catch { }
    Pop-Location
}
if (-not $buildHash) { $buildHash = Get-Date -Format 'yyyyMMdd.HHmm' }
$Script:BUILD        = $buildHash
$Script:FULL_VERSION = "$($Script:TOOL_VERSION)+build.$buildHash"

$Script:WAIT_ADB        = 15
$Script:WAIT_FASTBOOT   = 60
$Script:REBOOT_TIMEOUT  = 30
$Script:FLASH_TIMEOUT   = 3600
$Script:BACKUP_TIMEOUT  = 3600
$Script:MARGIN_MB       = 256
$Script:IS_AB           = $true
$Script:CURRENT_SLOT    = 'a'
$Script:SEVENZIP        = $null
$Script:LOG             = $null
$Script:ADB_PATH        = $null
$Script:FASTBOOT_PATH   = $null
$Script:ADB_VER         = $null
$Script:FASTBOOT_VER    = $null
$Script:SEVENZIP_VER    = $null
$Script:STRICT_VERSIONS = [bool]$StrictVersions

# ==============================================================================
# i18n
# ==============================================================================
$MSG = @{
    en = @{
        MainMenuTitle   = 'GSI Flash Tool'
        LogFile         = 'Log'
        MenuCheckDev    = 'Check devices (ADB / Fastboot)'
        MenuFromAndroid = 'Android  -> Fastbootd'
        MenuFromRecovery= 'Recovery -> Fastbootd'
        MenuFromBoot    = 'Bootloader -> Fastbootd'
        MenuAlreadyFb   = 'Already in Fastbootd'
        ServiceMenu     = 'SERVICE MENU'
        Exit            = 'Exit'
        Input           = 'Input: '
        Back            = 'Back'
        ActiveSlotLine  = 'Active slot: {0}  [A/B: {1}]'

        ActionUpdate    = 'Update system'
        ActionReset     = 'Reset and flash (Full Wipe)'
        ActionSlot      = 'Flash to specified slot (A/B)'
        ActionSwitch    = 'Switch active slot'
        ActionDirty     = 'Dirty flash'

        Backing         = 'Backup /data via ADB stream'
        FlashingGki     = 'Flash GKI kernels (boot + vendor_boot)'
        EmergencyFix    = 'Emergency dual-slot restore'

        CheckingBl      = 'Checking bootloader state...'
        BlUnlocked      = 'Bootloader: UNLOCKED'
        BlLocked        = 'CRITICAL: Bootloader is LOCKED!'
        BlOemDisabled   = 'ERROR: OEM Unlock disabled in Android!'

        WaitAdb         = 'Waiting for ADB device'
        WaitFastboot    = 'Waiting for Fastboot device'
        Timeout         = '[TIMEOUT]'
        Ok              = '[OK]'

        Error           = 'ERROR'
        Warning         = 'WARNING'
        Cancel          = 'Cancelled.'
        InvalidChoice   = 'Invalid choice.'
        PressKey        = 'Press any key to continue...'
        EnterConfirm    = 'Continue? (y/N): '
        EnterSlot       = 'Enter slot (a/b): '
        FlashOk         = 'Done.'

        ToolCheck       = 'Tool version check'
        ToolMissing     = 'not found'
        VersionTooOld   = 'version too old (need >= {0})'
        VersionUnknown  = 'version unknown'
        ToolsWarn       = 'Some tools missing or too old. Basic operations may not work.'
        StrictFail      = 'Strict version check enabled: aborting on version problems.'

        FoundImg        = 'Found system image'
        NoSystemImg     = 'No system images found.'
        ChooseImg       = 'Found multiple images. Choose one'
        ImgSuspect1     = 'WARNING: one or more images are suspiciously small (<100 MB).'
        ImgSuspect2     = '         Typical GSI is 600 MB - 4 GB. File may be corrupted,'
        ImgSuspect3     = '         incomplete, or not a system image at all.'
        ContinueAnyway  = 'Continue anyway? (y/N): '

        Unpacking       = 'Unpacking: {0} -> {1}'
        UnpackFailed    = 'Unpack failed: {0}'
        UnpackProgress  = 'unpack'
        Need7Zip        = 'Need 7-Zip for {0}'

        RebuildSuper    = 'SUPER RECONSTRUCTION'
        RebootToFb      = 'Rebooting to Fastbootd...'
        NotInFbReboot   = 'Not in Fastbootd, reboot needed'
        TargetPart      = 'Target partition: {0}'
        NewSize         = 'New size: {0} bytes'
        NotTouching     = 'NOT touching: vendor / odm / vendor_dlkm / system_dlkm'
        SuperBigWarn    = 'WARNING: partition > 4 GB. MTK overflow possible.'
        CreateFailed    = 'CRITICAL: create-logical-partition failed.'
        CreateFailed2   = 'super left without system/product/system_ext. DO NOT REBOOT.'

        ShaHeader       = 'SHA256 VERIFICATION:'
        ShaFileFound    = '[INFO] Found .sha256 file.'
        ShaPrompt       = 'Copy SHA256 hash from GitHub release and paste here (or Enter to skip).'
        ShaPromptShort  = 'Hash'
        ShaOk           = '[SHA256] OK.'
        ShaSkipNoHash   = '[SHA256] Hash not recognized. Skipping.'
        ShaSkipTooBig   = '[SHA256] .sha256 too large. Skipping.'
        ShaSkipErr      = '[SHA256] Hash calculation error. Skipping.'
        ShaSkipUser     = '[SHA256] Check skipped by user.'
        ShaMismatch     = 'SHA256 mismatch! Real: {0}'
        ShaRiskPrompt   = 'Continue at your own risk? (y/N): '

        VbMissing       = 'WARNING: vbmeta.img not found. Bootloop possible.'
        VbContinueNo    = 'Continue without vbmeta? (y/N): '
        VbInUserspace   = 'WARNING: You are in Fastbootd. vbmeta is a physical partition.'
        VbFlashing      = 'Flashing vbmeta...'

        NotAb           = 'Device is not A/B.'
        SetActiveWarn   = 'WARNING: you are in Fastbootd. set_active may not work on MTK.'
        SetActiveTry    = 'Try anyway? (y/N): '
        CurrentSlotMsg  = 'Current slot: {0}'
        SetActiveFail   = 'ERROR: set_active failed. On MTK use bootloader, not fastbootd.'

        SelectBoot      = 'Select BOOT (kernel):'
        SelectVendor    = 'Select VENDOR_BOOT:'
        SelectStableBoot= 'Stable BOOT image:'
        SelectStableVb  = 'Stable VENDOR_BOOT image:'
        FlashToSlot     = 'Flash to slot _{0}? (y/N): '

        BackupTitle     = 'BACKUP /DATA VIA ADB STREAM'
        BackupWarning   = 'Ensure device is in recovery (e.g. OrangeFox) and /data is decrypted.'
        BackupCriticalWarn = 'NOTE: /data backup does NOT include IMEI, Wi-Fi/BT MAC, or Widevine keys.'
        BackupCriticalHint = '      Those live in /persist, /nvram, /modemst*, /misc. Back them up separately from recovery.'
        BackupMountOk   = 'Mount check output written to log.'
        BackupMountAsk  = 'Is /data mounted and decrypted? (y/N): '
        BackupNoExcl    = 'tar does not support --exclude, doing full backup'
        BackupProgress  = 'Backup /data'
        BackupStatusFmt = '{0} MB @ {1} MB/s'
        BackupDone      = 'Backup OK: {0} ({1} MB)'
        BackupFailed    = 'Backup FAILED. See log: {0}'
        BackupNo7Zip    = 'Backup requires 7-Zip. Install 7-Zip 22.00+ and retry.'

        ExitCodeMsg     = 'Exit code: {0}'
    }
    ru = @{
        MainMenuTitle   = 'GSI Flash Tool'
        LogFile         = 'Лог'
        MenuCheckDev    = 'Проверить устройства (ADB / Fastboot)'
        MenuFromAndroid = 'Android  -> Fastbootd'
        MenuFromRecovery= 'Recovery -> Fastbootd'
        MenuFromBoot    = 'Bootloader -> Fastbootd'
        MenuAlreadyFb   = 'Уже в Fastbootd'
        ServiceMenu     = 'СЕРВИСНОЕ МЕНЮ'
        Exit            = 'Выход'
        Input           = 'Ввод: '
        Back            = 'Назад'
        ActiveSlotLine  = 'Активный слот: {0}  [A/B: {1}]'

        ActionUpdate    = 'Обновить систему'
        ActionReset     = 'Сброс и прошивка (Full Wipe)'
        ActionSlot      = 'Прошить в указанный слот (A/B)'
        ActionSwitch    = 'Переключить активный слот'
        ActionDirty     = 'Грязная прошивка'

        Backing         = 'Бэкап /data через ADB-стрим'
        FlashingGki     = 'Прошивка GKI-ядер (boot + vendor_boot)'
        EmergencyFix    = 'Экстренный откат (оба слота)'

        CheckingBl      = 'Проверка загрузчика...'
        BlUnlocked      = 'Загрузчик: РАЗБЛОКИРОВАН'
        BlLocked        = 'КРИТИЧЕСКАЯ ОШИБКА: Загрузчик заблокирован!'
        BlOemDisabled   = 'ОШИБКА: в Android выключен OEM Unlock!'

        WaitAdb         = 'Ожидание ADB-устройства'
        WaitFastboot    = 'Ожидание Fastboot-устройства'
        Timeout         = '[ТАЙМ-АУТ]'
        Ok              = '[OK]'

        Error           = 'ОШИБКА'
        Warning         = 'ВНИМАНИЕ'
        Cancel          = 'Отменено.'
        InvalidChoice   = 'Неверный ввод.'
        PressKey        = 'Нажмите любую клавишу для продолжения...'
        EnterConfirm    = 'Выполнить? (y/N): '
        EnterSlot       = 'Слот (a/b): '
        FlashOk         = 'Готово.'

        ToolCheck       = 'Проверка версий утилит'
        ToolMissing     = 'не найден'
        VersionTooOld   = 'версия устарела (нужно >= {0})'
        VersionUnknown  = 'версия не определена'
        ToolsWarn       = 'Часть утилит отсутствует или устарела. Базовые операции могут не работать.'
        StrictFail      = 'Включён строгий режим проверки: отказ из-за проблем с версиями.'

        FoundImg        = 'Найден образ системы'
        NoSystemImg     = 'Образы системы не найдены.'
        ChooseImg       = 'Найдено несколько образов. Выберите'
        ImgSuspect1     = 'ВНИМАНИЕ: один или несколько образов подозрительно малы (<100 МБ).'
        ImgSuspect2     = '         Типичный GSI весит 600 МБ - 4 ГБ. Файл может быть повреждён,'
        ImgSuspect3     = '         недокачан, или это вовсе не образ системы.'
        ContinueAnyway  = 'Всё равно продолжить? (y/N): '

        Unpacking       = 'Распаковка: {0} -> {1}'
        UnpackFailed    = 'Ошибка распаковки: {0}'
        UnpackProgress  = 'распаковка'
        Need7Zip        = 'Для {0} нужен 7-Zip'

        RebuildSuper    = 'РЕКОНСТРУКЦИЯ SUPER'
        RebootToFb      = 'Перезагрузка в Fastbootd...'
        NotInFbReboot   = 'Не в Fastbootd, нужна перезагрузка'
        TargetPart      = 'Целевой раздел: {0}'
        NewSize         = 'Новый размер: {0} байт'
        NotTouching     = 'НЕ трогаем: vendor / odm / vendor_dlkm / system_dlkm'
        SuperBigWarn    = 'ВНИМАНИЕ: раздел > 4 ГБ. Возможно переполнение на MTK.'
        CreateFailed    = 'КРИТИЧНО: create-logical-partition не удалось.'
        CreateFailed2   = 'super остался без system/product/system_ext. НЕ ПЕРЕЗАГРУЖАЙТЕ.'

        ShaHeader       = 'ПРОВЕРКА SHA256:'
        ShaFileFound    = '[INFO] Найден файл .sha256.'
        ShaPrompt       = 'Скопируйте SHA256 из GitHub-релиза и вставьте сюда (или Enter — пропустить).'
        ShaPromptShort  = 'Hash'
        ShaOk           = '[SHA256] OK.'
        ShaSkipNoHash   = '[SHA256] Хеш не распознан. Пропуск.'
        ShaSkipTooBig   = '[SHA256] Файл .sha256 слишком большой. Пропуск.'
        ShaSkipErr      = '[SHA256] Ошибка вычисления хеша. Пропуск.'
        ShaSkipUser     = '[SHA256] Проверка пропущена пользователем.'
        ShaMismatch     = 'Несовпадение SHA256! Реальный: {0}'
        ShaRiskPrompt   = 'Продолжить на свой риск? (y/N): '

        VbMissing       = 'ВНИМАНИЕ: vbmeta.img не найден. Возможен bootloop.'
        VbContinueNo    = 'Продолжить без vbmeta? (y/N): '
        VbInUserspace   = 'ВНИМАНИЕ: вы в Fastbootd. vbmeta — физический раздел.'
        VbFlashing      = 'Прошивка vbmeta...'

        NotAb           = 'Устройство не A/B.'
        SetActiveWarn   = 'ВНИМАНИЕ: вы в Fastbootd. set_active может не работать на MTK.'
        SetActiveTry    = 'Всё равно попробовать? (y/N): '
        CurrentSlotMsg  = 'Текущий слот: {0}'
        SetActiveFail   = 'ОШИБКА: set_active не удалось. На MTK используйте bootloader, не fastbootd.'

        SelectBoot      = 'Выберите BOOT (ядро):'
        SelectVendor    = 'Выберите VENDOR_BOOT:'
        SelectStableBoot= 'Стабильный BOOT-образ:'
        SelectStableVb  = 'Стабильный VENDOR_BOOT-образ:'
        FlashToSlot     = 'Прошить в слот _{0}? (y/N): '

        BackupTitle     = 'БЭКАП /DATA ЧЕРЕЗ ADB-СТРИМ'
        BackupWarning   = 'Убедитесь, что телефон в recovery (например, OrangeFox) и /data расшифрована.'
        BackupCriticalWarn = 'ВНИМАНИЕ: бэкап /data НЕ включает IMEI, MAC Wi-Fi/Bluetooth и ключи Widevine.'
        BackupCriticalHint = '         Они лежат в /persist, /nvram, /modemst*, /misc. Бэкапьте их отдельно из recovery.'
        BackupMountOk   = 'Вывод проверки mount записан в лог.'
        BackupMountAsk  = '/data смонтирована и расшифрована? (y/N): '
        BackupNoExcl    = 'tar не поддерживает --exclude, делаем полный бэкап'
        BackupProgress  = 'Бэкап /data'
        BackupStatusFmt = '{0} МБ @ {1} МБ/с'
        BackupDone      = 'Бэкап готов: {0} ({1} МБ)'
        BackupFailed    = 'Бэкап НЕ УДАЛСЯ. См. лог: {0}'
        BackupNo7Zip    = 'Для бэкапа нужен 7-Zip. Установите 7-Zip 22.00+ и повторите.'

        ExitCodeMsg     = 'Код выхода: {0}'
    }
}

function Resolve-Language {
    if ($Lang) { return $Lang }
    if ($env:LANG -and $env:LANG -match '^ru') { return 'ru' }
    if ($PSUICulture -match '^ru') { return 'ru' }
    if ([System.Globalization.CultureInfo]::CurrentUICulture.Name -match '^ru') { return 'ru' }
    if ([System.Globalization.CultureInfo]::CurrentCulture.Name -match '^ru') { return 'ru' }
    if ([System.Globalization.CultureInfo]::InstalledUICulture.Name -match '^ru') { return 'ru' }
    return 'en'
}

$Script:Lang = Resolve-Language

function T([string]$key) {
    $m = $MSG[$Script:Lang]
    if ($m.ContainsKey($key)) { return $m[$key] }
    return $MSG['en'][$key]
}

function Say([string]$text, [string]$color = 'White') {
    Write-Host $text -ForegroundColor $color
}

function Log([string]$text) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [INFO]  $text"
    Write-Host $line -ForegroundColor DarkGray
    if ($Script:LOG) { Add-Content -LiteralPath $Script:LOG -Value $line -Encoding UTF8 }
}
function LogWarn([string]$text) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [WARN]  $text"
    Write-Host $line -ForegroundColor Yellow
    if ($Script:LOG) { Add-Content -LiteralPath $Script:LOG -Value $line -Encoding UTF8 }
}
function LogErr([string]$text) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [ERROR] $text"
    Write-Host $line -ForegroundColor Red
    if ($Script:LOG) { Add-Content -LiteralPath $Script:LOG -Value $line -Encoding UTF8 }
}
function LogRaw([string]$text) {
    if ($Script:LOG -and $text) { Add-Content -LiteralPath $Script:LOG -Value $text -Encoding UTF8 }
}

function Pause() {
    Write-Host ''
    Write-Host -NoNewline (T 'PressKey')
    try {
        [void][Console]::ReadKey($true)
    } catch {
        Read-Host | Out-Null
    }
    Write-Host ''
}

function Confirm([string]$prompt = $null) {
    if (-not $prompt) { $prompt = T 'EnterConfirm' }
    $r = Read-Host -Prompt $prompt
    $result = ($r -match '^[Yy]')
    Log "Confirm '$prompt' -> $result"
    return $result
}

# ==============================================================================
# CLI flags
# ==============================================================================
if ($Version) { Write-Output $Script:TOOL_VERSION; exit 0 }
if ($Help) {
    Write-Output "GSI Flash Tool $($Script:TOOL_VERSION)"
    Write-Output "Build: $($Script:BUILD)"
    Write-Output "Usage: gsi-tool.ps1 [-Lang en|ru] [-Serial <serial>] [-StrictVersions] [-Version] [-Help]"
    exit 0
}

# ==============================================================================
# Environment checks
# ==============================================================================
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Host 'Windows 10/11 x64 required.' -ForegroundColor Red
    exit 1
}
if (-not [Environment]::Is64BitProcess) {
    Write-Host 'PowerShell is running in 32-bit mode. Restart from 64-bit cmd/powershell.' -ForegroundColor Red
    exit 1
}

# ==============================================================================
# Log init
# ==============================================================================
$logDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$Script:LOG = Join-Path $logDir "gsi-tool_${Script:TOOL_VERSION}_$ts.log"
Add-Content -LiteralPath $Script:LOG -Value "=== SESSION START $(Get-Date) ===" -Encoding UTF8
Add-Content -LiteralPath $Script:LOG -Value "Version: $($Script:TOOL_VERSION)" -Encoding UTF8
Add-Content -LiteralPath $Script:LOG -Value "Build:   $($Script:BUILD)" -Encoding UTF8
Add-Content -LiteralPath $Script:LOG -Value "Lang: $($Script:Lang) (PSUICulture=$PSUICulture, CurrentUI=$([System.Globalization.CultureInfo]::CurrentUICulture.Name), Installed=$([System.Globalization.CultureInfo]::InstalledUICulture.Name))" -Encoding UTF8
Add-Content -LiteralPath $Script:LOG -Value "StrictVersions: $($Script:STRICT_VERSIONS)" -Encoding UTF8
Add-Content -LiteralPath $Script:LOG -Value "Serial: $(if ($Script:Serial) { $Script:Serial } else { '(auto)' })" -Encoding UTF8
Add-Content -LiteralPath $Script:LOG -Value "PSScriptRoot: $PSScriptRoot" -Encoding UTF8

# ==============================================================================
# Tool detection + version check
# ==============================================================================
function Get-ExePath([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $local = Join-Path $PSScriptRoot "$name.exe"
    if (Test-Path -LiteralPath $local) { return $local }
    return $null
}

function Find-7Zip {
    $Script:SEVENZIP = $null
    $candidates = @(
        (Join-Path $PSScriptRoot '7z.exe'),
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
        (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')
    )
    foreach ($p in $candidates) {
        if (-not $p) { continue }
        if (Test-Path -LiteralPath $p) {
            $dll = Join-Path (Split-Path $p -Parent) '7z.dll'
            if (Test-Path -LiteralPath $dll) { $Script:SEVENZIP = $p; return $true }
        }
    }
    return $false
}

function Get-ToolVersion([string]$ExePath, [string]$Flag = '--version') {
    if (-not $ExePath) { return $null }
    try {
        $out = & $ExePath $Flag 2>&1 | Out-String
        $m = [regex]::Matches($out, '(?i)version\s+([0-9]+\.[0-9]+\.[0-9]+)')
        if ($m.Count -gt 0) { return $m[$m.Count - 1].Groups[1].Value }
        $m2 = [regex]::Matches($out, '([0-9]+\.[0-9]+\.[0-9]+)')
        if ($m2.Count -gt 0) { return $m2[0].Groups[1].Value }
    } catch { }
    return $null
}

function Get-7ZipVersion([string]$ExePath) {
    if (-not $ExePath) { return $null }
    try {
        $out = & $ExePath 2>&1 | Out-String
        $m = [regex]::Match($out, '(?i)7-Zip\s+([0-9]+\.[0-9]+)')
        if ($m.Success) { return $m.Groups[1].Value }
    } catch { }
    return $null
}

function Compare-ToolVersion([string]$Actual, [string]$Minimum) {
    if (-not $Actual) { return 0 }
    try {
        $a = $Actual
        $m = $Minimum
        while (($a -split '\.').Count -lt 3) { $a += '.0' }
        while (($m -split '\.').Count -lt 3) { $m += '.0' }
        return ([version]$a).CompareTo([version]$m)
    } catch { return 0 }
}

function Test-ToolVersions {
    Say (T 'ToolCheck') 'Cyan'
    Log "Tool version check (strict=$($Script:STRICT_VERSIONS))"
    $problems = 0

    # --- adb ---
    if (-not $Script:ADB_PATH) {
        Say "  adb      : $((T 'ToolMissing'))" 'Red'
        LogErr "adb not found"
        $problems++
    } else {
        $v = Get-ToolVersion $Script:ADB_PATH
        $Script:ADB_VER = $v
        if (-not $v) {
            Say "  adb      : $((T 'VersionUnknown'))  ($($Script:ADB_PATH))" 'Yellow'
            LogWarn "adb version unknown"
            $problems++
        } elseif ((Compare-ToolVersion $v '33.0.0') -lt 0) {
            Say ("  adb      : $v  " + ((T 'VersionTooOld') -f '33.0.0')) 'Yellow'
            LogWarn "adb version too old: $v (need >= 33.0.0)"
            $problems++
        } else {
            Say "  adb      : $v  ($($Script:ADB_PATH))" 'Green'
            Log "adb: $v"
        }
    }

    # --- fastboot ---
    if (-not $Script:FASTBOOT_PATH) {
        Say "  fastboot : $((T 'ToolMissing'))" 'Red'
        LogErr "fastboot not found"
        $problems++
    } else {
        $v = Get-ToolVersion $Script:FASTBOOT_PATH
        $Script:FASTBOOT_VER = $v
        if (-not $v) {
            Say "  fastboot : $((T 'VersionUnknown'))  ($($Script:FASTBOOT_PATH))" 'Yellow'
            LogWarn "fastboot version unknown"
            $problems++
        } elseif ((Compare-ToolVersion $v '33.0.0') -lt 0) {
            Say ("  fastboot : $v  " + ((T 'VersionTooOld') -f '33.0.0')) 'Yellow'
            LogWarn "fastboot version too old: $v (need >= 33.0.0)"
            $problems++
        } else {
            Say "  fastboot : $v  ($($Script:FASTBOOT_PATH))" 'Green'
            Log "fastboot: $v"
        }
    }

    # --- 7-Zip ---
    if ($Script:SEVENZIP) {
        $v = Get-7ZipVersion $Script:SEVENZIP
        $Script:SEVENZIP_VER = $v
        if (-not $v) {
            Say "  7-Zip    : $((T 'VersionUnknown'))  ($($Script:SEVENZIP))" 'Yellow'
            LogWarn "7-Zip version unknown"
            $problems++
        } elseif ((Compare-ToolVersion $v '22.00') -lt 0) {
            Say ("  7-Zip    : $v  " + ((T 'VersionTooOld') -f '22.00')) 'Yellow'
            LogWarn "7-Zip version too old: $v (need >= 22.00)"
            $problems++
        } else {
            Say "  7-Zip    : $v  ($($Script:SEVENZIP))" 'Green'
            Log "7-Zip: $v"
        }
    } else {
        Say "  7-Zip    : $((T 'ToolMissing'))" 'Yellow'
        LogWarn "7-Zip not found"
    }

    return $problems
}

# ==============================================================================
# Fastboot / ADB wrappers
# ==============================================================================
function Format-Args([string[]]$Args) {
    return ($Args | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
}

function Invoke-Fb {
    param(
        [int]$TimeoutSec = 30,
        [switch]$Tolerant,
        [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args
    )
    $cmdArgs = @()
    if ($Script:Serial) { $cmdArgs += @('-s', $Script:Serial) }
    $cmdArgs += $Args
    Log "fastboot $($Args -join ' ')"

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName               = $Script:FASTBOOT_PATH
    $proc.StartInfo.Arguments              = Format-Args $cmdArgs
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.RedirectStandardError  = $true
    $proc.StartInfo.UseShellExecute        = $false
    $proc.StartInfo.CreateNoWindow         = $true

    try { [void]$proc.Start() } catch {
        LogErr "Cannot start fastboot: $_"
        return $false
    }

    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch { }
        LogErr "fastboot TIMEOUT after ${TimeoutSec}s"
        return $false
    }

    try { [void]$outTask.Wait(2000) } catch { }
    try { [void]$errTask.Wait(2000) } catch { }

    $out = try { $outTask.Result } catch { '' }
    $err = try { $errTask.Result } catch { '' }
    $exitCode = $proc.ExitCode

    if ($out) { LogRaw "  fb stdout: $($out.Trim())" }
    if ($err) { LogRaw "  fb stderr: $($err.Trim())" }
    if ($exitCode -ne 0) {
        if ($Tolerant) { Log "fastboot exit=$exitCode (tolerated)"; return $true }
        LogWarn "fastboot exit code: $exitCode"
        return $false
    }
    return $true
}

function Invoke-Adb {
    param(
        [int]$TimeoutSec = 30,
        [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args
    )
    $cmdArgs = @()
    if ($Script:Serial) { $cmdArgs += @('-s', $Script:Serial) }
    $cmdArgs += $Args
    Log "adb $($Args -join ' ')"

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName               = $Script:ADB_PATH
    $proc.StartInfo.Arguments              = Format-Args $cmdArgs
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.RedirectStandardError  = $true
    $proc.StartInfo.UseShellExecute        = $false
    $proc.StartInfo.CreateNoWindow         = $true

    try { [void]$proc.Start() } catch {
        LogErr "Cannot start adb: $_"
        return $false
    }

    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch { }
        LogErr "adb TIMEOUT after ${TimeoutSec}s"
        return $false
    }

    try { [void]$outTask.Wait(2000) } catch { }
    try { [void]$errTask.Wait(2000) } catch { }

    $out = try { $outTask.Result } catch { '' }
    $err = try { $errTask.Result } catch { '' }
    $exitCode = $proc.ExitCode

    if ($out) { LogRaw "  adb stdout: $($out.Trim())" }
    if ($err) { LogRaw "  adb stderr: $($err.Trim())" }
    if ($exitCode -ne 0) { LogWarn "adb exit code: $exitCode"; return $false }
    return $true
}

function Invoke-FbFlash {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    if (-not (Invoke-Fb -TimeoutSec $Script:FLASH_TIMEOUT @Args)) {
        LogErr "fb_flash FAILED: fastboot $($Args -join ' ')"
        Say (T 'Error') 'Red'
        Say "  fastboot $($Args -join ' ') FAILED. See log: $($Script:LOG)" 'Red'
        Say '  DO NOT REBOOT the device.' 'Red'
        return $false
    }
    Log "fb_flash OK: fastboot $($Args -join ' ')"
    return $true
}

function Get-AdbDevices {
    $cmdArgs = @()
    if ($Script:Serial) { $cmdArgs += @('-s', $Script:Serial) }
    $cmdArgs += 'devices'
    return (& $Script:ADB_PATH @cmdArgs 2>$null)
}

function Get-FastbootDevices {
    $cmdArgs = @()
    if ($Script:Serial) { $cmdArgs += @('-s', $Script:Serial) }
    $cmdArgs += 'devices'
    return (& $Script:FASTBOOT_PATH @cmdArgs 2>$null)
}

function Wait-Adb {
    param([int]$Timeout = $Script:WAIT_ADB)
    Write-Host -NoNewline (T 'WaitAdb')
    for ($i = 0; $i -lt $Timeout; $i++) {
        $devs = Get-AdbDevices | Select-Object -Skip 1 | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\s(device|recovery)$' }
        if ($devs) {
            Say " $((T 'Ok'))" 'Green'
            Log "ADB found: $($devs -join ', ')"
            return $true
        }
        Write-Host -NoNewline '.'
        Start-Sleep -Seconds 1
    }
    Say " $((T 'Timeout'))" 'Red'
    LogErr "Wait-Adb TIMEOUT ($Timeout s)"
    return $false
}

function Wait-Fastboot {
    param([int]$Timeout = $Script:WAIT_FASTBOOT)
    Write-Host -NoNewline (T 'WaitFastboot')
    for ($i = 0; $i -lt $Timeout; $i++) {
        $devs = Get-FastbootDevices | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\sfastboot$' }
        if ($devs) {
            Say " $((T 'Ok'))" 'Green'
            Log "Fastboot found: $($devs -join ', ')"
            return $true
        }
        Write-Host -NoNewline '.'
        Start-Sleep -Seconds 1
    }
    Say " $((T 'Timeout'))" 'Red'
    LogErr "Wait-Fastboot TIMEOUT ($Timeout s)"
    return $false
}

function Get-FastbootVar([string]$name) {
    $cmdArgs = @()
    if ($Script:Serial) { $cmdArgs += @('-s', $Script:Serial) }
    $cmdArgs += @('getvar', $name)
    $out = & $Script:FASTBOOT_PATH @cmdArgs 2>&1 | Out-String
    if ($out -match "$name\s*:\s*([^\s\r\n]+)") { return $Matches[1].Trim() }
    return $null
}

function Get-CurrentSlot {
    $v = Get-FastbootVar 'current-slot'
    Log "current-slot = $v"
    if ($v -match '^[ab]') { return $v.Substring(0,1) }
    LogWarn "current-slot not detected, fallback 'a'"
    return 'a'
}

function Get-SlotCount {
    $v = Get-FastbootVar 'slot-count'
    Log "slot-count = $v"
    if ($v) { return [int]$v }
    return 2
}

function Test-Userspace {
    $v = Get-FastbootVar 'is-userspace'
    Log "is-userspace = $v"
    return ($v -eq 'yes')
}

function Test-BootloaderUnlocked {
    Say (T 'CheckingBl') 'Cyan'
    $u = Get-FastbootVar 'unlocked'
    $s = Get-FastbootVar 'secure'
    $a = Get-FastbootVar 'get_unlock_ability'
    Log "Bootloader: unlocked=$u secure=$s get_unlock_ability=$a"
    if ($u -eq 'yes') { Say "  $((T 'BlUnlocked'))" 'Green'; Log "Bootloader UNLOCKED (unlocked=yes)"; return $true }
    if ($s -eq 'no')  { Say "  $((T 'BlUnlocked'))" 'Green'; Log "Bootloader UNLOCKED (secure=no)"; return $true }
    if ($a -eq '0')   { Say "  $((T 'BlOemDisabled'))" 'Red'; LogErr "OEM Unlock disabled"; return $false }
    Say "  $((T 'BlLocked'))" 'Red'
    LogErr "Bootloader LOCKED"
    return $false
}

function Get-SysPart([string]$slot) {
    if ($Script:IS_AB) { return "system_$slot" } else { return 'system' }
}

# ==============================================================================
# Image helpers
# ==============================================================================
function Get-ImageSize([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        $fs = [IO.File]::OpenRead($Path)
        try {
            $magic = New-Object byte[] 4
            [void]$fs.Read($magic, 0, 4)
            $m = [BitConverter]::ToString($magic).Replace('-','').ToLower()
            if ($m -eq '3aff26ed') {
                $fs.Position = 0
                $h = New-Object byte[] 28
                [void]$fs.Read($h, 0, 28)
                $bs = [BitConverter]::ToUInt32($h, 12)
                $tb = [BitConverter]::ToUInt32($h, 16)
                return [UInt64]$bs * [UInt64]$tb
            }
            return (Get-Item -LiteralPath $Path).Length
        } finally { $fs.Close(); $fs.Dispose() }
    } catch { LogErr "Get-ImageSize: $_"; return 0 }
}

function Test-SparseIntegrity([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 'missing' }
    try {
        $fs = [IO.File]::OpenRead($Path)
        try {
            $magic = New-Object byte[] 4
            [void]$fs.Read($magic, 0, 4)
            $m = [BitConverter]::ToString($magic).Replace('-','').ToLower()
            if ($m -ne '3aff26ed') { return 'raw' }
            $fs.Position = 0
            $h = New-Object byte[] 28
            [void]$fs.Read($h, 0, 28)
            $bs = [BitConverter]::ToUInt32($h, 12)
            $tb = [BitConverter]::ToUInt32($h, 16)
            $expected = [UInt64]$bs * [UInt64]$tb
            $actual = (Get-Item -LiteralPath $Path).Length
            $min = [UInt64]($expected / 4)
            if ($actual -lt $min) { return "suspect:${actual}:${expected}" }
            return 'ok'
        } finally { $fs.Close(); $fs.Dispose() }
    } catch { LogErr "Test-SparseIntegrity: $_"; return 'error' }
}

function Get-PartitionSize([UInt64]$RawBytes) {
    if ($RawBytes -eq 0) { return 0 }
    $align = [UInt64]4096
    $margin = [UInt64]$Script:MARGIN_MB * 1MB
    $rem = [UInt64]0
    $div = [Math]::DivRem($RawBytes, $align, [ref]$rem)
    $aligned = [UInt64]$div * $align
    if ($rem -gt 0) { $aligned += $align }
    return [UInt64]$aligned + $margin
}

function Invoke-VerifySha256([string]$Path, [string]$Hash) {
    $hashSrc = if ($Hash -eq 'file') { 'file' } elseif ($Hash) { 'inline' } else { 'none' }
    Log "Verify SHA256: Path=$Path HashSource=$hashSrc"
    if (-not (Test-Path -LiteralPath $Path)) { LogErr "Image not found: $Path"; return 'missing_img' }
    $want = $null
    if ($Hash -and $Hash.Trim() -match '(?i)\b([a-f0-9]{64})\b') {
        $want = $Matches[1].ToLower()
    } else {
        $shaFile = "${Path}.sha256"
        if (Test-Path -LiteralPath $shaFile) {
            if ((Get-Item -LiteralPath $shaFile).Length -gt 4096) { LogWarn '.sha256 file too large'; return 'error_file_too_large' }
            try {
                $c = [IO.File]::ReadAllText($shaFile).Trim()
                if ($c -match '(?i)\b([a-f0-9]{64})\b') { $want = $Matches[1].ToLower() }
            } catch { LogWarn "Cannot read .sha256: $_" }
        }
    }
    if (-not $want) { LogWarn 'No SHA256 hash available'; return 'missing' }
    try {
        $stream = [IO.File]::OpenRead($Path)
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $bytes = $sha.ComputeHash($stream)
                $got = [BitConverter]::ToString($bytes).Replace('-','').ToLower()
            } finally { $sha.Dispose() }
        } finally { $stream.Close(); $stream.Dispose() }
        if ($got -eq $want) { Log "SHA256 OK ($got)"; return 'ok' }
        LogErr "SHA256 mismatch: want=$want got=$got"
        return "mismatch:$got"
    } catch { LogErr "SHA256 compute error: $_"; return 'error' }
}

# ==============================================================================
# Select images
# ==============================================================================
function Select-SystemImage {
    $excludePatterns = @('vbmeta','^boot','vendor','recovery','super','dtbo','userdata','metadata','system_dlkm')
    $all = @()
    foreach ($ext in @('*.img','*.img.xz','*.img.gz','*.img.zst')) {
        $all += @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $ext -File -ErrorAction SilentlyContinue)
    }
    $sys = @()
    foreach ($f in $all) {
        $skip = $false
        foreach ($p in $excludePatterns) {
            if ($f.Name -match $p) { $skip = $true; break }
        }
        if (-not $skip) { $sys += $f }
    }
    Log "Select-SystemImage: found $($sys.Count) candidate(s)"
    foreach ($f in $sys) { Log "  candidate: $($f.Name)" }
    if ($sys.Count -eq 0) { LogWarn 'No system images found'; Say (T 'NoSystemImg') 'Red'; return $null }

    $sizeWarn = $false
    foreach ($f in $sys) {
        $sizeMB = [Math]::Round($f.Length / 1MB)
        if ($sizeMB -lt 100) {
            LogWarn "Suspicious small image: $($f.Name) ($sizeMB MB)"
            $sizeWarn = $true
        } elseif ($sizeMB -lt 300) {
            LogWarn "Unusually small image: $($f.Name) ($sizeMB MB)"
        }
    }
    if ($sizeWarn) {
        Say (T 'ImgSuspect1') 'Yellow'
        Say (T 'ImgSuspect2') 'Yellow'
        Say (T 'ImgSuspect3') 'Yellow'
        if (-not (Confirm (T 'ContinueAnyway'))) { Log 'Aborted due to size check'; return $null }
    }

    if ($sys.Count -eq 1) {
        Log "Auto-selected: $($sys[0].Name)"
        Say "$(T 'FoundImg'): $($sys[0].Name)" 'Green'
        return $sys[0].FullName
    }
    Say (T 'ChooseImg') 'Cyan'
    for ($i = 0; $i -lt $sys.Count; $i++) {
        $sizeMB = [Math]::Round($sys[$i].Length / 1MB)
        $mark = " [$sizeMB MB]"
        if ($sizeMB -lt 100) { $mark = " [$sizeMB MB] SUSPICIOUS" }
        elseif ($sizeMB -lt 300) { $mark = " [$sizeMB MB] small" }
        Write-Host ("   {0}) {1}{2}" -f ($i+1), $sys[$i].Name, $mark)
    }
    while ($true) {
        $r = Read-Host -Prompt (T 'Input')
        if ($r -eq '0') { Log 'Image selection cancelled'; Say (T 'Cancel') 'Yellow'; return $null }
        $n = 0
        if ([int]::TryParse($r, [ref]$n) -and $n -ge 1 -and $n -le $sys.Count) {
            Log "User selected image: $($sys[$n-1].Name)"
            return $sys[$n-1].FullName
        }
        Say (T 'InvalidChoice') 'Yellow'
    }
}

function Select-BootImage {
    param([string]$Mask, [string]$Prompt)
    $files = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter $Mask -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { LogErr "No files matching $Mask"; Say "No files matching $Mask" 'Red'; return $null }
    if ($files.Count -eq 1) { Log "Auto-selected: $($files[0].Name)"; Say "Found: $($files[0].Name)" 'Green'; return $files[0].FullName }
    Say $Prompt 'Cyan'
    for ($i = 0; $i -lt $files.Count; $i++) { Write-Host ("   {0}) {1}" -f ($i+1), $files[$i].Name) }
    while ($true) {
        $r = Read-Host -Prompt (T 'Input')
        if ($r -eq '0') { return $null }
        $n = 0
        if ([int]::TryParse($r, [ref]$n) -and $n -ge 1 -and $n -le $files.Count) {
            Log "User selected: $($files[$n-1].Name)"
            return $files[$n-1].FullName
        }
        Say (T 'InvalidChoice') 'Yellow'
    }
}

function Resolve-SystemImage([string]$Path) {
    $lower = $Path.ToLower()
    foreach ($spec in @(
        @{ Ext = '\.img\.xz$';  Suffix = 3; Kind = '.xz';  Name = 'xz' },
        @{ Ext = '\.img\.gz$';  Suffix = 3; Kind = '.gz';  Name = 'gz' },
        @{ Ext = '\.img\.zst$'; Suffix = 4; Kind = '.zst'; Name = 'zst' }
    )) {
        if ($lower -match $spec.Ext) {
            if (-not $Script:SEVENZIP) {
                LogErr (T 'Need7Zip' -f $spec.Kind)
                Say ((T 'Need7Zip') -f $spec.Kind) 'Red'
                return $null
            }
            $out = $Path.Substring(0, $Path.Length - $spec.Suffix)
            if (-not (Test-Path -LiteralPath $out)) {
                Log "Unpacking $($spec.Kind): $Path -> $out"
                Say ((T 'Unpacking') -f $Path, $out) 'Cyan'
                & $Script:SEVENZIP x -y -bso0 -bsp1 $Path > $null
                if ($LASTEXITCODE -ne 0) {
                    LogErr ((T 'UnpackFailed') -f $spec.Kind)
                    Say ((T 'UnpackFailed') -f $spec.Kind) 'Red'
                    return $null
                }
            }
            return $out
        }
    }
    return $Path
}

# ==============================================================================
# Super reconstruction
# ==============================================================================
function Invoke-FreeSuperSpace {
    param([string]$Slot, [string]$SystemImg)
    Log "=== Invoke-FreeSuperSpace slot=$Slot img=$SystemImg ==="
    if (-not $Slot) { $Slot = $Script:CURRENT_SLOT }
    if (-not $SystemImg -or -not (Test-Path -LiteralPath $SystemImg)) {
        LogErr 'SYSTEM_IMG not set or missing'
        Say 'SYSTEM_IMG not set or missing' 'Red'; return $false
    }
    $integrity = Test-SparseIntegrity $SystemImg
    Log "Sparse integrity: $integrity"
    if ($integrity -match '^suspect:') {
        Say "Sparse image looks suspicious: $integrity" 'Yellow'
        if (-not (Confirm (T 'ContinueAnyway'))) { return $false }
    } elseif ($integrity -eq 'error') {
        Say 'Sparse integrity check error' 'Yellow'
    }
    $rawSize = Get-ImageSize $SystemImg
    if ($rawSize -le 0) { LogErr 'Cannot detect image size'; Say 'Cannot detect image size' 'Red'; return $false }
    $partSize = Get-PartitionSize $rawSize
    Log "raw=$rawSize part=$partSize (margin=$($Script:MARGIN_MB)MB)"
    Say ("raw=$rawSize, part=$partSize (margin=$($Script:MARGIN_MB)MB)") 'Gray'

    Say '--------------------------------------------------------' 'Cyan'
    Say (T 'ShaHeader') 'Cyan'
    $userHash = ''
    if (Test-Path -LiteralPath "${SystemImg}.sha256") {
        Log 'Found .sha256 file'
        Say (T 'ShaFileFound') 'Green'
        $userHash = 'file'
    } else {
        Say (T 'ShaPrompt') 'Gray'
        $userHash = Read-Host -Prompt (T 'ShaPromptShort')
        Log "SHA256 input: $(if ($userHash) { 'provided' } else { 'skipped' })"
    }
    if ($userHash) {
        $res = Invoke-VerifySha256 $SystemImg $userHash
        if ($res -match '^mismatch:') {
            LogErr "SHA256 mismatch: $res"
            Say (T 'Error') 'Red'
            Say ((T 'ShaMismatch') -f $res) 'Red'
            if (-not (Confirm (T 'ShaRiskPrompt'))) { return $false }
        } elseif ($res -eq 'ok') { Say (T 'ShaOk') 'Green' }
        elseif ($res -eq 'missing') { Say (T 'ShaSkipNoHash') 'Yellow' }
        elseif ($res -eq 'error_file_too_large') { Say (T 'ShaSkipTooBig') 'Yellow' }
        elseif ($res -eq 'error') { Say (T 'ShaSkipErr') 'Yellow' }
    } else { Say (T 'ShaSkipUser') 'Yellow' }
    Say '--------------------------------------------------------' 'Cyan'

    $tpart = Get-SysPart $Slot
    $opp = if ($Slot -eq 'a') { 'b' } else { 'a' }

    if (-not (Test-Userspace)) {
        Say (T 'RebootToFb') 'Cyan'
        Log (T 'NotInFbReboot')
        [void](Invoke-Fb -Tolerant 'reboot' 'fastboot')
        if (-not (Wait-Fastboot)) { return $false }
    }

    Say '--------------------------------------------------------' 'Cyan'
    Say (T 'RebuildSuper') 'Cyan'
    Say ((T 'TargetPart') -f $tpart) 'Gray'
    Say ((T 'NewSize') -f $partSize) 'Gray'
    Say (T 'NotTouching') 'Gray'
    Say '--------------------------------------------------------' 'Cyan'
    if (-not (Confirm)) { Log 'Rebuild cancelled by user'; return $false }

    if ($partSize -gt 4GB) {
        Say (T 'SuperBigWarn') 'Yellow'
        if (-not (Confirm)) { return $false }
    }

    Log "Deleting logical partitions (system/product/system_ext) in slots $Slot/$opp"
    if ($Script:IS_AB) {
        foreach ($s in @($Slot, $opp)) {
            foreach ($p in @('system','product','system_ext')) {
                [void](Invoke-Fb 'delete-logical-partition' "${p}_${s}")
            }
        }
    } else {
        foreach ($p in @('system','product','system_ext')) {
            [void](Invoke-Fb 'delete-logical-partition' $p)
        }
    }

    Log "Creating $tpart size=$partSize"
    Say "Creating $tpart ($partSize bytes)..." 'Cyan'
    if (-not (Invoke-Fb 'create-logical-partition' $tpart "$partSize")) {
        LogErr "create-logical-partition failed"
        Say (T 'CreateFailed') 'Red'
        Say (T 'CreateFailed2') 'Red'
        return $false
    }
    Log "Partition $tpart recreated: $partSize bytes"
    return $true
}

# ==============================================================================
# vbmeta
# ==============================================================================
function Confirm-Vbmeta {
    $vb = Join-Path $PSScriptRoot 'vbmeta.img'
    if (-not (Test-Path -LiteralPath $vb)) {
        LogWarn 'vbmeta.img not found, asking user'
        Say (T 'VbMissing') 'Yellow'
        return (Confirm (T 'VbContinueNo'))
    }
    if (Test-Userspace) {
        LogWarn 'In Fastbootd, vbmeta is a physical partition'
        Say (T 'VbInUserspace') 'Yellow'
    }
    Log "Flashing vbmeta: $vb"
    Say (T 'VbFlashing') 'Cyan'
    if (-not (Invoke-FbFlash '--disable-verity' '--disable-verification' 'flash' 'vbmeta' $vb)) {
        return (Confirm (T 'VbContinueNo'))
    }
    Log 'vbmeta flashed OK'
    return $true
}

# ==============================================================================
# Backup /data via ADB stream
# ==============================================================================
function Backup-DataStream {
    Clear-Host
    Log "=== Backup-DataStream ==="
    Say (T 'BackupTitle') 'Cyan'

    if (-not $Script:SEVENZIP) {
        Say (T 'BackupNo7Zip') 'Red'
        LogErr 'Backup requires 7-Zip'
        Pause; return
    }
    if (-not (Wait-Adb)) { Pause; return }

    Say (T 'BackupWarning') 'Yellow'
    Say (T 'BackupCriticalWarn') 'Yellow'
    Say (T 'BackupCriticalHint') 'Yellow'

    # --- mount check ---
    Log "Mount check: /data"
    $mountArgs = @()
    if ($Script:Serial) { $mountArgs += @('-s', $Script:Serial) }
    $mountArgs += @('shell', "mount | grep -E '/data|f2fs|ext4' || true")
    try {
        $mountOut = & $Script:ADB_PATH @mountArgs 2>&1 | Out-String
        if ($mountOut) { LogRaw "mount: $($mountOut.Trim())" }
    } catch { LogWarn "mount check failed: $_" }
    Say (T 'BackupMountOk') 'Gray'
    if (-not (Confirm (T 'BackupMountAsk'))) { Log 'Backup cancelled at mount prompt'; return }

    # --- excludes support probe ---
    $excludes = '--exclude=media --exclude=dalvik-cache --exclude=tombstones --exclude=dropbox'
    $probeArgs = @()
    if ($Script:Serial) { $probeArgs += @('-s', $Script:Serial) }
    $probeArgs += @('shell', "echo ADB_OK; tar $excludes -cf /dev/null -C /data . 2>/dev/null; echo RC=\$?")
    $probeOut = ''
    try { $probeOut = & $Script:ADB_PATH @probeArgs 2>&1 | Out-String } catch { }
    if ($probeOut -notmatch 'ADB_OK') {
        LogErr "adb shell probe failed (adb lost connection?)"
        Say ((T 'BackupFailed') -f $Script:LOG) 'Red'
        Pause; return
    }
    $useExcludes = ($probeOut -match 'RC=0\s*$')
    if (-not $useExcludes) {
        LogWarn 'tar --exclude not supported, doing full backup'
        Say (T 'BackupNoExcl') 'Yellow'
        $excludes = ''
    }

    # --- output path ---
    $backupDir = Join-Path $PSScriptRoot ("backups\data_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $outFile = Join-Path $backupDir 'userdata_backup.tar.7z'
    Log "Backup target: $outFile"

    $remoteTar = "tar -c -C /data $excludes ."

    # --- start adb exec-out tar ---
    $adbArgs = @()
    if ($Script:Serial) { $adbArgs += @('-s', $Script:Serial) }
    $adbArgs += @('exec-out', $remoteTar)

    $adbProc = New-Object System.Diagnostics.Process
    $adbProc.StartInfo.FileName               = $Script:ADB_PATH
    $adbProc.StartInfo.Arguments              = Format-Args $adbArgs
    $adbProc.StartInfo.RedirectStandardOutput = $true
    $adbProc.StartInfo.RedirectStandardError  = $false
    $adbProc.StartInfo.UseShellExecute        = $false
    $adbProc.StartInfo.CreateNoWindow         = $true

    # --- start 7z (stream writer) ---
    $szProc = New-Object System.Diagnostics.Process
    $szProc.StartInfo.FileName               = $Script:SEVENZIP
    $szProc.StartInfo.Arguments              = "a -sidata.tar -t7z -mx=9 -bso0 -bsp0 `"$outFile`""
    $szProc.StartInfo.RedirectStandardInput  = $true
    $szProc.StartInfo.RedirectStandardOutput = $false
    $szProc.StartInfo.RedirectStandardError  = $false
    $szProc.StartInfo.UseShellExecute        = $false
    $szProc.StartInfo.CreateNoWindow         = $true

    $started = $false
    try {
        Log "Starting adb exec-out tar"
        [void]$adbProc.Start()
        Log "Starting 7z (writer)"
        [void]$szProc.Start()
        $started = $true

        $buffer      = New-Object byte[] 65536
        $totalBytes  = [UInt64]0
        $lastUpdate  = [DateTime]::UtcNow
        $sw          = [System.Diagnostics.Stopwatch]::StartNew()

        while (($read = $adbProc.StandardOutput.BaseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $szProc.StandardInput.BaseStream.Write($buffer, 0, $read)
            $totalBytes += $read
            if (([DateTime]::UtcNow - $lastUpdate).TotalMilliseconds -ge 500) {
                $mb    = [Math]::Round($totalBytes / 1MB, 1)
                $speed = if ($sw.Elapsed.TotalSeconds -gt 0) { [Math]::Round($totalBytes / 1MB / $sw.Elapsed.TotalSeconds, 1) } else { 0 }
                Write-Progress -Activity (T 'BackupProgress') `
                               -Status   ((T 'BackupStatusFmt') -f $mb, $speed) `
                               -PercentComplete -1
                $lastUpdate = [DateTime]::UtcNow
            }
        }
        Log "adb stdout EOF, total=$totalBytes bytes"

        $szProc.StandardInput.BaseStream.Flush()
        $szProc.StandardInput.Close()
        $adbProc.WaitForExit()
        $szProc.WaitForExit()
        Write-Progress -Activity (T 'BackupProgress') -Completed

        $adbRc = $adbProc.ExitCode
        $szRc  = $szProc.ExitCode
        Log "adb exit=$adbRc  7z exit=$szRc"
        if ($adbRc -ne 0) { LogWarn "adb exec-out tar exit code: $adbRc" }
        if ($szRc -ne 0) {
            LogErr "7z exit code: $szRc"
            Say ((T 'BackupFailed') -f $Script:LOG) 'Red'
            Pause; return
        }

        if (Test-Path -LiteralPath $outFile) {
            $sz = (Get-Item -LiteralPath $outFile).Length
            $mb = [Math]::Round($sz / 1MB, 1)
            Say ((T 'BackupDone') -f $outFile, $mb) 'Green'
            Log "Backup OK: $outFile ($sz bytes)"
        }
        Pause
    } catch {
        LogErr "Backup exception: $_"
        Say ((T 'BackupFailed') -f $Script:LOG) 'Red'
        Write-Progress -Activity (T 'BackupProgress') -Completed
        if ($started) {
            try { if (-not $adbProc.HasExited) { $adbProc.Kill() } } catch { }
            try { if (-not $szProc.HasExited)  { $szProc.Kill()  } } catch { }
        }
        Pause
    }
}

# ==============================================================================
# GKI / Emergency
# ==============================================================================
function Install-GkiKernels {
    Clear-Host
    Log "=== Install-GkiKernels ==="
    $boot = Select-BootImage -Mask 'boot*.img' -Prompt (T 'SelectBoot')
    if (-not $boot) { return }
    $vb = Select-BootImage -Mask 'vendor_boot*.img' -Prompt (T 'SelectVendor')
    if (-not $vb) { return }
    Log "boot=$boot vendor_boot=$vb"

    if (-not (Wait-Adb)) { Pause; return }
    [void](Invoke-Adb 'reboot' 'bootloader')
    if (-not (Wait-Fastboot)) { Pause; return }
    if (-not (Test-BootloaderUnlocked)) { Pause; return }

    $slot = Get-CurrentSlot
    if (Confirm ((T 'FlashToSlot') -f $slot)) {
        if (-not (Invoke-FbFlash 'flash' "boot_$slot" $boot)) { Pause; return }
        if (-not (Invoke-FbFlash 'flash' "vendor_boot_$slot" $vb)) { Pause; return }
        [void](Invoke-Fb 'erase' 'cache')
        Log "GKI kernels flashed OK"
    }
    Pause
}

function Restore-EmergencySlots {
    Clear-Host
    Log "=== Restore-EmergencySlots ==="
    $b = Select-BootImage -Mask 'boot*.img' -Prompt (T 'SelectStableBoot')
    if (-not $b) { return }
    $v = Select-BootImage -Mask 'vendor_boot*.img' -Prompt (T 'SelectStableVb')
    if (-not $v) { return }
    Log "boot=$b vendor_boot=$v"

    if (-not (Wait-Fastboot)) { Pause; return }
    if (-not (Test-BootloaderUnlocked)) { Pause; return }

    Log "Writing to both slots"
    if (-not (Invoke-FbFlash 'flash' 'boot_a'        $b)) { Pause; return }
    if (-not (Invoke-FbFlash 'flash' 'vendor_boot_a' $v)) { Pause; return }
    if (-not (Invoke-FbFlash 'flash' 'boot_b'        $b)) { Pause; return }
    if (-not (Invoke-FbFlash 'flash' 'vendor_boot_b' $v)) { Pause; return }
    [void](Invoke-Fb 'set_active' 'a')
    Log "Dual-slot restore OK"
    [void](Invoke-Fb 'reboot')
    Pause
    exit 0
}

# ==============================================================================
# MENUS
# ==============================================================================
function Show-MainMenu {
    Clear-Host
    Say "$(T 'MainMenuTitle') $($Script:FULL_VERSION) (PowerShell)" 'Cyan'
    Say "$(T 'LogFile'): $($Script:LOG)" 'Gray'
    Say '========================================================' 'Cyan'
    Say "  1. $(T 'MenuCheckDev')"
    Say "  2. $(T 'MenuFromAndroid')"
    Say "  3. $(T 'MenuFromRecovery')"
    Say "  4. $(T 'MenuFromBoot')"
    Say "  5. $(T 'MenuAlreadyFb')"
    Say "  6. $(T 'ServiceMenu')"
    Say "  0. $(T 'Exit')"
    Say '========================================================' 'Cyan'
    $choice = Read-Host -Prompt (T 'Input')
    Log "Main menu: choice=$choice"
    return $choice
}

function Show-ActionMenu {
    Clear-Host
    Say ((T 'ActiveSlotLine') -f $Script:CURRENT_SLOT, $Script:IS_AB) 'Cyan'
    Say '========================================================' 'Cyan'
    Say "  1. $(T 'ActionUpdate')"
    Say "  2. $(T 'ActionReset')"
    Say "  3. $(T 'ActionSlot')"
    Say "  4. $(T 'ActionSwitch')"
    Say "  5. $(T 'ActionDirty')"
    Say "  0. $(T 'Back')"
    Say '========================================================' 'Cyan'
    $choice = Read-Host -Prompt (T 'Input')
    Log "Action menu: choice=$choice"
    return $choice
}

function Show-ServiceMenu {
    Clear-Host
    Say "==== $(T 'ServiceMenu') ====" 'Cyan'
    Say "  1. $(T 'Backing')"
    Say "  2. $(T 'FlashingGki')"
    Say "  3. $(T 'EmergencyFix')"
    Say "  0. $(T 'Back')"
    $choice = Read-Host -Prompt (T 'Input')
    Log "Service menu: choice=$choice"
    return $choice
}

# ==============================================================================
# Do-Flash
# ==============================================================================
function Do-Flash {
    param([string]$Mode)
    Log "=== Do-Flash mode=$Mode ==="
    $img = Select-SystemImage
    if (-not $img) { return }
    $resolved = Resolve-SystemImage $img
    if (-not $resolved) { LogErr "Resolve-SystemImage failed for $img"; return }
    $img = $resolved

    if ($Mode -eq 'slot') {
        $slot = Read-Host -Prompt (T 'EnterSlot')
        if ($slot -notmatch '^[ab]$') { $slot = $Script:CURRENT_SLOT }
        Log "Target slot: $slot"
        if (-not (Confirm-Vbmeta)) { return }
        if (-not (Invoke-FreeSuperSpace -Slot $slot -SystemImg $img)) { return }
        if (-not (Invoke-FbFlash 'flash' (Get-SysPart $slot) $img)) { return }
        [void](Invoke-Fb 'erase' 'cache')
        [void](Invoke-Fb 'set_active' $slot)
        [void](Invoke-Fb 'reboot')
        Log "Flash OK (slot mode). Exiting."
        Say (T 'FlashOk') 'Green'
        Pause
        exit 0
    }
    if ($Mode -eq 'update') {
        if (-not (Confirm-Vbmeta)) { return }
        if (-not (Invoke-FreeSuperSpace -Slot $Script:CURRENT_SLOT -SystemImg $img)) { return }
        if (-not (Invoke-FbFlash 'flash' (Get-SysPart $Script:CURRENT_SLOT) $img)) { return }
        [void](Invoke-Fb 'erase' 'cache')
        [void](Invoke-Fb 'reboot')
        Log "Flash OK (update mode). Exiting."
        Say (T 'FlashOk') 'Green'
        Pause
        exit 0
    }
    if ($Mode -eq 'reset') {
        if (-not (Confirm-Vbmeta)) { return }
        if (-not (Invoke-FreeSuperSpace -Slot $Script:CURRENT_SLOT -SystemImg $img)) { return }
        [void](Invoke-Fb '-w')
        if (-not (Invoke-FbFlash 'flash' (Get-SysPart $Script:CURRENT_SLOT) $img)) { return }
        [void](Invoke-Fb 'reboot')
        Log "Flash OK (reset mode). Exiting."
        Say (T 'FlashOk') 'Green'
        Pause
        exit 0
    }
    if ($Mode -eq 'dirty') {
        if (-not (Test-BootloaderUnlocked)) { return }
        if (-not (Invoke-FbFlash 'flash' (Get-SysPart $Script:CURRENT_SLOT) $img)) { return }
        [void](Invoke-Fb 'reboot')
        Log "Flash OK (dirty mode). Exiting."
        Say (T 'FlashOk') 'Green'
        Pause
        exit 0
    }
}

# ==============================================================================
# MAIN FLOW
# ==============================================================================
$Script:ADB_PATH      = Get-ExePath 'adb'
$Script:FASTBOOT_PATH = Get-ExePath 'fastboot'

Find-7Zip | Out-Null
$problems = Test-ToolVersions
if ($problems -gt 0) {
    if ($Script:STRICT_VERSIONS) {
        Say (T 'StrictFail') 'Red'
        LogErr "Strict version check failed ($problems problem(s)); aborting"
        exit 1
    }
    Say (T 'ToolsWarn') 'Yellow'
    if (-not (Confirm)) { exit 1 }
}

while ($true) {
    $Script:Proceed = $false
    while (-not $Script:Proceed) {
        $c = Show-MainMenu
        switch ($c) {
            '0' { Log 'Exit from main menu'; exit 0 }
            '6' {
                while ($true) {
                    $s = Show-ServiceMenu
                    if ($s -eq '0') { break }
                    switch ($s) {
                        '1' { Backup-DataStream }
                        '2' { Install-GkiKernels }
                        '3' { Restore-EmergencySlots }
                        default { Log "Unknown service choice: $s" }
                    }
                }
            }
            '5' { if (Wait-Fastboot) { $Script:Proceed = $true } }
            '4' { if (Wait-Fastboot) { [void](Invoke-Fb -Tolerant 'reboot' 'fastboot'); if (Wait-Fastboot) { $Script:Proceed = $true } } }
            '3' { if (Wait-Adb)   { [void](Invoke-Adb 'reboot' 'fastboot'); if (Wait-Fastboot) { $Script:Proceed = $true } } }
            '2' { if (Wait-Adb)   { [void](Invoke-Adb 'reboot' 'fastboot'); if (Wait-Fastboot) { $Script:Proceed = $true } } }
            '1' {
                Log "Devices: adb / fastboot"
                Say '-- ADB --' 'Cyan'
                & $Script:ADB_PATH devices
                Say '-- Fastboot --' 'Cyan'
                & $Script:FASTBOOT_PATH devices
            }
            default { }
        }
        if (-not $Script:Proceed) { Pause }
    }

    if (-not (Test-BootloaderUnlocked)) { Pause; continue }
    if ((Get-SlotCount) -eq 1) { $Script:IS_AB = $false } else { $Script:IS_AB = $true }
    $Script:CURRENT_SLOT = Get-CurrentSlot
    Log "A/B=$($Script:IS_AB) CURRENT_SLOT=$($Script:CURRENT_SLOT)"

    $Script:BackToMain = $false
    while (-not $Script:BackToMain) {
        $a = Show-ActionMenu
        switch ($a) {
            '0' { Log 'Back to main menu'; $Script:BackToMain = $true }
            '4' {
                if (-not $Script:IS_AB) { Say (T 'NotAb') 'Yellow'; Pause; continue }
                $newSlot = if ($Script:CURRENT_SLOT -eq 'a') { 'b' } else { 'a' }
                if (Test-Userspace) {
                    LogWarn "set_active in fastbootd: may fail on MTK"
                    Say (T 'SetActiveWarn') 'Yellow'
                    if (-not (Confirm (T 'SetActiveTry'))) { continue }
                }
                if (Invoke-Fb 'set_active' $newSlot) {
                    $Script:CURRENT_SLOT = $newSlot
                    Log "Switched active slot to $($Script:CURRENT_SLOT)"
                    Say ((T 'CurrentSlotMsg') -f $Script:CURRENT_SLOT) 'Green'
                } else {
                    LogErr "set_active $newSlot FAILED"
                    Say (T 'SetActiveFail') 'Red'
                }
                Pause
            }
            '1' { Do-Flash 'update' }
            '2' { Do-Flash 'reset' }
            '3' { Do-Flash 'slot' }
            '5' { Do-Flash 'dirty' }
            default { }
        }
    }
}