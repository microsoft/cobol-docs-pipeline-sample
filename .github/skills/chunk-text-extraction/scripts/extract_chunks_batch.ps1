#requires -Version 5.1
<#
.SYNOPSIS
  Run extract-chunks.py over many sources in parallel.

.DESCRIPTION
  Reusable batch wrapper for the chunk-text-extraction skill. Fans out
  .github/skills/chunk-text-extraction/scripts/extract-chunks.py across
  the given inputs using ForEach-Object -Parallel, captures per-file
  stdout/stderr/exit codes, persists a sorted result set to
  chunk_text_results.xml, and exits non-zero if any child failed.

.PARAMETER Files
  Explicit list of source paths (repo-relative or absolute).

.PARAMETER Paths
  One or more directories or globs to expand (e.g. repos/sample1/COBOL/*.CBL).

.PARAMETER Manifest
  Path to a JSON/CSV file describing entries:
    [{ "path": "...", "sourceRoot": "...", "outputDir": "...", "manifest": "..." }, ...]
  Overrides -Files/-Paths.

.PARAMETER SourceRoot
  Optional --source-root applied to every input.

.PARAMETER OutputDir
  Optional --output-dir applied to every input (rarely useful in batch mode;
  most callers want the per-file default docs/_shared/<file>/chunks/).

.PARAMETER Prune
  Pass --prune to every child invocation.

.PARAMETER Throttle
  Parallel degree. Defaults to [Environment]::ProcessorCount.

.PARAMETER ResultsXml
  Path for the Export-Clixml result file. Default: chunk_text_results.xml in CWD.

.PARAMETER ExcludeExtensions
  File extensions to skip when expanding -Paths (case-insensitive). Default:
  .cob, .inp, .itt (copybooks and JCL inline-data are consumed by reference,
  not chunked standalone). Pass an empty array to disable.

.EXAMPLE
  pwsh -File .github/skills/chunk-text-extraction/scripts/extract_chunks_batch.ps1 `
       -Paths repos/sample1/COBOL/*.CBL
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
  [string]$ResultsXml = 'temp/chunk_text_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt')
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$extractPy = Join-Path $scriptDir 'extract-chunks.py'
if (-not (Test-Path $extractPy)) { throw "extract-chunks.py not found at $extractPy" }

# Build entry list: @{ Path; SourceRoot; OutputDir; ManifestIn }
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
      ManifestIn = [string]$i.manifest
    })
  }
}
else {
  $collected = @()
  $excludeSet = @{}
  foreach ($e in $ExcludeExtensions) {
    if ($e) { $excludeSet[$e.ToLowerInvariant()] = $true }
  }

  if ($Files) {
    foreach ($f in $Files) {
      if ((Test-Path -LiteralPath $f -PathType Container)) {
        $collected += (Get-ChildItem -LiteralPath $f -File -Recurse -ErrorAction Stop |
          Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
          ForEach-Object { $_.FullName })
      }
      else {
        $collected += $f
      }
    }
  }
  if ($Paths) {
    foreach ($p in $Paths) {
      if ((Test-Path -LiteralPath $p -PathType Container)) {
        $collected += (Get-ChildItem -LiteralPath $p -File -Recurse -ErrorAction Stop |
          Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
          ForEach-Object { $_.FullName })
      }
      else {
        $collected += (Get-ChildItem -Path $p -File -ErrorAction Stop |
          Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
          ForEach-Object { $_.FullName })
      }
    }
  }
  if (-not $collected) { throw 'No inputs. Provide -Files, -Paths, or -Manifest.' }
  foreach ($f in $collected | Select-Object -Unique) {
    $entries.Add([pscustomobject]@{
      Path       = $f
      SourceRoot = $SourceRoot
      OutputDir  = $OutputDir
      ManifestIn = $null
    })
  }
}

$entries = @($entries | Sort-Object Path)

Write-Host "Extracting chunks for $($entries.Count) file(s) with throttle=$Throttle"

$pruneFlag = [bool]$Prune
$__helperDir = Split-Path -Parent $PSCommandPath
while ($__helperDir -and -not (Test-Path (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1'))) {
  $__parent = Split-Path -Parent $__helperDir
  if ($__parent -eq $__helperDir) { throw 'Invoke-PythonBatch.ps1 helper not found (walked to filesystem root).' }
  $__helperDir = $__parent
}
. (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1')

$results = Invoke-PythonBatch -Entries $entries -Throttle $Throttle `
  -Variables @{ extractPy = $extractPy; pruneFlag = $pruneFlag } `
  -BuildArgs {
  param($entry)
  $argv = @($extractPy, '--source', $entry.Path)
  if ($entry.SourceRoot) { $argv += @('--source-root', $entry.SourceRoot) }
  if ($entry.OutputDir)  { $argv += @('--output-dir', $entry.OutputDir) }
  if ($entry.ManifestIn) { $argv += @('--manifest', $entry.ManifestIn) }
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
