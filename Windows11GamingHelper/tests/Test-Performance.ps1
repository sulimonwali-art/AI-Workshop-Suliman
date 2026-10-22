# Dependency-free safety tests. Native powercfg and current-user registry are mocked.
# Real validation and atomic journal file I/O execute. No machine settings change.
[CmdletBinding()]
param([string]$ModulePath = (Join-Path $PSScriptRoot '..\GamingHelper.Performance.psm1'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0
$script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('gaming-performance-tests-' + [guid]::NewGuid().ToString('N'))
$script:Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
$script:High = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
function Assert-Equal {
    param($Actual,$Expected,[string]$Message)
    if(($Actual|ConvertTo-Json -Compress -Depth 20) -cne ($Expected|ConvertTo-Json -Compress -Depth 20)){
        throw ('{0}; expected {1}, got {2}' -f $Message,($Expected|ConvertTo-Json -Compress -Depth 20),($Actual|ConvertTo-Json -Compress -Depth 20))
    }
}
function Assert-Throws {
    param([scriptblock]$Script,[string]$Message)
    $thrown=$false; try { & $Script|Out-Null } catch {$thrown=$true; $script:LastThrown=$_.Exception.Message}
    if(-not $thrown){throw $Message}
}
function Test-Case {
    param([string]$Name,[scriptblock]$Body)
    try { & $Body; $script:Passed++; Write-Host ('PASS '+$Name) }
    catch { $script:Failed++; Write-Host ('FAIL '+$Name+': '+$_.Exception.Message) }
}
function Copy-State {param($State) $State|ConvertTo-Json -Depth 12|ConvertFrom-Json}

Import-Module $ModulePath -Force
$script:Module=Get-Module GamingHelper.Performance
if($null -eq $script:Module){throw 'Performance module did not import.'}
& $script:Module {
    $script:OriginalWriter=(Get-Command Save-PerformanceJournal).ScriptBlock
    $script:OriginalActiveReader=(Get-Command Get-PerformanceActivePowerPlan).ScriptBlock
    $script:OriginalPlanReader=(Get-Command Get-PerformancePowerPlans).ScriptBlock
    $script:OriginalPlanSetter=(Get-Command Set-PerformancePowerPlan).ScriptBlock
    function script:Assert-PerformancePlatform {}
    function script:Get-PerformanceIdentity { [pscustomobject]@{Sid='S-1-5-21-TEST';Machine='TEST-PC'} }
    function script:Enter-PerformanceLock { return $null }
    function script:Get-PerformanceActivePowerPlan { $script:TestPower }
    function script:Get-PerformancePowerPlans { $script:TestPlans }
    function script:Invoke-PerformancePowerCfg {
        param([string[]]$Arguments)
        $command=$Arguments -join ' '
        $script:TestNativeCalls.Add($command)
        if($script:TestNativeFailure -and $Arguments[0] -eq '/setactive'){throw 'Native powercfg failed (exit 23).'}
        if($script:TestNativeOutput.ContainsKey($command)){return $script:TestNativeOutput[$command]}
        throw ('Unexpected native command in test: '+$command)
    }
    function script:Get-PerformanceGpuState {
        param([string]$Executable)
        if($script:TestGpu.ContainsKey($Executable)){
            return ($script:TestGpu[$Executable]|ConvertTo-Json -Depth 12|ConvertFrom-Json)
        }
        [pscustomobject]@{Exists=$false;Kind=$null;Value=$null}
    }
    function script:Assert-TestCoverage {
        param($State)
        $covered=$false
        if(Test-Path -LiteralPath $script:TestBackups){
            foreach($file in Get-ChildItem -LiteralPath $script:TestBackups -Filter '*.json' -File){
                $journal=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
                $text=$State|ConvertTo-Json -Compress -Depth 12
                if($text -ceq ($journal.Applied|ConvertTo-Json -Compress -Depth 12) -or
                   $text -ceq ($journal.Before|ConvertTo-Json -Compress -Depth 12)){$covered=$true}
            }
        }
        if(-not $covered){throw 'SAFETY VIOLATION: mutation was not covered by an on-disk journal.'}
    }
    function script:Set-PerformancePowerPlan {
        param([string]$Id)
        if($script:TestUseRealPowerSetter){ & $script:OriginalPlanSetter -Id $Id; return }
        Assert-TestCoverage ([pscustomobject]@{Exists=$true;Kind='PowerPlan';Value=$Id})
        $script:TestWrites++
        if($script:TestFailMutation){throw 'Simulated powercfg access denied.'}
        $script:TestPower=$Id
    }
    function script:Set-PerformanceGpuState {
        param([string]$Executable,$State)
        Assert-TestCoverage $State
        $script:TestWrites++
        if($script:TestFailMutation){throw 'Simulated registry access denied.'}
        if($State.Exists){$script:TestGpu[$Executable]=$State|ConvertTo-Json -Depth 12|ConvertFrom-Json}
        else{$script:TestGpu.Remove($Executable)}
    }
    function script:Save-PerformanceJournal {
        param($Journal,[string]$Path)
        $script:TestSaves++
        if($script:TestSaves -eq $script:TestFailSave){throw 'Simulated journal persistence failure.'}
        & $script:OriginalWriter -Journal $Journal -Path $Path
        if($script:TestSaves -eq $script:TestRaceSave){
            if($Journal.Action -eq 'GameGpu'){$script:TestGpu[$script:TestExe]=$script:TestRaceState}
            else{$script:TestPower=$script:TestRaceState.Value}
        }
    }
}

function Reset-TestContext {
    $case=Join-Path $script:TestRoot ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($case)
    $exe=Join-Path $case 'test game.exe'
    [IO.File]::WriteAllText($exe,'Fixture only, never executed.')
    $backups=Join-Path $case 'backups'
    & $script:Module {
        param($Root,$Exe,$Balanced,$High)
        $script:TestBackups=$Root; $script:TestExe=$Exe
        $script:TestGpu=@{}; $script:TestWrites=0; $script:TestSaves=0
        $script:TestFailMutation=$false; $script:TestFailSave=-1
        $script:TestRaceSave=-1; $script:TestRaceState=$null
        $script:TestNativeOutput=@{}; $script:TestNativeCalls=New-Object 'Collections.Generic.List[string]'
        $script:TestNativeFailure=$false; $script:TestUseRealPowerSetter=$false
        $script:TestPower=$Balanced
        $script:TestPlans=@(
            [pscustomobject]@{Id=$Balanced;Name='Balanced';Kind='Balanced';Active=$true},
            [pscustomobject]@{Id=$High;Name='High performance';Kind='HighPerformance';Active=$false}
        )
    } $backups $exe $script:Balanced $script:High
    [pscustomobject]@{Root=$case;Exe=$exe;Backups=$backups}
}
function Get-TestWrites { & $script:Module {$script:TestWrites} }
function Set-FakeGpu {
    param([string]$Executable,$State)
    & $script:Module {param($E,$S) $script:TestGpu[$E]=$S} $Executable $State
}
function Get-FakeGpu {param([string]$Executable) & $script:Module {param($E) Get-PerformanceGpuState $E} $Executable}
function Edit-Journal {
    param([string]$Path,[scriptblock]$Edit)
    $journal=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
    & $Edit $journal
    $journal|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $Path -Encoding UTF8
}

try {
    Test-Case 'active power-plan parser accepts localized text and canonicalizes uppercase GUID' {
        $case=Reset-TestContext
        & $script:Module {
            $script:TestNativeOutput['/getactivescheme']='GUID des Energieschemas: 381B4222-F694-41F0-9685-FF5BB260DF2E (Ausbalanciert)'
        }
        $actual=& $script:Module { & $script:OriginalActiveReader }
        Assert-Equal $actual $script:Balanced 'Localized powercfg text was parsed by English wording or lost GUID casing'
    }
    Test-Case 'active power-plan parser rejects missing or ambiguous GUIDs' {
        $case=Reset-TestContext
        & $script:Module {$script:TestNativeOutput['/getactivescheme']='No recognizable scheme'}
        Assert-Throws { & $script:Module { & $script:OriginalActiveReader } } 'Missing GUID accepted'
        & $script:Module {$script:TestNativeOutput['/getactivescheme']='381b4222-f694-41f0-9685-ff5bb260df2e 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'}
        Assert-Throws { & $script:Module { & $script:OriginalActiveReader } } 'Ambiguous GUIDs accepted'
    }
    Test-Case 'power-plan inventory uses GUIDs independently of localized or custom names' {
        $case=Reset-TestContext
        & $script:Module {
            $script:TestNativeOutput['/list']=@'
Vorhandene Energieschemas
GUID des Energieschemas: 381b4222-f694-41f0-9685-ff5bb260df2e (Ausbalanciert) *
GUID des Energieschemas: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c (Hochleistung)
GUID des Energieschemas: 11111111-2222-3333-4444-555555555555 (OEM (Quiet))
'@
        }
        $plans=@(& $script:Module { & $script:OriginalPlanReader })
        Assert-Equal $plans.Count 3 'Localized or OEM plans were dropped'
        Assert-Equal $plans[0].Kind 'Balanced' 'Balanced plan identified by name rather than GUID'
        Assert-Equal $plans[1].Kind 'HighPerformance' 'High performance plan identified by name rather than GUID'
        Assert-Equal $plans[2].Kind 'Other' 'Custom plan was treated as a built-in optimization'
        Assert-Equal $plans[2].Name 'OEM (Quiet)' 'Custom parentheses were not retained'
    }
    Test-Case 'native power-plan setter rejects unlisted identifiers without invoking setactive' {
        $case=Reset-TestContext
        Assert-Throws { & $script:Module { & $script:OriginalPlanSetter -Id '11111111-2222-3333-4444-555555555555' } } 'Unlisted scheme was activated'
        Assert-Equal (& $script:Module {$script:TestNativeCalls.Count}) 0 'Native setactive called for an unavailable plan'
    }
    Test-Case 'powercfg failure propagates through the real setter into a failed apply result' {
        $case=Reset-TestContext
        & $script:Module {$script:TestUseRealPowerSetter=$true;$script:TestNativeFailure=$true}
        $result=Invoke-PerformanceAction -Action HighPerformancePower -BackupRoot $case.Backups -Confirm:$false
        Assert-Equal $result.Failed 1 'Native exit failure was reported as success'
        Assert-True ($result.Results[0].Message -like '*exit 23*') 'Underlying native failure details were lost'
        Assert-Equal (& $script:Module {$script:TestPower}) $script:Balanced 'Native failure altered mock active plan'
    }
    Test-Case 'unknown action and missing game cannot create changes or backup storage' {
        $case=Reset-TestContext
        Assert-Throws {Invoke-PerformanceAction -Action 'DisableSecurity' -BackupRoot $case.Backups -Confirm:$false} 'Unknown action accepted'
        Assert-Throws {Invoke-PerformanceAction -Action GameGpu -Executable (Join-Path $case.Root 'missing.exe') -BackupRoot $case.Backups -Confirm:$false} 'Missing game accepted'
        Assert-Equal (Get-TestWrites) 0 'Invalid action caused writes'
        Assert-True (-not(Test-Path -LiteralPath $case.Backups)) 'Invalid action created backups'
    }
    foreach($action in @('HighPerformancePower','GameGpu')){
        Test-Case ($action+' preview has no writes or backup directory') {
            $case=Reset-TestContext
            $result=Invoke-PerformanceAction -Action $action -Executable $case.Exe -BackupRoot $case.Backups -WhatIf
            Assert-True $result.Preview 'Preview not identified'
            Assert-Equal (Get-TestWrites) 0 'Preview mutated state'
            Assert-True (-not(Test-Path -LiteralPath $case.Backups)) 'Preview created backup storage'
        }
    }
    Test-Case 'already-active Balanced is a no-op without journaling' {
        $case=Reset-TestContext
        $result=Invoke-PerformanceAction -Action BalancedPower -BackupRoot $case.Backups -Confirm:$false
        Assert-Equal $result.Changed 0 'Already-active plan was changed'
        Assert-Equal (Get-TestWrites) 0 'No-op changed power plan'
        Assert-True (-not(Test-Path -LiteralPath $case.Backups)) 'No-op created a journal'
    }
    Test-Case 'unavailable High performance plan fails before any changes' {
        $case=Reset-TestContext
        & $script:Module {$script:TestPlans=@($script:TestPlans|Where-Object Kind -eq 'Balanced')}
        Assert-Throws {Invoke-PerformanceAction -Action HighPerformancePower -BackupRoot $case.Backups -Confirm:$false} 'Unavailable plan accepted'
        Assert-Equal (Get-TestWrites) 0 'Unavailable plan was activated'
    }
    Test-Case 'High performance records Balanced before activation and restores it' {
        $case=Reset-TestContext
        $result=Invoke-PerformanceAction -Action HighPerformancePower -BackupRoot $case.Backups -Confirm:$false
        Assert-Equal $result.Changed 1 'High performance not applied'
        Assert-Equal (& $script:Module {$script:TestPower}) $script:High 'Wrong power plan activated'
        $restore=Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false
        Assert-Equal $restore.Changed 1 'Original plan not restored'
        Assert-Equal (& $script:Module {$script:TestPower}) $script:Balanced 'Original Balanced plan lost'
    }
    Test-Case 'per-game GPU preference preserves unrelated semicolon options' {
        $case=Reset-TestContext
        $original=[pscustomobject]@{Exists=$true;Kind='String';Value='AutoHDREnable=1;GpuPreference=1;SwapEffectUpgradeEnable=0;'}
        Set-FakeGpu $case.Exe $original
        $result=Invoke-PerformanceAction -Action GameGpu -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
        Assert-Equal $result.Changed 1 'GPU preference not applied'
        $applied=Get-FakeGpu $case.Exe
        Assert-True ($applied.Value -cmatch 'AutoHDREnable=1;') 'Auto HDR preference lost'
        Assert-True ($applied.Value -cmatch 'SwapEffectUpgradeEnable=0;') 'Windowed-game preference lost'
        Assert-True ($applied.Value -cmatch 'GpuPreference=2;') 'High performance GPU value missing'
        Assert-True ($applied.Value -cnotmatch 'GpuPreference=1;') 'Old GPU preference retained'
        Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false|Out-Null
        Assert-Equal (Get-FakeGpu $case.Exe) $original 'Original full preference string not restored exactly'
    }
    Test-Case 'an originally absent GPU preference is removed on undo' {
        $case=Reset-TestContext
        $result=Invoke-PerformanceAction -Action GameGpu -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
        Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false|Out-Null
        Assert-True (-not(Get-FakeGpu $case.Exe).Exists) 'Originally absent preference not removed'
    }
    Test-Case 'GPU undo still works after the selected game is removed' {
        $case=Reset-TestContext
        $result=Invoke-PerformanceAction -Action GameGpu -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
        Remove-Item -LiteralPath $case.Exe
        $restore=Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false
        Assert-Equal $restore.Changed 1 'Removed game prevented registry cleanup'
    }
    foreach($action in @('HighPerformancePower','GameGpu')){
        Test-Case ($action+' restore preview leaves settings and journal bytes unchanged') {
            $case=Reset-TestContext
            $result=Invoke-PerformanceAction -Action $action -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
            $bytes=[IO.File]::ReadAllText($result.BackupPath)
            $restore=Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -WhatIf
            Assert-True $restore.Preview 'Restore preview not identified'
            Assert-Equal (Get-TestWrites) 1 'Restore preview changed state'
            Assert-Equal ([IO.File]::ReadAllText($result.BackupPath)) $bytes 'Restore preview changed journal bytes'
        }
        Test-Case ($action+' first-save failure prevents all state mutations') {
            $case=Reset-TestContext
            & $script:Module {$script:TestFailSave=1}
            Assert-Throws {Invoke-PerformanceAction -Action $action -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false} 'Persistence failure did not stop apply'
            Assert-Equal (Get-TestWrites) 0 'Mutation happened before durable journal'
        }
        Test-Case ($action+' post-write journal failure leaves an interrupted plan recoverable') {
            $case=Reset-TestContext
            & $script:Module {$script:TestFailSave=2}
            Assert-Throws {Invoke-PerformanceAction -Action $action -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false} 'Second save failure did not abort'
            Assert-Equal (Get-TestWrites) 1 ('Apply did not reach the expected interruption: '+$script:LastThrown)
            & $script:Module {$script:TestFailSave=-1}
            $backups=@(Get-PerformanceBackups -BackupRoot $case.Backups)
            Assert-Equal $backups.Count 1 'Interrupted journal not discoverable'
            $restore=Restore-PerformanceBackup -Path $backups[0].Path -BackupRoot $case.Backups -Confirm:$false
            Assert-Equal $restore.Changed 1 'Interrupted plan did not restore'
        }
        Test-Case ($action+' native mutation failure is reported and preserves original') {
            $case=Reset-TestContext
            & $script:Module {$script:TestFailMutation=$true}
            $result=Invoke-PerformanceAction -Action $action -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
            Assert-Equal $result.Failed 1 'Native failure reported as success'
            Assert-Equal $result.Changed 0 'Native failure counted as changed'
        }
        Test-Case ($action+' restore journal-save failure prevents restoration writes') {
            $case=Reset-TestContext
            $result=Invoke-PerformanceAction -Action $action -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
            & $script:Module {$script:TestFailSave=$script:TestSaves+1}
            Assert-Throws {Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false} 'Restore persistence failure ignored'
            Assert-Equal (Get-TestWrites) 1 'Restore wrote before durable save'
        }
        Test-Case ($action+' detects a late external preference change after backup persistence') {
            $case=Reset-TestContext
            & $script:Module {
                $script:TestRaceSave=1
                $script:TestRaceState=[pscustomobject]@{Exists=$true;Kind='PowerPlan';Value='11111111-2222-3333-4444-555555555555'}
            }
            if($action -eq 'GameGpu'){
                & $script:Module {$script:TestRaceState=[pscustomobject]@{Exists=$true;Kind='String';Value='GpuPreference=1;AutoHDREnable=1;'}}
            }
            $result=Invoke-PerformanceAction -Action $action -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
            Assert-Equal $result.Results[0].Status 'Conflict' 'Late apply change was not detected'
            Assert-Equal (Get-TestWrites) 0 'Late apply overwrote external preference'
        }
        Test-Case ($action+' detects a late external preference change while preparing restore') {
            $case=Reset-TestContext
            $result=Invoke-PerformanceAction -Action $action -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
            & $script:Module {
                $script:TestRaceSave=$script:TestSaves+1
                $script:TestRaceState=[pscustomobject]@{Exists=$true;Kind='PowerPlan';Value='11111111-2222-3333-4444-555555555555'}
            }
            if($action -eq 'GameGpu'){
                & $script:Module {$script:TestRaceState=[pscustomobject]@{Exists=$true;Kind='String';Value='GpuPreference=1;AutoHDREnable=1;'}}
            }
            $restore=Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false
            Assert-Equal $restore.Results[0].Status 'Conflict' 'Late restore change was not detected'
            Assert-Equal (Get-TestWrites) 1 'Late restore overwrote external preference'
        }
    }
    Test-Case 'a custom original power plan is preserved and restored exactly' {
        $case=Reset-TestContext
        $custom='11111111-2222-3333-4444-555555555555'
        & $script:Module {param($Id) $script:TestPower=$Id; $script:TestPlans+=@([pscustomobject]@{Id=$Id;Name='OEM';Kind='Other';Active=$true})} $custom
        $result=Invoke-PerformanceAction -Action HighPerformancePower -BackupRoot $case.Backups -Confirm:$false
        $restore=Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false
        Assert-Equal $restore.Changed 1 'Custom original plan did not restore'
        Assert-Equal (& $script:Module {$script:TestPower}) $custom 'Custom original plan was replaced with a guessed default'
    }
    Test-Case 'completed power-plan undo cannot overwrite a newer active plan' {
        $case=Reset-TestContext
        $result=Invoke-PerformanceAction -Action HighPerformancePower -BackupRoot $case.Backups -Confirm:$false
        Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false|Out-Null
        & $script:Module {$script:TestPower=$script:HighPerformanceId}
        Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false|Out-Null
        Assert-Equal (Get-TestWrites) 2 'Completed power-plan undo performed another write'
    }
    Test-Case 'newer external GPU choice is skipped and cannot be resurrected on retry' {
        $case=Reset-TestContext
        $result=Invoke-PerformanceAction -Action GameGpu -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
        $external=[pscustomobject]@{Exists=$true;Kind='String';Value='GpuPreference=1;AutoHDREnable=1;'}
        Set-FakeGpu $case.Exe $external
        $restore=Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false
        Assert-Equal $restore.Changed 0 'Conflicted GPU preference was restored'
        Assert-Equal (Get-FakeGpu $case.Exe) $external 'External GPU preference was overwritten'
        Set-FakeGpu $case.Exe ([pscustomobject]@{Exists=$true;Kind='String';Value='GpuPreference=2;'})
        Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false|Out-Null
        Assert-Equal (Get-TestWrites) 1 'A terminal conflict was resurrected'
    }
    Test-Case 'completed GPU undo never overwrites a later user choice' {
        $case=Reset-TestContext
        $result=Invoke-PerformanceAction -Action GameGpu -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
        Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false|Out-Null
        Set-FakeGpu $case.Exe ([pscustomobject]@{Exists=$true;Kind='String';Value='GpuPreference=2;'})
        Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false|Out-Null
        Assert-Equal (Get-TestWrites) 2 'Repeated completed undo changed state again'
    }
    foreach($mutation in @(
        @{Name='different SID';Edit={param($j)$j.Sid='OTHER'}},
        @{Name='different machine';Edit={param($j)$j.Machine='OTHER'}},
        @{Name='unknown action';Edit={param($j)$j.Action='RunCommand'}},
        @{Name='unexpected applied GPU value';Edit={param($j)$j.Applied.Value='ArbitrarySetting=1;'}},
        @{Name='unsupported original registry type';Edit={param($j)$j.Before=[pscustomobject]@{Exists=$true;Kind='DWord';Value=0}}},
        @{Name='wrong schema';Edit={param($j)$j.Schema='Untrusted/1'}},
        @{Name='non-executable target';Edit={param($j)$j.Target='C:\Windows\system.ini'}}
    )){
        Test-Case ('restore rejects '+$mutation.Name+' before any mutation') {
            $case=Reset-TestContext
            $result=Invoke-PerformanceAction -Action GameGpu -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
            Edit-Journal -Path $result.BackupPath -Edit $mutation.Edit
            Assert-Throws {Restore-PerformanceBackup -Path $result.BackupPath -BackupRoot $case.Backups -Confirm:$false} 'Invalid journal accepted'
            Assert-Equal (Get-TestWrites) 1 'Invalid journal caused a mutation'
            Assert-Equal @(Get-PerformanceBackups -BackupRoot $case.Backups).Count 0 'Invalid journal offered for restore'
        }
    }
    Test-Case 'restore rejects a journal copied outside its backup root' {
        $case=Reset-TestContext
        $result=Invoke-PerformanceAction -Action GameGpu -Executable $case.Exe -BackupRoot $case.Backups -Confirm:$false
        $outside=Join-Path $case.Root 'outside.json'
        Copy-Item -LiteralPath $result.BackupPath -Destination $outside
        Assert-Throws {Restore-PerformanceBackup -Path $outside -BackupRoot $case.Backups -Confirm:$false} 'Outside journal accepted'
        Assert-Equal (Get-TestWrites) 1 'Outside journal caused mutation'
    }
} finally {
    Remove-Module GamingHelper.Performance -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $script:TestRoot){Remove-Item -LiteralPath $script:TestRoot -Recurse -Force}
}
Write-Host ('Tests: {0} passed, {1} failed' -f $script:Passed,$script:Failed)
if($script:Failed -gt 0){exit 1}
