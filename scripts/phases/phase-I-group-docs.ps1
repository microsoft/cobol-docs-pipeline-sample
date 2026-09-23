#requires -Version 5.1
<#
.SYNOPSIS
  Phase I — Group documentation (per-group `index.md` + `complete.md`).
  Workspace-scoped phase that fans in over groups declared in
  config/grouping.yaml. Scaffold.

.DESCRIPTION
  Independent, autoconsistent entry point for phase I. When implemented
  the driver iterates groups from config/grouping.yaml, asserts every
  member's phase-E output exists (docs/<first-language>/<member>/{index,complete}.md),
  stages a per-group finalize bundle at
    docs/_shared/_groups/<group_id>/_doc-bundles/_finalize.bundle.{json,md}
  and dispatches the `group-doc-finalizer` agent once per group to write
    docs/<lang>/_groups/<group_id>/{index,complete}.md
  per requested language.

  Until implemented this phase exits non-zero so any caller surfaces the
  gap explicitly. An empty `groups: []` manifest is still treated as a
  no-op (exit 0).

.PARAMETER Manifest
  Path to the grouping manifest. Default: config/grouping.yaml.

.PARAMETER Languages
  Comma-separated language codes. Default: en.

.PARAMETER Agent
  Copilot agent identifier. Default: group-doc-finalizer.

.PARAMETER FinalizerThrottle
  Parallel limit for the per-group dispatch. Default: 4.

.PARAMETER DryRun
  Build dispatch commands without invoking the Copilot CLI. In dry-run
  the scaffold simply prints the planned per-group fan-out and exits 0.

.PARAMETER Force
  Regenerate/redispatch even when outputs are up to date.

.EXAMPLE
  pwsh -File scripts/phases/phase-I-group-docs.ps1 -Manifest config/grouping.yaml -DryRun
#>
[CmdletBinding()]
param(
  [string]$Manifest = 'config/grouping.yaml',
  [string]$ResultsDir = 'temp',
  [string]$Languages = 'en',
  [string]$Agent = 'group-doc-finalizer',
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
$stageBatch    = Join-Path $repoRoot '.github/skills/group-doc-finalizer/scripts/group_doc_stage_batch.ps1'
$finalizeBatch = Join-Path $repoRoot 'scripts/dispatchers/run-docs-group-doc-finalize-batch.ps1'
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
$stageXml = Join-Path $resultsDirFull 'group_doc_stage_results.xml'
$dispXml  = Join-Path $resultsDirFull 'copilot_group_doc_finalize_results.xml'

$groupIds = @($grouping.Groups | ForEach-Object { "$(($_.id))".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$langList = @($Languages -split '[,;\s]+' | Where-Object { $_ })

Write-PhaseEvent -Phase I -Event 'start' -Data @{
  manifest = $effectiveManifestPath; languages = $Languages; dryRun = [bool]$DryRun
}

exit (Invoke-PhaseBatch -PhaseId I -ResultsXml $dispXml -Action {
  Write-PhaseEvent -Phase I -Event 'step' -Data @{ name = 'stage' }
  & $stageBatch -Manifest $effectiveManifestPath -Languages $Languages -ResultsXml $stageXml
  if ($LASTEXITCODE -ne 0) { return }

  Write-PhaseEvent -Phase I -Event 'step' -Data @{ name = 'dispatch' }
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
    Write-PhaseEvent -Phase I -Event 'step' -Data @{ name = 'docx'; skipped = $true }
    return
  }
  if ($groupIds.Count -eq 0) {
    Write-PhaseEvent -Phase I -Event 'step' -Data @{ name = 'docx'; skipped = $true; reason = 'no-groups' }
    return
  }
  Write-PhaseEvent -Phase I -Event 'step' -Data @{ name = 'docx' }
  if (-not (Test-PandocAvailable -PandocPath $PandocPath)) {
    Write-Warning "pandoc not found ('$PandocPath'); skipping DOCX conversion. Markdown editions are complete."
    return
  }
  $mdTargets = New-Object System.Collections.Generic.List[string]
  foreach ($gid in $groupIds) {
    foreach ($lang in $langList) {
      $md = Join-Path $repoRoot ("docs/$lang/_groups/$gid/complete.md")
      if (Test-Path -LiteralPath $md) { $mdTargets.Add($md) }
    }
  }
  if ($mdTargets.Count -eq 0) {
    Write-Warning 'No group complete.md outputs found to convert to DOCX.'
    return
  }
  $docxResults = Invoke-MdToDocxBatch -MarkdownPaths $mdTargets -PandocPath $PandocPath -Force:$Force
  $docxFail = @($docxResults | Where-Object { $_.Exit -ne 0 })
  $docxResults | Export-Clixml -LiteralPath (Join-Path $resultsDirFull 'group_complete_docx_results.xml')
  Write-PhaseEvent -Phase I -Event 'step' -Data @{
    name = 'docx-done'; total = $docxResults.Count; failed = $docxFail.Count
  }
  if ($docxFail.Count -gt 0) {
    foreach ($f in $docxFail) { Write-Warning "DOCX failed: $($f.MarkdownPath) :: $($f.Stderr)" }
  }
})
