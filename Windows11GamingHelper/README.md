# Windows 11 Gaming Helper

A portable, opt-in gaming setup utility designed around an Intel Core i9-14900KF, NVIDIA RTX 4070 Ti 12 GB, 64 GB DDR5, SSD, and Windows 11. It combines reversible Windows preferences, optional power/GPU experiments, local diagnostics, benchmark CSV comparisons, and practical guides for settings that belong in Windows, your games, or vendor tools.

More tweaks do not automatically mean more performance. Start from a stable baseline, change one thing, measure the same game, and keep only changes that help your workload.

## Run it

1. Extract the entire folder to a location you control.
2. Read the scripts, then double-click **Launch.cmd** as your normal Windows user. The launcher does not request administrator rights.
3. Review the initial PC report. All tweak checkboxes start unchecked; scanning does not apply changes.
4. Choose individual changes or the conservative preset, which selects **Game Mode only**. Read each tradeoff, preview the selection, then explicitly apply it.
5. Test your games and recording tools. Sign out and back in when a desktop preference requires it; restart when Windows requests it for a manual graphics change.
6. Use Undo for supported changes you do not want to keep. Manual changes in other applications have their own undo steps.

Requires Windows 11 and its included **Windows PowerShell 5.1** with Windows Forms. There are no downloaded packages, accounts, subscriptions, or background services. PowerShell 7 is not required to use the program.

The launcher uses a process-only `RemoteSigned` execution policy; it does not permanently change your system's PowerShell policy. If Windows blocks an unsigned downloaded script, inspect the files and use **Properties → Unblock** only on trusted script files, if that option is present. Follow your organization's application-control and Group Policy requirements.

You can also open Windows PowerShell in this folder and run:

```powershell
powershell.exe -NoProfile -STA -File .\GamingHelper.ps1
```

## Reversible user settings

| Change | Purpose and tradeoff |
| --- | --- |
| Enable Game Mode | Conservative starting point. Benefits vary by game and background workload; this is the only item selected by the recommended preset. |
| Turn off Windows game capture | Disables Windows game recording, including retrospective clips. Game Bar recording stops working until restored. NVIDIA recording is separate. |
| Reduce Windows suggestions | Reduces selected promotional suggestions and suggested-app delivery. It does not uninstall apps, disable all telemetry, or promise more FPS. |
| Hide the Widgets button | Reduces taskbar clutter; does not uninstall Widgets or stop its background components. |
| Reduce transparency | Changes desktop appearance. A visual preference with no promised gaming gain. |
| Reduce minimize/maximize animations | Changes window animation preference. It does not increase a game's rendering rate. |
| Turn off pointer acceleration | Requests unaccelerated Windows pointer movement. Changes input feel; raw-input games may ignore it. Pointer speed is preserved. |
| Stop the controller button opening Game Bar | Changes the controller shortcut preference. Game Bar remains installed and available through other supported methods. |
| Turn off web search suggestions | Requests fewer web suggestions in Windows search. Some builds or policies may ignore the preference; local search remains installed. |

These are opt-in user preferences. Some Windows builds ignore or manage particular settings, so a registry change is not proof that the visible Windows behavior has changed. The helper records existing value types and values before each mutation.

## Optional performance experiments

The **Performance controls** tab offers separate preview, confirmation, and backup journals for these actions. They are not included in the conservative preset.

| Action | When to consider it |
| --- | --- |
| Use an existing Balanced power plan | Recommended baseline for this modern desktop. Restoring Balanced after an experiment can reduce unnecessary power draw without sacrificing measured game performance. |
| Try an existing High performance power plan | An experiment for a demonstrated scheduling/power-state problem. It may increase idle power, heat, and fan noise and can produce no FPS gain. Establish CPU stability and cooling first, especially on the 14900KF. |
| Prefer high-performance GPU for one game | Select the actual local game `.exe` to request Windows' high-performance GPU preference. The 14900KF has no integrated GPU, so a system with only your 4070 Ti may have no alternative adapter and no resulting gain. |

Power actions switch only plans that already exist; they do not create an Ultimate Performance plan or change CPU minimum state, voltage, or power limits. Windows may restrict a plan change; failures are reported rather than triggering automatic elevation. The active power scheme is a computer-wide choice even though its backup belongs to your current Windows profile.

The per-game GPU action preserves other preferences in the same Windows graphics entry. It does not change NVIDIA driver profiles, force ray tracing or DLSS options, or guarantee the application uses the requested adapter. Close and reopen the game when testing an app preference.

## Guides that target the bigger gains

The **Guides** tab covers 18 topics, with steps and tradeoffs: Intel firmware stability, cooling, display refresh rate, VRR/G-SYNC/frame caps, official NVIDIA drivers, per-game graphics and DLSS, Reflex latency, hardware-accelerated GPU scheduling, windowed optimizations, startup load, optional apps, overlays/recording, SSD space, the pagefile, connection quality, input/audio, Windows maintenance, and memory/XMP stability.

The advisor reads like a checklist. **Open Settings** opens the relevant Windows page when available. Official reference links open only when you click them. The helper does not silently apply a guide or claim that every item suits every game.

For this particular PC, prioritize:

