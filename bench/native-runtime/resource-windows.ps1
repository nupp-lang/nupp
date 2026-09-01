param(
    [Parameter(Mandatory = $true)]
    [string]$Benchmark,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-ChildText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    return [string](Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
}

function Child-Diagnostics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,

        [Parameter(Mandatory = $true)]
        [string]$ErrorOutput
    )

    $stdout = [string](Read-ChildText -Path $Output)
    $stderr = [string](Read-ChildText -Path $ErrorOutput)
    $stdout = $stdout.Trim()
    $stderr = $stderr.Trim()
    return "stdout=[$stdout] stderr=[$stderr]"
}

function Start-Benchmark {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$Output,

        [Parameter(Mandatory = $true)]
        [string]$ErrorOutput
    )

    $parameters = @{
        FilePath = $Benchmark
        PassThru = $true
        RedirectStandardOutput = $Output
        RedirectStandardError = $ErrorOutput
    }
    if ($Mode -ne "load") {
        $parameters.ArgumentList = @($Mode)
    }

    return Start-Process @parameters
}

function Stop-Benchmark {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process
    )

    if (-not $Process.HasExited) {
        $Process.Kill()
    }
    $Process.WaitForExit()
    $Process.Dispose()
}

function Wait-BenchmarkPid {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$Output,

        [Parameter(Mandatory = $true)]
        [string]$ErrorOutput
    )

    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        $lines = @()
        if (Test-Path -LiteralPath $Output) {
            $lines = @(
                Get-Content -LiteralPath $Output -ErrorAction Stop |
                    Where-Object { $_ -match '^NUPP_BENCH_PID(?:\s|$)' }
            )
        }
        if ($lines.Count -gt 0) {
            if ($lines.Count -ne 1) {
                throw "$Mode reported $($lines.Count) native process ID markers"
            }
            $line = [string]$lines[0]
            if ($line -notmatch '^NUPP_BENCH_PID ([1-9][0-9]*)\s*$') {
                throw "$Mode reported an invalid native process ID marker: $line"
            }
            $reportedPid = [long]$Matches[1]
            if ($reportedPid -ne [long]$Process.Id) {
                throw "$Mode reported native PID $reportedPid, but PowerShell launched PID $($Process.Id)"
            }
            return $reportedPid
        }
        if ($Process.HasExited) {
            $details = Child-Diagnostics -Output $Output -ErrorOutput $ErrorOutput
            throw "$Mode ended before reporting its native process ID: $details"
        }
        Start-Sleep -Milliseconds 10
    }

    $details = Child-Diagnostics -Output $Output -ErrorOutput $ErrorOutput
    throw "$Mode did not report its native process ID: $details"
}

function Wait-BenchmarkReady {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$Output,

        [Parameter(Mandatory = $true)]
        [string]$ErrorOutput
    )

    $expected = "READY $Mode"
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $Output) {
            $ready = @(
                Get-Content -LiteralPath $Output -ErrorAction Stop |
                    Where-Object { $_.TrimEnd() -eq $expected }
            )
            if ($ready.Count -gt 0) {
                return
            }
        }
        if ($Process.HasExited) {
            $details = Child-Diagnostics -Output $Output -ErrorOutput $ErrorOutput
            throw "$Mode ended before becoming ready: $details"
        }
        Start-Sleep -Milliseconds 10
    }

    $details = Child-Diagnostics -Output $Output -ErrorOutput $ErrorOutput
    throw "$Mode did not become ready: $details"
}

function Read-RssKiB {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,

        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    try {
        $Process.Refresh()
        if ($Process.HasExited) {
            return $null
        }
        $rss = [long][Math]::Floor($Process.WorkingSet64 / 1KB)
    }
    catch {
        if ($Process.HasExited) {
            return $null
        }
        throw "$Mode RSS sampling failed for PID $($Process.Id): $($_.Exception.Message)"
    }
    if ($rss -le 0) {
        throw "$Mode produced an invalid RSS sample for PID $($Process.Id): $rss"
    }

    return $rss
}

function Measure-Load {
    $mode = "load"
    $output = Join-Path $OutputDirectory "$mode.out"
    $errorOutput = Join-Path $OutputDirectory "$mode.err"
    $process = Start-Benchmark -Mode $mode -Output $output -ErrorOutput $errorOutput
    try {
        # Sample once before waiting for the marker so even a short benchmark
        # cannot finish during process discovery without an observation.
        $rss = Read-RssKiB -Process $process -Mode $mode
        $peak = 0L
        $sampleCount = 0
        if ($null -ne $rss) {
            $peak = $rss
            $sampleCount = 1
        }
        Wait-BenchmarkPid -Process $process -Mode $mode -Output $output -ErrorOutput $errorOutput | Out-Null
        while (-not $process.HasExited) {
            $rss = Read-RssKiB -Process $process -Mode $mode
            if ($null -eq $rss) {
                break
            }
            $sampleCount += 1
            if ($rss -gt $peak) {
                $peak = $rss
            }
            Start-Sleep -Milliseconds 50
        }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            $details = Child-Diagnostics -Output $output -ErrorOutput $errorOutput
            throw "$mode exited with status $($process.ExitCode): $details"
        }
        if ($sampleCount -eq 0) {
            throw "$mode benchmark ended without an RSS sample"
        }
        "load peak_rss_kib=$peak"
    }
    finally {
        Stop-Benchmark -Process $process
    }
}

function Measure-SlowMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    $output = Join-Path $OutputDirectory "$Mode.out"
    $errorOutput = Join-Path $OutputDirectory "$Mode.err"
    $process = Start-Benchmark -Mode $Mode -Output $output -ErrorOutput $errorOutput
    try {
        Wait-BenchmarkPid -Process $process -Mode $Mode -Output $output -ErrorOutput $errorOutput | Out-Null
        Wait-BenchmarkReady -Process $process -Mode $Mode -Output $output -ErrorOutput $errorOutput
        $previousSecond = 0
        foreach ($second in @(1, 3, 5)) {
            Start-Sleep -Seconds ($second - $previousSecond)
            $rss = Read-RssKiB -Process $process -Mode $Mode
            if ($null -eq $rss) {
                $details = Child-Diagnostics -Output $output -ErrorOutput $errorOutput
                throw "$Mode ended before the $second second RSS sample: $details"
            }
            "$Mode second=$second rss_kib=$rss"
            $previousSecond = $second
        }
    }
    finally {
        Stop-Benchmark -Process $process
    }
}

if (-not (Test-Path -LiteralPath $Benchmark -PathType Leaf)) {
    throw "native runtime benchmark does not exist: $Benchmark"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Measure-Load
Measure-SlowMode -Mode "net-slow-reader"
Measure-SlowMode -Mode "net-slow-writer"
Measure-SlowMode -Mode "http-slow-reader"
Measure-SlowMode -Mode "http-slow-writer"
