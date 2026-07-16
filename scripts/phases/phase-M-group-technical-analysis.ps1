#requires -Version 5.1
<#
.SYNOPSIS
  Phase M — Group technical analysis (ATE) single-pass finalizer + DOCX.
  Workspace-scoped phase that fans in over groups declared in
  config/grouping.yaml. Three steps: M.1 stage group bundles, M.2 dispatch
  per-group Copilot finalizer, M.3 convert technical-analysis.md -> .docx.

.DESCRIPTION
  Independent, autoconsistent entry point for phase M. Wraps:
    M.1  .github/skills/technical-analysis-writer/scripts/ta_group_stage_batch.ps1
    M.2  scripts/dispatchers/run-docs-ta-group-finalize-batch.ps1
    M.3  scripts/lib/Convert-MdToDocx.ps1 (pandoc, plain default styling)

  Single-pass: the consolidated narrative source is the per-group
  docs/en/_groups/<group_id>/complete.md (phase-I output), reorganized into
  the resolved group technical-analysis profile/template structure.

  An empty `groups: []` manifest is a no-op (exit 0).

.PARAMETER Manifest
  Path to the grouping manifest. Default: config/grouping.yaml.

.PARAMETER Languages
  Comma-separated language codes. Default: en.

.PARAMETER ProfileName
  Technical-analysis profile name override (passed to the stage script).

.PARAMETER Agent
  Copilot agent identifier. Default: technical-analysis-writer.

.PARAMETER FinalizerThrottle
  Parallel limit for the per-group dispatch. Default: 4.

.PARAMETER SkipDocx
  Skip the DOCX conversion step (emit Markdown only).

.PARAMETER DryRun
  Build dispatch commands without invoking the Copilot CLI (also skips DOCX).

.PARAMETER Force
  Regenerate/redispatch/reconvert even when outputs are up to date.

.EXAMPLE
  pwsh -File scripts/phases/phase-M-group-technical-analysis.ps1 -Manifest config/grouping.yaml -DryRun
#>
[CmdletBinding()]
param(
  [string]$Manifest = 'config/grouping.yaml',
  [string]$ResultsDir = 'temp',
  [string]$Languages = 'en',
  [string]$ProfileName,
  [string]$Agent = 'technical-analysis-writer',
  [int]$FinalizerThrottle = 4,
  [string]$PandocPath = 'pandoc',
  [switch]$SkipDocx,
  [switch]$DryRun,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-PhaseInputs.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Convert-MdToDocx.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-EffectiveGroupingManifest.ps1')
$repoRoot      = Get-RepoRoot -ScriptPath $PSCommandPath
$stageBatch    = Join-Path $repoRoot '.github/skills/technical-analysis-writer/scripts/ta_group_stage_batch.ps1'
$finalizeBatch = Join-Path $repoRoot 'scripts/dispatchers/run-docs-ta-group-finalize-batch.ps1'
foreach ($p in @($stageBatch, $finalizeBatch)) {
  if (-not (Test-Path $p)) { throw "Required script not found: $p" }
}

$manifestPath = if ([System.IO.Path]::IsPathRooted($Manifest)) { $Manifest } else { Join-Path $repoRoot $Manifest }
if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Grouping manifest not found: $manifestPath"
}

$grouping = Resolve-EffectiveGroupingManifest -RepoRoot $repoRoot -Manifest $manifestPath -GeneratedDir 'temp/_generated'
$effectiveManifestPath = $grouping.ManifestPath

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsDirFull = (Resolve-Path -LiteralPath $ResultsDir).Path
$stageXml = Join-Path $resultsDirFull 'ta_group_stage_results.xml'
$dispXml  = Join-Path $resultsDirFull 'copilot_ta_group_finalize_results.xml'

$groupIds = @($grouping.Groups | ForEach-Object { "$(($_.id))".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$langList = @($Languages -split '[,;\s]+' | Where-Object { $_ })

Write-PhaseEvent -Phase M -Event 'start' -Data @{
  manifest = $effectiveManifestPath; languages = $Languages; groups = $groupIds.Count; dryRun = [bool]$DryRun
}

exit (Invoke-PhaseBatch -PhaseId M -ResultsXml $dispXml -Action {
  Write-PhaseEvent -Phase M -Event 'step' -Data @{ name = 'stage' }
  $stageArgs = @{ Manifest = $effectiveManifestPath; Languages = $Languages; ResultsXml = $stageXml }
  if ($ProfileName) { $stageArgs.ProfileName = $ProfileName }
  & $stageBatch @stageArgs
  if ($LASTEXITCODE -ne 0) { return }

  Write-PhaseEvent -Phase M -Event 'step' -Data @{ name = 'dispatch' }
  $dispArgs = @{
    Manifest   = $effectiveManifestPath
    Languages  = $Languages
    Agent      = $Agent
    Throttle   = $FinalizerThrottle
    ResultsXml = $dispXml
  }
  if ($DryRun) { $dispArgs.DryRun = $true }
  if ($Force)  { $dispArgs.Force  = $true }
  & $finalizeBatch @dispArgs
  if ($LASTEXITCODE -ne 0) { return }

  if ($DryRun -or $SkipDocx) {
    Write-PhaseEvent -Phase M -Event 'step' -Data @{ name = 'docx'; skipped = $true }
    return
  }
  if ($groupIds.Count -eq 0) {
    Write-PhaseEvent -Phase M -Event 'step' -Data @{ name = 'docx'; skipped = $true; reason = 'no-groups' }
    return
  }

  Write-PhaseEvent -Phase M -Event 'step' -Data @{ name = 'docx' }
  if (-not (Test-PandocAvailable -PandocPath $PandocPath)) {
    Write-Warning "pandoc not found ('$PandocPath'); skipping DOCX conversion. Markdown editions are complete."
    return
  }
  $mdTargets = New-Object System.Collections.Generic.List[string]
  foreach ($gid in $groupIds) {
    foreach ($lang in $langList) {
      $md = Join-Path $repoRoot ("docs/$lang/_groups/$gid/technical-analysis.md")
      if (Test-Path -LiteralPath $md) { $mdTargets.Add($md) }
    }
  }
  if ($mdTargets.Count -eq 0) {
    Write-Warning 'No group technical-analysis.md outputs found to convert to DOCX.'
    return
  }
  $docxResults = Invoke-MdToDocxBatch -MarkdownPaths $mdTargets -PandocPath $PandocPath -Force:$Force
  $docxFail = @($docxResults | Where-Object { $_.Exit -ne 0 })
  $docxResults | Export-Clixml -LiteralPath (Join-Path $resultsDirFull 'ta_group_docx_results.xml')
  Write-PhaseEvent -Phase M -Event 'step' -Data @{
    name = 'docx-done'; total = $docxResults.Count; failed = $docxFail.Count
  }
  if ($docxFail.Count -gt 0) {
    foreach ($f in $docxFail) { Write-Warning "DOCX failed: $($f.MarkdownPath) :: $($f.Stderr)" }
  }
})
