#requires -Version 5.1
<#
.SYNOPSIS
  Phase K — Per-GROUP functional-analysis docs (group-scoped AFU).
  Three steps: K.1 stage per-group bundles, K.2 dispatch per-section
  Copilot calls, K.3 dispatch per-group finalizer Copilot calls.

.DESCRIPTION
  Independent, autoconsistent entry point for phase K. Fans in over
  groups declared in config/grouping.yaml and produces
    docs/<lang>/_groups/<group_id>/functional-analysis.md
  per requested language, via the `functional-analysis-group-writer` agent.

  Wraps:
    K.1  .github/skills/functional-analysis-group-writer/scripts/fa_group_stage_batch.ps1
    K.2  scripts/dispatchers/run-docs-fa-group-section-batch.ps1
    K.3  scripts/dispatchers/run-docs-fa-group-finalize-batch.ps1

  The inner stage/section/finalize batch scripts are scaffolds: if they
  exit non-zero this phase short-circuits and the wrapper itself surfaces
  the gap to the caller.

.PARAMETER Manifest
  Path to the grouping manifest. Default: config/grouping.yaml.

.PARAMETER Languages
  Comma-separated language codes. Default: en.

.PARAMETER ProfileName
  Functional-analysis profile name (forwarded to the stage script).

.PARAMETER Agent
  Copilot agent identifier for both dispatch steps.
  Default: functional-analysis-group-writer.

.PARAMETER SectionThrottle
  Parallel limit for the K.2 per-section dispatch. Default: 6.

.PARAMETER FinalizerThrottle
  Parallel limit for the K.3 per-group finalizer dispatch. Default: 4.

.PARAMETER Prune
  Prune stale staging outputs (forwarded to the stage script).

.PARAMETER DryRun
  Build dispatch commands without invoking the Copilot CLI.

.PARAMETER Force
  Regenerate/redispatch even when outputs are up to date.

.EXAMPLE
  pwsh -File scripts/phases/phase-K-group-functional-analysis.ps1 -Manifest config/grouping.yaml -DryRun
#>
[CmdletBinding()]
param(
  [string]$Manifest = 'config/grouping.yaml',
  [string]$ResultsDir = 'temp',
  [string]$Languages = 'en',
  [string]$ProfileName,
  [string]$Agent = 'functional-analysis-group-writer',
  [int]$SectionThrottle = 6,
  [int]$FinalizerThrottle = 4,
  [string]$PandocPath = 'pandoc',
  [switch]$SkipDocx,
  [switch]$Prune,
  [switch]$DryRun,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-PhaseInputs.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Convert-MdToDocx.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-EffectiveGroupingManifest.ps1')
$repoRoot      = Get-RepoRoot -ScriptPath $PSCommandPath
$stageBatch    = Join-Path $repoRoot '.github/skills/functional-analysis-group-writer/scripts/fa_group_stage_batch.ps1'
$sectionBatch  = Join-Path $repoRoot 'scripts/dispatchers/run-docs-fa-group-section-batch.ps1'
$finalizeBatch = Join-Path $repoRoot 'scripts/dispatchers/run-docs-fa-group-finalize-batch.ps1'
foreach ($p in @($stageBatch, $sectionBatch, $finalizeBatch)) {
  if (-not (Test-Path $p)) { throw "Required script not found: $p" }
}

$manifestPath = if ([System.IO.Path]::IsPathRooted($Manifest)) {
  $Manifest
} else {
  Join-Path $repoRoot $Manifest
}
if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Grouping manifest not found: $manifestPath"
}

$grouping = Resolve-EffectiveGroupingManifest -RepoRoot $repoRoot -Manifest $manifestPath -GeneratedDir 'temp/_generated'
$effectiveManifestPath = $grouping.ManifestPath

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsDirFull = (Resolve-Path -LiteralPath $ResultsDir).Path
$stageXml    = Join-Path $resultsDirFull 'fa_group_stage_results.xml'
$sectionXml  = Join-Path $resultsDirFull 'copilot_fa_group_section_results.xml'
$finalizeXml = Join-Path $resultsDirFull 'copilot_fa_group_finalize_results.xml'

