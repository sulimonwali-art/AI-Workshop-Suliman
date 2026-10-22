#requires -Version 5.1
<#
Windows 11 Gaming Helper. Runs as the current user; no elevation or downloads.
Use -Mode Audit for a read-only console report; -Mode Preview -Tweak <ids>
previews selected registry changes. The default opens the Windows interface.
#>
[CmdletBinding()]
param(
    [ValidateSet('Gui', 'Audit', 'Preview')]
    [string]$Mode = 'Gui',
    [string[]]$Tweak = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or [Environment]::OSVersion.Version.Build -lt 22000) {
    throw 'This program requires Windows 11. No settings have been changed.'
}
Import-Module (Join-Path $PSScriptRoot 'GamingHelper.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'GamingHelper.Performance.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'GamingHelper.Advisor.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'GamingHelper.Benchmark.psm1') -Force

if ($Mode -eq 'Audit') {
    Get-GamingSnapshot | ConvertTo-Json -Depth 6
    return
}
if ($Mode -eq 'Preview') {
    if ($Tweak.Count -eq 0) { throw 'Choose IDs from Get-GamingTweaks; for example game-mode or mouse-acceleration.' }
    Invoke-GamingPlan -Ids $Tweak -WhatIf | ConvertTo-Json -Depth 6
    return
}

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Open Launch.cmd, or run powershell.exe -NoProfile -STA -File .\GamingHelper.ps1.'
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$guiMutex = New-Object Threading.Mutex($false, ('Local\Win11GamingHelper.Gui.' + $userSid))
$haveMutex = $false
try { $haveMutex = $guiMutex.WaitOne(0) }
catch [Threading.AbandonedMutexException] { $haveMutex = $true }
if (-not $haveMutex) {
    [void][Windows.Forms.MessageBox]::Show('The helper is already open for this Windows user.', 'Gaming Helper')
    $guiMutex.Dispose()
    return
}

$script:backupRoot = Join-Path $env:LOCALAPPDATA 'Win11GamingHelper\Backups'
$script:performanceBackupRoot = Join-Path $env:LOCALAPPDATA 'Win11GamingHelper\PerformanceBackups'
$script:baseline = $null
$script:after = $null
$script:busy = $false
$script:catalog = @(Get-GamingTweaks)
$form = New-Object Windows.Forms.Form
$form.Text = 'Windows 11 Gaming Helper 2.0'
$form.Size = New-Object Drawing.Size(1120, 840)
$form.MinimumSize = New-Object Drawing.Size(980, 720)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi

function New-TextBox {
    param([bool]$ReadOnly = $true)
    $box = New-Object Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $ReadOnly
    $box.ScrollBars = 'Both'
    $box.WordWrap = $false
    $box.Dock = 'Fill'
    $box.Font = New-Object Drawing.Font('Consolas', 10)
    return $box
}
function New-Note {
    param([string]$Text, [int]$Height = 65)
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.Dock = 'Top'
    $label.Height = $Height
    $label.Padding = New-Object Windows.Forms.Padding(8)
    return $label
}
function New-Button {
    param([string]$Text, [int]$Width = 160)
    $button = New-Object Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 36
    $button.Margin = New-Object Windows.Forms.Padding(6)
    return $button
}
function New-Grid {
    $grid = New-Object Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.SelectionMode = 'FullRowSelect'
    $grid.BackgroundColor = [Drawing.Color]::White
    return $grid
}
function Set-GridRows {
    param($Grid, $Rows, [string[]]$Columns)
    $Grid.Columns.Clear()
    foreach ($name in $Columns) { [void]$Grid.Columns.Add($name, $name) }
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $cells = @($Columns | ForEach-Object { [string]$row.$_ })
        [void]$Grid.Rows.Add([object[]]$cells)
    }
}
function Show-Error {
    param([string]$Message)
    [void][Windows.Forms.MessageBox]::Show($form, $Message, 'Action stopped', 'OK', 'Error')
}
function Invoke-UiAction {
    param([scriptblock]$Action)
    if ($script:busy) { return }
    $script:busy = $true
    $form.UseWaitCursor = $true
    try { & $Action }
    catch {
        $message = $_.Exception.Message
        # A failed status save may follow a successful setting write. Offer the
        # recoverable Pending journal immediately without masking the cause.
        try { Refresh-Backups }
        catch { $message += "`r`nBackup list could not refresh: " + $_.Exception.Message }
        Show-Error $message
    }
    finally { $form.UseWaitCursor = $false; $script:busy = $false }
}
function Open-WindowsSetting {
    param([string]$Uri)
    Invoke-UiAction { Start-Process -FilePath $Uri -ErrorAction Stop }
}

