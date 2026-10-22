# Dependency-free safety tests. Registry and identity access are mocked in module scope.
# Run with PowerShell 7 on Linux or Windows; no real registry values are read or changed.
[CmdletBinding()]
param([string]$ModulePath = (Join-Path $PSScriptRoot '..\GamingHelper.Core.psm1'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0
$script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('gaming-helper-tests-' + [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if (($Actual | ConvertTo-Json -Compress -Depth 20) -cne ($Expected | ConvertTo-Json -Compress -Depth 20)) {
        throw ('{0}; expected {1}, received {2}' -f $Message, ($Expected | ConvertTo-Json -Compress -Depth 20), ($Actual | ConvertTo-Json -Compress -Depth 20))
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    if (-not $thrown) { throw $Message }
}

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Passed++
        Write-Host ('PASS ' + $Name)
    } catch {
        $script:Failed++
        Write-Host ('FAIL ' + $Name + ': ' + $_.Exception.Message)
    }
}

Import-Module $ModulePath -Force
$script:Module = Get-Module GamingHelper.Core
if ($null -eq $script:Module) { throw 'The core module did not import.' }

# Replace only the operating-system boundary. JSON validation, atomic persistence,
# target allowlists, ShouldProcess and recovery logic remain the real implementation.
& $script:Module {
    $script:OriginalJournalWriter = (Get-Command Save-GamingJournal).ScriptBlock
    function script:Assert-GamingPlatform { }
    function script:Get-GamingIdentity {
        [pscustomobject]@{ Sid = $script:TestSid; Machine = $script:TestMachine }
    }
    function script:Enter-GamingLock { return $null }
    function script:Get-GamingRegistryState {
        param([string]$Path, [string]$Name)
        $key = $Path + '|' + $Name
        if ($script:TestRegistry.ContainsKey($key)) {
            return ($script:TestRegistry[$key] | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
        }
        [pscustomobject]@{ Exists = $false; Kind = $null; Value = $null }
    }
    function script:Save-GamingJournal {
        param($Journal, [string]$Path)
        $script:TestSaveCount++
        if ($script:TestFailSave -eq $script:TestSaveCount) { throw 'Simulated journal persistence failure.' }
        & $script:OriginalJournalWriter -Journal $Journal -Path $Path
        if ($script:TestRaceSave -eq $script:TestSaveCount) {
            $script:TestRegistry['Software\Microsoft\GameBar|' + $script:TestRaceName] = $script:TestRaceState
        }
    }
    function script:Set-GamingRegistryState {
        param([string]$Path, [string]$Name, $State)
        # Every simulated registry mutation must already have a recoverable record
        # on disk, including the original state. This also tests interrupted saves.
        $covered = $false
        if (Test-Path -LiteralPath $script:TestBackupRoot) {
            foreach ($file in Get-ChildItem -LiteralPath $script:TestBackupRoot -Filter '*.json' -File) {
                $journal = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                foreach ($entry in $journal.Entries) {
                    if ($entry.Path -ceq $Path -and $entry.Name -ceq $Name) {
                        $apply = $entry.Status -ceq 'Pending' -and (Test-GamingStateEqual $State $entry.Applied)
                        $restore = $entry.RestoreStatus -ceq 'Pending' -and (Test-GamingStateEqual $State $entry.Before)
                        if ($apply -or $restore) { $covered = $true }
                    }
                }
            }
        }
        if (-not $covered) { throw 'SAFETY VIOLATION: a registry write had no durable prior journal.' }
        $script:TestWriteCount++
        if ($Name -ceq $script:TestFailSetName) { throw 'Simulated registry access denied.' }
        $key = $Path + '|' + $Name
        if ($State.Exists) {
            $script:TestRegistry[$key] = $State | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        } else { $script:TestRegistry.Remove($key) }
    }
}

function Reset-TestContext {
    $root = Join-Path $script:TestRoot ([guid]::NewGuid().ToString('N'))
    & $script:Module {
        param($Root)
        $script:TestRegistry = @{}
        $script:TestSid = 'S-1-5-21-TEST'
        $script:TestMachine = 'TEST-PC'
        $script:TestWriteCount = 0
        $script:TestSaveCount = 0
        $script:TestFailSave = -1
        $script:TestFailSetName = ''
        $script:TestRaceSave = -1
        $script:TestRaceName = ''
        $script:TestRaceState = $null
        $script:TestBackupRoot = $Root
    } $root
    $root
}

function Set-FakeValue {
    param([string]$Name, $State, [string]$Path = 'Software\Microsoft\GameBar')
    & $script:Module {
        param($N, $S, $P)
        $script:TestRegistry[$P + '|' + $N] = $S
    } $Name $State $Path
}

function Get-TestWrites { & $script:Module { $script:TestWriteCount } }

function Edit-Journal {
    param([string]$Path, [scriptblock]$Edit)
    $journal = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    & $Edit $journal
    $journal | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

try {
    Test-Case 'only nine explicit, explained tweaks are exposed' {
        $catalog = @(Get-GamingTweaks)
        Assert-Equal @($catalog.Id) @('game-mode', 'background-capture', 'suggestions', 'hide-widgets', 'reduce-transparency', 'reduce-animations', 'mouse-acceleration', 'controller-gamebar', 'search-web') 'Unexpected public tweak IDs'
        Assert-Equal @($catalog | Where-Object Recommended | ForEach-Object Id) @('game-mode') 'Unconditional preset includes a tradeoff-sensitive setting'
        foreach ($entry in $catalog) {
            Assert-True (-not [string]::IsNullOrWhiteSpace($entry.Category)) 'Missing category'
            Assert-True (-not [string]::IsNullOrWhiteSpace($entry.Impact)) 'Missing impact explanation'
            Assert-True (-not [string]::IsNullOrWhiteSpace($entry.Tradeoff)) 'Missing tradeoff'
        }
    }

    Test-Case 'unknown and empty selections cannot mutate anything' {
        $root = Reset-TestContext
        Assert-Throws { Invoke-GamingPlan -Ids @('game-mode', 'disable-defender') -BackupRoot $root -Confirm:$false } 'Unknown tweak was accepted'
        Assert-Throws { Invoke-GamingPlan -Ids @() -BackupRoot $root -Confirm:$false } 'Empty selection was accepted'
        Assert-Equal (Get-TestWrites) 0 'Invalid selections wrote registry values'
        Assert-True (-not (Test-Path -LiteralPath $root)) 'Invalid selection created a backup directory'
    }

    Test-Case 'preview never creates backup storage or changes values' {
        $root = Reset-TestContext
        $result = Invoke-GamingPlan -Ids @((Get-GamingTweaks).Id) -BackupRoot $root -WhatIf
        Assert-True $result.Preview 'Preview not identified'
        Assert-Equal @($result.Results).Count 17 'Preview did not cover the selected settings'
        Assert-Equal (Get-TestWrites) 0 'Preview wrote registry values'
        Assert-True (-not (Test-Path -LiteralPath $root)) 'Preview created backup storage'
    }

    Test-Case 'apply persists original values before each mutation and restores absent values' {
        $root = Reset-TestContext
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        Assert-Equal $result.Changed 2 'Expected two applied Game Mode values'
        Assert-Equal (Get-TestWrites) 2 'Unexpected registry write count'
        Assert-True (Test-Path -LiteralPath $result.BackupPath) 'No persistent journal created'
        $restored = Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false
        Assert-Equal $restored.Changed 2 'Expected two restored values'
        $left = & $script:Module { $script:TestRegistry.Count }
        Assert-Equal $left 0 'Originally absent values were not removed'
    }

    Test-Case 'already configured values need no backup or registry write' {
        $root = Reset-TestContext
        $desired = [pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = 1 }
        Set-FakeValue 'AllowAutoGameMode' $desired
        Set-FakeValue 'AutoGameModeEnabled' $desired
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        Assert-Equal $result.Changed 0 'Unchanged preferences were written'
        Assert-Equal (Get-TestWrites) 0 'Unchanged preferences triggered writes'
        Assert-True (-not (Test-Path -LiteralPath $root)) 'Unchanged preferences created a backup'
    }

    Test-Case 'string input and animation preferences retain their required registry types' {
        $root = Reset-TestContext
        $mousePath = 'Control Panel\Mouse'
        $windowPath = 'Control Panel\Desktop\WindowMetrics'
        Set-FakeValue 'MouseSpeed' ([pscustomobject]@{Exists=$true;Kind='String';Value='1'}) $mousePath
        Set-FakeValue 'MouseThreshold1' ([pscustomobject]@{Exists=$true;Kind='String';Value='6'}) $mousePath
        Set-FakeValue 'MouseThreshold2' ([pscustomobject]@{Exists=$true;Kind='String';Value='10'}) $mousePath
        Set-FakeValue 'MinAnimate' ([pscustomobject]@{Exists=$true;Kind='String';Value='1'}) $windowPath
        $result = Invoke-GamingPlan -Ids @('mouse-acceleration','reduce-animations') -BackupRoot $root -Confirm:$false
        Assert-Equal $result.Changed 4 'Typed preferences were not all applied'
        $applied = & $script:Module { @($script:TestRegistry.Values) }
        foreach ($state in $applied) {
            Assert-Equal $state.Kind 'String' 'A string target was converted to DWORD'
            Assert-Equal $state.Value '0' 'A string preference has the wrong target'
            Assert-True ($state.Value -is [string]) 'The target value lost its string type'
        }
        $restored = Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false
        Assert-Equal $restored.Changed 4 'Typed preferences did not restore'
        $mouse = & $script:Module { Get-GamingRegistryState 'Control Panel\Mouse' 'MouseThreshold2' }
        Assert-Equal $mouse.Value '10' 'Mouse threshold original was lost'
        $animation = & $script:Module { Get-GamingRegistryState 'Control Panel\Desktop\WindowMetrics' 'MinAnimate' }
        Assert-Equal $animation.Value '1' 'Animation original was lost'
    }

    Test-Case 'expanded DWORD settings all restore originally absent values' {
        $root = Reset-TestContext
        $result = Invoke-GamingPlan -Ids @('reduce-transparency','controller-gamebar','search-web') -BackupRoot $root -Confirm:$false
        Assert-Equal $result.Changed 3 'Expanded DWORD settings did not apply'
        $journal = Get-Content -LiteralPath $result.BackupPath -Raw | ConvertFrom-Json
        foreach ($entry in $journal.Entries) { Assert-Equal $entry.Applied.Kind 'DWord' 'DWORD preference was incorrectly typed' }
        $restored = Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false
        Assert-Equal $restored.Changed 3 'Expanded DWORD settings did not restore'
        Assert-Equal (& $script:Module {$script:TestRegistry.Count}) 0 'Expanded settings left registry values behind'
    }

    Test-Case 'original version-one DWORD journal remains restorable after expansion' {
        $root = Reset-TestContext
        [void][IO.Directory]::CreateDirectory($root)
        $path = Join-Path $root 'original-release.json'
        $journal = [pscustomobject]@{
            Schema='Win11GamingHelper.Backup/1'; SessionId=[guid]::NewGuid().ToString('D')
            CreatedUtc='2026-10-21T00:00:00Z'; Sid='S-1-5-21-TEST'; Machine='TEST-PC'; Status='Applied'
            Entries=@([pscustomobject]@{
                TweakId='game-mode'; Path='Software\Microsoft\GameBar'; Name='AllowAutoGameMode'
                Before=[pscustomobject]@{Exists=$false;Kind=$null;Value=$null}
                Applied=[pscustomobject]@{Exists=$true;Kind='DWord';Value=1}; Status='Applied'; RestoreStatus=$null
            })
        }
        $journal | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
        Set-FakeValue 'AllowAutoGameMode' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=1})
        $result = Restore-GamingBackup -Path $path -BackupRoot $root -Confirm:$false
        Assert-Equal $result.Changed 1 'Original backup format is no longer accepted'
        Assert-Equal (& $script:Module {$script:TestRegistry.Count}) 0 'Original absent state did not restore'
    }

    foreach ($state in @(
        [pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = -1 },
        [pscustomobject]@{ Exists = $true; Kind = 'QWord'; Value = [long]9223372036854775806 },
        [pscustomobject]@{ Exists = $true; Kind = 'String'; Value = 'original text' },
        [pscustomobject]@{ Exists = $true; Kind = 'ExpandString'; Value = '%USERPROFILE%\original' },
        [pscustomobject]@{ Exists = $true; Kind = 'Binary'; Value = @(0, 127, 255) },
        [pscustomobject]@{ Exists = $true; Kind = 'None'; Value = @(1, 2) },
        [pscustomobject]@{ Exists = $true; Kind = 'MultiString'; Value = @('one', 'two') }
    )) {
        Test-Case ('original ' + $state.Kind + ' type and value survive JSON roundtrip restore') {
            $root = Reset-TestContext
            Set-FakeValue 'AllowAutoGameMode' $state
            Set-FakeValue 'AutoGameModeEnabled' ([pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = 1 })
            $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
            Assert-Equal $result.Changed 1 'Unexpected apply count'
            $restored = Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false
            Assert-Equal $restored.Changed 1 'Original typed state did not restore'
            $actual = & $script:Module { Get-GamingRegistryState 'Software\Microsoft\GameBar' 'AllowAutoGameMode' }
            Assert-Equal $actual $state 'Typed original state changed'
        }
    }

    Test-Case 'restore preview leaves registry and backup bytes unchanged' {
        $root = Reset-TestContext
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        $before = [IO.File]::ReadAllText($result.BackupPath)
        $restored = Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -WhatIf
        Assert-True $restored.Preview 'Restore preview not identified'
        Assert-Equal (Get-TestWrites) 2 'Restore preview wrote registry values'
        Assert-Equal ([IO.File]::ReadAllText($result.BackupPath)) $before 'Restore preview modified the journal'
    }

    Test-Case 'concurrent user preference changes are preserved during restore' {
        $root = Reset-TestContext
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        $external = [pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = 7 }
        Set-FakeValue 'AllowAutoGameMode' $external
        $restored = Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false
        Assert-Equal @($restored.Results | Where-Object Status -eq 'Conflict').Count 1 'Concurrent change was not reported'
        $actual = & $script:Module { Get-GamingRegistryState 'Software\Microsoft\GameBar' 'AllowAutoGameMode' }
        Assert-Equal $actual $external 'Concurrent user preference was overwritten'
    }

    Test-Case 'repeating completed restore cannot undo a newer user choice' {
        $root = Reset-TestContext
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false | Out-Null
        $writes = Get-TestWrites
        $newChoice = [pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = 1 }
        Set-FakeValue 'AllowAutoGameMode' $newChoice
        Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false | Out-Null
        Assert-Equal (Get-TestWrites) $writes 'Repeated restore performed additional writes'
        $actual = & $script:Module { Get-GamingRegistryState 'Software\Microsoft\GameBar' 'AllowAutoGameMode' }
        Assert-Equal $actual $newChoice 'Completed restore overwrote a newer choice'
    }

    Test-Case 'a previously conflicted restore entry cannot be resurrected by retry' {
        $root = Reset-TestContext
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        Set-FakeValue 'AllowAutoGameMode' ([pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = 7 })
        Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false | Out-Null
        $writes = Get-TestWrites
        $newChoice = [pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = 1 }
        Set-FakeValue 'AllowAutoGameMode' $newChoice
        Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false | Out-Null
        Assert-Equal (Get-TestWrites) $writes 'Retry reapplied a previously conflicted entry'
        $actual = & $script:Module { Get-GamingRegistryState 'Software\Microsoft\GameBar' 'AllowAutoGameMode' }
        Assert-Equal $actual $newChoice 'Retry overwrote a newer user preference'
    }

    Test-Case 'apply detects an external change during durable journal persistence' {
        $root = Reset-TestContext
        & $script:Module {
            $script:TestRaceSave = 1
            $script:TestRaceName = 'AllowAutoGameMode'
            $script:TestRaceState = [pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = 7 }
        }
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        Assert-Equal @($result.Results | Where-Object Status -eq 'Conflict').Count 1 'Late apply conflict was not reported'
        $actual = & $script:Module { Get-GamingRegistryState 'Software\Microsoft\GameBar' 'AllowAutoGameMode' }
        Assert-Equal $actual.Value 7 'Late apply race overwrote an external preference'
    }

    Test-Case 'restore detects an external change during durable journal persistence' {
        $root = Reset-TestContext
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        & $script:Module {
            $script:TestRaceSave = $script:TestSaveCount + 1
            $script:TestRaceName = 'AutoGameModeEnabled'
            $script:TestRaceState = [pscustomobject]@{ Exists = $true; Kind = 'DWord'; Value = 7 }
        }
        $restored = Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false
        Assert-Equal @($restored.Results | Where-Object Status -eq 'Conflict').Count 1 'Late restore conflict was not reported'
        $actual = & $script:Module { Get-GamingRegistryState 'Software\Microsoft\GameBar' 'AutoGameModeEnabled' }
        Assert-Equal $actual.Value 7 'Late restore race overwrote an external preference'
    }

    Test-Case 'backup directories with linked ancestors are rejected before writes' {
        $root = Reset-TestContext
        $real = Join-Path $root 'real'
        $link = Join-Path $root 'linked'
        [void][IO.Directory]::CreateDirectory((Join-Path $real 'backups'))
        $linkType = 'SymbolicLink'
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $linkType = 'Junction' }
        New-Item -ItemType $linkType -Path $link -Target $real -ErrorAction Stop | Out-Null
        $linkedRoot = Join-Path $link 'backups'
        Assert-Throws { Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $linkedRoot -Confirm:$false } 'Linked ancestor was accepted'
        Assert-Equal (Get-TestWrites) 0 'Linked backup path caused a registry mutation'
    }

    Test-Case 'a first journal-save failure prevents every registry write' {
        $root = Reset-TestContext
        & $script:Module { $script:TestFailSave = 1 }
        Assert-Throws { Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false } 'Journal failure did not abort apply'
        Assert-Equal (Get-TestWrites) 0 'Apply wrote before its first durable journal'
    }

    Test-Case 'failure saving applied status retains a recoverable pending journal' {
        $root = Reset-TestContext
        & $script:Module { $script:TestFailSave = 2 }
        Assert-Throws { Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false } 'Status-save failure did not abort apply'
        Assert-Equal (Get-TestWrites) 1 'Apply continued after losing journal persistence'
        $backup = @(Get-GamingBackups -BackupRoot $root)
        Assert-Equal $backup.Count 1 'Interrupted apply journal cannot be discovered'
        & $script:Module { $script:TestFailSave = -1 }
        $restored = Restore-GamingBackup -Path $backup[0].Path -BackupRoot $root -Confirm:$false
        Assert-Equal $restored.Changed 1 'Pending original state was not recoverable'
    }

    Test-Case 'registry write failures are reported without corrupting other originals' {
        $root = Reset-TestContext
        & $script:Module { $script:TestFailSetName = 'AutoGameModeEnabled' }
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        Assert-Equal $result.Failed 1 'Registry access failure was not reported'
        Assert-Equal $result.Changed 1 'Successful setting was misreported'
        & $script:Module { $script:TestFailSetName = '' }
        $restored = Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false
        Assert-Equal $restored.Changed 1 'Successful partial apply was not recoverable'
        Assert-Equal $restored.Failed 0 'Restore unnecessarily failed for never-applied value'
    }

    foreach ($mutation in @(
        @{ Name = 'different SID'; Edit = { param($j) $j.Sid = 'S-1-5-21-OTHER' } },
        @{ Name = 'different machine'; Edit = { param($j) $j.Machine = 'OTHER-PC' } },
        @{ Name = 'arbitrary registry path'; Edit = { param($j) $j.Entries[0].Path = 'Software\Unsupported' } },
        @{ Name = 'arbitrary registry value'; Edit = { param($j) $j.Entries[0].Name = 'Unsupported' } },
        @{ Name = 'unexpected applied value'; Edit = { param($j) $j.Entries[0].Applied.Value = 8 } },
        @{ Name = 'unsupported original type'; Edit = { param($j) $j.Entries[0].Before.Exists = $true; $j.Entries[0].Before.Kind = 'Invalid'; $j.Entries[0].Before.Value = 0 } },
        @{ Name = 'duplicate registry entry'; Edit = { param($j) $j.Entries = @($j.Entries) + @($j.Entries[0]) } },
        @{ Name = 'unsupported schema'; Edit = { param($j) $j.Schema = 'Untrusted/1' } }
    )) {
        Test-Case ('restore rejects ' + $mutation.Name + ' before any mutation') {
            $root = Reset-TestContext
            $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
            Edit-Journal -Path $result.BackupPath -Edit $mutation.Edit
            Assert-Throws { Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false } 'Invalid journal was accepted'
            Assert-Equal (Get-TestWrites) 2 'Invalid restore mutated the registry'
            Assert-Equal @(Get-GamingBackups -BackupRoot $root).Count 0 'Invalid backup was offered for restore'
        }
    }

    Test-Case 'restore rejects journals outside the selected backup directory' {
        $root = Reset-TestContext
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        $other = Join-Path $script:TestRoot 'outside.json'
        Copy-Item -LiteralPath $result.BackupPath -Destination $other
        Assert-Throws { Restore-GamingBackup -Path $other -BackupRoot $root -Confirm:$false } 'External journal path was accepted'
        Assert-Equal (Get-TestWrites) 2 'External-path restore mutated the registry'
    }

    Test-Case 'a restore journal-save failure prevents restoration writes' {
        $root = Reset-TestContext
        $result = Invoke-GamingPlan -Ids 'game-mode' -BackupRoot $root -Confirm:$false
        & $script:Module { $script:TestFailSave = $script:TestSaveCount + 1 }
        Assert-Throws { Restore-GamingBackup -Path $result.BackupPath -BackupRoot $root -Confirm:$false } 'Restore save failure was ignored'
        Assert-Equal (Get-TestWrites) 2 'Restore wrote before durable journal update'
    }
} finally {
    Remove-Module GamingHelper.Core -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:TestRoot) { Remove-Item -LiteralPath $script:TestRoot -Recurse -Force }
}

Write-Host ('Tests: {0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
