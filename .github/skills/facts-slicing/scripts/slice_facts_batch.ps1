#requires -Version 5.1
<#
.SYNOPSIS
  Run slice-facts.py over many sources in parallel.

.DESCRIPTION
  Reusable batch wrapper for the facts-slicing skill. Fans out
  .github/skills/facts-slicing/scripts/slice-facts.py across the given
  inputs using ForEach-Object -Parallel, captures per-file stdout/stderr/
  exit codes, persists a sorted result set to slice_results.xml, and
  exits non-zero if any child failed.

.PARAMETER Files
  Explicit list of source paths (repo-relative or absolute).

.PARAMETER Paths
  One or more directories or globs to expand (e.g. repos/sample1/COBOL/*.CBL).

.PARAMETER Manifest
  Path to a JSON/CSV file describing entries:
    [{ "path": "...", "sourceRoot": "...", "outputDir": "..." }, ...]
  Overrides -Files/-Paths.

.PARAMETER SourceRoot
  Optional --source-root applied to every input.

.PARAMETER OutputDir
  Optional --output-dir applied to every input (rare; usually leave default).

.PARAMETER Prune
  Pass --prune to every child invocation.

.PARAMETER Throttle
  Parallel degree. Defaults to [Environment]::ProcessorCount.

.PARAMETER ResultsXml
  Path for the Export-Clixml result file. Default: slice_results.xml.

.PARAMETER ExcludeExtensions
  File extensions to skip when expanding -Paths (case-insensitive). Default:
  .cob, .inp, .itt — copybooks and JCL inline-data are consumed by reference,
  not sliced standalone. Pass an empty array to disable.

.EXAMPLE
  pwsh -File .github/skills/facts-slicing/scripts/slice_facts_batch.ps1 `
       -Paths repos/sample1/COBOL/*.CBL -Prune
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [string]$OutputDir,
  [switch]$Prune,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsXml = 'temp/slice_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt')
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$slicePy   = Join-Path $scriptDir 'slice-facts.py'
if (-not (Test-Path $slicePy)) { throw "slice-facts.py not found at $slicePy" }

$entries = [System.Collections.Generic.List[object]]::new()

if ($Manifest) {
  $raw = Get-Content -Raw -LiteralPath $Manifest
  $items =
    if ($Manifest -match '\.csv$') { $raw | ConvertFrom-Csv }
    else                            { $raw | ConvertFrom-Json }
  foreach ($i in $items) {
    $entries.Add([pscustomobject]@{
      Path       = [string]$i.path
      SourceRoot = [string]$i.sourceRoot
      OutputDir  = [string]$i.outputDir
    })
  }
}
else {
  $collected = @()
  if ($Files) { $collected += $Files }
  if ($Paths) {
    $excludeSet = @{}
    foreach ($e in $ExcludeExtensions) {
      if ($e) { $excludeSet[$e.ToLowerInvariant()] = $true }
    }
    foreach ($p in $Paths) {
      $collected += (Get-ChildItem -Path $p -File -ErrorAction Stop |
        Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
        ForEach-Object { $_.FullName })
    }
  }
  if (-not $collected) { throw 'No inputs. Provide -Files, -Paths, or -Manifest.' }
  foreach ($f in $collected | Select-Object -Unique) {
    $entries.Add([pscustomobject]@{
      Path       = $f
      SourceRoot = $SourceRoot
      OutputDir  = $OutputDir
    })
  }
}

$entries = @($entries | Sort-Object Path)
$pruneFlag = [bool]$Prune

Write-Host "Slicing facts for $($entries.Count) file(s) with throttle=$Throttle"

$__helperDir = Split-Path -Parent $PSCommandPath
while ($__helperDir -and -not (Test-Path (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1'))) {
  $__parent = Split-Path -Parent $__helperDir
  if ($__parent -eq $__helperDir) { throw 'Invoke-PythonBatch.ps1 helper not found (walked to filesystem root).' }
  $__helperDir = $__parent
}
. (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1')

$results = Invoke-PythonBatch -Entries $entries -Throttle $Throttle `
  -Variables @{ slicePy = $slicePy; pruneFlag = $pruneFlag } `
  -BuildArgs {
  param($entry)
  $argv = @($slicePy, '--source', $entry.Path)
  if ($entry.SourceRoot) { $argv += @('--source-root', $entry.SourceRoot) }
  if ($entry.OutputDir)  { $argv += @('--output-dir', $entry.OutputDir) }
  if ($pruneFlag)        { $argv += '--prune' }
  return ,$argv
}
$results = @($results | Sort-Object Path)

$results | Export-Clixml -LiteralPath $ResultsXml

$failed = @($results | Where-Object { $_.Exit -ne 0 })
$ok     = $results.Count - $failed.Count

Write-Host "DONE total=$($results.Count) ok=$ok failed=$($failed.Count)"
if ($failed.Count -gt 0) {
  Write-Host 'Failures:'
  $failed | ForEach-Object { Write-Host "  [$($_.Exit)] $($_.Path)" }
  exit 1
}
exit 0
