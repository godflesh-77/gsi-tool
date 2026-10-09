# ==============================================================================
# GSI FLASH & SERVICE TOOL 0.9.9 (PowerShell edition)
# Windows 10/11 x64 only.
# ==============================================================================

[CmdletBinding()]
param(
    [ValidateSet('en','ru')][string]$Lang,
    [switch]$Version,
    [switch]$Help,
    [string]$Serial
)

$null = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

$Script:TOOL_VERSION   = '0.9.9'

# Build identifier: git short hash if .git exists, else timestamp
$buildHash = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    Push-Location $PSScriptRoot
    try { $buildHash = & git rev-parse --short HEAD 2>$null } catch { }
    Pop-Location
}
if (-not $buildHash) { $buildHash = Get-Date -Format 'yyyyMMdd.HHmm' }
$Script:BUILD        = $buildHash
$Script:FULL_VERSION = "$($Script:TOOL_VERSION)+build.$buildHash"

$Script:WAIT_ADB       = 15
$Script:WAIT_FASTBOOT  = 60
$Script:REBOOT_TIMEOUT = 30
$Script:MARGIN_MB      = 256
$Script:IS_AB          = $true
$Script:CURRENT_SLOT   = 'a'
$Script:SEVENZIP       = $null
$Script:LOG            = $null
$Script:ADB_PATH       = $null
$Script:FASTBOOT_PATH  = $null

