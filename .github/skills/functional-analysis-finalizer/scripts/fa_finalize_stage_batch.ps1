#requires -Version 5.1
<#
.SYNOPSIS
  Pre-stage phase-G per-file functional-analysis FINALIZE bundles for many
  sources in parallel.

.DESCRIPTION
  Companion to `.github/skills/functional-analysis-writer/scripts/fa_stage_batch.ps1`.
  Where that script stages the per-SECTION bundles, this script stages the
  per-FILE finalizer bundle by fanning
  `.github/skills/functional-analysis-finalizer/scripts/assemble-inputs.py`
  across the given inputs using the shared runspace-pool helper.

  It is deterministic (no LLM) and produces
    docs/_shared/<file>/_fa-bundles/_finalize.bundle.json (+ .bundle.md)
  from the per-section drafts written by the section-dispatch step, so the
  per-file finalizer dispatch (run-docs-fa-finalize-batch.ps1) has a bundle
  to read. Without this step the finalizer reports "Finalize bundle missing".

  Files opted-out of FA (copybooks, BMS) are skipped by extension exactly like
  the per-section stager.

.PARAMETER Files
  Explicit list of source paths (repo-relative or absolute).

.PARAMETER Paths
  One or more directories or globs to expand (e.g. repos/sample1/COBOL/*.CBL).

.PARAMETER Manifest
  Path to a JSON/CSV file describing entries:
    [{ "path": "...", "sourceRoot": "...", "profileName": "..." }, ...]
  Overrides -Files/-Paths.

.PARAMETER SourceRoot
  Optional --source-root applied to every input.

.PARAMETER Languages
  Comma-separated language list passed as --languages. Default: 'en'.

.PARAMETER ProfileName
  Optional FA profile name override applied to every input. When omitted,
  the assembler auto-detects the profile per source.

.PARAMETER Throttle
  Parallel degree. Defaults to [Environment]::ProcessorCount.

.PARAMETER ResultsXml
  Path for the Export-Clixml result file. Default: fa_finalize_stage_results.xml.

.PARAMETER ExcludeExtensions
  File extensions to skip when expanding -Paths (case-insensitive). Default:
  .cob, .inp, .itt — copybooks and JCL inline-data are not staged standalone.

.EXAMPLE
  pwsh -File .github/skills/functional-analysis-finalizer/scripts/fa_finalize_stage_batch.ps1 `
       -Paths repos/sample1/COBOL/*.CBL -Languages en
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [string]$Languages = 'en',
  [string]$ProfileName,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsXml = 'temp/fa_finalize_stage_results.xml',
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
      Path        = [string]$i.path
      SourceRoot  = [string]$i.sourceRoot
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
      ProfileName = $ProfileName
    })
  }
}

$entries = @($entries | Sort-Object Path)

Write-Host "Staging FA finalize bundles for $($entries.Count) file(s) with throttle=$Throttle (languages=$Languages)"

$__helperDir = Split-Path -Parent $PSCommandPath
while ($__helperDir -and -not (Test-Path (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1'))) {
  $__parent = Split-Path -Parent $__helperDir
  if ($__parent -eq $__helperDir) { throw 'Invoke-PythonBatch.ps1 helper not found (walked to filesystem root).' }
  $__helperDir = $__parent
}
. (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1')

$results = Invoke-PythonBatch -Entries $entries -Throttle $Throttle `
  -Variables @{ assemblePy = $assemblePy; Languages = $Languages } `
  -BuildArgs {
  param($entry)
  $argv = @($assemblePy, '--source', $entry.Path, '--languages', $Languages)
  if ($entry.SourceRoot)  { $argv += @('--source-root',  $entry.SourceRoot) }
  if ($entry.ProfileName) { $argv += @('--profile-name', $entry.ProfileName) }
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
