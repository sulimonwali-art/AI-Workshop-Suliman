# Data-only recommendations. Loading this module never changes Windows settings.
# Written using ASCII and Windows PowerShell 5.1-compatible syntax.
Set-StrictMode -Version 2.0

function New-GamingGuide {
    param(
        [string]$Id, [string]$Category, [string]$Name, [int]$Priority,
        [string[]]$Steps, [string]$Tradeoff,
        [AllowNull()][string]$SettingsUri = $null,
        [AllowNull()][string]$ReferenceUrl = $null
    )
    [pscustomobject]@{
        Id = $Id; Category = $Category; Name = $Name; Priority = $Priority
        Steps = @($Steps); Tradeoff = $Tradeoff
        SettingsUri = $SettingsUri; ReferenceUrl = $ReferenceUrl
    }
}

function Get-GamingGuides {
    @(
        New-GamingGuide -Id 'intel-stability' -Category 'Stability' -Name '14900KF: BIOS and Intel defaults' -Priority 1 -Steps @(
            'Identify your exact motherboard or prebuilt model. Use its manufacturer support page to check the current stable BIOS and Intel processor stability guidance.',
            'Follow the manufacturer update procedure and precautions. Keep your BitLocker recovery key available before firmware changes; this helper does not read, store, or alter it.',
            'Use the manufacturer documented Intel default settings. Avoid unlimited CPU power, automatic overclock presets, or copied voltage settings while establishing a stable baseline.',
            'Investigate crashes or instability before optimizing. A BIOS update is not proof that an already unstable processor has recovered.'
        ) -Tradeoff 'Firmware updating is a separate, higher-impact task. This helper does not flash firmware or alter voltage, power limits, or security.' -ReferenceUrl 'https://www.intel.com/content/www/us/en/support.html'

        New-GamingGuide -Id 'cooling-baseline' -Category 'Stability' -Name 'Check cooling before changing power plans' -Priority 2 -Steps @(
            'Run a familiar game or repeatable benchmark at your normal settings. Use a trusted hardware monitoring tool to inspect CPU/GPU temperatures, clocks, utilization, and thermal-throttling indicators.',
            'Compare values to the component manufacturer specifications. This helper does not read temperature sensors or diagnose the cooling system.',
            'Check airflow, dust, fan/pump operation, and cooler installation if temperatures or throttling appear abnormal.',
            'Keep Balanced power as the baseline. Test High performance only after the system is stable; record temperatures and frame times before keeping it.'
        ) -Tradeoff 'A 14900KF can produce substantial heat. Higher idle clocks or power consumption do not establish better gaming performance.'

        New-GamingGuide -Id 'display-refresh' -Category 'Display' -Name 'Use the monitor refresh rate you paid for' -Priority 3 -Steps @(
            'Open Advanced display and select the monitor used for gaming.',
            'Choose its highest supported refresh rate that works with your desired resolution, HDR, cable, and port. Verify the monitor on-screen menu too.',
            'Make sure your game uses that monitor and the intended refresh rate; avoid a clone/mirror arrangement that forces a lower rate.',
            'If the display becomes unstable, use a supported cable/port combination and restore the prior mode.'
        ) -Tradeoff 'Refresh rate improves display opportunities, not rendered FPS. Some resolution/HDR/refresh combinations have bandwidth limits.' -SettingsUri 'ms-settings:display-advanced'

        New-GamingGuide -Id 'vrr-frame-cap' -Category 'Display' -Name 'Match VRR, G-SYNC, V-Sync, and a frame cap' -Priority 4 -Steps @(
            'Check whether your monitor supports variable refresh rate and whether it is enabled in the monitor menu and NVIDIA settings.',
            'Choose a latency/tearing goal for the game. Test the game recommended VRR/V-Sync combination rather than copying a global preset.',
            'For a VRR setup, test a frame cap within the monitor VRR range. Some configurations benefit from a cap a few FPS below maximum refresh; the appropriate margin depends on the limiter and game.',
            'Avoid stacking multiple frame limiters. Compare input feel, tearing, and frame-time consistency in the same test scene.'
        ) -Tradeoff 'The best cap depends on the monitor, game engine, and competitive versus visual priorities. The helper does not force NVIDIA driver settings.' -ReferenceUrl 'https://www.nvidia.com/en-us/geforce/technologies/g-sync/'

        New-GamingGuide -Id 'nvidia-driver' -Category 'Graphics' -Name 'Use an official NVIDIA driver and a measured baseline' -Priority 5 -Steps @(
            'Compare the GPU and driver reported by this helper to the intended RTX 4070 Ti. Obtain drivers from NVIDIA or your PC manufacturer.',
            'Check relevant driver release notes when diagnosing a game-specific issue. Newer is not proof of better performance in every game.',
            'Restart when the driver installer requests it, then allow game shaders to finish compiling before benchmarking.',
            'Use per-game NVIDIA profiles for experiments. Keep a record of your previous settings and avoid third-party driver-profile packs.'
        ) -Tradeoff 'The helper does not download, install, remove, or roll back drivers. Driver changes deserve a separate test and can invalidate earlier benchmark comparisons.' -ReferenceUrl 'https://www.nvidia.com/en-us/drivers/'

        New-GamingGuide -Id 'game-graphics' -Category 'Graphics' -Name 'Tune resolution, VRAM, DLSS, and ray tracing per game' -Priority 6 -Steps @(
            'Use the game benchmark or a repeatable gameplay scene to identify whether you are limited by the GPU, CPU, or frame cap.',
            'On the 12 GB RTX 4070 Ti, reduce texture or other memory-heavy settings if the game exceeds available VRAM and stutters. Usage counters alone do not prove a VRAM bottleneck.',
            'For GPU-bound games, test supported DLSS Super Resolution modes, ray-tracing reductions, and expensive lighting/shadow settings one at a time.',
            'Frame generation can improve displayed smoothness in supported games, but generated frames do not provide the same input-response improvement as a higher base rendering rate. Test image quality and latency too.'
        ) -Tradeoff 'Game graphics changes usually have greater impact than desktop clutter settings, but trade image quality against frame rate. Supported DLSS features vary by game and GPU generation.' -ReferenceUrl 'https://www.nvidia.com/en-us/geforce/technologies/dlss/'

        New-GamingGuide -Id 'reflex-latency' -Category 'Graphics' -Name 'Test in-game NVIDIA Reflex for input latency' -Priority 7 -Steps @(
            'If the game offers NVIDIA Reflex, start with the game recommended supported option and compare input response.',
            'Measure latency separately from average FPS where the game or your equipment provides a reliable measurement.',
            'Test Boost separately if offered: keeping GPU clocks higher can increase power draw and heat.',
            'Do not combine arbitrary global low-latency driver presets, priority hacks, and frame limits without checking how the game implements them.'
        ) -Tradeoff 'Lower latency and higher average FPS are different goals. Reflex availability and behavior depend on the game.' -ReferenceUrl 'https://www.nvidia.com/en-us/geforce/technologies/reflex/'

        New-GamingGuide -Id 'hags' -Category 'Graphics' -Name 'Evaluate hardware-accelerated GPU scheduling' -Priority 8 -Steps @(
            'Open Graphics settings and review the default graphics settings available on your Windows build.',
            'Record the current hardware-accelerated GPU scheduling setting. Check requirements for features you use, including supported frame-generation modes.',
            'If you test another value, restart Windows when requested and compare the same game and capture configuration.',
            'Restore your starting value if frame times, compatibility, recording, or stability worsen.'
        ) -Tradeoff 'Hardware-accelerated GPU scheduling is not a universal FPS switch. The helper links to the supported Windows setting rather than forcing an undocumented registry value.' -SettingsUri 'ms-settings:display-advancedgraphics'

        New-GamingGuide -Id 'windowed-optimizations' -Category 'Graphics' -Name 'Review windowed optimizations and per-game graphics' -Priority 9 -Steps @(
            'Open Graphics settings and review optimizations for windowed games, where available on your Windows build.',
            'Test the supported per-app setting for the game and display mode you actually use; leave unrelated games unchanged.',
            'For the helper GPU preference action, choose the actual local game executable, not an installer or launcher unless that is the process being configured.',
            'The 14900KF has no integrated GPU; a PC with only the 4070 Ti already has one usable rendering GPU. Setting High performance cannot create an additional faster GPU.'
        ) -Tradeoff 'Graphics preferences are requests to Windows and the app may choose its own adapter. Per-app overrides can improve compatibility or have no measurable effect.' -SettingsUri 'ms-settings:display-advancedgraphics'

        New-GamingGuide -Id 'startup-load' -Category 'Background load' -Name 'Reduce startup load selectively' -Priority 10 -Steps @(
            'Open Startup apps and review entries you recognize, using the inventory as a starting point rather than a removal list.',
            'Disable optional chat, updater, cloud-sync, or launcher startup only if you do not need those features immediately after sign-in.',
            'Keep required device support, audio/controller software, security, anti-cheat, and game services. Do not disable an entry merely because its name is unfamiliar.',
            'Restart and verify the software and peripherals you use. Re-enable anything whose absence causes problems.'
        ) -Tradeoff 'Fewer startup apps can reduce background work and sign-in time, but many idle apps have little effect in a running game. These manual changes are outside the helper Undo.' -SettingsUri 'ms-settings:startupapps'

        New-GamingGuide -Id 'optional-apps' -Category 'Background load' -Name 'Remove optional apps you recognize' -Priority 11 -Steps @(
            'Open Installed apps. Sort or inspect apps you installed or received with the PC, and identify software you do not use.',
            'Confirm how to reinstall an app before removing it. Review trial antivirus, duplicate launchers, and promotional apps individually.',
            'Keep Microsoft Store, Xbox/Game Pass components you use, runtime libraries, device drivers, and components whose purpose is unclear.',
            'Uninstall through Windows or the vendor uninstaller. The helper does not mass-remove provisioned packages or delete system apps.'
        ) -Tradeoff 'Uninstalling unused software can recover space, but installed apps are not automatically a gaming bottleneck. Manual removal is outside the helper Undo and may require downloads to reverse.' -SettingsUri 'ms-settings:appsfeatures'

        New-GamingGuide -Id 'recording-overlays' -Category 'Background load' -Name 'Review capture and overlays you actually use' -Priority 12 -Steps @(
            'List active recording, instant-replay, streaming, overlay, and monitoring tools, including Windows capture, NVIDIA recording, Steam, Discord, and game launchers.',
            'Disable only unused recording or overlay features, through each app supported settings. Test one at a time.',
            'The helper Windows capture tweak disables Windows game recording, including retrospective clips; NVIDIA recording is a separate setting.',
            'Keep voice chat, accessibility, streaming, or metrics features you need. Recheck clips and microphone behavior after changes.'
        ) -Tradeoff 'Recording can consume resources, but costs vary by configuration. Disabling capture sacrifices functionality and is never selected automatically.' -SettingsUri 'ms-settings:gaming-gamedvr'

        New-GamingGuide -Id 'ssd-space' -Category 'Storage and memory' -Name 'Keep SSD space available and let Windows optimize it' -Priority 13 -Steps @(
            'Check the local-drive free-space report and review Windows Storage settings when space is low.',
            'Move or uninstall unused games and review Windows cleanup categories before deleting files. Keep saves and content you need.',
            'Let Windows perform its normal SSD optimization and TRIM. Do not repeatedly force defragmentation or install SSD booster tools.',
            'Keep shader caches unless diagnosing a specific issue; deleting them can cause recompilation stutter.'
        ) -Tradeoff 'Free space helps Windows, updates, and game installations operate, but cleanup alone does not guarantee higher FPS. This helper does not delete caches or files.' -SettingsUri 'ms-settings:storagesense'

        New-GamingGuide -Id 'pagefile-memory' -Category 'Storage and memory' -Name 'Keep the pagefile system-managed with 64 GB RAM' -Priority 14 -Steps @(
            'Leave the Windows pagefile system-managed unless you are troubleshooting a documented requirement.',
            'Use Task Manager to inspect memory pressure and committed memory during a representative session instead of assuming 64 GB prevents every memory issue.',
            'Avoid standby-list purges, RAM cleaners, and repeated memory compression changes as a gaming preset.',
            'Close an unnecessary memory-heavy workload when it is demonstrably competing with the game.'
        ) -Tradeoff 'Disabling the pagefile can cause allocation failures and reduce crash-dump support. Clearing useful cache can hurt performance.'

        New-GamingGuide -Id 'network-latency' -Category 'Input and network' -Name 'Improve connection consistency without TCP hacks' -Priority 15 -Steps @(
            'Separate local frame-time stutter from network latency, jitter, or packet loss using the game network statistics where available.',
            'Prefer a reliable wired Ethernet connection when practical. For Wi-Fi, check signal quality, interference, and the appropriate access point.',
            'Pause competing downloads and cloud uploads for a test. Compare the same game server or region.',
            'Use adapter/router vendor guidance for actual connection problems. DNS changes do not generally lower latency after a game connection has been established.'
        ) -Tradeoff 'The helper does not change TCP registry parameters, disable network offloads, or promise lower ping. Network congestion and remote servers may be outside your PC control.' -SettingsUri 'ms-settings:network-status'

        New-GamingGuide -Id 'input-audio' -Category 'Input and network' -Name 'Keep input and audio reliable' -Priority 16 -Steps @(
            'Use supported mouse/controller firmware and drivers. Check the game raw-input option if available.',
            'The helper mouse acceleration tweak affects the Windows pointer and some games; raw-input games may ignore it. Keep your original choice if it feels better.',
            'Check audio device selection and latency inside the game and the device supported software before changing Windows services.',
            'Do not disable audio, Bluetooth, controller, anti-cheat, or accessibility components blindly. Prefer documented per-app settings.'
        ) -Tradeoff 'Pointer acceleration is a preference, not an FPS gain. Extreme polling rates or unsupported device tweaks can add CPU load or cause compatibility problems.' -SettingsUri 'ms-settings:sound'

        New-GamingGuide -Id 'updates-security' -Category 'Maintenance' -Name 'Keep Windows security and updates working' -Priority 17 -Steps @(
            'Install supported Windows updates and device updates through trusted channels, then test when an update materially changes the system.',
            'Schedule active hours and restarts around gaming sessions rather than permanently disabling Windows Update.',
            'Keep Defender, Memory Integrity, Secure Boot, and anti-cheat requirements intact. Do not add broad game-folder antivirus exclusions as a performance preset.',
            'Use Game Mode as a conservative starting point and leave speculative security tradeoffs out of a gaming profile.'
        ) -Tradeoff 'Security changes can affect protection, compatibility, and anti-cheat access. This helper does not disable security features or update services.' -SettingsUri 'ms-settings:windowsupdate' -ReferenceUrl 'https://support.microsoft.com/windows'

        New-GamingGuide -Id 'memory-stability' -Category 'Stability' -Name 'Check memory speed and XMP stability deliberately' -Priority 18 -Steps @(
            'Compare the configured memory speed reported by the PC check with the memory kit and motherboard supported settings.',
            'Establish a stable CPU and memory baseline before considering an XMP profile. XMP is a memory overclock and may need stability testing.',
            'If you use a profile, follow motherboard documentation and test memory plus your real workloads. Revert when errors or crashes appear.',
            'Do not copy voltages, disable CPU hybrid cores, or change thread affinity to chase a benchmark without a specific, verified diagnosis.'
        ) -Tradeoff 'Higher memory speed can help some CPU-limited workloads, but errors and instability outweigh a small benchmark gain. The helper does not change BIOS or memory settings.'
    )
}

Export-ModuleMember -Function Get-GamingGuides
