# Compatible with Windows PowerShell 5.1; no installation or administrator rights required.
Set-StrictMode -Version 2.0

function Get-GamingDefinitions {
    @(
        [pscustomobject]@{
            Id = 'game-mode'; Name = 'Enable Windows Game Mode'
            Category = 'Gaming'; Impact = 'Game-dependent'; Recommended = $true
            Description = 'Let Windows prioritize the game while you play.'
            Tradeoff = 'Uses the Windows Game Mode setting. Benefits depend on the game and background load.'
            Values = @(
                @{ Path = 'Software\Microsoft\GameBar'; Name = 'AllowAutoGameMode'; Value = 1 },
                @{ Path = 'Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Value = 1 }
            )
        },
        [pscustomobject]@{
            Id = 'background-capture'; Name = 'Turn off Windows game capture'
            Category = 'Gaming'; Impact = 'Recording overhead'; Recommended = $false
            Description = 'Disable Windows game recording and background capture for this user.'
            Tradeoff = 'Windows game clips and recording will stop working until restored. NVIDIA recording is separate.'
            Values = @(
                @{ Path = 'Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled'; Value = 0 },
                @{ Path = 'System\GameConfigStore'; Name = 'GameDVR_Enabled'; Value = 0 }
            )
        },
        [pscustomobject]@{
            Id = 'suggestions'; Name = 'Reduce Windows suggestions'
            Category = 'Clutter'; Impact = 'No FPS promise'; Recommended = $false
            Description = 'Turn off several promotional suggestions and automatic suggested-app delivery for this user.'
            Tradeoff = 'A convenience and clutter change; it does not promise higher FPS. Some Windows builds ignore these settings.'
            Values = @(
                @{ Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0 },
                @{ Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Value = 0 },
                @{ Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Value = 0 },
                @{ Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Value = 0 },
                @{ Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Value = 0 }
            )
        },
        [pscustomobject]@{
            Id = 'hide-widgets'; Name = 'Hide the Widgets taskbar button'
            Category = 'Clutter'; Impact = 'Cosmetic'; Recommended = $false
            Description = 'Hide the Widgets button for this user. Windows may require signing out before it updates.'
            Tradeoff = 'Cosmetic only. It does not uninstall Widgets or stop its background components; builds may ignore it.'
            Values = @(@{ Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Value = 0 })
        },
        [pscustomobject]@{
            Id = 'reduce-transparency'; Name = 'Turn off desktop transparency'
            Category = 'Desktop effects'; Impact = 'Desktop responsiveness'; Recommended = $false
            Description = 'Use opaque Windows surfaces instead of transparent desktop effects.'
            Tradeoff = 'Changes desktop appearance; a modern gaming GPU may show no measurable game FPS difference.'
            Values = @(@{ Path = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; Value = 0 })
        },
        [pscustomobject]@{
            Id = 'reduce-animations'; Name = 'Reduce window minimize animations'
            Category = 'Desktop effects'; Impact = 'Desktop responsiveness'; Recommended = $false
            Description = 'Turn off the minimize and maximize window animation preference.'
            Tradeoff = 'This does not disable every Windows animation or improve in-game FPS. Sign out and back in for it to refresh.'
            Values = @(@{ Path = 'Control Panel\Desktop\WindowMetrics'; Name = 'MinAnimate'; Kind = 'String'; Value = '0' })
        },
        [pscustomobject]@{
            Id = 'mouse-acceleration'; Name = 'Turn off Windows pointer acceleration'
            Category = 'Input'; Impact = 'Input preference'; Recommended = $false
            Description = 'Disable Enhance pointer precision for the Windows pointer and games that use that pointer path.'
            Tradeoff = 'Pointer feel changes. Games using raw mouse input usually ignore this preference; it is not an FPS tweak. Sign out and back in to refresh.'
            Values = @(
                @{ Path = 'Control Panel\Mouse'; Name = 'MouseSpeed'; Kind = 'String'; Value = '0' },
                @{ Path = 'Control Panel\Mouse'; Name = 'MouseThreshold1'; Kind = 'String'; Value = '0' },
                @{ Path = 'Control Panel\Mouse'; Name = 'MouseThreshold2'; Kind = 'String'; Value = '0' }
            )
        },
        [pscustomobject]@{
            Id = 'controller-gamebar'; Name = 'Stop controller button opening Game Bar'
            Category = 'Input'; Impact = 'Avoid interruptions'; Recommended = $false
            Description = 'Stop the controller Xbox button from opening Windows Game Bar.'
            Tradeoff = 'The controller shortcut stops working. Game Bar stays installed; some builds or controller software may handle the button separately.'
            Values = @(@{ Path = 'Software\Microsoft\GameBar'; Name = 'UseNexusForGameBarEnabled'; Value = 0 })
        },
        [pscustomobject]@{
            Id = 'search-web'; Name = 'Reduce web suggestions in Windows Search'
            Category = 'Clutter'; Impact = 'Search preference'; Recommended = $false
            Description = 'Request fewer online search suggestions through the current-user Explorer search policy.'
            Tradeoff = 'Online suggestions may disappear; local search stays available. Windows may require sign-out or ignore this policy. No gaming FPS benefit is promised.'
            Values = @(@{ Path = 'Software\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Value = 1 })
        }
    )
}

function Get-GamingTweaks {
    foreach ($definition in Get-GamingDefinitions) {
        [pscustomobject]@{
            Id = $definition.Id; Name = $definition.Name
            Description = $definition.Description; Tradeoff = $definition.Tradeoff
            Category = $definition.Category; Impact = $definition.Impact; Recommended = $definition.Recommended
        }
    }
}

function Get-GamingDesiredState {
    param([hashtable]$Setting)
    # Earlier schema-1 definitions implied DWORD. Keep those journals compatible.
    $kind = 'DWord'
    if ($Setting.ContainsKey('Kind')) { $kind = [string]$Setting.Kind }
    switch ($kind) {
        'DWord' { $value = [int]$Setting.Value }
        'String' { $value = [string]$Setting.Value }
        default { throw 'Unsupported target type in the built-in settings catalog.' }
    }
    [pscustomobject]@{ Exists = $true; Kind = $kind; Value = $value }
}

function Assert-GamingPlatform {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        [Environment]::OSVersion.Version.Build -lt 22000) {
        throw 'This utility supports Windows 11 only. No changes were made.'
    }
}

function Get-GamingIdentity {
    [pscustomobject]@{
        Sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        Machine = [Environment]::MachineName
    }
}

function Get-GamingDefaultBackupRoot {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA is unavailable.' }
    Join-Path $env:LOCALAPPDATA 'Win11GamingHelper\Backups'
}

function Resolve-GamingBackupRoot {
    param([string]$BackupRoot, [switch]$Create)
    if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $BackupRoot = Get-GamingDefaultBackupRoot }
    $full = [IO.Path]::GetFullPath($BackupRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($full.StartsWith('\\') -or -not [IO.Path]::IsPathRooted($full)) {
        throw 'Backups must be kept in a local directory, not a network share.'
    }
    # Reject junctions/symlinks anywhere in the destination, not just its leaf.
    $ancestor = $full
    while (-not [string]::IsNullOrEmpty($ancestor)) {
        if (Test-Path -LiteralPath $ancestor) {
            $ancestorItem = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
            if ($ancestorItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'The backup directory cannot contain a link or junction in its path.'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($ancestor)
        if ($parent -eq $ancestor) { break }
        $ancestor = $parent
    }
    if (Test-Path -LiteralPath $full) {
        $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'The backup directory must be a regular local directory, not a link.'
        }
    } elseif ($Create) {
        [void][IO.Directory]::CreateDirectory($full)
    }
    $full
}

function Enter-GamingLock {
    $identity = Get-GamingIdentity
    $mutex = New-Object Threading.Mutex($false, ('Local\Win11GamingHelper_' + $identity.Sid))
    try {
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Another apply or restore operation is running. Close it and try again.' }
        $mutex
    } catch { $mutex.Dispose(); throw }
}

function Get-GamingRegistryState {
    param([string]$Path, [string]$Name)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path, $false)
    try {
        if ($null -eq $key -or @($key.GetValueNames()) -notcontains $Name) {
            return [pscustomobject]@{ Exists = $false; Kind = $null; Value = $null }
        }
        [pscustomobject]@{
            Exists = $true
            Kind = $key.GetValueKind($Name).ToString()
            Value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
    } finally { if ($null -ne $key) { $key.Dispose() } }
}

function Test-GamingStateEqual {
    param($Left, $Right)
    if ([bool]$Left.Exists -ne [bool]$Right.Exists) { return $false }
    if (-not $Left.Exists) { return $true }
    if ([string]$Left.Kind -cne [string]$Right.Kind) { return $false }
    $leftValues = @($Left.Value); $rightValues = @($Right.Value)
    if ($leftValues.Count -ne $rightValues.Count) { return $false }
    for ($i = 0; $i -lt $leftValues.Count; $i++) {
        if ([string]$leftValues[$i] -cne [string]$rightValues[$i]) { return $false }
    }
    return $true
}

function Set-GamingRegistryState {
    param([string]$Path, [string]$Name, $State)
    if (-not $State.Exists) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path, $true)
        try { if ($null -ne $key) { $key.DeleteValue($Name, $false); $key.Flush() } }
        finally { if ($null -ne $key) { $key.Dispose() } }
        return
    }
    $kind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$State.Kind)
    switch ([string]$State.Kind) {
        'DWord' { $value = [int]$State.Value }
        'QWord' { $value = [long]$State.Value }
        'Binary' { $value = [byte[]]@($State.Value) }
        'None' { $value = [byte[]]@($State.Value) }
        'MultiString' { $value = [string[]]@($State.Value) }
        default { $value = [string]$State.Value }
    }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Path)
    try { $key.SetValue($Name, $value, $kind); $key.Flush() }
    finally { if ($null -ne $key) { $key.Dispose() } }
}

