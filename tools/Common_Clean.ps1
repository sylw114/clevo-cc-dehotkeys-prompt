param(
    [switch]$RunRepair,
    [switch]$FullClean,
    [switch]$Force
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    Write-Host $line -ForegroundColor $Color
}

function Stop-ClevoProcesses {
    $procs = @(
        "ControlCenter30", "CC40", "FnKey", "DCHUService", "LaunchFnkey",
        "WakePanelUp_Hook", "HKClipSvc", "HKFltrInstaller", "perkeyhook",
        "FanSpeedSetting", "BatteryPackUtility", "EnergySaveUtility",
        "CPUOverclocking", "GPUOverclocking", "LedKeyboardSetting", "Flexikey",
        "XtuService", "runme", "CC"
    )
    foreach ($p in $procs) {
        Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Remove-FilterFromClassKey {
    param(
        [string]$ClassGuid,
        [string]$BadFilterName,
        [string]$RequiredBaseFilter
    )
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$ClassGuid"
    if (-not (Test-Path $regPath)) { return }

    $props = Get-ItemProperty -Path $regPath -Name "UpperFilters" -ErrorAction SilentlyContinue
    if ($null -eq $props -or $null -eq $props.UpperFilters) {
        Set-ItemProperty -Path $regPath -Name "UpperFilters" -Value ([string[]]@($RequiredBaseFilter)) -Type MultiString
        Write-Log "  [Class $ClassGuid] Restored missing base UpperFilters = $RequiredBaseFilter" "Yellow"
    } else {
        $orig = @($props.UpperFilters | Where-Object { $_ -ne $null -and $_.Trim() -ne "" })
        $filtered = @($orig | Where-Object { $_.Trim() -ine $BadFilterName })
        $hasRemoved = ($filtered.Count -ne $orig.Count)
        if (-not ($filtered -contains $RequiredBaseFilter)) {
            $filtered = @($filtered + $RequiredBaseFilter)
        }
        if ($hasRemoved -or ($filtered.Count -ne $orig.Count)) {
            Set-ItemProperty -Path $regPath -Name "UpperFilters" -Value ([string[]]$filtered) -Type MultiString
            Write-Log "  [Class $ClassGuid] Updated UpperFilters: [$($orig -join ', ')] -> [$($filtered -join ', ')]" "Green"
        } else {
            Write-Log "  [Class $ClassGuid] UpperFilters already clean: [$($filtered -join ', ')]" "Gray"
        }
    }

    $lprops = Get-ItemProperty -Path $regPath -Name "LowerFilters" -ErrorAction SilentlyContinue
    if ($null -ne $lprops -and $null -ne $lprops.LowerFilters) {
        $lorig = @($lprops.LowerFilters | Where-Object { $_ -ne $null -and $_.Trim() -ne "" })
        $lclean = @($lorig | Where-Object { $_.Trim() -ine $BadFilterName })
        if ($lclean.Count -ne $lorig.Count) {
            if ($lclean.Count -eq 0) {
                Remove-ItemProperty -Path $regPath -Name "LowerFilters" -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -Path $regPath -Name "LowerFilters" -Value ([string[]]$lclean) -Type MultiString
            }
            Write-Log "  [Class $ClassGuid] Removed $BadFilterName from LowerFilters" "Green"
        }
    }
}

function Remove-HotkeyDeviceEnumFilters {
    $enumRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum"
    if (-not (Test-Path $enumRoot)) { return }
    Get-ChildItem -Path $enumRoot -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $p = $_.PSPath
        foreach ($propName in @("UpperFilters", "LowerFilters")) {
            $val = (Get-ItemProperty -Path $p -Name $propName -ErrorAction SilentlyContinue).$propName
            if ($null -ne $val) {
                $arr = @($val | Where-Object { $_ -ne $null -and $_.Trim() -ne "" })
                $clean = @($arr | Where-Object { $_.Trim() -ine "HKKbdFltr" -and $_.Trim() -ine "HKMouFltr" })
                if ($clean.Count -ne $arr.Count) {
                    if ($clean.Count -eq 0) {
                        Remove-ItemProperty -Path $p -Name $propName -ErrorAction SilentlyContinue
                    } else {
                        Set-ItemProperty -Path $p -Name $propName -Value ([string[]]$clean) -Type MultiString
                    }
                    Write-Log "  Cleaned device $propName on $($_.PSChildName)" "Green"
                }
            }
        }
    }
}

function Remove-OemDriverByOrigName {
    param(
        [string[]]$OrigInfNames,
        [string[]]$InfMarkers = @()
    )
    $toDelete = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    $raw = (& pnputil.exe /enum-drivers 2>&1) -join "`n"
    $blocks = $raw -split "(?:\r?\n){2,}"
    foreach ($blk in $blocks) {
        $pub = $null
        $orig = $null
        foreach ($line in ($blk -split "\r?\n")) {
            if ($line -match "[:：]\s*(oem\d+\.inf)\s*$") {
                $pub = $Matches[1].Trim()
            }
            elseif ($line -match "[:：]\s*([^\s\\/:：]+\.inf)\s*$") {
                $cand = $Matches[1].Trim().ToLowerInvariant()
                if ($cand -notlike "oem*.inf") { $orig = $cand }
            }
        }
        if ($pub -and $orig) {
            foreach ($target in $OrigInfNames) {
                if ($orig -eq $target.ToLowerInvariant()) {
                    [void]$toDelete.Add($pub)
                }
            }
        }
    }

    if ($InfMarkers.Count -gt 0 -and (Test-Path "$env:SystemRoot\INF")) {
        Get-ChildItem "$env:SystemRoot\INF\oem*.inf" -ErrorAction SilentlyContinue | ForEach-Object {
            $infFile = $_
            try {
                $txt = [System.IO.File]::ReadAllText($infFile.FullName)
                foreach ($m in $InfMarkers) {
                    if ($txt.IndexOf($m, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        [void]$toDelete.Add($infFile.Name)
                        break
                    }
                }
            } catch {}
        }
    }

    foreach ($pubInf in $toDelete) {
        Write-Log "  Removing DriverStore package $pubInf..." "Yellow"
        & pnputil.exe /delete-driver $pubInf /uninstall /force 2>&1 | Out-Null
    }
}

function Invoke-CleanHotkeysAndLegacy {
    param([switch]$FullClean)

    Write-Log "Step 1: Stopping Clevo Control Center / hotkey processes..." "Cyan"
    Stop-ClevoProcesses
    Start-Sleep -Milliseconds 500

    Write-Log "Step 2: Safely cleaning HKKbdFltr / HKMouFltr filters (preserving kbdclass / mouclass)..." "Cyan"
    Remove-FilterFromClassKey -ClassGuid "{4d36e96b-e325-11ce-bfc1-08002be10318}" -BadFilterName "HKKbdFltr" -RequiredBaseFilter "kbdclass"
    Remove-FilterFromClassKey -ClassGuid "{4d36e96f-e325-11ce-bfc1-08002be10318}" -BadFilterName "HKMouFltr" -RequiredBaseFilter "mouclass"
    Remove-HotkeyDeviceEnumFilters

    Write-Log "Step 3: Removing HKClipSvc / HKKbdFltr / HKMouFltr services and DriverStore files..." "Cyan"
    foreach ($svc in @("HKClipSvc", "HKKbdFltr", "HKMouFltr")) {
        & sc.exe stop $svc 2>&1 | Out-Null
        & sc.exe delete $svc 2>&1 | Out-Null
        $svcKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
        if (Test-Path $svcKey) {
            Remove-Item -Path $svcKey -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "  Removed service key $svcKey" "Gray"
        }
    }
    Remove-OemDriverByOrigName -OrigInfNames @("hkkbdfltr.inf", "hkmoufltr.inf") -InfMarkers @("HKKbdFltr.sys", "HKMouFltr.sys")

    foreach ($sysFile in @(
        "$env:SystemRoot\System32\drivers\HKKbdFltr.sys",
        "$env:SystemRoot\System32\drivers\HKMouFltr.sys",
        "$env:SystemRoot\System32\HKClipSvc.exe",
        "C:\ccfw\FKeyDriver.zip"
    )) {
        if (Test-Path $sysFile) {
            Remove-Item -Path $sysFile -Force -ErrorAction SilentlyContinue
            Write-Log "  Removed leftover file $sysFile" "Gray"
        }
    }

    Write-Log "Step 4: Removing any CLEVOCO.Flexikey UWP remnants..." "Cyan"
    Get-AppxPackage -AllUsers "*CLEVOCO.Flexikey*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Log "  Removing AppxPackage $($_.PackageFullName)" "Gray"
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -like "*CLEVOCO.Flexikey*" } | ForEach-Object {
        Write-Log "  Removing ProvisionedPackage $($_.PackageName)" "Gray"
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
    }

    if ($FullClean) {
        Write-Log "Step 5: Cleaning previous Control Center 3.0 UWP / CCDCHUService (unlock-explorer trigger) / XTU remnants..." "Cyan"
        foreach ($svc in @("CCDCHUService", "Xtu3Service")) {
            & sc.exe stop $svc 2>&1 | Out-Null
            & sc.exe delete $svc 2>&1 | Out-Null
            $svcKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
            if (Test-Path $svcKey) {
                Remove-Item -Path $svcKey -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Remove-OemDriverByOrigName -OrigInfNames @("acpibridge.inf", "acpibridge1.inf") -InfMarkers @("ACPI\CLV0001", "ACPI\CLV0002", "AcpiBridge.sys", "AcpiBridge1.sys")

        Get-AppxPackage -AllUsers "*CLEVOCO*" -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "  Removing AppxPackage $($_.PackageFullName)" "Gray"
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -like "*CLEVOCO*" } | ForEach-Object {
            Write-Log "  Removing ProvisionedPackage $($_.PackageName)" "Gray"
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        }

        foreach ($runPath in @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        )) {
            if (Test-Path $runPath) {
                $item = Get-Item $runPath -ErrorAction SilentlyContinue
                foreach ($vn in $item.GetValueNames()) {
                    $vv = [string]$item.GetValue($vn)
                    if ($vn -match "ControlCenter|ComboKey|FnKey|LaunchFnkey|Flexikey|HKClipSvc" -or $vv -match "ControlCenter|ComboKey|LaunchFnkey|HKClipSvc|Flexikey") {
                        Remove-ItemProperty -Path $runPath -Name $vn -ErrorAction SilentlyContinue
                        Write-Log "  Removed stale Run entry [$runPath] $vn" "Gray"
                    }
                }
            }
        }

        & wevtutil.exe cl OutLog 2>&1 | Out-Null
        & wevtutil.exe cl PowerBiosServerLog 2>&1 | Out-Null
        $acpiParam = "HKLM:\SYSTEM\CurrentControlSet\Services\AcpiBridge\Parameters"
        if (Test-Path $acpiParam) {
            Remove-ItemProperty -Path $acpiParam -Name "AppSettings" -ErrorAction SilentlyContinue
        }
        if (Test-Path "HKLM:\SOFTWARE\ControlCenterAP") {
            Remove-Item -Path "HKLM:\SOFTWARE\ControlCenterAP" -Recurse -Force -ErrorAction SilentlyContinue
        }

        $ccProgDir = "${env:ProgramFiles(x86)}\ControlCenter"
        foreach ($dir in @($ccProgDir, "C:\ComboKey")) {
            if (Test-Path $dir) {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "  Cleaned directory $dir" "Gray"
            }
        }
    }
}

if ($RunRepair) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "Administrator privileges are required when running -RunRepair."
        exit 1
    }
    $script:LogFile = Join-Path $env:TEMP "Clevo_Hotkey_Repair.log"
    if (-not $Force) {
        $ans = Read-Host "Repair Clevo UpperFilters/services (FullClean=$FullClean)? Type YES to proceed"
        if ($ans -ne "YES") { Write-Host "Cancelled."; exit 0 }
    }
    Invoke-CleanHotkeysAndLegacy -FullClean:$FullClean
    Write-Log "Cleanup completed. Please reboot Windows to ensure all drivers/filters reload cleanly." "Yellow"
}
