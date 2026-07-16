#requires -Version 5.1
<#
.SYNOPSIS
  Pre-stage phase-G per-FA-section bundles for many sources in parallel.

.DESCRIPTION
  Fans out .github/skills/functional-analysis-writer/scripts/stage-bundles.py
  across the given inputs using a runspace pool helper, captures per-file
  stdout/stderr/exit codes, persists a sorted result set to fa_stage_results.xml,
  and exits non-zero if any child failed.

  This is the bulk pre-stager for phase G (functional analysis). It does NOT
  call any LLM — it only assembles deterministic prompt bundles under
  docs/_shared/<file>/_fa-bundles/<section_id>.bundle.json (+ .bundle.md)
  so the functional-analysis-writer agent can read them one section at a time.

  Files opted-out of FA (copybooks, BMS) get a `_skipped.json` tombstone
  written and the child exits 0.

.PARAMETER Files
  Explicit list of source paths (repo-relative or absolute).

.PARAMETER Paths
  One or more directories or globs to expand (e.g. repos/sample1/COBOL/*.CBL).

.PARAMETER Manifest
  Path to a JSON/CSV file describing entries:
    [{ "path": "...", "sourceRoot": "...", "bundlesDir": "...", "profileName": "..." }, ...]
  Overrides -Files/-Paths.

.PARAMETER SourceRoot
  Optional --source-root applied to every input.

.PARAMETER BundlesDir
  Optional --bundles-dir override (rare; usually leave default).

.PARAMETER Languages
  Comma-separated language list passed as --languages. Default: 'en'.

.PARAMETER ProfileName
  Optional FA profile name override applied to every input. When omitted,
  fa_profile_resolver auto-detects the profile per source.

.PARAMETER Prune
  Pass --prune to every child.

.PARAMETER Force
  Pass --force to every child (re-stage even when bundle is up-to-date).

.PARAMETER Throttle
  Parallel degree. Defaults to [Environment]::ProcessorCount.

.PARAMETER ResultsXml
  Path for the Export-Clixml result file. Default: fa_stage_results.xml.

.PARAMETER ExcludeExtensions
  File extensions to skip when expanding -Paths (case-insensitive). Default:
  .cob, .inp, .itt — copybooks and JCL inline-data are not staged standalone.

.EXAMPLE
  pwsh -File .github/skills/functional-analysis-writer/scripts/fa_stage_batch.ps1 `
       -Paths repos/sample1/COBOL/*.CBL -Languages en,it -Prune
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [string]$BundlesDir,
  [string]$Languages = 'en',
  [string]$ProfileName,
  [switch]$Prune,
  [switch]$Force,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsXml = 'temp/fa_stage_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt')
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$stagePy   = Join-Path $scriptDir 'stage-bundles.py'
if (-not (Test-Path $stagePy)) { throw "stage-bundles.py not found at $stagePy" }

$entries = [System.Collections.Generic.List[object]]::new()

if ($Manifest) {
  $raw = Get-Content -Raw -LiteralPath $Manifest
  $items =
    if ($Manifest -match '\.csv$') { $raw | ConvertFrom-Csv }
    else                            { $raw | ConvertFrom-Json }
  foreach ($i in $items) {
    $entries.Add([pscustomobject]@{
      Path        = [string]$i.path
      SourceRoot  = [string]$i.sourceRoot
      BundlesDir  = [string]$i.bundlesDir
      ProfileName = [string]$i.profileName
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
      Path        = $f
      SourceRoot  = $SourceRoot
      BundlesDir  = $BundlesDir
      ProfileName = $ProfileName
    })
  }
}

$entries   = @($entries | Sort-Object Path)
$pruneFlag = [bool]$Prune
$forceFlag = [bool]$Force

Write-Host "Staging FA bundles for $($entries.Count) file(s) with throttle=$Throttle (languages=$Languages)"

$__helperDir = Split-Path -Parent $PSCommandPath
while ($__helperDir -and -not (Test-Path (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1'))) {
  $__parent = Split-Path -Parent $__helperDir
  if ($__parent -eq $__helperDir) { throw 'Invoke-PythonBatch.ps1 helper not found (walked to filesystem root).' }
  $__helperDir = $__parent
}
. (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1')

$results = Invoke-PythonBatch -Entries $entries -Throttle $Throttle `
  -Variables @{ stagePy = $stagePy; Languages = $Languages; pruneFlag = $pruneFlag; forceFlag = $forceFlag } `
  -BuildArgs {
  param($entry)
  $argv = @($stagePy, '--source', $entry.Path, '--languages', $Languages)
  if ($entry.SourceRoot)  { $argv += @('--source-root',  $entry.SourceRoot) }
  if ($entry.BundlesDir)  { $argv += @('--bundles-dir',  $entry.BundlesDir) }
  if ($entry.ProfileName) { $argv += @('--profile-name', $entry.ProfileName) }
  if ($pruneFlag)         { $argv += '--prune' }
  if ($forceFlag)         { $argv += '--force' }
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