$stageArgs = @{
  Manifest   = $manifestPath
  Languages  = $Languages
  ResultsXml = $stageXml
}
if ($ProfileName) { $stageArgs.ProfileName = $ProfileName }
if ($Prune)       { $stageArgs.Prune       = $true }
if ($Force)       { $stageArgs.Force       = $true }

$sectionArgs = @{
  Manifest   = $manifestPath
  Languages  = $Languages
  Agent      = $Agent
  Throttle   = $SectionThrottle
  ResultsXml = $sectionXml
}
if ($DryRun) { $sectionArgs.DryRun = $true }
if ($Force)  { $sectionArgs.Force  = $true }

$finalizeArgs = @{
  Manifest   = $manifestPath
  Languages  = $Languages
  Agent      = $Agent
  Throttle   = $FinalizerThrottle
  ResultsXml = $finalizeXml
}
if ($DryRun) { $finalizeArgs.DryRun = $true }
if ($Force)  { $finalizeArgs.Force  = $true }

$groupIds = @($grouping.Groups | ForEach-Object { "$(($_.id))".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$langList = @($Languages -split '[,;\s]+' | Where-Object { $_ })

Write-PhaseEvent -Phase K -Event 'start' -Data @{
  manifest = $effectiveManifestPath; languages = $Languages; dryRun = [bool]$DryRun
}

exit (Invoke-PhaseBatch -PhaseId K -ResultsXml $finalizeXml -Action {
  Write-PhaseEvent -Phase K -Event 'step' -Data @{ name = 'stage' }
  $stageArgs.Manifest = $effectiveManifestPath
  & $stageBatch @stageArgs
  if ($LASTEXITCODE -ne 0) { return }
  Write-PhaseEvent -Phase K -Event 'step' -Data @{ name = 'section-dispatch' }
  $sectionArgs.Manifest = $effectiveManifestPath
  & $sectionBatch @sectionArgs
  if ($LASTEXITCODE -ne 0) { return }
  Write-PhaseEvent -Phase K -Event 'step' -Data @{ name = 'finalize-dispatch' }
  $finalizeArgs.Manifest = $effectiveManifestPath
  & $finalizeBatch @finalizeArgs
  if ($LASTEXITCODE -ne 0) { return }

  if ($DryRun -or $SkipDocx) {
    Write-PhaseEvent -Phase K -Event 'step' -Data @{ name = 'docx'; skipped = $true }
    return
  }
  if ($groupIds.Count -eq 0) {
    Write-PhaseEvent -Phase K -Event 'step' -Data @{ name = 'docx'; skipped = $true; reason = 'no-groups' }
    return
  }
  Write-PhaseEvent -Phase K -Event 'step' -Data @{ name = 'docx' }
  if (-not (Test-PandocAvailable -PandocPath $PandocPath)) {
    Write-Warning "pandoc not found ('$PandocPath'); skipping DOCX conversion. Markdown editions are complete."
    return
  }
  $mdTargets = New-Object System.Collections.Generic.List[string]
  foreach ($gid in $groupIds) {
    foreach ($lang in $langList) {
      $md = Join-Path $repoRoot ("docs/$lang/_groups/$gid/functional-analysis.md")
      if (Test-Path -LiteralPath $md) { $mdTargets.Add($md) }
    }
  }
  if ($mdTargets.Count -eq 0) {
    Write-Warning 'No group functional-analysis.md outputs found to convert to DOCX.'
    return
  }
  $docxResults = Invoke-MdToDocxBatch -MarkdownPaths $mdTargets -PandocPath $PandocPath -Force:$Force
  $docxFail = @($docxResults | Where-Object { $_.Exit -ne 0 })
  $docxResults | Export-Clixml -LiteralPath (Join-Path $resultsDirFull 'fa_group_docx_results.xml')
  Write-PhaseEvent -Phase K -Event 'step' -Data @{
    name = 'docx-done'; total = $docxResults.Count; failed = $docxFail.Count
  }
  if ($docxFail.Count -gt 0) {
    foreach ($f in $docxFail) { Write-Warning "DOCX failed: $($f.MarkdownPath) :: $($f.Stderr)" }
  }
})
