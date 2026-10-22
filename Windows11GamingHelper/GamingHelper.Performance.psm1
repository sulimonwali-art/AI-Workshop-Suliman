#requires -Version 5.1
# Supported power-plan and per-game GPU controls only.
Set-StrictMode -Version 2.0
$script:BalancedId = '381b4222-f694-41f0-9685-ff5bb260df2e'
$script:HighPerformanceId = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:GpuPath = 'Software\Microsoft\DirectX\UserGpuPreferences'

function Assert-PerformancePlatform {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [Environment]::OSVersion.Version.Build -lt 22000) {
        throw 'Performance controls support Windows 11 only.'
    }
}
function Get-PerformanceIdentity {
    [pscustomobject]@{ Sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value; Machine = [Environment]::MachineName }
}
function Enter-PerformanceLock {
    $identity = Get-PerformanceIdentity
    $mutex = New-Object Threading.Mutex($false, ('Local\Win11GamingHelper.Performance.' + $identity.Sid))
    try {
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Another performance apply or restore operation is running.' }
        return $mutex
    } catch { $mutex.Dispose(); throw }
}
function Invoke-PerformancePowerCfg {
    param([string[]]$Arguments)
    $tool = Join-Path $env:SystemRoot 'System32\powercfg.exe'
    if (-not [IO.File]::Exists($tool)) { throw 'Windows powercfg.exe is unavailable.' }
    $output = @(& $tool @Arguments 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('Windows rejected the power-plan operation (exit ' + $code + '): ' + ($output -join ' ')) }
    return ($output -join "`n")
}
function ConvertTo-PerformanceGuid {
    param([string]$Value)
    $guid = [Guid]::Empty
    if (-not [Guid]::TryParse($Value, [ref]$guid)) { throw 'Invalid power-plan identifier.' }
    return $guid.ToString('D')
}
function Get-PerformanceActivePowerPlan {
    $text = Invoke-PerformancePowerCfg -Arguments @('/getactivescheme')
    $matches = [regex]::Matches($text, '(?i)\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b')
    if ($matches.Count -ne 1) { throw 'Could not identify the active Windows power plan.' }
    return (ConvertTo-PerformanceGuid $matches[0].Value)
}
function Get-PerformancePowerPlans {
    Assert-PerformancePlatform
    $text = Invoke-PerformancePowerCfg -Arguments @('/list')
    $active = Get-PerformanceActivePowerPlan
    foreach ($line in ($text -split '\r?\n')) {
        if ($line -match '(?i)\b(?<id>[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})\s+\((?<name>.*)\)\s*\*?\s*$') {
            $id = ConvertTo-PerformanceGuid $Matches.id
            $kind = 'Other'
            if ($id -eq $script:BalancedId) { $kind = 'Balanced' }
            if ($id -eq $script:HighPerformanceId) { $kind = 'HighPerformance' }
            [pscustomobject]@{ Id = $id; Name = [string]$Matches.name; Active = ($id -eq $active); Kind = $kind }
        }
    }
}
function Set-PerformancePowerPlan {
    param([string]$Id)
    $id = ConvertTo-PerformanceGuid $Id
    if (@(Get-PerformancePowerPlans | Where-Object { $_.Id -ieq $id }).Count -ne 1) {
        throw 'The saved/requested power plan no longer exists. No replacement plan was created.'
    }
    [void](Invoke-PerformancePowerCfg -Arguments @('/setactive', $id))
}