function Save-GamingJournal {
    param($Journal, [string]$Path)
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $stream = $null
    try {
        $json = $Journal | ConvertTo-Json -Depth 12
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($json)
        $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose(); $stream = $null
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function New-GamingResult {
    param([string]$TweakId, [string]$Path, [string]$Name, [string]$Status, [string]$Message)
    [pscustomobject]@{ TweakId = $TweakId; Path = $Path; Name = $Name; Status = $Status; Message = $Message }
}

function New-GamingSummary {
    param([string]$BackupPath, [object[]]$Results, [bool]$Preview)
    [pscustomobject]@{
        BackupPath = $BackupPath; Results = @($Results); Preview = $Preview
        Changed = @($Results | Where-Object { $_.Status -in @('Applied', 'Restored') }).Count
        Failed = @($Results | Where-Object { $_.Status -eq 'Failed' }).Count
        Skipped = @($Results | Where-Object { $_.Status -notin @('Applied', 'Restored', 'Failed') }).Count
    }
}

function Invoke-GamingPlan {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory = $true)][string[]]$Ids, [string]$BackupRoot)
    Assert-GamingPlatform
    $definitions = @(Get-GamingDefinitions)
    foreach ($id in $Ids) {
        if (@($definitions | Where-Object { $_.Id -ceq $id }).Count -ne 1) { throw "Unknown tweak ID: $id" }
    }
    $selected = @($definitions | Where-Object { $Ids -ccontains $_.Id })
    if ($selected.Count -eq 0) { throw 'Choose at least one tweak.' }
    $results = New-Object 'System.Collections.Generic.List[object]'
    $journalPath = $null; $journal = $null; $mutex = $null
    try {
        if (-not $WhatIfPreference) { $mutex = Enter-GamingLock }
        foreach ($definition in $selected) {
            foreach ($setting in $definition.Values) {
                $before = Get-GamingRegistryState -Path $setting.Path -Name $setting.Name
                $after = Get-GamingDesiredState -Setting $setting
                if (Test-GamingStateEqual $before $after) {
                    $results.Add((New-GamingResult $definition.Id $setting.Path $setting.Name 'Unchanged' 'Already set.'))
                    continue
                }
                $targetText = $after.Kind + ': ' + (ConvertTo-Json -InputObject $after.Value -Compress -Depth 4)
                if (-not $PSCmdlet.ShouldProcess(('HKCU\' + $setting.Path + '\' + $setting.Name), ('Set ' + $targetText))) {
                    $beforeText = 'absent'
                    if ($before.Exists) { $beforeText = $before.Kind + ': ' + (ConvertTo-Json -InputObject $before.Value -Compress -Depth 4) }
                    $results.Add((New-GamingResult $definition.Id $setting.Path $setting.Name 'Preview' ($beforeText + ' -> ' + $targetText)))
                    continue
                }
                if ($null -eq $journal) {
                    $root = Resolve-GamingBackupRoot -BackupRoot $BackupRoot -Create
                    $identity = Get-GamingIdentity
                    $session = [Guid]::NewGuid().ToString('D')
                    $journalPath = Join-Path $root ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + $session + '.json')
                    $journal = [pscustomobject]@{
                        Schema = 'Win11GamingHelper.Backup/1'; SessionId = $session
                        CreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
                        Sid = $identity.Sid; Machine = $identity.Machine; Status = 'Applying'; Entries = @()
                    }
                }
                $entry = [pscustomobject]@{
                    TweakId = $definition.Id; Path = $setting.Path; Name = $setting.Name
                    Before = $before; Applied = $after; Status = 'Pending'; RestoreStatus = $null
                }
                $journal.Entries = @($journal.Entries) + @($entry)
                # This must succeed before touching the registry. Pending entries are recoverable.
                Save-GamingJournal -Journal $journal -Path $journalPath
                $latest = Get-GamingRegistryState -Path $setting.Path -Name $setting.Name
                if (-not (Test-GamingStateEqual $latest $before)) {
                    $entry.Status = 'Conflict'
                    $results.Add((New-GamingResult $definition.Id $setting.Path $setting.Name 'Conflict' 'Value changed while the backup was saved; left untouched.'))
                    Save-GamingJournal -Journal $journal -Path $journalPath
                    continue
                }
                try {
                    Set-GamingRegistryState -Path $setting.Path -Name $setting.Name -State $after
                    if (-not (Test-GamingStateEqual (Get-GamingRegistryState $setting.Path $setting.Name) $after)) {
                        throw 'The value did not retain the requested state; a policy may manage it.'
                    }
                    $entry.Status = 'Applied'
                    $results.Add((New-GamingResult $definition.Id $setting.Path $setting.Name 'Applied' 'Saved original value and applied change.'))
                } catch {
                    $entry.Status = 'Failed'
                    $results.Add((New-GamingResult $definition.Id $setting.Path $setting.Name 'Failed' $_.Exception.Message))
                }
                # A failed save stops the operation. The prior Pending record still holds the original state.
                Save-GamingJournal -Journal $journal -Path $journalPath
            }
        }
        if ($null -ne $journal) {
            $journal.Status = 'Applied'
            if (@($results | Where-Object { $_.Status -in @('Failed', 'Conflict') }).Count -gt 0) { $journal.Status = 'Partial' }
            Save-GamingJournal -Journal $journal -Path $journalPath
        }
        New-GamingSummary -BackupPath $journalPath -Results $results.ToArray() -Preview ([bool]$WhatIfPreference)
    } catch {
        $message = $_.Exception.Message
        if ($journalPath) { $message += " Backup journal: $journalPath. Stop and use Restore before making further changes." }
        throw $message
    } finally {
        if ($null -ne $mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() }
    }
}

