#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Menu','Status','Preview','Refresh')][string]$Action = 'Menu',
    [switch]$DryRun,
    [switch]$NonInteractive,
    [switch]$Demo,
    [switch]$Library
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Version = '1.0.0'
$script:ServiceNames = @('NVDisplay.ContainerLocalSystem','NvContainerLocalSystem')
$script:LogFile = $null
$script:DemoMode = [bool]$Demo

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Line([string]$Text = '', [ConsoleColor]$Color = 'Gray') {
    Write-Host $Text -ForegroundColor $Color
}

function Write-Event([string]$Text, [string]$Level = 'INFO') {
    $color = 'Gray'
    if ($Level -eq 'OK') { $color = 'Green' }
    if ($Level -eq 'WARN') { $color = 'Yellow' }
    if ($Level -eq 'ERROR') { $color = 'Red' }
    Write-Line ('  [{0,-5}] {1}' -f $Level,$Text) $color
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Encoding UTF8 -Value ('{0:O} [{1}] {2}' -f (Get-Date),$Level,$Text) }
        catch { Write-Line ('  Logging unavailable: ' + $_.Exception.Message) Yellow }
    }
}

function Start-RunLog {
    $base = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'GPU Refresher\Logs'
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    $script:LogFile = Join-Path $base ('refresh-{0:yyyyMMdd-HHmmss}-{1}.log' -f (Get-Date),$PID)
    Set-Content -LiteralPath $script:LogFile -Encoding UTF8 -Value ('GPU Refresher ' + $script:Version)
}

function Get-SystemSnapshot {
    if ($script:DemoMode) {
        return [pscustomobject]@{
            Intel = @([pscustomobject]@{Name='Intel(R) UHD Graphics'; PNPDeviceID='DEMO-INTEL'; ConfigManagerErrorCode=0})
            Nvidia = @([pscustomobject]@{Name='NVIDIA GeForce RTX 4050 Laptop GPU'; PNPDeviceID='DEMO-NVIDIA'; ConfigManagerErrorCode=0})
            MonitorsKnown=$true; ExternalCount=0; ActiveCount=1; OnAC=$false; Battery=72
        }
    }
    $adapters = @(Get-CimInstance Win32_VideoController -ErrorAction Stop)
    $intel = @($adapters | Where-Object { $_.PNPDeviceID -like 'PCI\VEN_8086*' })
    $nvidia = @($adapters | Where-Object { $_.PNPDeviceID -like 'PCI\VEN_10DE*' })
    $known = $false; $external = 0; $activeCount = 0
    try {
        $monitors = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction Stop | Where-Object { $_.Active })
        $activeCount = $monitors.Count
        # D3DKMDT_VIDEO_OUTPUT_TECHNOLOGY: LVDS, embedded DP/UDI, INTERNAL.
        $internalTypes = @(6,11,13,2147483648,-2147483648)
        $external = @($monitors | Where-Object { [long]$_.VideoOutputTechnology -notin $internalTypes }).Count
        $known = $activeCount -gt 0
    } catch { $known = $false }
    $onAC = $null; $battery = $null
    try {
        $power = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop)
        if ($power.Count -gt 0) { $onAC = [bool](@($power | Where-Object { $_.PowerOnline }).Count -gt 0) }
        $batteries = @(Get-CimInstance Win32_Battery -ErrorAction Stop)
        if ($batteries.Count -gt 0) { $battery = $batteries[0].EstimatedChargeRemaining }
    } catch { }
    return [pscustomobject]@{Intel=$intel; Nvidia=$nvidia; MonitorsKnown=$known; ExternalCount=$external; ActiveCount=$activeCount; OnAC=$onAC; Battery=$battery}
}

function Get-RefreshBlockers($Snapshot) {
    if (@($Snapshot.Nvidia).Count -ne 1) { 'Exactly one NVIDIA adapter is required.' }
    if (@($Snapshot.Intel | Where-Object { $_.ConfigManagerErrorCode -eq 0 }).Count -eq 0) { 'An enabled Intel graphics adapter is required. Check hybrid graphics mode.' }
    if (@($Snapshot.Nvidia | Where-Object { $_.ConfigManagerErrorCode -ne 0 }).Count -gt 0) { 'The NVIDIA adapter has a device error or is disabled. Enable or repair it in Device Manager first.' }
    if (-not $Snapshot.MonitorsKnown) { 'Active display connections could not be verified. Refresh is blocked.' }
    elseif ($Snapshot.ExternalCount -gt 0) { 'An external display is still active. Disconnect the display/dock and scan again.' }
}