$header = New-Note ("Gaming setup and tuning | " + [Security.Principal.WindowsIdentity]::GetCurrent().Name + "`r`nPreview each change first. Power plans affect the PC; other tweaks affect this user. Compare your benchmarks and use Undo.") 66
$header.BackColor = [Drawing.Color]::FromArgb(230, 240, 248)
$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$overview = New-Object Windows.Forms.TabPage
$overview.Text = 'PC check'
$tuning = New-Object Windows.Forms.TabPage
$tuning.Text = 'Gaming settings'
$apps = New-Object Windows.Forms.TabPage
$apps.Text = 'Apps and startup'
$performance = New-Object Windows.Forms.TabPage
$performance.Text = 'Performance'
$guides = New-Object Windows.Forms.TabPage
$guides.Text = 'Guides'
$benchmarks = New-Object Windows.Forms.TabPage
$benchmarks.Text = 'Benchmark CSV'
$restore = New-Object Windows.Forms.TabPage
$restore.Text = 'Undo changes'
$tabs.TabPages.AddRange(@($overview, $tuning, $performance, $guides, $apps, $benchmarks, $restore))
$form.Controls.Add($tabs)
$form.Controls.Add($header)

$overviewText = New-TextBox
$overviewText.Text = 'Reading local PC information...'
$overviewButtons = New-Object Windows.Forms.FlowLayoutPanel
$overviewButtons.Dock = 'Bottom'
$overviewButtons.Height = 54
$scanButton = New-Button 'Refresh PC check'
$displayButton = New-Button 'Display settings'
$gameSettingsButton = New-Button 'Game Mode settings' 180
$overviewButtons.Controls.AddRange(@($scanButton, $displayButton, $gameSettingsButton))
$overview.Controls.Add($overviewText)
$overview.Controls.Add($overviewButtons)
$overview.Controls.Add((New-Note 'Start here. Check the actual hardware and review the README for Intel BIOS stability guidance, display refresh rate, and benchmarking. This tool does not overclock, install drivers, or change Windows security.' 65))

$tweakList = New-Object Windows.Forms.ListView
$tweakList.View = 'Details'
$tweakList.CheckBoxes = $true
$tweakList.FullRowSelect = $true
$tweakList.ShowItemToolTips = $true
$tweakList.Dock = 'Top'
$tweakList.Height = 275
[void]$tweakList.Columns.Add('Optional setting', 245)
[void]$tweakList.Columns.Add('Category', 115)
[void]$tweakList.Columns.Add('Effect and tradeoff', 780)
foreach ($item in $script:catalog) {
    $listItem = New-Object Windows.Forms.ListViewItem([string]$item.Name)
    $listItem.Tag = $item.Id
    $listItem.ToolTipText = $item.Description + "`r`n" + $item.Tradeoff + "`r`nExpected impact: " + $item.Impact
    [void]$listItem.SubItems.Add([string]$item.Category)
    [void]$listItem.SubItems.Add(($item.Description + ' ' + $item.Tradeoff))
    [void]$tweakList.Items.Add($listItem)
}
$tuneOutput = New-TextBox
$tuneOutput.Text = 'Select only the settings you want. Preview reads current values without writing backups or settings.'
$tuneButtons = New-Object Windows.Forms.FlowLayoutPanel
$tuneButtons.Dock = 'Bottom'
$tuneButtons.Height = 54
$previewButton = New-Button 'Preview selection'
$applyButton = New-Button 'Apply selection'
$applyButton.Enabled = $false
$presetButton = New-Button 'Conservative preset' 185
$clearButton = New-Button 'Clear selection' 145
$tuneButtons.Controls.AddRange(@($presetButton, $clearButton, $previewButton, $applyButton))
$tuning.Controls.Add($tuneOutput)
$tuning.Controls.Add($tuneButtons)
$tuning.Controls.Add($tweakList)
$tuning.Controls.Add((New-Note 'All checkboxes start unchecked. Turning off Windows game capture disables Windows game recording; NVIDIA recording is separate. Cosmetic changes have no promised FPS benefit. Read the tradeoffs, then preview your selection before applying it.' 65))