function Assert-GamingSavedState {
    param($State)
    if ($null -eq $State -or $State.Exists -isnot [bool]) { throw 'Invalid registry state in backup.' }
    if (-not $State.Exists) {
        if ($null -ne $State.Kind -or $null -ne $State.Value) { throw 'Invalid absent registry state.' }
        return
    }
    if ([string]$State.Kind -notin @('DWord', 'QWord', 'String', 'ExpandString', 'Binary', 'None', 'MultiString')) {
        throw 'Unsupported registry type in backup.'
    }
    switch ([string]$State.Kind) {
        'DWord' { if ($State.Value -isnot [int] -and $State.Value -isnot [long]) { throw 'Invalid DWORD backup value.' }; [void][int]$State.Value }
        'QWord' { if ($State.Value -isnot [int] -and $State.Value -isnot [long]) { throw 'Invalid QWORD backup value.' }; [void][long]$State.Value }
        { $_ -in @('Binary', 'None') } {
            foreach ($part in @($State.Value)) {
                if (($part -isnot [int] -and $part -isnot [long] -and $part -isnot [byte]) -or $part -lt 0 -or $part -gt 255) { throw 'Invalid binary backup value.' }
            }
        }
        'MultiString' { foreach ($part in @($State.Value)) { if ($part -isnot [string]) { throw 'Invalid multi-string backup value.' } } }
        default { if ($State.Value -isnot [string]) { throw 'Invalid string backup value.' } }
    }
}

