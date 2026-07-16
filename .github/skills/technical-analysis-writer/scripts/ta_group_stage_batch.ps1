#requires -Version 5.1
<#
.SYNOPSIS
  Stage per-GROUP technical-analysis (ATE) finalize bundles for phase M.

.DESCRIPTION
  Iterates groups declared in config/grouping.yaml and fans out
  assemble-group-inputs.py once per group to produce
    docs/_shared/_groups/<group_id>/_ta-group-bundles/_finalize.bundle.{json,md}
  using the existing Invoke-PythonBatch runspace-pool helper.

  If grouping.yaml has zero groups, this phase is a graceful no-op (exit 0).
#>
[CmdletBinding()]
param(
  [string]$Manifest = 'config/grouping.yaml',
  [string]$Languages = 'en',
  [string]$ProfileName,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsXml = 'temp/ta_group_stage_results.xml'
)

$ErrorActionPreference = 'Stop'

$scriptDir  = Split-Path -Parent $PSCommandPath
$assemblePy = Join-Path $scriptDir 'assemble-group-inputs.py'
if (-not (Test-Path $assemblePy)) { throw "assemble-group-inputs.py not found at $assemblePy" }

# Walk up to find the repo root (the parent of .github).
$repoRoot = $scriptDir
while ($repoRoot -and -not (Test-Path (Join-Path $repoRoot '.github'))) {
  $parent = Split-Path -Parent $repoRoot
  if ($parent -eq $repoRoot) { throw 'Unable to locate repo root from ta_group_stage_batch.ps1.' }
  $repoRoot = $parent
}

$manifestPath = if ([System.IO.Path]::IsPathRooted($Manifest)) { $Manifest } else { Join-Path $repoRoot $Manifest }
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Grouping manifest not found: $manifestPath" }

$readerScript = Join-Path $repoRoot 'scripts/lib/read_groups.py'
if (-not (Test-Path -LiteralPath $readerScript)) {
  throw "Group reader helper not found: $readerScript"
}
$groupsJson = & python $readerScript $manifestPath
if ($LASTEXITCODE -ne 0) { throw "Failed to read groups from $manifestPath" }
$groupIds = @(@($groupsJson | ConvertFrom-Json) | ForEach-Object { "$($_.id)".Trim() })
$groupIds = @($groupIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

if ($groupIds.Count -eq 0) {
  Write-Host 'ta_group_stage_batch: no groups declared in grouping.yaml — no-op.'
  @() | Export-Clixml -LiteralPath $ResultsXml
  exit 0
}

Write-Host "Staging technical-analysis group bundles for $($groupIds.Count) group(s) with throttle=$Throttle (languages=$Languages)"

$helperDir = $scriptDir
while ($helperDir -and -not (Test-Path (Join-Path $helperDir 'scripts/lib/Invoke-PythonBatch.ps1'))) {
  $parent = Split-Path -Parent $helperDir
  if ($parent -eq $helperDir) { throw 'Invoke-PythonBatch.ps1 helper not found (walked to filesystem root).' }
  $helperDir = $parent
}
. (Join-Path $helperDir 'scripts/lib/Invoke-PythonBatch.ps1')

$entries = @($groupIds | ForEach-Object { [pscustomobject]@{ Path = $_; GroupId = $_ } })

$results = Invoke-PythonBatch -Entries $entries -Throttle $Throttle `
  -Variables @{ assemblePy = $assemblePy; Languages = $Languages; Manifest = $manifestPath; ProfileName = $ProfileName } `
  -BuildArgs {
    param($entry)
    if ([string]::IsNullOrWhiteSpace($entry.GroupId)) {
      throw 'ta_group_stage_batch: encountered empty group id while building python arguments.'
    }
    $out = "docs/_shared/_groups/$($entry.GroupId)/_ta-group-bundles/_finalize.bundle.json"
    $argv = @($assemblePy, '--group-id', $entry.GroupId, '--languages', $Languages,
              '--manifest', $Manifest, '--out', $out)
    if ($ProfileName) { $argv += @('--profile-name', $ProfileName) }
    return ,$argv
  }

$results = @($results | Sort-Object Path)
$results | Export-Clixml -LiteralPath $ResultsXml

$failed = @($results | Where-Object { $_.Exit -ne 0 })
$ok = $results.Count - $failed.Count
Write-Host "DONE total=$($results.Count) ok=$ok failed=$($failed.Count)"
if ($failed.Count -gt 0) {
  Write-Host 'Failures:'
  $failed | ForEach-Object { Write-Host "  [$($_.Exit)] $($_.Path) :: $($_.Stderr)" }
  exit 1
}
exit 0