$appTabs = New-Object Windows.Forms.TabControl
$appTabs.Dock = 'Fill'
$startupTab = New-Object Windows.Forms.TabPage
$startupTab.Text = 'Startup inventory'
$installedTab = New-Object Windows.Forms.TabPage
$installedTab.Text = 'Store app inventory'
$startupGrid = New-Grid
$appGrid = New-Grid
$startupTab.Controls.Add($startupGrid)
$installedTab.Controls.Add($appGrid)
$appTabs.TabPages.AddRange(@($startupTab, $installedTab))
$appButtons = New-Object Windows.Forms.FlowLayoutPanel
$appButtons.Dock = 'Bottom'
$appButtons.Height = 54
$startupButton = New-Button 'Open Startup apps' 180
$installedButton = New-Button 'Open Installed apps' 180
$appButtons.Controls.AddRange(@($startupButton, $installedButton))
$apps.Controls.Add($appTabs)
$apps.Controls.Add($appButtons)
$apps.Controls.Add((New-Note 'Review apps you recognize in Windows Settings. The inventory is advisory and may be incomplete; this helper never uninstalls apps. Keep NVIDIA/audio drivers, security tools, and any game launchers or Xbox components you use. Manual uninstalls are outside Undo.' 75))

$performanceOutput = New-TextBox
$performanceOutput.Text = 'Read each tradeoff. Balanced is the recommended starting point for a 14900KF. Select a control, preview it, then apply it. Changing the power plan affects the whole PC.'
$powerPanel = New-Object Windows.Forms.FlowLayoutPanel
$powerPanel.Dock = 'Top'; $powerPanel.Height = 130
$powerNote = New-Note 'Power plan experiment: High performance can increase idle power, fan noise and heat without improving FPS. Keep Intel defaults and test temperatures/stability. Only plans already present on this PC are offered.' 60
$powerNote.Dock = 'None'; $powerNote.Width = 1000
$powerChoice = New-Object Windows.Forms.ComboBox
$powerChoice.DropDownStyle = 'DropDownList'; $powerChoice.Width = 300; $powerChoice.DisplayMember = 'Label'
$powerPreviewButton = New-Button 'Preview power plan' 180
$powerApplyButton = New-Button 'Apply power plan' 180
$powerApplyButton.Enabled = $false
$powerPanel.Controls.AddRange(@($powerNote, $powerChoice, $powerPreviewButton, $powerApplyButton))
$gpuPanel = New-Object Windows.Forms.FlowLayoutPanel
$gpuPanel.Dock = 'Top'; $gpuPanel.Height = 150
$gpuNote = New-Note 'Per-game GPU preference: choose the actual game executable, not its launcher. Windows may already use your RTX 4070 Ti; the 14900KF has no integrated GPU, so this usually adds no performance. No game is launched by this helper.' 65
$gpuNote.Dock = 'None'; $gpuNote.Width = 1000
$gpuPath = New-Object Windows.Forms.TextBox
$gpuPath.Width = 475; $gpuPath.ReadOnly = $true; $gpuPath.Margin = New-Object Windows.Forms.Padding(6)
$gpuBrowseButton = New-Button 'Choose game' 135
$gpuPreviewButton = New-Button 'Preview GPU' 135
$gpuApplyButton = New-Button 'Apply GPU' 135
$gpuApplyButton.Enabled = $false
$gpuPanel.Controls.AddRange(@($gpuNote, $gpuPath, $gpuBrowseButton, $gpuPreviewButton, $gpuApplyButton))
$performanceButtons = New-Object Windows.Forms.FlowLayoutPanel
$performanceButtons.Dock = 'Bottom'; $performanceButtons.Height = 54
$graphicsButton = New-Button 'Windows graphics settings' 240
$performanceButtons.Controls.Add($graphicsButton)
$performance.Controls.Add($performanceOutput)
$performance.Controls.Add($performanceButtons)
$performance.Controls.Add($gpuPanel)
$performance.Controls.Add($powerPanel)
$performance.Controls.Add((New-Note 'Optional experiments with saved originals. Test one change at a time. Permissions and organizational policies still apply; this tool does not elevate itself. Power-plan and GPU backups appear in Undo changes.' 65))