function Read-GamingJournal {
    param([string]$Path, [string]$BackupRoot)
    $root = Resolve-GamingBackupRoot -BackupRoot $BackupRoot
    $full = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetDirectoryName($full) -ine $root -or [IO.Path]::GetExtension($full) -ine '.json') {
        throw 'Select a JSON backup directly inside the configured backup directory.'
    }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 1048576) {
        throw 'The backup must be a regular JSON file smaller than 1 MB.'
    }
    $journal = Get-Content -LiteralPath $full -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $identity = Get-GamingIdentity
    if ($journal.Schema -cne 'Win11GamingHelper.Backup/1' -or $journal.Sid -cne $identity.Sid -or $journal.Machine -ine $identity.Machine) {
        throw 'This backup belongs to a different computer/user or uses an unsupported format.'
    }
    $guid = [Guid]::Empty
    if (-not [Guid]::TryParse([string]$journal.SessionId, [ref]$guid)) { throw 'Invalid backup session ID.' }
    if ([string]$journal.Status -notin @('Applying', 'Applied', 'Partial', 'Restoring', 'Restored', 'RestorePartial')) { throw 'Invalid backup status.' }
    if (@($journal.Entries).Count -eq 0 -or @($journal.Entries).Count -gt 32) { throw 'Invalid backup entry count.' }
    $definitions = @(Get-GamingDefinitions)
    $seen = @{}
    foreach ($entry in $journal.Entries) {
        $definition = @($definitions | Where-Object { $_.Id -ceq $entry.TweakId })
        if ($definition.Count -ne 1) { throw 'Unknown tweak in backup.' }
        $setting = @($definition[0].Values | Where-Object { $_.Path -ceq $entry.Path -and $_.Name -ceq $entry.Name })
        if ($setting.Count -ne 1) { throw 'Backup contains a registry value outside the supported allowlist.' }
        $key = [string]$entry.Path + '\' + [string]$entry.Name
        if ($seen.ContainsKey($key)) { throw 'Duplicate registry value in backup.' }
        $seen[$key] = $true
        if ([string]$entry.Status -notin @('Pending', 'Applied', 'Failed', 'Conflict')) { throw 'Invalid entry status.' }
        if ($null -ne $entry.RestoreStatus -and [string]$entry.RestoreStatus -notin @('Pending', 'Restored', 'AlreadyOriginal', 'Conflict', 'Failed')) {
            throw 'Invalid restore status.'
        }
        Assert-GamingSavedState $entry.Before
        Assert-GamingSavedState $entry.Applied
        $desired = Get-GamingDesiredState -Setting $setting[0]
        if (-not (Test-GamingStateEqual $entry.Applied $desired)) { throw 'Backup contains an unexpected applied value.' }
    }
    [pscustomobject]@{ Journal = $journal; Path = $full }
}

