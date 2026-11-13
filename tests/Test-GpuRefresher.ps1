$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\GPU-Refresher.ps1" -Library
$script:Passed = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:Passed++
    Write-Host "PASS: $Message" -ForegroundColor Green
}
function New-Snapshot {
    [pscustomobject]@{
        Intel=@([pscustomobject]@{Name='Intel';PNPDeviceID='PCI\VEN_8086';ConfigManagerErrorCode=0})
        Nvidia=@([pscustomobject]@{Name='NVIDIA';PNPDeviceID='PCI\VEN_10DE';ConfigManagerErrorCode=0})
        MonitorsKnown=$true;ExternalCount=0;ActiveCount=1;OnAC=$false;Battery=80
    }
}
$s = New-Snapshot
Assert (@(Get-RefreshBlockers $s).Count -eq 0) 'Undocked hybrid configuration is accepted'
$s.ExternalCount=1
Assert (@(Get-RefreshBlockers $s).Count -gt 0) 'External monitor blocks reset'
$s = New-Snapshot; $s.MonitorsKnown=$false
Assert (@(Get-RefreshBlockers $s).Count -gt 0) 'Unknown display topology blocks reset'
$s = New-Snapshot; $s.Intel[0].ConfigManagerErrorCode=22
Assert (@(Get-RefreshBlockers $s).Count -gt 0) 'Disabled Intel graphics blocks reset'
$s = New-Snapshot; $s.Nvidia[0].ConfigManagerErrorCode=22
Assert (@(Get-RefreshBlockers $s).Count -gt 0) 'Disabled NVIDIA graphics blocks reset'
$s = New-Snapshot; $s.Nvidia=@($s.Nvidia[0],$s.Nvidia[0])
Assert (@(Get-RefreshBlockers $s).Count -gt 0) 'Ambiguous NVIDIA devices block reset'

# Every side effect is replaced below. Never touch real services/devices.
function Test-Administrator { return $script:Admin }
function Start-RunLog { $script:LogFile=$null }
function Get-SystemSnapshot { $script:Scans++; if ($script:Scans -gt 1 -and $script:BadAfter) { $bad=New-Snapshot; $bad.Nvidia[0].ConfigManagerErrorCode=43; return $bad }; return $script:Snapshot }
function Get-RunningNvidiaServices { [pscustomobject]@{Name='NVDisplay.ContainerLocalSystem'}; [pscustomobject]@{Name='NvContainerLocalSystem'} }
function Stop-NvidiaService($Name) { $script:Events.Add('stop:'+$Name); if ($script:FailStop) { throw 'simulated stop timeout' } }
function Restore-NvidiaService($Name) { $script:Events.Add('restore:'+$Name); if ($script:FailRestore) { throw 'simulated restore failure' } }
function Invoke-AdapterRestart($InstanceId) { $script:Events.Add('reset:'+$InstanceId); if ($script:FailReset) { throw 'simulated native failure' } }
function Reset-Fixture {
    $script:Events=New-Object 'System.Collections.Generic.List[string]'
    $script:Snapshot=New-Snapshot; $script:Admin=$true; $script:DemoMode=$false
    $script:FailStop=$false; $script:FailReset=$false; $script:FailRestore=$false; $script:BadAfter=$false; $script:Scans=0
}
Reset-Fixture
$ok=Invoke-Refresh
Assert $ok 'Normal refresh succeeds'
Assert (($script:Events -join ',') -eq 'stop:NVDisplay.ContainerLocalSystem,stop:NvContainerLocalSystem,reset:PCI\VEN_10DE,restore:NVDisplay.ContainerLocalSystem,restore:NvContainerLocalSystem') 'Only running scoped services are stopped and restored around exact device reset'
Reset-Fixture; $script:FailReset=$true
$ok=Invoke-Refresh
Assert (-not $ok) 'Native reset failure is reported'
Assert (@($script:Events | Where-Object { $_ -like 'restore:*' }).Count -eq 2) 'All services restored after reset failure'
Reset-Fixture; $script:FailStop=$true
$ok=Invoke-Refresh
Assert (-not $ok) 'Service stop timeout is reported'
Assert (($script:Events -join ',') -eq 'stop:NVDisplay.ContainerLocalSystem,restore:NVDisplay.ContainerLocalSystem') 'Stop timeout restores attempted service and prevents reset'
Reset-Fixture; $script:FailRestore=$true
$ok=Invoke-Refresh
Assert (-not $ok) 'Service recovery failure prevents success report'
Assert (@($script:Events | Where-Object { $_ -like 'restore:*' }).Count -eq 2) 'Recovery continues after one service fails'
Reset-Fixture; $script:BadAfter=$true
$ok=Invoke-Refresh
Assert (-not $ok) 'Post-reset device error prevents success report'
Reset-Fixture
$ok=Invoke-Refresh -PreviewOnly
Assert ($ok -and $script:Events.Count -eq 0) 'Preview performs no mutations'
Reset-Fixture; $script:DemoMode=$true
$ok=Invoke-Refresh
Assert ($ok -and $script:Events.Count -eq 0) 'Demo cannot perform mutations'
Reset-Fixture; $script:Snapshot.ExternalCount=1
$caught=$false
try { [void](Invoke-Refresh) } catch { $caught=$true }
Assert ($caught -and $script:Events.Count -eq 0) 'Fresh topology guard prevents all mutations'
Reset-Fixture; $script:Admin=$false
$caught=$false
try { [void](Invoke-Refresh) } catch { $caught=$true }
Assert ($caught -and $script:Events.Count -eq 0) 'Non-admin execution cannot stop services'
Write-Host "$script:Passed checks passed. No live reset was performed."