function Resolve-PerformanceLocalPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw 'Choose an absolute local path.' }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and
        [IO.Path]::GetPathRoot($Path) -notmatch '^[A-Za-z]:[\\/]$') { throw 'Choose a full drive-letter path, such as C:\Games\Game.exe.' }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\')) { throw 'Network/device paths are not supported.' }
    $drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($full))
    if ($drive.DriveType -eq [IO.DriveType]::Network) { throw 'Network drives are not supported.' }
    $ancestor = $full
    while (-not [string]::IsNullOrEmpty($ancestor)) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links or junctions are not supported in this path.' }
        }
        $parent = [IO.Path]::GetDirectoryName($ancestor)
        if ($parent -eq $ancestor) { break }
        $ancestor = $parent
    }
    return $full
}
function Resolve-PerformanceExecutable {
    param([string]$Executable, [switch]$AllowMissing)
    $full = Resolve-PerformanceLocalPath $Executable
    if ([IO.Path]::GetExtension($full) -ine '.exe') { throw 'Choose the actual game .exe file, not a shortcut or launcher URI.' }
    if (Test-Path -LiteralPath $full) {
        if ((Get-Item -LiteralPath $full -Force -ErrorAction Stop).PSIsContainer) { throw 'The selected executable is a directory.' }
    } elseif (-not $AllowMissing) { throw 'The selected game executable does not exist.' }
    return $full
}
function Resolve-PerformanceBackupRoot {
    param([string]$BackupRoot, [switch]$Create)
    if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA is unavailable.' }
        $BackupRoot = Join-Path $env:LOCALAPPDATA 'Win11GamingHelper\PerformanceBackups'
    }
    $resolved = Resolve-PerformanceLocalPath $BackupRoot
    if ($resolved -ieq [IO.Path]::GetPathRoot($resolved)) { throw 'Use a dedicated backup folder, not a drive root.' }
    $full = $resolved.TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (Test-Path -LiteralPath $full) {
        if (-not (Get-Item -LiteralPath $full -Force -ErrorAction Stop).PSIsContainer) { throw 'The backup root must be a directory.' }
    } elseif ($Create) { [void][IO.Directory]::CreateDirectory($full) }
    return $full
}
function Get-PerformanceGpuState {
    param([string]$Executable)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:GpuPath, $false)
    try {
        if ($null -eq $key -or @($key.GetValueNames()) -notcontains $Executable) {
            return [pscustomobject]@{ Exists = $false; Kind = $null; Value = $null }
        }
        return [pscustomobject]@{
            Exists = $true; Kind = $key.GetValueKind($Executable).ToString()
            Value = $key.GetValue($Executable, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
    } finally { if ($null -ne $key) { $key.Dispose() } }
}
function Set-PerformanceGpuState {
    param([string]$Executable, $State)
    if (-not $State.Exists) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:GpuPath, $true)
        try { if ($null -ne $key) { $key.DeleteValue($Executable, $false); $key.Flush() } }
        finally { if ($null -ne $key) { $key.Dispose() } }
        return
    }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:GpuPath)
    try { $key.SetValue($Executable, [string]$State.Value, [Microsoft.Win32.RegistryValueKind]::String); $key.Flush() }
    finally { if ($null -ne $key) { $key.Dispose() } }
}
function Assert-PerformanceGpuState {
    param($State)
    if ($null -eq $State -or $State.Exists -isnot [bool]) { throw 'Invalid GPU preference state.' }
    if (-not $State.Exists) {
        if ($null -ne $State.Kind -or $null -ne $State.Value) { throw 'Invalid absent GPU preference.' }
    } elseif ($State.Kind -cne 'String' -or $State.Value -isnot [string] -or $State.Value.Length -gt 32768) {
        throw 'The existing/saved GPU preference has an unfamiliar type or length; left untouched.'
    }
}
function Merge-PerformanceGpuPreference {
    param([string]$Value)
    $pattern = '(?i)(?<prefix>^|;)(?<space>\s*)GpuPreference\s*=[^;]*(?=;|$)'
    if ([regex]::IsMatch($Value, $pattern)) {
        return [regex]::Replace($Value, $pattern, '${prefix}${space}GpuPreference=2')
    }
    if ([string]::IsNullOrEmpty($Value)) { return 'GpuPreference=2;' }
    if ($Value.EndsWith(';')) { return $Value + 'GpuPreference=2;' }
    return $Value + ';GpuPreference=2;'
}
function Get-PerformanceGamePreference {
    param([Parameter(Mandatory = $true)][string]$Executable)
    Assert-PerformancePlatform
    $full = Resolve-PerformanceExecutable $Executable
    $state = Get-PerformanceGpuState -Executable $full
    Assert-PerformanceGpuState $state
    [pscustomobject]@{
        Executable = $full; Exists = $state.Exists; Kind = $state.Kind; Value = $state.Value
        HighPerformance = ($state.Exists -and [string]$state.Value -ceq (Merge-PerformanceGpuPreference ([string]$state.Value)))
    }
}
function Test-PerformanceStateEqual {
    param($Left, $Right)
    return ([bool]$Left.Exists -eq [bool]$Right.Exists -and [string]$Left.Kind -ceq [string]$Right.Kind -and [string]$Left.Value -ceq [string]$Right.Value)
}
function Get-PerformanceActionState {
    param([string]$Action, [string]$Target)
    if ($Action -eq 'GameGpu') { return (Get-PerformanceGpuState -Executable $Target) }
    return [pscustomobject]@{ Exists = $true; Kind = 'PowerPlan'; Value = (Get-PerformanceActivePowerPlan) }
}
function Set-PerformanceActionState {
    param([string]$Action, [string]$Target, $State)
    if ($Action -eq 'GameGpu') { Set-PerformanceGpuState -Executable $Target -State $State }
    else { Set-PerformancePowerPlan -Id ([string]$State.Value) }
}
function Save-PerformanceJournal {
    param($Journal, [string]$Path)
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $stream = $null
    try {
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($Journal | ConvertTo-Json -Depth 8))
        $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true); $stream.Dispose(); $stream = $null
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}
function New-PerformanceSummary {
    param([string]$Action, [string]$Target, [string]$Status, [string]$Message, [string]$BackupPath, [bool]$Preview)
    [pscustomobject]@{
        BackupPath = $BackupPath; Preview = $Preview
        Results = @([pscustomobject]@{ TweakId = $Action; Path = $Target; Name = $Action; Status = $Status; Message = $Message })
        Changed = [int]($Status -in @('Applied', 'Restored'))
        Skipped = [int]($Status -notin @('Applied', 'Restored', 'Failed'))
        Failed = [int]($Status -eq 'Failed')
    }
}
function Invoke-PerformanceAction {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('BalancedPower', 'HighPerformancePower', 'GameGpu')][string]$Action,
        [string]$Executable, [string]$BackupRoot
    )
    Assert-PerformancePlatform
    # ValidateSet accepts case-insensitive input; journals keep one canonical spelling.
    foreach ($allowedAction in @('BalancedPower', 'HighPerformancePower', 'GameGpu')) {
        if ($Action -ieq $allowedAction) { $Action = $allowedAction; break }
    }
    $mutex = $null; $journalPath = $null
    try {
        if (-not $WhatIfPreference) { $mutex = Enter-PerformanceLock }
        $target = 'ActivePowerPlan'
        if ($Action -eq 'GameGpu') { $target = Resolve-PerformanceExecutable $Executable }
        $before = Get-PerformanceActionState -Action $Action -Target $target
        if ($Action -eq 'GameGpu') {
            Assert-PerformanceGpuState $before
            $desired = [pscustomobject]@{ Exists = $true; Kind = 'String'; Value = (Merge-PerformanceGpuPreference ([string]$before.Value)) }
            $effect = 'Set per-game High performance GPU preference; other GPU options are preserved. On a single-GPU 14900KF PC this may make no difference.'
        } else {
            $id = $script:BalancedId
            if ($Action -eq 'HighPerformancePower') { $id = $script:HighPerformanceId }
            if (@(Get-PerformancePowerPlans | Where-Object { $_.Id -ieq $id }).Count -ne 1) {
                throw 'This power plan is not present. Modern Standby/OEM systems may support only Balanced; no plan was created.'
            }
            $desired = [pscustomobject]@{ Exists = $true; Kind = 'PowerPlan'; Value = $id }
            $effect = 'Select the existing Balanced power plan. Usually the suitable starting point for a modern hybrid CPU.'
            if ($Action -eq 'HighPerformancePower') { $effect = 'Try the existing High performance power plan. Can increase heat, power use and fan noise on your 14900KF; may not improve FPS. Applies to the active PC power plan.' }
        }
        if (Test-PerformanceStateEqual $before $desired) { return (New-PerformanceSummary $Action $target 'Unchanged' 'Already configured; no backup or write needed.' $null ([bool]$WhatIfPreference)) }
        if (-not $PSCmdlet.ShouldProcess($target, $effect)) {
            return (New-PerformanceSummary $Action $target 'Preview' ($effect + ' Current: ' + [string]$before.Value + ' -> ' + [string]$desired.Value) $null ([bool]$WhatIfPreference))
        }
        $root = Resolve-PerformanceBackupRoot -BackupRoot $BackupRoot -Create
        $identity = Get-PerformanceIdentity; $session = [Guid]::NewGuid().ToString('D')
        $journalPath = Join-Path $root ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + $session + '.json')
        $journal = [pscustomobject]@{
            Schema = 'Win11GamingHelper.Performance/1'; SessionId = $session; CreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
            Sid = $identity.Sid; Machine = $identity.Machine; Action = $Action; Target = $target
            Before = $before; Applied = $desired; Status = 'Pending'; RestoreStatus = $null
        }
        Save-PerformanceJournal -Journal $journal -Path $journalPath
        if (-not (Test-PerformanceStateEqual (Get-PerformanceActionState $Action $target) $before)) {
            $journal.Status = 'Conflict'; Save-PerformanceJournal $journal $journalPath
            return (New-PerformanceSummary $Action $target 'Conflict' 'Preference changed while backup was written; left untouched.' $journalPath $false)
        }
        $status = 'Applied'; $message = $effect + ' Previous state saved.'
        try {
            Set-PerformanceActionState -Action $Action -Target $target -State $desired
            if (-not (Test-PerformanceStateEqual (Get-PerformanceActionState $Action $target) $desired)) { throw 'Windows did not retain the requested setting.' }
            $journal.Status = 'Applied'
        } catch { $status = 'Failed'; $message = $_.Exception.Message; $journal.Status = 'Failed' }
        Save-PerformanceJournal -Journal $journal -Path $journalPath
        return (New-PerformanceSummary $Action $target $status $message $journalPath $false)
    } catch {
        $message = $_.Exception.Message
        if ($journalPath) { $message += ' Backup: ' + $journalPath + '. Review Undo before more changes.' }
        throw $message
    } finally { if ($null -ne $mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() } }
}
function Read-PerformanceJournal {
    param([string]$Path, [string]$BackupRoot)
    $root = Resolve-PerformanceBackupRoot -BackupRoot $BackupRoot
    $full = Resolve-PerformanceLocalPath $Path
    if ([IO.Path]::GetDirectoryName($full) -ine $root -or [IO.Path]::GetExtension($full) -ine '.json') { throw 'Select a JSON backup directly inside the performance backup folder.' }
    $file = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 1048576) { throw 'The backup must be a regular JSON file smaller than 1 MB.' }
    $journal = Get-Content -LiteralPath $full -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $identity = Get-PerformanceIdentity
    if ($journal.Schema -cne 'Win11GamingHelper.Performance/1' -or $journal.Sid -cne $identity.Sid -or $journal.Machine -ine $identity.Machine) { throw 'This backup belongs to another user/computer or uses an unknown format.' }
    $session = [Guid]::Empty
    if (-not [Guid]::TryParse([string]$journal.SessionId, [ref]$session)) { throw 'Invalid backup session.' }
    if ($journal.Action -cnotin @('BalancedPower', 'HighPerformancePower', 'GameGpu') -or $journal.Status -cnotin @('Pending', 'Applied', 'Failed', 'Conflict')) { throw 'Unknown action or status in backup.' }
    if ($null -ne $journal.RestoreStatus -and $journal.RestoreStatus -cnotin @('Pending', 'Restored', 'AlreadyOriginal', 'Conflict', 'Failed')) { throw 'Invalid restore status.' }
    if ($journal.Action -ceq 'GameGpu') {
        $target = Resolve-PerformanceExecutable -Executable ([string]$journal.Target) -AllowMissing
        if ($target -cne [string]$journal.Target) { throw 'The saved game path is not canonical.' }
        Assert-PerformanceGpuState $journal.Before; Assert-PerformanceGpuState $journal.Applied
        if (-not $journal.Applied.Exists -or [string]$journal.Applied.Value -cne (Merge-PerformanceGpuPreference ([string]$journal.Before.Value))) { throw 'Unexpected GPU preference in backup.' }
    } else {
        if ($journal.Target -cne 'ActivePowerPlan') { throw 'Unexpected power target in backup.' }
        foreach ($state in @($journal.Before, $journal.Applied)) {
            if ($state.Exists -isnot [bool] -or -not $state.Exists -or $state.Kind -cne 'PowerPlan' -or $state.Value -isnot [string]) { throw 'Invalid power-plan state in backup.' }
            if ([string]$state.Value -cne (ConvertTo-PerformanceGuid ([string]$state.Value))) { throw 'Power-plan GUID is not canonical.' }
        }
        $expected = $script:BalancedId
        if ($journal.Action -ceq 'HighPerformancePower') { $expected = $script:HighPerformanceId }
        if ($journal.Applied.Value -cne $expected) { throw 'Unexpected power plan in backup.' }
    }
    return [pscustomobject]@{ Path = $full; Journal = $journal }
}
function Restore-PerformanceBackup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory = $true)][string]$Path, [string]$BackupRoot)
    Assert-PerformancePlatform
    $mutex = $null
    try {
        if (-not $WhatIfPreference) { $mutex = Enter-PerformanceLock }
        $saved = Read-PerformanceJournal -Path $Path -BackupRoot $BackupRoot
        $journal = $saved.Journal; $action = [string]$journal.Action; $target = [string]$journal.Target
        if ($journal.RestoreStatus -in @('Restored', 'AlreadyOriginal', 'Conflict') -or $journal.Status -eq 'Conflict') {
            $status = 'AlreadyRestored'; $message = 'This backup was already handled; newer choices are preserved.'
            if ($journal.RestoreStatus -eq 'Conflict' -or $journal.Status -eq 'Conflict') { $status = 'Conflict'; $message = 'An external change was previously detected; this backup will not overwrite it.' }
            return (New-PerformanceSummary $action $target $status $message $saved.Path ([bool]$WhatIfPreference))
        }
        $current = Get-PerformanceActionState $action $target
        if (Test-PerformanceStateEqual $current $journal.Before) {
            if (-not $WhatIfPreference) { $journal.RestoreStatus = 'AlreadyOriginal'; Save-PerformanceJournal $journal $saved.Path }
            return (New-PerformanceSummary $action $target 'AlreadyOriginal' 'The saved original state is already present.' $saved.Path ([bool]$WhatIfPreference))
        }
        if (-not (Test-PerformanceStateEqual $current $journal.Applied)) {
            if (-not $WhatIfPreference) { $journal.RestoreStatus = 'Conflict'; Save-PerformanceJournal $journal $saved.Path }
            return (New-PerformanceSummary $action $target 'Conflict' 'The setting changed afterward; left untouched.' $saved.Path ([bool]$WhatIfPreference))
        }
        if (-not $PSCmdlet.ShouldProcess($target, 'Restore saved original performance preference')) {
            return (New-PerformanceSummary $action $target 'Preview' 'Would restore the original saved preference.' $saved.Path ([bool]$WhatIfPreference))
        }
        $journal.RestoreStatus = 'Pending'; Save-PerformanceJournal $journal $saved.Path
        if (-not (Test-PerformanceStateEqual (Get-PerformanceActionState $action $target) $journal.Applied)) {
            $journal.RestoreStatus = 'Conflict'; Save-PerformanceJournal $journal $saved.Path
            return (New-PerformanceSummary $action $target 'Conflict' 'Setting changed while restore was prepared; left untouched.' $saved.Path $false)
        }
        $status = 'Restored'; $message = 'Restored the exact saved original preference.'
        try {
            Set-PerformanceActionState -Action $action -Target $target -State $journal.Before
            if (-not (Test-PerformanceStateEqual (Get-PerformanceActionState $action $target) $journal.Before)) { throw 'Could not verify the restored original preference.' }
            $journal.RestoreStatus = 'Restored'
        } catch { $journal.RestoreStatus = 'Failed'; $status = 'Failed'; $message = $_.Exception.Message }
        Save-PerformanceJournal $journal $saved.Path
        return (New-PerformanceSummary $action $target $status $message $saved.Path $false)
    } finally { if ($null -ne $mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() } }
}
function Get-PerformanceBackups {
    param([string]$BackupRoot)
    $root = Resolve-PerformanceBackupRoot -BackupRoot $BackupRoot
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Filter '*.json' -ErrorAction Stop | Sort-Object Name -Descending)) {
        try {
            $saved = Read-PerformanceJournal -Path $file.FullName -BackupRoot $root
            $status = [string]$saved.Journal.Status
            if ($null -ne $saved.Journal.RestoreStatus) { $status = [string]$saved.Journal.RestoreStatus }
            [pscustomobject]@{ Path = $saved.Path; CreatedUtc = [string]$saved.Journal.CreatedUtc; Status = $status; Count = 1; Action = [string]$saved.Journal.Action }
        } catch { Write-Verbose ('Ignored invalid performance backup ' + $file.Name + ': ' + $_.Exception.Message) }
    }
}
Export-ModuleMember -Function Get-PerformancePowerPlans, Get-PerformanceGamePreference, Invoke-PerformanceAction, Restore-PerformanceBackup, Get-PerformanceBackups