function Restore-GamingBackup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory = $true)][string]$Path, [string]$BackupRoot)
    Assert-GamingPlatform
    $mutex = $null
    try {
        if (-not $WhatIfPreference) { $mutex = Enter-GamingLock }
        $saved = Read-GamingJournal -Path $Path -BackupRoot $BackupRoot
        $journal = $saved.Journal
        $results = New-Object 'System.Collections.Generic.List[object]'
        $entries = @($journal.Entries)
        [array]::Reverse($entries)
        foreach ($entry in $entries) {
            # A completed or externally changed entry must never become eligible again.
            if ($journal.Status -eq 'Restored' -or $entry.RestoreStatus -in @('Restored', 'AlreadyOriginal', 'Conflict') -or $entry.Status -eq 'Conflict') {
                $status = 'AlreadyRestored'
                $message = 'Entry was already handled; later user choices are preserved.'
                if ($entry.RestoreStatus -eq 'Conflict' -or $entry.Status -eq 'Conflict') {
                    $status = 'Conflict'; $message = 'An external change was previously detected; left untouched.'
                }
                $results.Add((New-GamingResult $entry.TweakId $entry.Path $entry.Name $status $message))
                continue
            }
            $current = Get-GamingRegistryState -Path $entry.Path -Name $entry.Name
            if (Test-GamingStateEqual $current $entry.Before) {
                $results.Add((New-GamingResult $entry.TweakId $entry.Path $entry.Name 'AlreadyOriginal' 'Original state is already present.'))
                if (-not $WhatIfPreference) {
                    $entry.RestoreStatus = 'AlreadyOriginal'
                    Save-GamingJournal -Journal $journal -Path $saved.Path
                }
                continue
            }
            if (-not (Test-GamingStateEqual $current $entry.Applied)) {
                $results.Add((New-GamingResult $entry.TweakId $entry.Path $entry.Name 'Conflict' 'Value changed after the tweak; left untouched.'))
                if (-not $WhatIfPreference) {
                    $entry.RestoreStatus = 'Conflict'
                    Save-GamingJournal -Journal $journal -Path $saved.Path
                }
                continue
            }
            if (-not $PSCmdlet.ShouldProcess(('HKCU\' + $entry.Path + '\' + $entry.Name), 'Restore saved original value')) {
                $results.Add((New-GamingResult $entry.TweakId $entry.Path $entry.Name 'Preview' 'Would restore saved original state.'))
                continue
            }
            $journal.Status = 'Restoring'; $entry.RestoreStatus = 'Pending'
            Save-GamingJournal -Journal $journal -Path $saved.Path
            # Narrow the external-editor race after disk I/O. Registry APIs have no compare-and-swap.
            $latest = Get-GamingRegistryState -Path $entry.Path -Name $entry.Name
            if (-not (Test-GamingStateEqual $latest $entry.Applied)) {
                $entry.RestoreStatus = 'Conflict'
                $results.Add((New-GamingResult $entry.TweakId $entry.Path $entry.Name 'Conflict' 'Value changed while restore was prepared; left untouched.'))
                Save-GamingJournal -Journal $journal -Path $saved.Path
                continue
            }
            try {
                Set-GamingRegistryState -Path $entry.Path -Name $entry.Name -State $entry.Before
                if (-not (Test-GamingStateEqual (Get-GamingRegistryState $entry.Path $entry.Name) $entry.Before)) { throw 'The original state could not be verified.' }
                $entry.RestoreStatus = 'Restored'
                $results.Add((New-GamingResult $entry.TweakId $entry.Path $entry.Name 'Restored' 'Restored the saved original state.'))
            } catch {
                $entry.RestoreStatus = 'Failed'
                $results.Add((New-GamingResult $entry.TweakId $entry.Path $entry.Name 'Failed' $_.Exception.Message))
            }
            Save-GamingJournal -Journal $journal -Path $saved.Path
        }
        if (-not $WhatIfPreference -and $journal.Status -ne 'Restored') {
            $journal.Status = 'Restored'
            if (@($results | Where-Object { $_.Status -in @('Failed', 'Conflict', 'Preview') }).Count -gt 0) { $journal.Status = 'RestorePartial' }
            Save-GamingJournal -Journal $journal -Path $saved.Path
        }
        New-GamingSummary -BackupPath $saved.Path -Results $results.ToArray() -Preview ([bool]$WhatIfPreference)
    } finally {
        if ($null -ne $mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() }
    }
}

function Get-GamingBackups {
    param([string]$BackupRoot)
    $root = Resolve-GamingBackupRoot -BackupRoot $BackupRoot
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction Stop | Sort-Object Name -Descending)) {
        try {
            $saved = Read-GamingJournal -Path $file.FullName -BackupRoot $root
            [pscustomobject]@{
                Path = $saved.Path; CreatedUtc = [string]$saved.Journal.CreatedUtc
                Status = [string]$saved.Journal.Status; Count = @($saved.Journal.Entries).Count
            }
        } catch {
            # Invalid files are not offered for restore; never interpret arbitrary registry instructions.
            Write-Verbose ('Ignored invalid backup ' + $file.Name + ': ' + $_.Exception.Message)
        }
    }
}

