[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\GamingHelper.Benchmark.psm1') -Force
$passed = 0; $failed = 0
function Check {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:passed++; Write-Host "PASS $Name" }
    catch { $script:failed++; Write-Host "FAIL ${Name}: $($_.Exception.Message)" }
}
function Equal { param($Actual, $Expected) if ($Actual -ne $Expected) { throw "Expected $Expected, received $Actual" } }
function Throws { param([scriptblock]$Body) $caught=$false; try { & $Body | Out-Null } catch { $caught=$true }; if (-not $caught) { throw 'Expected rejection.' } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('gaming-bench-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
    Check 'constant 10ms frames give 100 FPS and 10ms p99' {
        $m = Measure-GamingFrameTimes -FrameTimeMs (@(10.0) * 100)
        Equal $m.AverageFps 100; Equal $m.OnePercentLowFps 100
        Equal $m.P99FrameTimeMs 10; Equal $m.FramesOver50ms 0
        Equal $m.PointOnePercentLowFps $null
    }
    Check 'slowest1% mean differs from overall FPS and p99' {
        $m = Measure-GamingFrameTimes -FrameTimeMs ((@(10.0) * 99) + @(100.0))
        Equal $m.OnePercentLowFps 10; Equal $m.AverageFps 91.74
        Equal $m.P99FrameTimeMs 10; Equal $m.FramesOver50ms 1
    }
    Check '0.1% low requires1000 frames and keeps slow outliers' {
        $m = Measure-GamingFrameTimes -FrameTimeMs ((@(10.0) * 999) + @(1000.0))
        Equal $m.PointOnePercentLowFps 1; Equal $m.OnePercentLowFps 9.17
    }
    Check 'bad frame times and undersized samples are rejected' {
        foreach ($bad in @(0, -1, [double]::NaN, [double]::PositiveInfinity)) {
            Throws { Measure-GamingFrameTimes -FrameTimeMs ((@(10.0) * 99) + @($bad)) }
        }
        Throws { Measure-GamingFrameTimes -FrameTimeMs (@(10.0) * 99) }
    }
    $path = Join-Path $root 'frames.csv'
    Check 'PresentMon import preserves timings and reports zero rows' {
        @('Application,ProcessID,SwapChainAddress,MsBetweenPresents', 'game.exe,1,0x1,0') + (@('game.exe,1,0x1,10') * 100) | Set-Content -LiteralPath $path
        $m = Import-GamingBenchmark -Path $path
        Equal $m.SourceColumn 'MsBetweenPresents'; Equal $m.Frames 100; Equal $m.DiscardedZeroRows 1
    }
    Check 'mixed processes and swap chains are rejected' {
        foreach ($row in @('other.exe,1,0x1,10', 'game.exe,2,0x1,10', 'game.exe,1,0x2,10')) {
            @('Application,ProcessID,SwapChainAddress,MsBetweenPresents', 'game.exe,1,0x1,10', $row) | Set-Content -LiteralPath $path
            Throws { Import-GamingBenchmark -Path $path }
        }
    }
    Check 'explicit ms header accepted and invalid data rejected' {
        @('FrameTimeMs') + (@('20') * 100) | Set-Content -LiteralPath $path
        Equal (Import-GamingBenchmark -Path $path).AverageFps 50
        Add-Content -LiteralPath $path -Value 'invalid'
        Throws { Import-GamingBenchmark -Path $path }
        @('FPS') + (@('60') * 100) | Set-Content -LiteralPath $path
        Throws { Import-GamingBenchmark -Path $path }
    }
    Check 'comparison reports signed changes and lower frame time as better' {
        $a = Measure-GamingFrameTimes -FrameTimeMs (@(20.0) * 100)
        $b = Measure-GamingFrameTimes -FrameTimeMs (@(10.0) * 100)
        $comparison = @(Compare-GamingBenchmarks -Before $a -After $b)
        Equal $comparison[0].ChangePercent 100
        Equal $comparison[3].ChangePercent -50; Equal $comparison[3].Better 'Lower'
        Equal $comparison[2].ChangePercent $null
        $b.SourceColumn = 'Different'; Throws { Compare-GamingBenchmarks -Before $a -After $b }
    }
} finally { Remove-Item -LiteralPath $root -Force -Recurse; Remove-Module GamingHelper.Benchmark }
Write-Host "Benchmark tests: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