- **14900KF stability:** Use your exact motherboard or prebuilt manufacturer's current stable BIOS guidance and documented Intel defaults. Diagnose existing crashes before optimizing. Firmware updating is a separate process; keep relevant recovery information available and follow the manufacturer's precautions.
- **4070 Ti and monitor:** Confirm refresh rate and VRR support. Resolution, ray tracing, VRAM use, supported DLSS settings, and in-game Reflex usually deserve testing before desktop cosmetic preferences.
- **64 GB DDR5:** Keep the pagefile system-managed. XMP is a separate stability-sensitive memory overclock; the helper does not enable it or change voltages.
- **2 TB SSD:** Review low free space and allow normal Windows SSD optimization/TRIM. Avoid repeated cache deletion, forced defragmentation, and third-party SSD boosters.

## Debloating and startup review

Use the startup and Store-app inventory as a starting point, then open **Startup apps** or **Installed apps**. Inspect optional software you recognize; confirm how to reinstall it before removing it. Installed software is not necessarily running or consuming meaningful gaming resources.

The program does not mass-uninstall apps or remove provisioned packages. Keep Microsoft Store, Xbox/Game Pass components you use, runtime libraries, drivers, audio/network/controller support, anti-cheat, accessibility, and security components. Manual uninstalls and startup changes are outside the helper Undo.

## Backups and Undo

The helper records prior state before supported changes. Journals belong to the current Windows user and machine:

```text
User preference backups:
%LOCALAPPDATA%\Win11GamingHelper\Backups

Power/GPU action backups:
%LOCALAPPDATA%\Win11GamingHelper\PerformanceBackups
```

Choose the newest relevant backup first. Undo skips an entry if the current value or power plan differs from the state applied by that entry, preserving later choices. Review skipped or failed results. Completed or externally conflicted entries cannot silently become eligible again when the same backup is restored twice.

Keep journals until testing is finished and close other tuning tools while applying or restoring. Windows preferences and power plans do not provide an atomic compare-and-set operation; the helper checks again just before a supported write, but no local tool can prevent every simultaneous external edit.

These journals are **not full PC backups or Windows restore points**. They cannot undo a driver install, BIOS update, game setting, manual uninstall, or changes made elsewhere. Normal Windows policy or an update can override a preference later. Existing user-setting journals from the earlier version remain supported.

## Measure whether a change helped

Use the same game, scene or built-in benchmark, graphics settings, resolution, frame cap, and recording state. Let shaders finish compiling and use several passes. Compare frame-time consistency and low-percentile performance alongside average FPS. Keep latency, image quality, temperature, power draw, and stability in view rather than chasing one headline number.

The **Benchmark CSV** tab compares baseline and after-change frame-time captures that you supply. It does not record gameplay, run a game benchmark, or manufacture a performance result. Export a comma-delimited CSV from PresentMon or another suitable tool with one of these millisecond columns:

- `MsBetweenPresents`
- `FrameTimeMs`
- `Frame Time (ms)`
- `Frametime (ms)`

Use one game/process/swapchain stream with at least 100 positive frame-time rows. Do not combine separate capture streams, different games, or different resolutions/settings into one comparison. Zero timing rows are counted and discarded; invalid, negative, or nonfinite timing data is rejected. Long frame times are retained rather than silently trimming stutters away.

The reported definitions are:

- Average FPS: `1000 / mean frame time in ms`.
- 1% low: `1000 / mean of the slowest ceil(1% of positive rows)`.
- 0.1% low: the same method for the slowest 0.1%, shown only with at least 1,000 positive rows.
- P99 frame time: nearest-rank 99th percentile of positive frame-time rows.

These summaries describe the supplied timing column, not measured input latency. Tool definitions and presentation/frametime metrics can differ, so use comparable captures and the same source column. Metadata checks can reject clearly incompatible sources, but you are responsible for matching the scene, graphics, display/capture conditions, and test duration.

There is no **maximize everything** button: capture, input, power, and graphics choices have different tradeoffs. A quieter desktop is useful, but it is not proof of higher gaming performance.

The helper does not disable Defender, Windows Update, Memory Integrity, Secure Boot, services, the pagefile, or CPU/GPU safeguards. It does not overclock, flash firmware, install drivers, purge RAM/standby lists, force CPU affinity, set real-time priority, or apply timer/TCP registry folklore.

## Read-only console mode and tests

From Windows PowerShell in this folder, these commands only read your PC or preview user preferences:

```powershell
.\GamingHelper.ps1 -Mode Audit
.\GamingHelper.ps1 -Mode Preview -Tweak @('game-mode', 'background-capture')
```

Reports stay local. Startup commands can contain personal paths, usernames, or arguments; review them before sharing. The helper sends no telemetry or automatic network requests. Opening an official reference link through your browser is a deliberate user action.

Developers can run the scripts under `tests` in PowerShell 7. They mock Windows registry, identity, and power-command boundaries while exercising real temporary journal files. See `VALIDATION.txt` for the recorded test results and limitations.

The Windows Forms UI, Windows PowerShell 5.1 runtime, actual registry/power integration, and gaming results have not been validated by execution on this Linux build machine. Parsing and mocked safety tests do not establish real Windows behavior; check those on Windows 11 before relying on the utility.