function Show-Header {
    Write-Line
    Write-Line '    ___ ___ _   _   ___ ___ ___ ___ ___ ___ _  _ ___ ___ ' DarkCyan
    Write-Line '   / __| _ \ | | | | _ \ __| __| _ \ __/ __| || | __| _ \' Cyan
    Write-Line '  | (_ |  _/ |_| | |   / _|| _||   / _|\__ \ __ | _||   /' Cyan
    Write-Line '   \___|_|  \___/  |_|_\___|_| |_|_\___|___/_||_|___|_|_\' Blue
    Write-Line
    Write-Line ('  Undock. Refresh. Keep going.                   v' + $script:Version) DarkGray
    Write-Line '  ------------------------------------------------------' DarkCyan
    Write-Line
    if ($script:DemoMode) { Write-Line '  DEMO / simulated hardware / no changes can run' Magenta; Write-Line }
}

function Show-Snapshot($Snapshot) {
    $powerText = 'Unknown'
    if ($Snapshot.OnAC -eq $true) { $powerText = 'Plugged in' }
    elseif ($Snapshot.OnAC -eq $false) { $powerText = 'On battery' }
    if ($null -ne $Snapshot.Battery) { $powerText += (' / {0}%' -f $Snapshot.Battery) }
    $displayText = 'Unable to verify'
    if ($Snapshot.MonitorsKnown) { $displayText = '{0} active / {1} external' -f $Snapshot.ActiveCount,$Snapshot.ExternalCount }
    Write-Line '  YOUR LAPTOP' White
    Write-Line ('  Power       {0}' -f $powerText)
    Write-Line ('  Displays    {0}' -f $displayText)
    foreach ($gpu in @($Snapshot.Intel) + @($Snapshot.Nvidia)) {
        Write-Line ('  Graphics    {0}' -f $gpu.Name)
        Write-Line ('              Device status: {0} (0 = ready)' -f $gpu.ConfigManagerErrorCode) DarkGray
    }
    $blockers = @(Get-RefreshBlockers $Snapshot)
    Write-Line
    if ($blockers.Count -eq 0) { Write-Line '  READY  /  Undocked display configuration detected' Green }
    else { foreach ($reason in $blockers) { Write-Line ('  WAIT   /  ' + $reason) Yellow } }
    Write-Line
}

function Show-Plan($Snapshot) {
    Write-Line '  THE REFRESH' White
    Write-Line '  01  Pause running NVIDIA display/container services.'
    Write-Line '  02  Restart the NVIDIA display adapter with Windows PnPUtil.'
    Write-Line '  03  Restore the services that were running; verify device state.'
    Write-Line
    Write-Line '  Windows notifies apps that the adapter was reset. Each app must'
    Write-Line '  recover its own graphics device; a move to Intel is not guaranteed.'
    Write-Line '  Some apps may need reopening. Save your work before refreshing.' Yellow
    Write-Line '  The display may flicker. A driver can still require a reboot.' Yellow
    Write-Line
    Write-Line '  No app kills, shell restarts, GPU disabling, power-plan edits,' DarkGray
    Write-Line '  scheduled tasks, or unrelated service restarts.' DarkGray
    foreach ($gpu in @($Snapshot.Nvidia)) { Write-Line ('  Target: ' + $gpu.PNPDeviceID) DarkGray }
    Write-Line
}

function Get-RunningNvidiaServices {
    foreach ($name in $script:ServiceNames) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $service -and $service.Status -eq 'Running') { $service }
    }
}

function Stop-NvidiaService([string]$Name) {
    # Do not force-stop dependent services.
    Stop-Service -Name $Name -ErrorAction Stop
    (Get-Service -Name $Name -ErrorAction Stop).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(20))
}

function Restore-NvidiaService([string]$Name) {
    Start-Service -Name $Name -ErrorAction Stop
    (Get-Service -Name $Name -ErrorAction Stop).WaitForStatus('Running',[TimeSpan]::FromSeconds(20))
}

