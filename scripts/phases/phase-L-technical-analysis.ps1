#requires -Version 5.1
<#
.SYNOPSIS
  Phase L — Technical analysis (ATE) per-file single-pass finalizer + DOCX.
  Three steps: L.1 stage bundles, L.2 dispatch per-file Copilot finalizer,
  L.3 convert authored technical-analysis.md -> technical-analysis.docx.

.DESCRIPTION
  Independent, autoconsistent entry point for phase L. Wraps:
    L.1  .github/skills/technical-analysis-writer/scripts/ta_stage_batch.ps1
    L.2  scripts/dispatchers/run-docs-ta-finalize-batch.ps1
    L.3  scripts/lib/Convert-MdToDocx.ps1 (pandoc, plain default styling)

  Single-pass: the consolidated narrative source is the per-file
  docs/<first-language>/<basename>/complete.md (phase-E output), reorganized into the
  resolved technical-analysis profile/template structure. Copybooks/BMS
  are tombstoned by the stager and skipped.

  Prereqs per source: docs/<first-language>/<basename>/complete.md. On a missing prereq,
  exits with code 4.

.PARAMETER Languages
  Comma-separated language codes. Default: en.

.PARAMETER ProfileName
  Technical-analysis profile name override (passed to the stage script).

.PARAMETER Agent
  Copilot agent identifier for dispatch. Default: technical-analysis-writer.

.PARAMETER FinalizerThrottle
  Parallel limit for the L.2 per-file dispatch. Default: 4.

.PARAMETER SkipDocx
  Skip the L.3 DOCX conversion step (emit Markdown only).

.PARAMETER DryRun
  Build dispatch commands without invoking the Copilot CLI (also skips DOCX).

.PARAMETER Force
  Regenerate/redispatch/reconvert even when outputs are up to date.

.EXAMPLE
  pwsh -File scripts/phases/phase-L-technical-analysis.ps1 -Paths repos/sample1/COBOL/*.CBL -DryRun
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
$repoRoot      = Get-RepoRoot -ScriptPath $PSCommandPath
$stageBatch    = Join-Path $repoRoot '.github/skills/technical-analysis-writer/scripts/ta_stage_batch.ps1'
$finalizeBatch = Join-Path $repoRoot 'scripts/dispatchers/run-docs-ta-finalize-batch.ps1'
foreach ($p in @($stageBatch, $finalizeBatch)) {
  if (-not (Test-Path $p)) { throw "Required script not found: $p" }
}
if (-not $Files -and -not $Paths -and -not $Manifest) {
  throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
}

$sources = Get-PhaseInputs -Files $Files -Paths $Paths -Manifest $Manifest
$primaryLanguage = ($Languages -split ',')[0].Trim().ToLowerInvariant()
Assert-PhasePrereqs -RepoRoot $repoRoot -Sources $sources -PhaseId L `
  -RequiredArtifacts @("docs/$primaryLanguage/<basename>/complete.md")

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsDirFull = (Resolve-Path -LiteralPath $ResultsDir).Path
$stageXml    = Join-Path $resultsDirFull 'ta_stage_results.xml'
$finalizeXml = Join-Path $resultsDirFull 'copilot_ta_finalize_results.xml'

$stageArgs = Add-SourceSelectorArgs -Target @{
                Throttle   = $Throttle
                Languages  = $Languages
                ResultsXml = $stageXml
              } -Files $Files -Paths $Paths -Manifest $Manifest -SourceRoot $SourceRoot
if ($ProfileName) { $stageArgs.ProfileName = $ProfileName }

# Dispatch step does NOT accept -SourceRoot.
$finalizeArgs = Add-SourceSelectorArgs -Target @{
                Throttle   = $FinalizerThrottle
                Languages  = $Languages
                Agent      = $Agent
                ResultsXml = $finalizeXml
                DryRun     = [bool]$DryRun
              } -Files $Files -Paths $Paths -Manifest $Manifest
if ($Force) { $finalizeArgs.Force = $true }

$langList = @($Languages -split '[,;\s]+' | Where-Object { $_ })

exit (Invoke-PhaseBatch -PhaseId L -ResultsXml $finalizeXml -Action {
  Write-PhaseEvent -Phase L -Event 'step' -Data @{ name = 'stage' }
  & $stageBatch @stageArgs
  if ($LASTEXITCODE -ne 0) { return }

  Write-PhaseEvent -Phase L -Event 'step' -Data @{ name = 'finalize-dispatch' }
  & $finalizeBatch @finalizeArgs
  if ($LASTEXITCODE -ne 0) { return }

  if ($DryRun -or $SkipDocx) {
    Write-PhaseEvent -Phase L -Event 'step' -Data @{ name = 'docx'; skipped = $true }
    return
  }

  Write-PhaseEvent -Phase L -Event 'step' -Data @{ name = 'docx' }
  if (-not (Test-PandocAvailable -PandocPath $PandocPath)) {
    Write-Warning "pandoc not found ('$PandocPath'); skipping DOCX conversion. Markdown editions are complete."
    return
  }
  $mdTargets = New-Object System.Collections.Generic.List[string]
  foreach ($src in $sources) {
    $basename = [System.IO.Path]::GetFileName($src)
    foreach ($lang in $langList) {
      $md = Join-Path $repoRoot ("docs/$lang/$basename/technical-analysis.md")
      if (Test-Path -LiteralPath $md) { $mdTargets.Add($md) }
    }
  }
  if ($mdTargets.Count -eq 0) {
    Write-Warning 'No technical-analysis.md outputs found to convert to DOCX.'
    return
  }
  $docxResults = Invoke-MdToDocxBatch -MarkdownPaths $mdTargets -PandocPath $PandocPath -Force:$Force
  $docxFail = @($docxResults | Where-Object { $_.Exit -ne 0 })
  $docxResults | Export-Clixml -LiteralPath (Join-Path $resultsDirFull 'ta_docx_results.xml')
  Write-PhaseEvent -Phase L -Event 'step' -Data @{
    name = 'docx-done'; total = $docxResults.Count; failed = $docxFail.Count
  }
  if ($docxFail.Count -gt 0) {
    foreach ($f in $docxFail) { Write-Warning "DOCX failed: $($f.MarkdownPath) :: $($f.Stderr)" }
  }
})
