# ==============================================================================
# GSI FLASH TOOL HELPER 0.9.8 (Strict Win10+)
# ==============================================================================

param(
    [Parameter(Mandatory=$true)][string]$Mode,
    [Parameter(Mandatory=$false)][string]$Path,
    [Parameter(Mandatory=$false)][int]$Margin = 256,
    [Parameter(Mandatory=$false)][int]$Timeout = 10,
    [Parameter(Mandatory=$false)][string]$SevenZip,
    [Parameter(Mandatory=$false)][string]$Output,
    [Parameter(Mandatory=$false)][string]$AdbCmd,
    [Parameter(Mandatory=$false)][int]$StreamTimeout = 3600,
    [Parameter(Mandatory=$false)][string]$Hash
)

switch ($Mode) {
    "size" {
        if (-not (Test-Path -LiteralPath $Path)) { Write-Output 0; exit 1 }
        try {
            $fs = [IO.File]::OpenRead($Path)
            try {
                $magicBytes = New-Object byte[] 4
                $null = $fs.Read($magicBytes, 0, 4)
                $magic = [BitConverter]::ToString($magicBytes).Replace('-','').ToLower()

                if ($magic -eq "3aff26ed") {
                    $fs.Position = 0
                    $header = New-Object byte[] 28
                    $null = $fs.Read($header, 0, 28)
                    $blkSize   = [BitConverter]::ToUInt32($header, 12)
                    $totalBlks = [BitConverter]::ToUInt32($header, 16)
                    $rawSize = [UInt64]$blkSize * [UInt64]$totalBlks
                    Write-Output $rawSize
                } else {
                    Write-Output (Get-Item -LiteralPath $Path).Length
                }
            }
            finally { $fs.Close(); $fs.Dispose() }
        }
        catch { Write-Output 0; exit 1 }
    }

    "timestamp" {
        Write-Output (Get-Date -Format "yyyyMMdd_HHmmss")
    }

    "sparse_integrity" {
        if (-not (Test-Path -LiteralPath $Path)) { Write-Output "missing"; exit 1 }
        try {
            $fs = [IO.File]::OpenRead($Path)
            try {
                $magicBytes = New-Object byte[] 4
                $null = $fs.Read($magicBytes, 0, 4)
                $magic = [BitConverter]::ToString($magicBytes).Replace('-','').ToLower()

                if ($magic -ne "3aff26ed") { Write-Output "raw"; exit 0 }

                $fs.Position = 0
                $header = New-Object byte[] 28
                $null = $fs.Read($header, 0, 28)
                $blkSize   = [BitConverter]::ToUInt32($header, 12)
                $totalBlks = [BitConverter]::ToUInt32($header, 16)
                $expected  = [UInt64]$blkSize * [UInt64]$totalBlks
                $actual    = (Get-Item -LiteralPath $Path).Length
                $minSize   = [UInt64]($expected / 4)

                if ($actual -lt $minSize) {
                    # Fix 0.9.5: ${actual} / ${expected} — иначе $actual: трактуется как drive-ref
                    Write-Output "suspect:${actual}:${expected}"
                } else {
                    Write-Output "ok"
                }
            }
            finally { $fs.Close(); $fs.Dispose() }
        }
        catch { Write-Output "error"; exit 1 }
    }

    "calculate_partition" {
        try { $raw = [UInt64]$Path } catch { Write-Output 0; exit 1 }
        if ($raw -eq 0) { Write-Output 0; exit 0 }
        $align = [UInt64]4096
        $marginBytes = [UInt64]$Margin * 1MB
        $rem = [UInt64]0
        $div = [Math]::DivRem($raw, $align, [ref]$rem)
        $aligned = [UInt64]$div * $align
        if ($rem -gt 0) { $aligned += $align }
        Write-Output ([UInt64]$aligned + $marginBytes)
    }

    "disk_free_mb" {
        $dir = if ($Path) { $Path } else { "." }
        try {
            $full = [IO.Path]::GetFullPath($dir)
            $root = [IO.Path]::GetPathRoot($full)
            $drive = New-Object System.IO.DriveInfo($root)
            Write-Output ([UInt64]($drive.AvailableFreeSpace / 1MB))
        }
        catch { Write-Output 0; exit 1 }
    }

    "need_mb_x3" {
        try {
            $bytes = [UInt64](Get-Item -LiteralPath $Path).Length
            Write-Output ([UInt64][Math]::Floor($bytes / 1MB * 3))
        }
        catch { Write-Output 0; exit 1 }
    }

    "need_mb_x4" {
        try {
            $bytes = [UInt64](Get-Item -LiteralPath $Path).Length
            Write-Output ([UInt64][Math]::Floor($bytes / 1MB * 4))
        }
        catch { Write-Output 0; exit 1 }
    }

    "reboot" {
        $rebootArgs = @("reboot")
        if ($Path -and $Path.Trim() -ne "") { $rebootArgs += $Path }
        try {
            $proc = Start-Process -FilePath "fastboot" -ArgumentList $rebootArgs -NoNewWindow -PassThru
            if (-not $proc.WaitForExit($Timeout * 1000)) {
                try { $proc.Kill() } catch {}
                Write-Output "timeout"
            } else {
                Write-Output "ok"
            }
        } catch {
            Write-Output "error"
        }
    }

    "adb_reboot" {
        $rebootArgs = @("reboot")
        if ($Path -and $Path.Trim() -ne "") { $rebootArgs += $Path }
        try {
            $proc = Start-Process -FilePath "adb" -ArgumentList $rebootArgs -NoNewWindow -PassThru
            if (-not $proc.WaitForExit($Timeout * 1000)) {
                try { $proc.Kill() } catch {}
                Write-Output "timeout"
            } else {
                Write-Output "ok"
            }
        } catch {
            Write-Output "error"
        }
    }

    "stream_backup" {
        if (-not $SevenZip) { Write-Output "no_7zip";   exit 1 }
        if (-not $Output)   { Write-Output "no_output"; exit 1 }
        if (-not $AdbCmd)   { Write-Output "no_adbcmd"; exit 1 }

        try {
            $adb = New-Object System.Diagnostics.Process
            $adb.StartInfo.FileName               = "adb"
            $adb.StartInfo.Arguments              = "exec-out `"$AdbCmd`""
            $adb.StartInfo.RedirectStandardOutput = $true
            $adb.StartInfo.RedirectStandardError  = $false
            $adb.StartInfo.UseShellExecute        = $false
            $adb.StartInfo.CreateNoWindow         = $true
            [void]$adb.Start()

            $sz = New-Object System.Diagnostics.Process
            $sz.StartInfo.FileName              = $SevenZip
            $sz.StartInfo.Arguments             = "a -si -t7z -mx=5 -bso0 -bsp0 `"$Output`""
            $sz.StartInfo.RedirectStandardInput = $true
            $sz.StartInfo.RedirectStandardError = $false
            $sz.StartInfo.UseShellExecute       = $false
            $sz.StartInfo.CreateNoWindow        = $true
            [void]$sz.Start()
            $copyTask = $adb.StandardOutput.BaseStream.CopyToAsync($sz.StandardInput.BaseStream)
            if (-not $copyTask.Wait($StreamTimeout * 1000)) {
                try { $adb.Kill() } catch {}
                try { $sz.Kill() } catch {}
                Write-Output "timeout"
                exit 1
            }
            $sz.StandardInput.Close()

            if (-not $sz.WaitForExit($StreamTimeout * 1000)) {
                try { $sz.Kill() } catch {}
                try { $adb.Kill() } catch {}
                Write-Output "timeout"
                exit 1
            }
            if (-not $adb.WaitForExit(5000)) {
                try { $adb.Kill() } catch {}
            }

            if ($adb.ExitCode -ne 0) { Write-Output "adb_error"; exit 1 }
            if ($sz.ExitCode  -ne 0) { Write-Output "7z_error";  exit 1 }

            if (-not (Test-Path -LiteralPath $Output)) { Write-Output "no_file"; exit 1 }
            $size = (Get-Item -LiteralPath $Output).Length
            if ($size -lt 1024) { Write-Output "too_small"; exit 1 }

            Write-Output "ok"
        } catch {
            try { if ($adb -and -not $adb.HasExited) { $adb.Kill() } } catch {}
            try { if ($sz  -and -not $sz.HasExited)  { $sz.Kill()  } } catch {}
            Write-Output "exception:$_"
            exit 1
        }
    }

    "verify_sha256" {
        if (-not (Test-Path -LiteralPath $Path)) { Write-Output "missing_img"; exit 1 }

        $want = $null

        # 1) Интерактивный ввод из -Hash (если передан)
        if ($Hash -and $Hash.Trim() -match '(?i)\b([a-f0-9]{64})\b') {
            $want = $Matches[1].ToLower()
        }
        # 2) Локальный файл ${Path}.sha256 (если рядом)
        else {
            $shaFile = "${Path}.sha256"
            if (Test-Path -LiteralPath $shaFile) {
                if ((Get-Item -LiteralPath $shaFile).Length -gt 4096) {
                    Write-Output "error_file_too_large"
                    exit 1
                }
                try {
                    $content = [IO.File]::ReadAllText($shaFile).Trim()
                    if ($content -match '(?i)\b([a-f0-9]{64})\b') {
                        $want = $Matches[1].ToLower()
                    }
                } catch { }
            }
        }

        if (-not $want) { Write-Output "missing"; exit 0 }

        try {
            # PS 5.1 + PS 7 совместимость (SHA256Managed устарел в Core)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $stream = [IO.File]::OpenRead($Path)
            try {
                $hashBytes = $sha256.ComputeHash($stream)
                $got = [BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
            }
            finally {
                $stream.Close(); $stream.Dispose()
                $sha256.Dispose()
            }

            if ($got -eq $want) { Write-Output "ok" }
            else { Write-Output "mismatch:$got" }
        }
        catch {
            Write-Output "error"
            exit 1
        }
    }
	
    default {
        Write-Error "Неизвестный режим: $Mode"
        exit 2
    }
}