$guideList = New-Object Windows.Forms.ListBox
$guideList.Dock = 'Left'; $guideList.Width = 315; $guideList.DisplayMember = 'Label'
foreach ($guide in @(Get-GamingGuides | Sort-Object Priority)) {
    [void]$guideList.Items.Add([pscustomobject]@{ Label = $guide.Name; Guide = $guide })
}
$guideText = New-TextBox
$guideText.WordWrap = $true
$guideButtons = New-Object Windows.Forms.FlowLayoutPanel
$guideButtons.Dock = 'Bottom'; $guideButtons.Height = 54
$guideSettingsButton = New-Button 'Open relevant Settings' 220
$guideReferenceButton = New-Button 'Official reference' 190
$guideSettingsButton.Enabled = $false; $guideReferenceButton.Enabled = $false
$guideButtons.Controls.AddRange(@($guideSettingsButton, $guideReferenceButton))
$guides.Controls.Add($guideText)
$guides.Controls.Add($guideButtons)
$guides.Controls.Add($guideList)
$guides.Controls.Add((New-Note 'Hardware and game settings often have more impact than desktop tweaks. These guides explain the steps and tradeoffs; they do not change settings automatically. Open official references only when you choose to.' 65))

$benchmarkText = New-TextBox
$benchmarkText.Text = 'Import a baseline capture and a capture after a change. Use comma-delimited CSV with MsBetweenPresents or an explicit supported frame-time column in milliseconds. Export one game/process and one swap chain, with at least 100 positive frames. This helper does not capture gameplay.'
$benchmarkButtons = New-Object Windows.Forms.FlowLayoutPanel
$benchmarkButtons.Dock = 'Bottom'; $benchmarkButtons.Height = 54
$baselineButton = New-Button 'Import baseline CSV' 200
$afterButton = New-Button 'Import test CSV' 200
$resetBenchmarkButton = New-Button 'Clear comparison' 180
$benchmarkButtons.Controls.AddRange(@($baselineButton, $afterButton, $resetBenchmarkButton))
$benchmarks.Controls.Add($benchmarkText)
$benchmarks.Controls.Add($benchmarkButtons)
$benchmarks.Controls.Add((New-Note 'Measure the same game, scene, settings, resolution and recording state. Finish shader compilation and repeat runs. CSV analysis stays local. Comparisons cannot prove that a tweak caused a change; record conditions yourself.' 70))

$backupList = New-Object Windows.Forms.ListBox
$backupList.Dock = 'Top'
$backupList.Height = 155
$backupList.DisplayMember = 'Label'
$restoreOutput = New-TextBox
$restoreOutput.Text = 'User-setting backups: LocalAppData\Win11GamingHelper\Backups. Power/GPU backups: LocalAppData\Win11GamingHelper\PerformanceBackups. Undo skips newer changes; inspect all results. Keep the files until testing is finished.'
$restoreButtons = New-Object Windows.Forms.FlowLayoutPanel
$restoreButtons.Dock = 'Bottom'
$restoreButtons.Height = 54
$refreshBackupButton = New-Button 'Refresh backups'
$restoreButton = New-Button 'Undo selected backup' 210
$restoreButtons.Controls.AddRange(@($refreshBackupButton, $restoreButton))
$restore.Controls.Add($restoreOutput)
$restore.Controls.Add($restoreButtons)
$restore.Controls.Add($backupList)
$restore.Controls.Add((New-Note 'Choose the newest relevant backup first. Undo is limited to changes recorded by this tool for this Windows user on this machine. A registry journal is not a full system backup. Unrelated later changes are preserved.' 65))