function Get-GamingSnapshot {
    Assert-GamingPlatform
    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $os = $cpu = $gpu = $bios = 'Unavailable'; $memory = $null
    $startup = @(); $apps = @(); $gpuDriver = @(); $disks = @()
    $displays = @(); $memoryModules = @(); $powerPlan = 'Unavailable'
    try {
        $system = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $os = [string]$system.Caption + ' (build ' + [string]$system.BuildNumber + ')'
        $memory = [Math]::Round(([double]$system.TotalVisibleMemorySize / 1MB), 1)
    } catch { $warnings.Add('Windows or memory details could not be read: ' + $_.Exception.Message) }
    try { $cpu = (@(Get-CimInstance Win32_Processor -ErrorAction Stop | ForEach-Object { $_.Name.Trim() }) -join ', ') }
    catch { $warnings.Add('CPU details could not be read.') }
    try {
        $adapters = @(Get-CimInstance Win32_VideoController -ErrorAction Stop)
        $gpu = (@($adapters | ForEach-Object { $_.Name }) -join ', ')
        $gpuDriver = @($adapters | Select-Object Name, DriverVersion)
        $displays = @($adapters | ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Width = $_.CurrentHorizontalResolution
                Height = $_.CurrentVerticalResolution
                RefreshHz = $_.CurrentRefreshRate
            }
        })
    }
    catch { $warnings.Add('GPU details could not be read.') }
    try {
        $firmware = Get-CimInstance Win32_BIOS -ErrorAction Stop
        $bios = [string]$firmware.Manufacturer + ' ' + [string]$firmware.SMBIOSBIOSVersion
    } catch { $warnings.Add('BIOS details could not be read.') }
    try {
        $memoryModules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                BankLabel = $_.BankLabel
                CapacityGB = [Math]::Round(([double]$_.Capacity / 1GB), 1)
                ConfiguredMHz = $_.ConfiguredClockSpeed
            }
        })
    } catch { $warnings.Add('Configured memory speed could not be read.') }
    try {
        $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
        $output = @(& $powercfg /getactivescheme 2>&1)
        if ($LASTEXITCODE -ne 0) { throw 'Windows could not read the active power scheme.' }
        $powerPlan = ($output -join ' ').Trim()
    } catch { $warnings.Add('The active power plan could not be read.') }
    try {
        $fixedDrives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)
        $disks = @($fixedDrives | ForEach-Object {
            [pscustomobject]@{
                DeviceID = $_.DeviceID
                SizeGB = [Math]::Round(([double]$_.Size / 1GB), 1)
                FreeGB = [Math]::Round(([double]$_.FreeSpace / 1GB), 1)
            }
        })
        foreach ($drive in $fixedDrives) {
            if ($drive.DeviceID -ieq $env:SystemDrive -and [double]$drive.Size -gt 0 -and
                ([double]$drive.FreeSpace / [double]$drive.Size) -lt 0.10) {
                $warnings.Add('The Windows drive has less than 10% free space. Review storage in Windows Settings; this tool does not delete files.')
            }
        }
    } catch { $warnings.Add('Local drive free space could not be read.') }
    try {
        $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Select-Object Name, Command, Location, User)
    } catch { $warnings.Add('Startup inventory could not be read. Use Settings > Apps > Startup.') }
    try {
        $apps = @(Get-AppxPackage -ErrorAction Stop | Sort-Object Name | Select-Object Name, @{ Name = 'PackageName'; Expression = { $_.PackageFullName } }, Version)
    } catch { $warnings.Add('Microsoft Store app inventory could not be read. Use Settings > Apps > Installed apps.') }
    $warnings.Add('This tool does not measure FPS, CPU/GPU temperatures, or determine whether firmware is current.')
    $warnings.Add('Adapter-reported display modes may omit monitors or show incomplete refresh data. Check Advanced display settings for each monitor.')
    [pscustomobject]@{
        Summary = "$os`r`nCPU: $cpu`r`nGPU: $gpu`r`nMemory: $memory GB`r`nBIOS: $bios"
        OS = $os; CPU = $cpu; GPU = $gpu; GPUDriver = $gpuDriver; MemoryGB = $memory; BIOS = $bios; Disks = $disks
        PowerPlan = $powerPlan; Displays = $displays; MemoryModules = $memoryModules
        Startup = $startup; Apps = $apps; Warnings = $warnings.ToArray()
    }
}

Export-ModuleMember -Function Get-GamingTweaks, Get-GamingSnapshot, Invoke-GamingPlan, Restore-GamingBackup, Get-GamingBackups