# ==============================================================================
# i18n
# ==============================================================================
$MSG = @{
    en = @{
        LogFile        = 'Log'
        FromAndroid    = 'Android  -> Fastbootd'
        FromRecovery   = 'Recovery -> Fastbootd'
        FromBootloader = 'Bootloader -> Fastbootd'
        AlreadyFb      = 'Already in Fastbootd'
        ServiceMenu    = 'SERVICE MENU'
        Exit           = 'Exit'
        Input          = 'Input: '
        ActionUpdate   = 'Update system'
        ActionReset    = 'Reset and flash (Full Wipe)'
        ActionSlot     = 'Flash to specified slot (A/B)'
        ActionSwitch   = 'Switch active slot'
        ActionDirty    = 'Dirty flash'
        Back           = 'Back'
        CheckingBl     = 'Checking bootloader state...'
        BlUnlocked     = 'Bootloader: UNLOCKED'
        BlLocked       = 'CRITICAL: Bootloader is LOCKED!'
        WaitAdb        = 'Waiting for ADB device'
        WaitFastboot   = 'Waiting for Fastboot device'
        Timeout        = '[TIMEOUT]'
        Ok             = '[OK]'
        FoundImg       = 'Found system image'
        ChooseImg      = 'Found multiple images. Choose one'
        Cancel         = 'Cancelled.'
        InvalidChoice  = 'Invalid choice.'
        EnterSlot      = 'Enter slot (a/b): '
        EnterConfirm   = 'Continue? (y/N): '
        FlashOk        = 'Done.'
        RebuildSuper   = 'SUPER RECONSTRUCTION'
        Backing        = 'Backup /data via ADB stream'
        FlashingGki    = 'Flash GKI kernels (boot + vendor_boot)'
        EmergencyFix   = 'Emergency dual-slot restore'
        PressKey       = 'Press Enter to continue...'
        Error          = 'ERROR'
        ToolCheck      = 'Tool version check'
        ToolMissing    = 'not found'
    }
    ru = @{
        LogFile        = 'Лог'
        FromAndroid    = 'Android  -> Fastbootd'
        FromRecovery   = 'Recovery -> Fastbootd'
        FromBootloader = 'Bootloader -> Fastbootd'
        AlreadyFb      = 'Уже в Fastbootd'
        ServiceMenu    = 'СЕРВИСНОЕ МЕНЮ'
        Exit           = 'Выход'
        Input          = 'Ввод: '
        ActionUpdate   = 'Обновить систему'
        ActionReset    = 'Сброс и прошивка (Full Wipe)'
        ActionSlot     = 'Прошить в указанный слот (A/B)'
        ActionSwitch   = 'Переключить активный слот'
        ActionDirty    = 'Грязная прошивка'
        Back           = 'Назад'
        CheckingBl     = 'Проверка загрузчика...'
        BlUnlocked     = 'Загрузчик: РАЗБЛОКИРОВАН'
        BlLocked       = 'КРИТИЧЕСКАЯ ОШИБКА: Загрузчик заблокирован!'
        WaitAdb        = 'Ожидание ADB-устройства'
        WaitFastboot   = 'Ожидание Fastboot-устройства'
        Timeout        = '[ТАЙМ-АУТ]'
        Ok             = '[OK]'
        FoundImg       = 'Найден образ системы'
        ChooseImg      = 'Найдено несколько образов. Выберите'
        Cancel         = 'Отменено.'
        InvalidChoice  = 'Неверный ввод.'
        EnterSlot      = 'Слот (a/b): '
        EnterConfirm   = 'Выполнить? (y/N): '
        FlashOk        = 'Готово.'
        RebuildSuper   = 'РЕКОНСТРУКЦИЯ SUPER'
        Backing        = 'Бэкап /data через ADB-стрим'
        FlashingGki    = 'Прошивка GKI-ядер (boot + vendor_boot)'
        EmergencyFix   = 'Экстренный откат (оба слота)'
        PressKey       = 'Нажмите Enter для продолжения...'
        Error          = 'ОШИБКА'
        ToolCheck      = 'Проверка версий утилит'
        ToolMissing    = 'не найден'
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
    Read-Host -Prompt (T 'PressKey')
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
    Write-Output "Usage: gsi-tool.ps1 [-Lang en|ru] [-Serial <serial>] [-Version] [-Help]"
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
Add-Content -LiteralPath $Script:LOG -Value "PSScriptRoot: $PSScriptRoot" -Encoding UTF8

# ==============================================================================
# Tool detection
# ==============================================================================
function Get-ExePath([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $local = Join-Path $PSScriptRoot "$name.exe"
    if (Test-Path -LiteralPath $local) { return $local }
    return $null
}

function Test-ToolVersions {
    Say (T 'ToolCheck') 'Cyan'
    Log "Tool version check"
    $problems = 0
    if (-not $Script:ADB_PATH)      { Say "  adb      : $(T 'ToolMissing')" 'Red';    LogErr "adb not found";      $problems++ }
    else                            { Say "  adb      : $($Script:ADB_PATH)" 'Green'; Log "adb: $($Script:ADB_PATH)" }
    if (-not $Script:FASTBOOT_PATH) { Say "  fastboot : $(T 'ToolMissing')" 'Red';    LogErr "fastboot not found"; $problems++ }
    else                            { Say "  fastboot : $($Script:FASTBOOT_PATH)" 'Green'; Log "fastboot: $($Script:FASTBOOT_PATH)" }
    if ($Script:SEVENZIP)           { Say "  7-Zip    : $($Script:SEVENZIP)" 'Green'; Log "7-Zip: $($Script:SEVENZIP)" }
    else                            { Say "  7-Zip    : $(T 'ToolMissing')" 'Yellow'; LogWarn "7-Zip not found" }
    return $problems
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
            if (Test-Path -LiteralPath $dll) {
                $Script:SEVENZIP = $p
                return $true
            }
        }
    }
    return $false
}

# ==============================================================================
# Fastboot / ADB wrappers
# ==============================================================================
function Invoke-Fb {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    $cmdArgs = @()
    if ($Script:Serial) { $cmdArgs += @('-s', $Script:Serial) }
    $cmdArgs += $Args
    Log "fastboot $($Args -join ' ')"

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName               = $Script:FASTBOOT_PATH
    $proc.StartInfo.Arguments              = ($cmdArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.RedirectStandardError  = $true
    $proc.StartInfo.UseShellExecute        = $false
    $proc.StartInfo.CreateNoWindow         = $true

    try { [void]$proc.Start() } catch {
        LogErr "Cannot start fastboot: $_"
        return $false
    }

    # Async read prevents buffer overrun deadlock on fastboot stderr flood
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    if (-not $proc.WaitForExit($Script:REBOOT_TIMEOUT * 1000)) {
        try { $proc.Kill() } catch { }
        LogErr "fastboot TIMEOUT after $($Script:REBOOT_TIMEOUT)s"
        return $false
    }

    try { [void]$outTask.Wait(2000) } catch { }
    try { [void]$errTask.Wait(2000) } catch { }

    $out = try { $outTask.Result } catch { '' }
    $err = try { $errTask.Result } catch { '' }
    $exitCode = $proc.ExitCode

    if ($out) { LogRaw "  fb stdout: $($out.Trim())" }
    if ($err) { LogRaw "  fb stderr: $($err.Trim())" }
    if ($exitCode -ne 0) { LogWarn "fastboot exit code: $exitCode" }
    return ($exitCode -eq 0)
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    $cmdArgs = @()
    if ($Script:Serial) { $cmdArgs += @('-s', $Script:Serial) }
    $cmdArgs += $Args
    Log "adb $($Args -join ' ')"

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName               = $Script:ADB_PATH
    $proc.StartInfo.Arguments              = ($cmdArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
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

    if (-not $proc.WaitForExit($Script:REBOOT_TIMEOUT * 1000)) {
        try { $proc.Kill() } catch { }
        LogErr "adb TIMEOUT after $($Script:REBOOT_TIMEOUT)s"
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
    if (-not (Invoke-Fb @Args)) {
        LogErr "fb_flash FAILED: fastboot $($Args -join ' ')"
        Say (T 'Error') 'Red'
        Say "  fastboot $($Args -join ' ') FAILED. See log: $($Script:LOG)" 'Red'
        Say '  DO NOT REBOOT the device.' 'Red'
        return $false
    }
    Log "fb_flash OK: fastboot $($Args -join ' ')"
    return $true
}

function Wait-Adb {
    param([int]$Timeout = $Script:WAIT_ADB)
    Write-Host -NoNewline (T 'WaitAdb')
    for ($i = 0; $i -lt $Timeout; $i++) {
        $devs = & $Script:ADB_PATH devices 2>$null | Select-Object -Skip 1 | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\s(device|recovery)$' }
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
        $devs = & $Script:FASTBOOT_PATH devices 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\sfastboot$' }
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
    $out = & $Script:FASTBOOT_PATH getvar $name 2>&1 | Out-String
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
    if ($a -eq '0')   { Say '  ERROR: OEM Unlock disabled in Android!' 'Red'; LogErr "OEM Unlock disabled"; return $false }
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
    if ($sys.Count -eq 0) { LogWarn 'No system images found'; Say 'No system images found.' 'Red'; return $null }

    # Size check — GSI normally weighs 600 MB - 4 GB
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
        Say 'WARNING: one or more images are suspiciously small (<100 MB).' 'Yellow'
        Say '         Typical GSI is 600 MB - 4 GB. File may be corrupted,' 'Yellow'
        Say '         incomplete, or not a system image at all.' 'Yellow'
        if (-not (Confirm 'Continue anyway? (y/N): ')) { Log 'Aborted due to size check'; return $null }
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
    if ($lower -match '\.img\.xz$') {
        if (-not $Script:SEVENZIP) { LogErr 'Need 7-Zip for .xz'; Say 'Need 7-Zip for .xz' 'Red'; return $null }
        $out = $Path.Substring(0, $Path.Length - 3)
        if (-not (Test-Path -LiteralPath $out)) {
            Log "Unpacking .xz: $Path -> $out"
            Say "Unpacking: $Path -> $out" 'Cyan'
            & $Script:SEVENZIP x -y -bso0 -bsp1 $Path > $null
            if ($LASTEXITCODE -ne 0) { LogErr 'Unpack .xz failed'; Say 'Unpack .xz failed' 'Red'; return $null }
        }
        return $out
    }
    if ($lower -match '\.img\.gz$') {
        if (-not $Script:SEVENZIP) { LogErr 'Need 7-Zip for .gz'; Say 'Need 7-Zip for .gz' 'Red'; return $null }
        $out = $Path.Substring(0, $Path.Length - 3)
        if (-not (Test-Path -LiteralPath $out)) {
            Log "Unpacking .gz: $Path -> $out"
            & $Script:SEVENZIP x -y -bso0 -bsp1 $Path > $null
            if ($LASTEXITCODE -ne 0) { LogErr 'Unpack .gz failed'; Say 'Unpack .gz failed' 'Red'; return $null }
        }
        return $out
    }
    if ($lower -match '\.img\.zst$') {
        if (-not $Script:SEVENZIP) { LogErr 'Need 7-Zip for .zst'; Say 'Need 7-Zip for .zst' 'Red'; return $null }
        $out = $Path.Substring(0, $Path.Length - 4)
        if (-not (Test-Path -LiteralPath $out)) {
            Log "Unpacking .zst: $Path -> $out"
            & $Script:SEVENZIP x -y -bso0 -bsp1 $Path > $null
            if ($LASTEXITCODE -ne 0) { LogErr 'Unpack .zst failed'; Say 'Unpack .zst failed' 'Red'; return $null }
        }
        return $out
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
        if (-not (Confirm 'Continue anyway? (y/N): ')) { return $false }
    } elseif ($integrity -eq 'error') {
        Say 'Sparse integrity check error' 'Yellow'
    }
    $rawSize = Get-ImageSize $SystemImg
    if ($rawSize -le 0) { LogErr 'Cannot detect image size'; Say 'Cannot detect image size' 'Red'; return $false }
    $partSize = Get-PartitionSize $rawSize
    Log "raw=$rawSize part=$partSize (margin=$($Script:MARGIN_MB)MB)"
    Say ("raw=$rawSize, part=$partSize (margin=$($Script:MARGIN_MB)MB)") 'Gray'

    Say '--------------------------------------------------------' 'Cyan'
    Say 'SHA256 VERIFICATION:' 'Cyan'
    $userHash = ''
    if (Test-Path -LiteralPath "${SystemImg}.sha256") {
        Log 'Found .sha256 file'
        Say '[INFO] Found .sha256 file.' 'Green'
        $userHash = 'file'
    } else {
        Say 'Copy SHA256 hash from GitHub release and paste here (or Enter to skip).' 'Gray'
        $userHash = Read-Host -Prompt 'Hash'
        Log "SHA256 input: $(if ($userHash) { 'provided' } else { 'skipped' })"
    }
    if ($userHash) {
        $res = Invoke-VerifySha256 $SystemImg $userHash
        if ($res -match '^mismatch:') {
            LogErr "SHA256 mismatch: $res"
            Say (T 'Error') 'Red'
            Say "  Real: $res" 'Red'
            if (-not (Confirm 'Continue at your own risk? (y/N): ')) { return $false }
        } elseif ($res -eq 'ok') { Say '[SHA256] OK.' 'Green' }
        elseif ($res -eq 'missing') { Say '[SHA256] Hash not recognized. Skipping.' 'Yellow' }
        elseif ($res -eq 'error_file_too_large') { Say '[SHA256] .sha256 too large. Skipping.' 'Yellow' }
        elseif ($res -eq 'error') { Say '[SHA256] Hash calculation error. Skipping.' 'Yellow' }
    } else { Say '[SHA256] Check skipped by user.' 'Yellow' }
    Say '--------------------------------------------------------' 'Cyan'

    $tpart = Get-SysPart $Slot
    $opp = if ($Slot -eq 'a') { 'b' } else { 'a' }

    if (-not (Test-Userspace)) {
        Say 'Rebooting to Fastbootd...' 'Cyan'
        Log 'Not in Fastbootd, reboot needed'
        if (-not (Invoke-Fb 'reboot' 'fastboot')) {
            LogErr 'fastboot reboot fastboot failed'
            Say 'ERROR: failed to send reboot command to device.' 'Red'
            return $false
        }
        if (-not (Wait-Fastboot)) { return $false }
    }

    Say '--------------------------------------------------------' 'Cyan'
    Say (T 'RebuildSuper') 'Cyan'
    Say "  Target partition: $tpart" 'Gray'
    Say "  New size: $partSize bytes" 'Gray'
    Say '  NOT touching: vendor / odm / vendor_dlkm / system_dlkm' 'Gray'
    Say '--------------------------------------------------------' 'Cyan'
    if (-not (Confirm)) { Log 'Rebuild cancelled by user'; return $false }

    if ($partSize -gt 4GB) {
        Say 'WARNING: partition > 4 GB. MTK overflow possible.' 'Yellow'
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
        Say 'CRITICAL: create-logical-partition failed.' 'Red'
        Say 'super left without system/product/system_ext. DO NOT REBOOT.' 'Red'
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
        Say 'WARNING: vbmeta.img not found. Bootloop possible.' 'Yellow'
        return (Confirm 'Continue without vbmeta? (y/N): ')
    }
    if (Test-Userspace) {
        LogWarn 'In Fastbootd, vbmeta is a physical partition'
        Say 'WARNING: You are in Fastbootd. vbmeta is a physical partition.' 'Yellow'
    }
    Log "Flashing vbmeta: $vb"
    Say 'Flashing vbmeta...' 'Cyan'
    if (-not (Invoke-FbFlash '--disable-verity' '--disable-verification' 'flash' 'vbmeta' $vb)) {
        return (Confirm 'Continue without vbmeta? (y/N): ')
    }
    Log 'vbmeta flashed OK'
    return $true
}

# ==============================================================================
# GKI / Emergency
# ==============================================================================
function Install-GkiKernels {
    Clear-Host
    Log "=== Install-GkiKernels ==="
    $boot = Select-BootImage -Mask 'boot*.img' -Prompt 'Select BOOT (kernel):'
    if (-not $boot) { return }
    $vb = Select-BootImage -Mask 'vendor_boot*.img' -Prompt 'Select VENDOR_BOOT:'
    if (-not $vb) { return }
    Log "boot=$boot vendor_boot=$vb"

    if (-not (Wait-Adb)) { Pause; return }
    [void](Invoke-Adb 'reboot' 'bootloader')
    if (-not (Wait-Fastboot)) { Pause; return }
    if (-not (Test-BootloaderUnlocked)) { Pause; return }

    $slot = Get-CurrentSlot
    if (Confirm "Flash to slot _$slot? (y/N): ") {
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
    $b = Select-BootImage -Mask 'boot*.img' -Prompt 'Stable BOOT image:'
    if (-not $b) { return }
    $v = Select-BootImage -Mask 'vendor_boot*.img' -Prompt 'Stable VENDOR_BOOT image:'
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
    Say "GSI Flash Tool $($Script:FULL_VERSION) (PowerShell)" 'Cyan'
    Say "$(T 'LogFile'): $($Script:LOG)" 'Gray'
    Say '========================================================' 'Cyan'
    Say "  1. Check devices (ADB / Fastboot)"
    Say "  2. $(T 'FromAndroid')"
    Say "  3. $(T 'FromRecovery')"
    Say "  4. $(T 'FromBootloader')"
    Say "  5. $(T 'AlreadyFb')"
    Say "  6. $(T 'ServiceMenu')"
    Say "  0. $(T 'Exit')"
    Say '========================================================' 'Cyan'
    $choice = Read-Host -Prompt (T 'Input')
    Log "Main menu: choice=$choice"
    return $choice
}

function Show-ActionMenu {
    Clear-Host
    Say "Active slot: $($Script:CURRENT_SLOT)  [A/B: $($Script:IS_AB)]" 'Cyan'
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
    Say 'Some tools missing. Basic operations may not work.' 'Yellow'
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
                        '1' { Log 'Service: backup_data_stream (not yet ported)'; Say 'Backup: not yet ported from 0.9.8' 'Yellow' }
                        '2' { Install-GkiKernels }
                        '3' { Restore-EmergencySlots }
                        default { Log "Unknown service choice: $s" }
                    }
                }
            }
            '5' { if (Wait-Fastboot) { $Script:Proceed = $true } }
            '4' { if (Wait-Fastboot) { [void](Invoke-Fb 'reboot' 'fastboot'); if (Wait-Fastboot) { $Script:Proceed = $true } } }
            '3' { if (Wait-Adb)   { [void](Invoke-Adb 'reboot' 'fastboot'); if (Wait-Fastboot) { $Script:Proceed = $true } } }
            '2' { if (Wait-Adb)   { [void](Invoke-Adb 'reboot' 'fastboot'); if (Wait-Fastboot) { $Script:Proceed = $true } } }
            '1' { & $Script:ADB_PATH devices; & $Script:FASTBOOT_PATH devices }
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
                if (-not $Script:IS_AB) { Say 'Device is not A/B.' 'Yellow'; Pause; continue }
                $newSlot = if ($Script:CURRENT_SLOT -eq 'a') { 'b' } else { 'a' }
                if (Test-Userspace) {
                    LogWarn "set_active in fastbootd: may fail on MTK"
                    Say 'WARNING: you are in Fastbootd. set_active may not work on MTK.' 'Yellow'
                    if (-not (Confirm 'Try anyway? (y/N): ')) { continue }
                }
                if (Invoke-Fb 'set_active' $newSlot) {
                    $Script:CURRENT_SLOT = $newSlot
                    Log "Switched active slot to $($Script:CURRENT_SLOT)"
                    Say "Current slot: $($Script:CURRENT_SLOT)" 'Green'
                } else {
                    LogErr "set_active $newSlot FAILED"
                    Say 'ERROR: set_active failed. On MTK use bootloader, not fastbootd.' 'Red'
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