function Get-SelectedTweakIds {
    @($tweakList.CheckedItems | ForEach-Object { [string]$_.Tag })
}
function Format-PlanResult {
    param($Result)
    $lines = New-Object 'Collections.Generic.List[string]'
    if ($Result.Preview) { $lines.Add('Preview: no settings or backups were written.') }
    else { $lines.Add(('Changed: {0} | Skipped or already set: {1} | Failed: {2}' -f $Result.Changed, $Result.Skipped, $Result.Failed)) }
    if ($Result.BackupPath) { $lines.Add(('Backup: ' + $Result.BackupPath)) }
    $lines.Add('')
    foreach ($entry in @($Result.Results)) {
        $lines.Add(('[{0}] {1}: {2}' -f $entry.Status, $entry.TweakId, $entry.Message))
        $lines.Add(('  ' + $entry.Path + ' / ' + $entry.Name))
    }
    $lines.Add('')
    $lines.Add('Settings may require signing out and back in. Close games before changing settings; compare the same benchmark before and after.')
    return ($lines -join "`r`n")
}
function Refresh-Backups {
    $backupList.Items.Clear()
    foreach ($backup in @(Get-GamingBackups -BackupRoot $script:backupRoot)) {
        [void]$backupList.Items.Add([pscustomobject]@{
            Label = ('{0} | {1} | {2} values' -f $backup.CreatedUtc, $backup.Status, $backup.Count)
            Path = $backup.Path
            Kind = 'User settings'
        })
    }
    foreach ($backup in @(Get-PerformanceBackups -BackupRoot $script:performanceBackupRoot)) {
        [void]$backupList.Items.Add([pscustomobject]@{
            Label = ('{0} | {1} | {2}' -f $backup.CreatedUtc, $backup.Action, $backup.Status)
            Path = $backup.Path
            Kind = 'Performance'
        })
    }
    $sortedBackups = @($backupList.Items | Sort-Object { [IO.Path]::GetFileName($_.Path) } -Descending)
    $backupList.Items.Clear()
    foreach ($item in $sortedBackups) { [void]$backupList.Items.Add($item) }
    if ($backupList.Items.Count -gt 0) { $backupList.SelectedIndex = 0 }
}
function Refresh-PC {
    $snapshot = Get-GamingSnapshot
    $report = @(
        $snapshot.Summary, '',
        'WINDOWS', ($snapshot.OS | Out-String),
        'PROCESSOR', ($snapshot.CPU | Out-String),
        'GRAPHICS', ($snapshot.GPU | Out-String),
        'GRAPHICS DRIVER', ($snapshot.GPUDriver | Format-Table -AutoSize | Out-String -Width 140),
        ('MEMORY: ' + $snapshot.MemoryGB + ' GB'), '',
        'BIOS', ($snapshot.BIOS | Out-String),
        'LOCAL DISK FREE SPACE', ($snapshot.Disks | Format-Table -AutoSize | Out-String -Width 140),
        'POWER PLAN', $snapshot.PowerPlan, '',
        'REPORTED DISPLAY MODES', ($snapshot.Displays | Format-Table -AutoSize | Out-String -Width 140),
        'REPORTED RAM CONFIGURATION', ($snapshot.MemoryModules | Format-Table -AutoSize | Out-String -Width 140),
        'NOTES', ($snapshot.Warnings -join "`r`n"), '',
        'Recommended for your 14900KF / RTX 4070 Ti:',
        '- Use the motherboard vendor''s current stable BIOS and Intel default settings.',
        '- Use an official NVIDIA driver; verify your monitor''s refresh rate in Display settings.',
        '- Keep Windows security, automatic updates, and the system-managed pagefile enabled.',
        '- Benchmark before and after. No automatic FPS gain is guaranteed.'
    )
    $overviewText.Text = $report -join "`r`n"
    Set-GridRows $startupGrid $snapshot.Startup @('Name', 'Command', 'Location', 'User')
    Set-GridRows $appGrid $snapshot.Apps @('Name', 'PackageName', 'Version')
    Refresh-PowerChoices
    Refresh-Backups
}

