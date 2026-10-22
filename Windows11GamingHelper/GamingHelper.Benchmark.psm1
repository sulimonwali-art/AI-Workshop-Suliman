# Offline frame-time analysis. Compatible with Windows PowerShell 5.1.
Set-StrictMode -Version 2.0

function Measure-GamingFrameTimes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][double[]]$FrameTimeMs, [string]$Label = 'Run')
    if ($FrameTimeMs.Count -lt 100) { throw 'Use at least 100 positive frame times for a useful comparison.' }
    $total = 0.0
    foreach ($value in $FrameTimeMs) {
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -le 0) {
            throw 'Frame times must be finite, positive milliseconds.'
        }
        $total += $value
    }
    if ([double]::IsInfinity($total)) { throw 'Frame-time total is too large.' }
    $sorted = [double[]]$FrameTimeMs.Clone()
    [array]::Sort($sorted)
    $count = $sorted.Length
    $slowCount = [int][Math]::Ceiling($count * 0.01)
    $slowTotal = 0.0
    for ($i = $count - $slowCount; $i -lt $count; $i++) { $slowTotal += $sorted[$i] }
    $tinyLow = $null
    if ($count -ge 1000) {
        $tinyCount = [int][Math]::Ceiling($count * 0.001)
        $tinyTotal = 0.0
        for ($i = $count - $tinyCount; $i -lt $count; $i++) { $tinyTotal += $sorted[$i] }
        $tinyLow = [Math]::Round((1000.0 * $tinyCount / $tinyTotal), 2)
    }
    [pscustomobject]@{
        Label = $Label; Frames = $count
        DurationSeconds = [Math]::Round($total / 1000.0, 2)
        AverageFps = [Math]::Round(1000.0 * $count / $total, 2)
        OnePercentLowFps = [Math]::Round(1000.0 * $slowCount / $slowTotal, 2)
        PointOnePercentLowFps = $tinyLow
        P99FrameTimeMs = [Math]::Round($sorted[[int][Math]::Ceiling($count * 0.99) - 1], 3)
        FramesOver50ms = @($FrameTimeMs | Where-Object { $_ -gt 50.0 }).Count
        SourceColumn = 'FrameTimeMs'; DiscardedZeroRows = 0
    }
}

function Import-GamingBenchmark {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label = 'Run')
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Extension -ine '.csv' -or $file.Length -gt 52428800) {
        throw 'Choose a CSV file no larger than 50 MB.'
    }
    $rows = @(Import-Csv -LiteralPath $file.FullName -ErrorAction Stop)
    if ($rows.Count -eq 0) { throw 'The CSV contains no data rows.' }
    $columns = @($rows[0].PSObject.Properties.Name)
    $column = $null
    foreach ($candidate in @('MsBetweenPresents', 'FrameTimeMs', 'Frame Time (ms)', 'Frametime (ms)')) {
        if ($columns -contains $candidate) { $column = $candidate; break }
    }
    if (-not $column) { throw 'Use comma-delimited CSV with MsBetweenPresents, FrameTimeMs, Frame Time (ms), or Frametime (ms). Values must be milliseconds with a decimal point.' }
    # PresentMon can combine processes and swap chains: do not report a misleading FPS.
    foreach ($identityColumn in @('Application', 'ProcessID', 'ProcessId', 'SwapChainAddress')) {
        if ($columns -cnotcontains $identityColumn) { continue }
        $distinct = @{}
        foreach ($row in $rows) {
            $identity = [string]$row.$identityColumn
            if (-not [string]::IsNullOrWhiteSpace($identity)) { $distinct[$identity] = $true }
            if ($distinct.Count -gt 1) { throw "The CSV mixes multiple $identityColumn values. Export one game/process and one swap chain before comparing." }
        }
    }
    $times = New-Object 'Collections.Generic.List[double]'
    $zeros = 0; $rowNumber = 1
    foreach ($row in $rows) {
        $rowNumber++
        $number = 0.0
        $valid = [double]::TryParse([string]$row.$column, [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$number)
        if (-not $valid -or [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0) {
            throw "Invalid millisecond frame time at CSV line $rowNumber. No outliers have been removed."
        }
        if ($number -eq 0) { $zeros++; continue }
        $times.Add($number)
    }
    $result = Measure-GamingFrameTimes -FrameTimeMs $times.ToArray() -Label $Label
    $result.SourceColumn = $column
    $result.DiscardedZeroRows = $zeros
    return $result
}

function Compare-GamingBenchmarks {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Before, [Parameter(Mandatory = $true)]$After)
    if ($Before.SourceColumn -cne $After.SourceColumn) {
        throw 'Use the same frame-time column and capture method for both runs.'
    }
    foreach ($metric in @('AverageFps', 'OnePercentLowFps', 'PointOnePercentLowFps', 'P99FrameTimeMs')) {
        $baseline = $Before.$metric; $measured = $After.$metric
        $change = $null
        if ($null -ne $baseline -and $null -ne $measured -and [double]$baseline -gt 0) {
            $change = [Math]::Round((([double]$measured / [double]$baseline) - 1.0) * 100.0, 2)
        }
        [pscustomobject]@{
            Metric = $metric; Before = $baseline; After = $measured; ChangePercent = $change
            Better = $(if ($metric -eq 'P99FrameTimeMs') { 'Lower' } else { 'Higher' })
        }
    }
}

Export-ModuleMember -Function Measure-GamingFrameTimes, Import-GamingBenchmark, Compare-GamingBenchmarks