function Invoke-AdapterRestart([string]$InstanceId) {
    $exe = Join-Path $env:SystemRoot 'System32\pnputil.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Windows PnPUtil is unavailable.' }
    $output = & $exe /restart-device $InstanceId 2>&1
    $nativeExit = $LASTEXITCODE
    foreach ($line in $output) { Write-Event ([string]$line) }
    if ($nativeExit -eq 3010 -or $nativeExit -eq 1641) { throw 'Windows reports that a reboot is required. No reboot was requested by GPU Refresher.' }
    if ($nativeExit -ne 0) { throw ('PnPUtil failed with exit code {0}.' -f $nativeExit) }
}

function Invoke-Refresh([switch]$PreviewOnly) {
    # Re-read immediately before mutations, even if the menu scan was clear.
    $snapshot = Get-SystemSnapshot
    $blockers = @(Get-RefreshBlockers $snapshot)
    if ($PreviewOnly -or $script:DemoMode) {
        Show-Plan $snapshot
        foreach ($reason in $blockers) { Write-Event $reason 'WARN' }
        Write-Event 'Preview complete. No services or devices were changed.' 'OK'
        return $true
    }
    if ($blockers.Count -gt 0) { throw ($blockers -join ' ') }
    if (-not (Test-Administrator)) { throw 'Administrator access is required. Use Refresh in the menu to request elevation.' }
    Start-RunLog
    Write-Event ('Target: ' + $snapshot.Nvidia[0].PNPDeviceID)
    $restore = New-Object 'System.Collections.Generic.List[string]'
    $failed = $false
    try {
        Write-Event 'Step 1/3 - Pausing NVIDIA container services.'
        foreach ($service in @(Get-RunningNvidiaServices)) {
            # Record BEFORE stop: a timeout may still leave the service stopped.
            $restore.Add($service.Name)
            Stop-NvidiaService $service.Name
            Write-Event ('Paused ' + $service.Name) 'OK'
        }
        Write-Event 'Step 2/3 - Restarting the NVIDIA adapter. The display may flicker.'
        Invoke-AdapterRestart $snapshot.Nvidia[0].PNPDeviceID
        Write-Event 'Windows accepted the adapter restart.' 'OK'
    } catch {
        $failed = $true
        Write-Event $_.Exception.Message 'ERROR'
    } finally {
        Write-Event 'Step 3/3 - Restoring previously running services.'
        foreach ($name in $restore) {
            try { Restore-NvidiaService $name; Write-Event ('Restored ' + $name) 'OK' }
            catch { $failed = $true; Write-Event ('Could not restore ' + $name + ': ' + $_.Exception.Message) 'ERROR' }
        }
    }
    try {
        $after = Get-SystemSnapshot
        $target = @($after.Nvidia | Where-Object { $_.PNPDeviceID -eq $snapshot.Nvidia[0].PNPDeviceID })
        if ($target.Count -ne 1 -or $target[0].ConfigManagerErrorCode -ne 0) {
            $failed = $true
            Write-Event 'The NVIDIA adapter is not reporting ready. Check Device Manager.' 'ERROR'
        }
    } catch { $failed = $true; Write-Event ('Verification failed: ' + $_.Exception.Message) 'ERROR' }
    if ($failed) { Write-Event 'Refresh incomplete. Review the log for the failing step.' 'WARN' }
    else {
        Write-Event 'Refresh completed. NVIDIA is enabled and its device status is ready.' 'OK'
        Write-Event 'This does not verify Intel migration or GPU sleep. Check battery draw after a minute.'
    }
    Write-Line ('  Log: ' + $script:LogFile) DarkGray
    return (-not $failed)
}

function Start-ElevatedRefresh {
    # Only fixed arguments and this script path are forwarded to the admin process.
    if ($PSCommandPath.Contains('"')) { throw 'Unsupported quote in script path.' }
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Refresh' -f $PSCommandPath
    $child = Start-Process -FilePath $hostExe -ArgumentList $arguments -Verb RunAs -PassThru -Wait
    if ($child.ExitCode -ne 0) { throw ('Refresh window exited with code ' + $child.ExitCode) }
}