function Refresh-PowerChoices {
    $powerChoice.Items.Clear()
    try {
        foreach ($plan in @(Get-PerformancePowerPlans)) {
            if ($plan.Kind -notin @('Balanced', 'HighPerformance')) { continue }
            $action = 'BalancedPower'; $label = 'Balanced (recommended)'
            if ($plan.Kind -eq 'HighPerformance') { $action = 'HighPerformancePower'; $label = 'High performance (test only)' }
            if ($plan.Active) { $label += ' - currently active' }
            [void]$powerChoice.Items.Add([pscustomobject]@{ Label = $label; Action = $action })
        }
        if ($powerChoice.Items.Count -gt 0) { $powerChoice.SelectedIndex = 0 }
        else { $performanceOutput.Text = 'No supported Balanced or High performance plan is available. Use Windows power settings; this helper does not create power schemes.' }
    } catch { $performanceOutput.Text = 'Power plan read failed: ' + $_.Exception.Message }
    $powerApplyButton.Enabled = $false
}
function Show-BenchmarkComparison {
    $parts = New-Object 'Collections.Generic.List[string]'
    foreach ($run in @($script:baseline, $script:after)) {
        if ($null -ne $run) { $parts.Add(($run | Format-List | Out-String)) }
    }
    if ($null -ne $script:baseline -and $null -ne $script:after) {
        $comparison = @(Compare-GamingBenchmarks -Before $script:baseline -After $script:after)
        $parts.Add(($comparison | Format-Table Metric, Before, After, ChangePercent, Better -AutoSize | Out-String -Width 130))
    }
    $parts.Add('Average FPS = 1000 / mean frame time. 1% low = 1000 / mean of slowest ceil(1%) frames; 0.1% low requires 1000 frames. P99 uses nearest rank. Zero timings are counted and excluded; other slow frames are retained.')
    $parts.Add('These are capture/present timing metrics, not a latency or input-response measurement. Keep the capture method and test conditions identical. No gain is guaranteed.')
    $benchmarkText.Text = $parts -join "`r`n"
}
function Select-BenchmarkFile {
    param([bool]$Baseline)
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter = 'Frame-time CSV (*.csv)|*.csv'; $dialog.CheckFileExists = $true
    try {
        if ($dialog.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK) { return }
        $label = 'Test'; if ($Baseline) { $label = 'Baseline' }
        $run = Import-GamingBenchmark -Path $dialog.FileName -Label $label
        $other = $script:baseline; if ($Baseline) { $other = $script:after }
        if ($null -ne $other -and $other.SourceColumn -cne $run.SourceColumn) { throw 'Choose the same frame-time column and capture method as the other run, or clear the comparison.' }
        if ($Baseline) { $script:baseline = $run } else { $script:after = $run }
        Show-BenchmarkComparison
    } finally { $dialog.Dispose() }
}
function Invoke-PerformanceUi {
    param([ValidateSet('BalancedPower', 'HighPerformancePower', 'GameGpu')][string]$Action, [switch]$Preview)
    $arguments = @{ Action = $Action; BackupRoot = $script:performanceBackupRoot }
    if ($Action -eq 'GameGpu') {
        if ([string]::IsNullOrWhiteSpace($gpuPath.Text)) { throw 'Choose the game executable first.' }
        $arguments.Executable = $gpuPath.Text
    }
    if ($Preview) {
        $result = Invoke-PerformanceAction @arguments -WhatIf
        $performanceOutput.Text = Format-PlanResult $result
        if ($Action -eq 'GameGpu') { $gpuApplyButton.Enabled = $true } else { $powerApplyButton.Enabled = $true }
        return
    }
    $tradeoff = 'Restore the normal Balanced power plan. Previous active plan is saved.'
    if ($Action -eq 'HighPerformancePower') { $tradeoff = 'High performance affects this PC and can increase power draw and heat, especially on a 14900KF. It may not improve FPS. Check cooling and benchmark. Your current plan will be saved.' }
    if ($Action -eq 'GameGpu') { $tradeoff = 'Set the selected game to prefer the high-performance GPU. Your 14900KF/4070 Ti may already use it. Existing preferences will be saved. The helper does not launch this executable.' }
    $answer = [Windows.Forms.MessageBox]::Show($form, $tradeoff + "`r`n`r`nApply this optional change?", 'Confirm performance change', 'YesNo', 'Question', 'Button2')
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    $result = Invoke-PerformanceAction @arguments -Confirm:$false
    $performanceOutput.Text = Format-PlanResult $result
    $powerApplyButton.Enabled = $false; $gpuApplyButton.Enabled = $false
    Refresh-Backups
    if ($Action -ne 'GameGpu') { Refresh-PowerChoices }
    if ($result.Failed -gt 0) { Show-Error 'The change failed. Read the results and check Undo before retrying.' }
}

