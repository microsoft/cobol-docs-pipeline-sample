<#
.SYNOPSIS
  Aggregate every *_results*.xml CLIXML batch/dispatch result file into a single
  Markdown perf dashboard.

.DESCRIPTION
  Each `run-docs-*-batch.ps1` / `*_batch.ps1` writer exports a `[pscustomobject[]]`
  via `Export-Clixml`. Two shapes are emitted across the pipeline:
    - Batch shape   (chunk, extract, slice, facts): Path, Exit, Stdout, Stderr
    - Dispatch shape (Copilot dispatchers):         TaskId, BundlePath, Exit,
                                                    Status, DurationMs, Attempts

  This script imports every matched file, normalises both shapes into a common
  record, and renders a Markdown report containing per-file counts, a
  cross-pipeline status histogram, p50/p95/p99 duration percentiles, retry
  statistics, and the top-N slowest tasks across the entire run.

.PARAMETER Paths
  One or more file globs (relative to -WorkingDirectory) or absolute paths.
  Default: the canonical 11 phase result files in the repo root.

.PARAMETER OutputPath
  Markdown destination. Default: temp/results-summary.md.

.PARAMETER WorkingDirectory
  Base for relative Paths. Default: current directory.

.PARAMETER TopSlowest
  Number of slowest tasks to list. Default: 10.

.EXAMPLE
  pwsh -File scripts/lib/aggregate-results.ps1
  pwsh -File scripts/lib/aggregate-results.ps1 -Paths copilot_*_results.xml -TopSlowest 25
#>
[CmdletBinding()]
param(
  [string[]]$Paths = @('*_results*.xml'),
  [string]$OutputPath = 'temp/results-summary.md',
  [string]$WorkingDirectory = (Get-Location).Path,
  [ValidateRange(1, 200)][int]$TopSlowest = 10
)

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Percentile {
  param([double[]]$Values, [double]$P)
  if (-not $Values -or $Values.Count -eq 0) { return $null }
  $sorted = @($Values | Sort-Object)
  $rank = [Math]::Ceiling(($P / 100.0) * $sorted.Count) - 1
  if ($rank -lt 0) { $rank = 0 }
  if ($rank -ge $sorted.Count) { $rank = $sorted.Count - 1 }
  return $sorted[$rank]
}

function Get-StatusFromRecord {
  param($Record)
  if ($Record.PSObject.Properties.Match('Status').Count -gt 0 -and $Record.Status) {
    return [string]$Record.Status
  }
  if ($Record.PSObject.Properties.Match('Exit').Count -gt 0) {
    if ($null -eq $Record.Exit) { return 'unknown' }
    return $(if ([int]$Record.Exit -eq 0) { 'ok' } else { "exit=$($Record.Exit)" })
  }
  return 'unknown'
}

function Get-KeyFromRecord {
  param($Record)
  foreach ($name in @('TaskId', 'SourceName', 'GroupId', 'SectionId', 'Path', 'BundlePath')) {
    if ($Record.PSObject.Properties.Match($name).Count -gt 0 -and $Record.$name) {
      return [string]$Record.$name
    }
  }
  return '(no-key)'
}

function ConvertTo-NormalizedRecord {
  param($Raw, [string]$SourceFile)
  $duration = 0
  if ($Raw.PSObject.Properties.Match('DurationMs').Count -gt 0 -and $null -ne $Raw.DurationMs) {
    $duration = [int]$Raw.DurationMs
  }
  $attempts = $null
  if ($Raw.PSObject.Properties.Match('Attempts').Count -gt 0 -and $null -ne $Raw.Attempts) {
    $attempts = [int]$Raw.Attempts
  }
  $exit = $null
  if ($Raw.PSObject.Properties.Match('Exit').Count -gt 0 -and $null -ne $Raw.Exit) {
    $exit = [int]$Raw.Exit
  }
  [pscustomobject]@{
    File       = $SourceFile
    Key        = Get-KeyFromRecord -Record $Raw
    Status     = Get-StatusFromRecord -Record $Raw
    Exit       = $exit
    DurationMs = $duration
    Attempts   = $attempts
  }
}

