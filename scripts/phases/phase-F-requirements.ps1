#requires -Version 5.1
<#
.SYNOPSIS
  Phase F — Technical requirements docs (per-requirements-section author +
  per-file finalizer).
  Three steps: F.1 stage bundles, F.2 dispatch per-section Copilot calls,
  F.3 dispatch per-file finalizer Copilot calls.

.DESCRIPTION
  Independent, autoconsistent entry point for phase F. Wraps:
    F.1  .github/skills/requirements-writer/scripts/req_stage_batch.ps1
    F.2  scripts/dispatchers/run-docs-req-section-batch.ps1
    F.3  scripts/dispatchers/run-docs-req-finalize-batch.ps1

  Mirrors the shape of phase G (functional-analysis) but drives the
  requirements profiles under `config/templates/docs/requirements/`
  (`default`, `ate-org-applicazione`, `ate-org-interfaccia`) and
  writes `docs/<lang>/<file>/requirements.md` per requested language.

  Prereqs per source: docs/<first-language>/<basename>/complete.md (phase-E output).
  On a missing prereq, exits with code 4.

.PARAMETER Languages
  Comma-separated language codes. Default: en.

.PARAMETER ProfileName
  Requirements profile name (passed to the stage script).

.PARAMETER Agent
  Copilot agent identifier for both dispatch steps. Default: requirements-writer.

.PARAMETER SectionThrottle
  Parallel limit for the F.2 per-section dispatch. Default: 6.

.PARAMETER FinalizerThrottle
  Parallel limit for the F.3 per-file finalizer dispatch. Default: 4.

.PARAMETER Prune
  Prune stale staging outputs (forwarded to req_stage_batch.ps1).

.PARAMETER DryRun
  Build dispatch commands without invoking the Copilot CLI.

.PARAMETER Force
  Regenerate/redispatch even when outputs are up to date.