function Show-Help {
    Write-Line '  HOW IT WORKS' White
    Write-Line '  Your batch file resets the NVIDIA device to release stale GPU'
    Write-Line '  contexts after undocking. This tool uses that device-reset method'
    Write-Line '  and restores NVIDIA services to their previous running state.'
    Write-Line
    Write-Line '  Unplug the dock/display, save work, then choose Refresh.'
    Write-Line '  Intel graphics must be enabled in hybrid mode. If an app still'
    Write-Line '  holds NVIDIA awake, reopen it and set Power saving for that app'
    Write-Line '  in Windows Settings > System > Display > Graphics.'
    Write-Line
    Write-Line '  A reset affects all clients of this NVIDIA adapter. Windows has'
    Write-Line '  no universal command to move every running app/service to Intel.'
    Write-Line '  GPU Refresher does not promise 0 W, D3Cold, or a particular LED.'
    Write-Line
}

function Wait-ForReturn { [void](Read-Host '  Press Enter to return') }

function Invoke-Main {
    try { $Host.UI.RawUI.WindowTitle = 'GPU Refresher' } catch { }
    if ($Action -ne 'Menu') {
        Show-Header
        if ($Action -eq 'Status') { Show-Snapshot (Get-SystemSnapshot); return 0 }
        if ($Action -eq 'Preview' -or $DryRun -or $Demo) {
            Show-Snapshot (Get-SystemSnapshot)
            [void](Invoke-Refresh -PreviewOnly)
            return 0
        }
        if ($NonInteractive) { throw 'A live refresh requires interactive confirmation. Use -Action Preview for automation.' }
        $snapshot = Get-SystemSnapshot
        Show-Snapshot $snapshot
        Show-Plan $snapshot
        $blockers = @(Get-RefreshBlockers $snapshot)
        if ($blockers.Count -gt 0) { throw ($blockers -join ' ') }
        if (-not (Test-Administrator)) { Start-ElevatedRefresh; return 0 }
        if ((Read-Host '  Save work, then type REFRESH to continue') -cne 'REFRESH') { Write-Line '  Cancelled.'; return 0 }
        $ok = Invoke-Refresh
        [void](Read-Host '  Press Enter to close')
        if ($ok) { return 0 } else { return 1 }
    }
    if ($NonInteractive) { throw 'Use -Action Status or Preview with -NonInteractive.' }
    while ($true) {
        Clear-Host
        Show-Header
        try { Show-Snapshot (Get-SystemSnapshot) } catch { Write-Event ('Scan failed: ' + $_.Exception.Message) 'ERROR' }
        Write-Line '  [R]  Refresh GPU      Release stale NVIDIA contexts' Cyan
        Write-Line '  [P]  Preview          See the exact refresh steps'
        Write-Line '  [S]  Scan again       Update hardware and dock status'
        Write-Line '  [G]  Graphics         Open Windows per-app preferences'
        Write-Line '  [H]  Help             Understand the refresh'
        Write-Line '  [Q]  Quit'
        Write-Line
        $choice = (Read-Host '  gpu >').Trim().ToUpperInvariant()
        try {
            switch ($choice) {
                'Q' { return 0 }
                'S' { continue }
                'P' { [void](Invoke-Refresh -PreviewOnly); Wait-ForReturn }
                'H' { Show-Help; Wait-ForReturn }
                'G' { if ($script:DemoMode) { Write-Line '  Demo: settings launch skipped.' } else { Start-Process 'ms-settings:display-advancedgraphics' }; Wait-ForReturn }
                'R' {
                    if ($script:DemoMode -or $DryRun) { [void](Invoke-Refresh -PreviewOnly); Wait-ForReturn; continue }
                    $snapshot = Get-SystemSnapshot
                    $blockers = @(Get-RefreshBlockers $snapshot)
                    if ($blockers.Count -gt 0) { throw ($blockers -join ' ') }
                    Show-Plan $snapshot
                    if (Test-Administrator) {
                        if ((Read-Host '  Save work, then type REFRESH to continue') -cne 'REFRESH') { continue }
                        [void](Invoke-Refresh)
                    } else { Start-ElevatedRefresh }
                    Wait-ForReturn
                }
                default { Write-Line '  Choose R, P, S, G, H, or Q.' Yellow; Wait-ForReturn }
            }
        } catch { Write-Event $_.Exception.Message 'ERROR'; Wait-ForReturn }
    }
}

if (-not $Library) {
    try { $code = Invoke-Main; exit $code }
    catch { Write-Event $_.Exception.Message 'ERROR'; if (-not $NonInteractive) { [void](Read-Host '  Press Enter to close') }; exit 1 }
}
