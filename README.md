# GPU Refresher

**Undock. Refresh. Keep going.**

[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE)](#requirements)
[![Tests](https://github.com/nf5054/gpu-refresher/actions/workflows/test.yml/badge.svg)](https://github.com/nf5054/gpu-refresher/actions/workflows/test.yml)

GPU Refresher is a Windows terminal utility for hybrid Intel + NVIDIA laptops that keep the discrete GPU awake after disconnecting a dock or external display. It restarts the NVIDIA adapter and restores its running container services to help release stale GPU contexts without restarting Windows.

```text
    ___ ___ _   _   ___ ___ ___ ___ ___ ___ _  _ ___ ___
   / __| _ \ | | | | _ \ __| __| _ \ __/ __| || | __| _ \
  | (_ |  _/ |_| | |   / _|| _||   / _|\__ \ __ | _||   /
   \___|_|  \___/  |_|_\___|_| |_|_\___|___/_||_|___|_|_\

  Undock. Refresh. Keep going.

  [R] Refresh GPU   [P] Preview   [S] Scan again
  [G] Graphics     [H] Help      [Q] Quit
```

> **Save your work first.** A reset may cause screen flicker, and some graphics apps may need reopening. A completed reset does not guarantee that every app switches to Intel or that battery drain is resolved.

## Get started

1. [Download the project ZIP](https://github.com/nf5054/gpu-refresher/archive/refs/heads/main.zip) and extract it, or clone the repository:

   ```powershell
   git clone https://github.com/nf5054/gpu-refresher.git
   cd gpu-refresher
   ```

2. Disconnect the external display or dock and save your work.
3. Double-click **GPU Refresher.cmd**.
4. Press **P** to preview the steps or **R** to refresh.
5. Approve the administrator prompt when requested, then type `REFRESH` in the refresh window.
6. Keep the window open until service restoration finishes.

No installer or additional packages are needed. Keep the CMD launcher and PowerShell script in the same folder. Administrator access is only requested for a live refresh.

## Features

- Colored terminal interface with a large ASCII-art banner.
- Adapter, battery, power-source, and active display status.
- Automatic NVIDIA device detection without hard-coded device IDs.
- Hardware checks that block a live reset while an external display is active or the display state cannot be verified.
- Preview and demo modes that do not reset hardware.
- Restoration of previously running NVIDIA container services after an attempted reset, including failure handling.
- Per-run logs and a shortcut to Windows per-app graphics settings.

## Requirements

| Component | Requirement |
| --- | --- |
| OS | Windows 10 version 2004 or later, or Windows 11 |
| Shell | Windows PowerShell 5.1, included with Windows |
| Graphics | Enabled Intel graphics and exactly one enabled NVIDIA display adapter |
| Configuration | Hybrid graphics mode with the external display/dock disconnected |
| Permissions | Administrator access for a live refresh |

## Menu

| Key | Action |
| --- | --- |
| **R** | Check the current hardware state and refresh the NVIDIA adapter |
| **P** | Preview the refresh steps without changing devices or services |
| **S** | Rescan adapters, displays, and power status |
| **G** | Open Windows per-app graphics preferences |
| **H** | Read help and limitations |
| **Q** | Quit |

## How it works

1. Detect the NVIDIA adapter's actual device instance ID.
2. Verify that Intel graphics is enabled, NVIDIA reports no device error, and no external display is reported active. Unverified display connections block a live refresh.
3. Pause `NVDisplay.ContainerLocalSystem` and `NvContainerLocalSystem` only when already running. Missing or stopped services are left alone.
4. Run Windows' `pnputil /restart-device` against that NVIDIA adapter.
5. Attempt to restore the previously running services, even after a reset failure, then check the adapter's reported device status.

The tool does not kill applications, restart Explorer, disable NVIDIA, change power plans, restart unrelated services, or install a background task. It never requests a system reboot; Windows or a driver may still report that a reboot is required.

### What a reset can and cannot do

Restarting an adapter affects the graphics clients using it. Each application must handle its own graphics-device recovery. Windows has no universal command to move every running application and service to Intel graphics.

A reset can help release stale GPU contexts after undocking. GPU sleep and battery savings still depend on applications, drivers, firmware, and hybrid/MUX mode. GPU Refresher does not verify GPU power draw or guarantee D3Cold, 0 W, a particular LED color, or improved battery life.

If an app keeps NVIDIA awake, select **Power saving** for it in **Windows Settings > System > Display > Graphics**, then reopen it. Some apps explicitly choose their GPU.

## Command-line usage

From PowerShell in the project folder:

```powershell
# Inspect actual hardware without changing it
& '.\GPU Refresher.cmd' -Action Status -NonInteractive

# Preview the refresh plan
& '.\GPU Refresher.cmd' -Action Preview -NonInteractive

# Exercise the refresh entry point without making changes
& '.\GPU Refresher.cmd' -Action Refresh -DryRun -NonInteractive

# Explore the menu with simulated hardware
& '.\GPU Refresher.cmd' -Demo
```

Live refresh requires interactive confirmation. `-Demo` uses simulated hardware and cannot run a live reset. `-DryRun` prevents refresh mutations.

Exit code **0** means the requested action completed, including a preview or user cancellation. Exit code **1** indicates an error. A preview may list blockers and still return 0 because no reset was attempted.

The launcher applies execution-policy bypass to its PowerShell process only; it does not change the system execution policy.

## Logs and troubleshooting

Logs from live refresh attempts are saved to:

```text
%LOCALAPPDATA%\GPU Refresher\Logs
```

| Message or symptom | Next step |
| --- | --- |
| External display is active | Disconnect the display/dock, then press **S** to rescan. |
| Display connections cannot be verified | Check the local display configuration. Refresh remains blocked until verification succeeds. |
| Intel graphics is unavailable | Check Device Manager and the laptop's hybrid/MUX configuration. |
| NVIDIA is disabled or reports an error | Enable or repair the adapter in Device Manager before retrying. |
| A service could not be restored | Review the log and the named service in Windows Services. |
| An app still uses NVIDIA | Choose **Power saving** for the app in Windows graphics settings, then reopen it. |

## Development and tests

The app is a standalone PowerShell script with a CMD launcher. There is no build step.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\tests\Test-GpuRefresher.ps1'
```

The suite contains **19 isolated checks** covering hardware guards, service restoration, and failure handling. All service and device mutations are replaced with simulations. GitHub Actions runs these checks and a simulated preview on Windows.

Local validation also covered the Windows PowerShell 5.1 launcher, a live read-only hardware scan, preview/demo modes, and menu exit. **No live adapter reset was performed during development** because an external display was connected. Actual application recovery and battery savings remain unverified.

For a bug report, include your Windows version, GPU models, the error message, and relevant log lines. Remove personal paths or device identifiers before sharing logs.

## References

- [Microsoft: PnPUtil command syntax](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax)
- [Microsoft: handling graphics device removal/reset](https://learn.microsoft.com/en-us/windows/uwp/gaming/handling-device-lost-scenarios)