.EXAMPLE
  pwsh -File scripts/phases/phase-F-requirements.ps1 -Paths repos/sample1/COBOL/*.CBL -DryRun
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsDir = 'temp',
  [string]$Languages = 'en',
  [string]$ProfileName,
  [string]$Agent = 'requirements-writer',
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
$repoRoot          = Get-RepoRoot -ScriptPath $PSCommandPath
$stageBatch        = Join-Path $repoRoot '.github/skills/requirements-writer/scripts/req_stage_batch.ps1'
$finalizeStageBatch = Join-Path $repoRoot '.github/skills/requirements-finalizer/scripts/req_finalize_stage_batch.ps1'
$sectionBatch      = Join-Path $repoRoot 'scripts/dispatchers/run-docs-req-section-batch.ps1'
$finalizeBatch     = Join-Path $repoRoot 'scripts/dispatchers/run-docs-req-finalize-batch.ps1'
foreach ($p in @($stageBatch, $finalizeStageBatch, $sectionBatch, $finalizeBatch)) {
  if (-not (Test-Path $p)) { throw "Required script not found: $p" }
}
if (-not $Files -and -not $Paths -and -not $Manifest) {
  throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
}

$sources = Get-PhaseInputs -Files $Files -Paths $Paths -Manifest $Manifest

# Requirements docs are not generated for PROC (*.prc) sources. Drop them and
# pin downstream expansion to the filtered file list so the batch wrappers
# (which re-expand -Paths/-Manifest on their own) cannot re-introduce them.
$prcSources = @($sources | Where-Object { [System.IO.Path]::GetExtension($_).ToLowerInvariant() -eq '.prc' })
if ($prcSources.Count -gt 0) {
  $sources = @($sources | Where-Object { [System.IO.Path]::GetExtension($_).ToLowerInvariant() -ne '.prc' })
  Write-PhaseEvent -Phase F -Event 'skip' -Data @{ reason = 'prc-excluded'; count = $prcSources.Count }
  if ($sources.Count -eq 0) {
    Write-PhaseEvent -Phase F -Event 'skip' -Data @{ reason = 'no-eligible-sources' }
    exit 0
  }
  $Files    = $sources
  $Paths    = $null
  $Manifest = $null
}

$primaryLanguage = ($Languages -split ',')[0].Trim().ToLowerInvariant()
Assert-PhasePrereqs -RepoRoot $repoRoot -Sources $sources -PhaseId F `
  -RequiredArtifacts @("docs/$primaryLanguage/<basename>/complete.md")

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsDirFull = (Resolve-Path -LiteralPath $ResultsDir).Path
$stageXml         = Join-Path $resultsDirFull 'req_stage_results.xml'
$finalizeStageXml = Join-Path $resultsDirFull 'req_finalize_stage_results.xml'
$sectionXml       = Join-Path $resultsDirFull 'copilot_req_section_results.xml'
$finalizeXml      = Join-Path $resultsDirFull 'copilot_req_finalize_results.xml'

$stageArgs = Add-SourceSelectorArgs -Target @{
                Throttle   = $Throttle
                Languages  = $Languages
                ResultsXml = $stageXml
              } -Files $Files -Paths $Paths -Manifest $Manifest -SourceRoot $SourceRoot
if ($ProfileName) { $stageArgs.ProfileName = $ProfileName }
if ($Prune)       { $stageArgs.Prune       = $true }
if ($Force)       { $stageArgs.Force       = $true }

# Per-file finalizer bundle stager (deterministic; builds _finalize.bundle.json
# from the per-section drafts written by the section-dispatch step).
$finalizeStageArgs = Add-SourceSelectorArgs -Target @{
                Throttle   = $Throttle
                Languages  = $Languages
                ResultsXml = $finalizeStageXml
              } -Files $Files -Paths $Paths -Manifest $Manifest -SourceRoot $SourceRoot
if ($ProfileName) { $finalizeStageArgs.ProfileName = $ProfileName }

# Dispatch steps do NOT accept -SourceRoot.
$sectionArgs = Add-SourceSelectorArgs -Target @{
                Throttle   = $SectionThrottle
                Languages  = $Languages
                Agent      = $Agent
                ResultsXml = $sectionXml
                DryRun     = [bool]$DryRun
              } -Files $Files -Paths $Paths -Manifest $Manifest
if ($Force) { $sectionArgs.Force = $true }

$finalizeArgs = Add-SourceSelectorArgs -Target @{
                Throttle   = $FinalizerThrottle
                Languages  = $Languages
                Agent      = $Agent
                ResultsXml = $finalizeXml
                DryRun     = [bool]$DryRun
              } -Files $Files -Paths $Paths -Manifest $Manifest
if ($Force) { $finalizeArgs.Force = $true }

$langList = @($Languages -split '[,;\s]+' | Where-Object { $_ })

exit (Invoke-PhaseBatch -PhaseId F -ResultsXml $finalizeXml -Action {
  Write-PhaseEvent -Phase F -Event 'step' -Data @{ name = 'stage' }
  & $stageBatch @stageArgs
  if ($LASTEXITCODE -ne 0) { return }
  Write-PhaseEvent -Phase F -Event 'step' -Data @{ name = 'section-dispatch' }
  & $sectionBatch @sectionArgs
  if ($LASTEXITCODE -ne 0) { return }
  Write-PhaseEvent -Phase F -Event 'step' -Data @{ name = 'finalize-stage' }
  & $finalizeStageBatch @finalizeStageArgs
  if ($LASTEXITCODE -ne 0) { return }
  Write-PhaseEvent -Phase F -Event 'step' -Data @{ name = 'finalize-dispatch' }
  & $finalizeBatch @finalizeArgs
  if ($LASTEXITCODE -ne 0) { return }

  if ($DryRun -or $SkipDocx) {
    Write-PhaseEvent -Phase F -Event 'step' -Data @{ name = 'docx'; skipped = $true }
    return
  }
  Write-PhaseEvent -Phase F -Event 'step' -Data @{ name = 'docx' }
  if (-not (Test-PandocAvailable -PandocPath $PandocPath)) {
    Write-Warning "pandoc not found ('$PandocPath'); skipping DOCX conversion. Markdown editions are complete."
    return
  }
  $mdTargets = New-Object System.Collections.Generic.List[string]
  foreach ($src in $sources) {
    $basename = [System.IO.Path]::GetFileName($src)
    foreach ($lang in $langList) {
      $md = Join-Path $repoRoot ("docs/$lang/$basename/requirements.md")
      if (Test-Path -LiteralPath $md) { $mdTargets.Add($md) }
    }
  }
  if ($mdTargets.Count -eq 0) {
    Write-Warning 'No requirements.md outputs found to convert to DOCX.'
    return
  }
  $docxResults = Invoke-MdToDocxBatch -MarkdownPaths $mdTargets -PandocPath $PandocPath -Force:$Force
  $docxFail = @($docxResults | Where-Object { $_.Exit -ne 0 })
  $docxResults | Export-Clixml -LiteralPath (Join-Path $resultsDirFull 'req_docx_results.xml')
  Write-PhaseEvent -Phase F -Event 'step' -Data @{
    name = 'docx-done'; total = $docxResults.Count; failed = $docxFail.Count
  }
  if ($docxFail.Count -gt 0) {
    foreach ($f in $docxFail) { Write-Warning "DOCX failed: $($f.MarkdownPath) :: $($f.Stderr)" }
  }
})