Push-Location $WorkingDirectory
try {
  $files = New-Object System.Collections.Generic.List[string]
  foreach ($p in $Paths) {
    $resolved = @()
    try {
      $resolved = Get-ChildItem -Path $p -File -ErrorAction Stop | ForEach-Object { $_.FullName }
    } catch {
      Write-Warning "no match: $p"
      continue
    }
    foreach ($f in $resolved) { [void]$files.Add($f) }
  }
  $files = @($files | Sort-Object -Unique)

  if (-not $files -or $files.Count -eq 0) {
    Write-Warning "No *_results*.xml files found under '$WorkingDirectory'."
    exit 1
  }

  $allRecords = New-Object System.Collections.Generic.List[object]
  $perFile = New-Object System.Collections.Generic.List[object]
  $errors  = New-Object System.Collections.Generic.List[object]

  foreach ($f in $files) {
    $name = [IO.Path]::GetFileName($f)
    try {
      $raw = Import-Clixml -LiteralPath $f
    } catch {
      $errors.Add([pscustomobject]@{ File = $name; Error = $_.Exception.Message })
      continue
    }
    if ($null -eq $raw) { continue }
    $records = @($raw | ForEach-Object { ConvertTo-NormalizedRecord -Raw $_ -SourceFile $name })

    $count = $records.Count
    $okCount = @($records | Where-Object { $_.Status -eq 'ok' -or $_.Exit -eq 0 }).Count
    $failCount = @($records | Where-Object {
      ($_.Status -notin @('ok','skipped-up-to-date','skipped-opt-out','dry-run','missing-bundle','missing-bundles-dir','no-section-bundles')) -and
      ($_.Exit -ne 0 -and $null -ne $_.Exit)
    }).Count
    $skipCount = @($records | Where-Object { $_.Status -like 'skipped*' -or $_.Status -eq 'dry-run' }).Count
    $durations = @($records | Where-Object { $_.DurationMs -gt 0 } | ForEach-Object { [double]$_.DurationMs })
    $totalSec = if ($durations) { [Math]::Round(($durations | Measure-Object -Sum).Sum / 1000.0, 1) } else { 0 }
    $retries  = @($records | Where-Object { $_.Attempts -ne $null -and $_.Attempts -gt 1 })

    $perFile.Add([pscustomobject]@{
      File       = $name
      Count      = $count
      Ok         = $okCount
      Skipped    = $skipCount
      Failed     = $failCount
      Retried    = $retries.Count
      TotalSec   = $totalSec
      P50ms      = if ($durations) { [int](Get-Percentile -Values $durations -P 50) } else { 0 }
      P95ms      = if ($durations) { [int](Get-Percentile -Values $durations -P 95) } else { 0 }
      P99ms      = if ($durations) { [int](Get-Percentile -Values $durations -P 99) } else { 0 }
    })
    foreach ($r in $records) { [void]$allRecords.Add($r) }
  }

  # Global status histogram
  $statusHist = @($allRecords | Group-Object Status |
    Sort-Object Count -Descending |
    Select-Object @{N='Status';E={$_.Name}}, Count)

  # Global duration percentiles
  $allDurations = @($allRecords | Where-Object { $_.DurationMs -gt 0 } | ForEach-Object { [double]$_.DurationMs })
  $globalP50 = if ($allDurations) { [int](Get-Percentile -Values $allDurations -P 50) } else { 0 }
  $globalP95 = if ($allDurations) { [int](Get-Percentile -Values $allDurations -P 95) } else { 0 }
  $globalP99 = if ($allDurations) { [int](Get-Percentile -Values $allDurations -P 99) } else { 0 }
  $globalTotalSec = if ($allDurations) { [Math]::Round(($allDurations | Measure-Object -Sum).Sum / 1000.0, 1) } else { 0 }

  # Top-N slowest
  $slowest = @($allRecords |
    Where-Object { $_.DurationMs -gt 0 } |
    Sort-Object DurationMs -Descending |
    Select-Object -First $TopSlowest)

  # Retry summary
  $retriedAll = @($allRecords | Where-Object { $_.Attempts -ne $null -and $_.Attempts -gt 1 })
  $retrySuccess = @($retriedAll | Where-Object { $_.Status -eq 'ok' -or $_.Exit -eq 0 }).Count
  $retryFail    = $retriedAll.Count - $retrySuccess

  # Render markdown
  $sb = [System.Text.StringBuilder]::new()
  $now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  [void]$sb.AppendLine("# Pipeline results summary")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("- Generated: $now")
  [void]$sb.AppendLine("- Files scanned: $($files.Count)")
  [void]$sb.AppendLine("- Total records: $($allRecords.Count)")
  [void]$sb.AppendLine("- Total dispatch time: $globalTotalSec s")
  [void]$sb.AppendLine("- Global duration p50 / p95 / p99 (ms): $globalP50 / $globalP95 / $globalP99")
  if ($retriedAll.Count -gt 0) {
    [void]$sb.AppendLine("- Retried tasks: $($retriedAll.Count) (succeeded after retry: $retrySuccess, still failed: $retryFail)")
  }
  [void]$sb.AppendLine("")

  [void]$sb.AppendLine("## Per-file aggregates")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("| File | Count | Ok | Skipped | Failed | Retried | Total (s) | p50 (ms) | p95 (ms) | p99 (ms) |")
  [void]$sb.AppendLine("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
  foreach ($row in ($perFile | Sort-Object File)) {
    [void]$sb.AppendLine(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f `
      $row.File, $row.Count, $row.Ok, $row.Skipped, $row.Failed, $row.Retried, `
      $row.TotalSec, $row.P50ms, $row.P95ms, $row.P99ms))
  }
  [void]$sb.AppendLine("")

  [void]$sb.AppendLine("## Status histogram (all files)")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("| Status | Count |")
  [void]$sb.AppendLine("|---|---:|")
  foreach ($s in $statusHist) {
    [void]$sb.AppendLine(("| {0} | {1} |" -f $s.Status, $s.Count))
  }
  [void]$sb.AppendLine("")

  [void]$sb.AppendLine("## Top $TopSlowest slowest tasks")
  [void]$sb.AppendLine("")
  if ($slowest) {
    [void]$sb.AppendLine("| File | Key | Status | Duration (ms) | Attempts |")
    [void]$sb.AppendLine("|---|---|---|---:|---:|")
    foreach ($t in $slowest) {
      $att = if ($null -ne $t.Attempts) { $t.Attempts } else { '' }
      [void]$sb.AppendLine(("| {0} | {1} | {2} | {3} | {4} |" -f `
        $t.File, $t.Key, $t.Status, $t.DurationMs, $att))
    }
  } else {
    [void]$sb.AppendLine("_No tasks reported a non-zero duration._")
  }
  [void]$sb.AppendLine("")

  if ($errors.Count -gt 0) {
    [void]$sb.AppendLine("## Files that failed to import")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| File | Error |")
    [void]$sb.AppendLine("|---|---|")
    foreach ($e in $errors) {
      [void]$sb.AppendLine(("| {0} | {1} |" -f $e.File, ($e.Error -replace '\|','\|')))
    }
    [void]$sb.AppendLine("")
  }

  $outFull = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $WorkingDirectory $OutputPath }
  $outDir = Split-Path -Parent $outFull
  if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    [void](New-Item -ItemType Directory -Path $outDir -Force)
  }
  [System.IO.File]::WriteAllText($outFull, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
  Write-Host "Wrote $outFull ($($files.Count) files, $($allRecords.Count) records)"
} finally {
  Pop-Location
}