$scanButton.Add_Click({ Invoke-UiAction { Refresh-PC } })
$displayButton.Add_Click({ Open-WindowsSetting 'ms-settings:display' })
$gameSettingsButton.Add_Click({ Open-WindowsSetting 'ms-settings:gaming-gamemode' })
$startupButton.Add_Click({ Open-WindowsSetting 'ms-settings:startupapps' })
$installedButton.Add_Click({ Open-WindowsSetting 'ms-settings:appsfeatures' })
$refreshBackupButton.Add_Click({ Invoke-UiAction { Refresh-Backups } })
$presetButton.Add_Click({
    foreach ($row in $tweakList.Items) {
        $row.Checked = @($script:catalog | Where-Object { $_.Id -eq $row.Tag -and $_.Recommended }).Count -gt 0
    }
    $tuneOutput.Text = 'Conservative preset: Game Mode only. Recording and personal input/desktop preferences are unchanged unless you select their options. Preview this selection first.'
})
$clearButton.Add_Click({ foreach ($row in $tweakList.Items) { $row.Checked = $false } })
$tweakList.Add_ItemChecked({ $applyButton.Enabled = $false })
$powerChoice.Add_SelectedIndexChanged({ $powerApplyButton.Enabled = $false })
$powerPanel.Add_SizeChanged({ $powerNote.Width = [Math]::Max(100, $powerPanel.ClientSize.Width - 24) })
$gpuPanel.Add_SizeChanged({ $gpuNote.Width = [Math]::Max(100, $gpuPanel.ClientSize.Width - 24) })
$powerPreviewButton.Add_Click({ Invoke-UiAction {
    if ($null -eq $powerChoice.SelectedItem) { throw 'No supported power plan is selected.' }
    Invoke-PerformanceUi -Action $powerChoice.SelectedItem.Action -Preview
} })
$powerApplyButton.Add_Click({ Invoke-UiAction {
    if ($null -eq $powerChoice.SelectedItem) { throw 'No supported power plan is selected.' }
    Invoke-PerformanceUi -Action $powerChoice.SelectedItem.Action
} })
$gpuBrowseButton.Add_Click({ Invoke-UiAction {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter = 'Game executable (*.exe)|*.exe'; $dialog.CheckFileExists = $true
    try { if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) { $gpuPath.Text = $dialog.FileName; $gpuApplyButton.Enabled = $false } }
    finally { $dialog.Dispose() }
} })
$gpuPreviewButton.Add_Click({ Invoke-UiAction { Invoke-PerformanceUi -Action 'GameGpu' -Preview } })
$gpuApplyButton.Add_Click({ Invoke-UiAction { Invoke-PerformanceUi -Action 'GameGpu' } })
$graphicsButton.Add_Click({ Open-WindowsSetting 'ms-settings:display-advancedgraphics' })
$guideList.Add_SelectedIndexChanged({
    if ($null -eq $guideList.SelectedItem) { return }
    $guide = $guideList.SelectedItem.Guide
    $guideText.Text = @($guide.Name, '', ('Category: ' + $guide.Category), '', ($guide.Steps -join "`r`n`r`n"), '', ('Tradeoff: ' + $guide.Tradeoff)) -join "`r`n"
    $guideSettingsButton.Enabled = -not [string]::IsNullOrWhiteSpace($guide.SettingsUri)
    $guideReferenceButton.Enabled = -not [string]::IsNullOrWhiteSpace($guide.ReferenceUrl)
})
$guideSettingsButton.Add_Click({ Invoke-UiAction {
    if ($null -eq $guideList.SelectedItem) { return }
    $uri = [string]$guideList.SelectedItem.Guide.SettingsUri
    if ($uri -notin @('ms-settings:display-advanced', 'ms-settings:display-advancedgraphics', 'ms-settings:startupapps', 'ms-settings:appsfeatures', 'ms-settings:gaming-gamedvr', 'ms-settings:storagesense', 'ms-settings:network-status', 'ms-settings:sound', 'ms-settings:windowsupdate', 'ms-settings:windowsdefender', 'ms-settings:gaming-gamemode')) { throw 'Unsupported Settings link.' }
    Start-Process -FilePath $uri -ErrorAction Stop
} })
$guideReferenceButton.Add_Click({ Invoke-UiAction {
    if ($null -eq $guideList.SelectedItem) { return }
    $uri = [uri]$guideList.SelectedItem.Guide.ReferenceUrl
    if ($uri.Scheme -ne 'https' -or $uri.Host -notin @('intel.com', 'www.intel.com', 'nvidia.com', 'www.nvidia.com', 'support.microsoft.com')) { throw 'Unsupported reference website.' }
    Start-Process -FilePath $uri.AbsoluteUri -ErrorAction Stop
} })
$baselineButton.Add_Click({ Invoke-UiAction { Select-BenchmarkFile -Baseline $true } })
$afterButton.Add_Click({ Invoke-UiAction { Select-BenchmarkFile -Baseline $false } })
$resetBenchmarkButton.Add_Click({ $script:baseline = $null; $script:after = $null; $benchmarkText.Text = 'Comparison cleared. Import baseline and test CSV captures.' })
$previewButton.Add_Click({
    Invoke-UiAction {
        $ids = @(Get-SelectedTweakIds)
        if ($ids.Count -eq 0) { throw 'Select at least one optional setting first.' }
        $result = Invoke-GamingPlan -Ids $ids -BackupRoot $script:backupRoot -WhatIf
        $tuneOutput.Text = 'PREVIEW ONLY - no settings changed.' + "`r`n`r`n" + (Format-PlanResult $result)
        $applyButton.Enabled = $true
    }
})
$applyButton.Add_Click({
    Invoke-UiAction {
        $ids = @(Get-SelectedTweakIds)
        if ($ids.Count -eq 0) { throw 'Select at least one optional setting first.' }
        $names = @($script:catalog | Where-Object { $_.Id -in $ids } | ForEach-Object { $_.Name + "`r`n" + $_.Tradeoff + "`r`n" })
        $message = "Apply these settings for this Windows user?`r`n`r`n" + ($names -join "`r`n") + "`r`n`r`nEach previous value is saved before its change. Close games first. Review tradeoffs above; use Undo to restore recorded changes."
        $answer = [Windows.Forms.MessageBox]::Show($form, $message, 'Confirm selected changes', 'YesNo', 'Question', 'Button2')
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
        $result = Invoke-GamingPlan -Ids $ids -BackupRoot $script:backupRoot -Confirm:$false
        $tuneOutput.Text = Format-PlanResult $result
        Refresh-Backups
        if ($result.Failed -gt 0) { Show-Error 'Some changes failed. Read the results and use Undo for any settings already changed.' }
    }
})
$restoreButton.Add_Click({
    Invoke-UiAction {
        if ($null -eq $backupList.SelectedItem) { throw 'Select a backup first.' }
        $path = [string]$backupList.SelectedItem.Path
        $answer = [Windows.Forms.MessageBox]::Show($form, "Restore the original values from this backup?`r`n`r`n$path`r`n`r`nValues changed afterward by another program will be skipped.", 'Confirm Undo', 'YesNo', 'Question', 'Button2')
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
        if ($backupList.SelectedItem.Kind -eq 'Performance') {
            $result = Restore-PerformanceBackup -Path $path -BackupRoot $script:performanceBackupRoot -Confirm:$false
            Refresh-PowerChoices
        } else { $result = Restore-GamingBackup -Path $path -BackupRoot $script:backupRoot -Confirm:$false }
        $restoreOutput.Text = Format-PlanResult $result
        Refresh-Backups
        if (@($result.Results | Where-Object { $_.Status -in @('Conflict', 'Failed') }).Count -gt 0) {
            [void][Windows.Forms.MessageBox]::Show($form, 'Undo needs review: some values failed or were skipped. Read the results before making more changes.', 'Undo results', 'OK', 'Information')
        }
    }
})
$form.Add_Shown({ Invoke-UiAction { Refresh-PC } })
if ($guideList.Items.Count -gt 0) { $guideList.SelectedIndex = 0 }
$form.Add_FormClosing({ param($sender, $eventArgs) if ($script:busy) { $eventArgs.Cancel = $true } })
try { [void]$form.ShowDialog() }
finally {
    $form.Dispose()
    if ($haveMutex) { $guiMutex.ReleaseMutex() }
    $guiMutex.Dispose()
}
