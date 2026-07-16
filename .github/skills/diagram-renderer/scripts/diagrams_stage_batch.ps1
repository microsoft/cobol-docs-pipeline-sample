#requires -Version 5.1
<#
.SYNOPSIS
  Pre-stage phase-G per-file diagram-renderer bundles for many sources in
  parallel.

.DESCRIPTION
  Fans out .github/skills/diagram-renderer/scripts/assemble-inputs.py across
  the given inputs using a runspace pool helper, writes one
  `docs/_shared/<file>/_diagrams.bundle.json` per source, captures per-file
  stdout/stderr/exit codes, persists a sorted result set to
  diagrams_stage_results.xml, and exits non-zero if any child failed.

  Deterministic. No LLM calls — only assembles prompt bundles so the
  diagram-renderer agent can read them one source at a time.

.PARAMETER Files
  Explicit list of source paths (repo-relative or absolute).

.PARAMETER Paths
  One or more directories or globs to expand.

.PARAMETER Manifest
  Path to a JSON/CSV file describing entries:
    [{ "path": "...", "sourceRoot": "...", "profile": "..." }, ...]
  Overrides -Files/-Paths.

.PARAMETER SourceRoot
  Optional --source-root applied to every input.

.PARAMETER ProfileName
  Optional --profile path override applied to every input.

.PARAMETER BundlePath
  Optional override for the per-file bundle output path template. When omitted,
  bundles are written to `docs/_shared/<basename>/_diagrams.bundle.json`.

.PARAMETER Throttle
  Parallel degree. Defaults to [Environment]::ProcessorCount.

.PARAMETER ResultsXml
  Path for the Export-Clixml result file. Default: diagrams_stage_results.xml.

.PARAMETER ExcludeExtensions
  File extensions to skip when expanding -Paths (case-insensitive). Default:
  .cob, .inp, .itt.
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [string]$ProfileName,
  [string]$BundlePath,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsXml = 'temp/diagrams_stage_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt')
)

$ErrorActionPreference = 'Stop'

$scriptDir  = Split-Path -Parent $PSCommandPath
$assemblePy = Join-Path $scriptDir 'assemble-inputs.py'
if (-not (Test-Path $assemblePy)) { throw "assemble-inputs.py not found at $assemblePy" }

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
      Profile    = [string]$i.profile
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
      Profile    = $ProfileName
    })
  }
}

$entries = @($entries | Sort-Object Path)

Write-Host "Staging diagram bundles for $($entries.Count) file(s) with throttle=$Throttle"

$__helperDir = Split-Path -Parent $PSCommandPath
while ($__helperDir -and -not (Test-Path (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1'))) {
  $__parent = Split-Path -Parent $__helperDir
  if ($__parent -eq $__helperDir) { throw 'Invoke-PythonBatch.ps1 helper not found (walked to filesystem root).' }
  $__helperDir = $__parent
}
. (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1')

$results = Invoke-PythonBatch -Entries $entries -Throttle $Throttle `
  -Variables @{ assemblePy = $assemblePy; BundlePath = $BundlePath } `
  -BuildArgs {
  param($entry)
  $basename = [System.IO.Path]::GetFileName($entry.Path)
  $outPath  = if ($BundlePath) { $BundlePath } else { "docs/_shared/$basename/_diagrams.bundle.json" }
  $argv = @($assemblePy, '--source', $entry.Path, '--out', $outPath)
  if ($entry.SourceRoot) { $argv += @('--source-root', $entry.SourceRoot) }
  if ($entry.Profile)    { $argv += @('--profile',     $entry.Profile) }
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
