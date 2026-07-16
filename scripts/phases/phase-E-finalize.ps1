#requires -Version 5.1
<#
.SYNOPSIS
  Phase E — Per-file section finalizer (index.md + complete.md).
  Two steps: E.1 stage finalize bundles, E.2 dispatch Copilot finalizer.

.DESCRIPTION
  Independent, autoconsistent entry point for phase E. Wraps:
    E.1  .github/skills/section-doc-finalizer/scripts/finalize_stage_batch.ps1
    E.2  scripts/dispatchers/run-docs-finalize-batch.ps1

  Prereqs per source: at least one docs/en/<basename>/sections/*.md.
  On a missing prereq, exits with code 4.

.PARAMETER Languages
  Comma-separated language codes. Default: en.

.PARAMETER Agent
  Copilot agent identifier. Default: section-doc-finalizer.

.PARAMETER FinalizerThrottle
  Parallel limit for the Copilot dispatch step. Default: 4.

.PARAMETER DryRun
  Build dispatch commands without invoking the Copilot CLI.

.PARAMETER Force
  Re-finalize even if outputs are up to date.

.EXAMPLE
  pwsh -File scripts/phases/phase-E-finalize.ps1 -Paths repos/sample1/COBOL/*.CBL -DryRun
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
  [string]$Agent = 'section-doc-finalizer',
  [int]$FinalizerThrottle = 4,
  [string]$PandocPath = 'pandoc',
  [switch]$SkipDocx,
  [switch]$DryRun,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-PhaseInputs.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Convert-MdToDocx.ps1')
$repoRoot     = Get-RepoRoot -ScriptPath $PSCommandPath
$stageBatch   = Join-Path $repoRoot '.github/skills/section-doc-finalizer/scripts/finalize_stage_batch.ps1'
$dispBatch    = Join-Path $repoRoot 'scripts/dispatchers/run-docs-finalize-batch.ps1'
$assembleBatch = Join-Path $repoRoot '.github/skills/section-doc-finalizer/scripts/assemble_complete_batch.ps1'
foreach ($p in @($stageBatch, $dispBatch, $assembleBatch)) {
  if (-not (Test-Path $p)) { throw "Required script not found: $p" }
}
if (-not $Files -and -not $Paths -and -not $Manifest) {
  throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
}

$sources = Get-PhaseInputs -Files $Files -Paths $Paths -Manifest $Manifest
Assert-PhasePrereqs -RepoRoot $repoRoot -Sources $sources -PhaseId E `
  -RequiredArtifacts @('docs/en/<basename>/sections/*.md')

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsDirFull = (Resolve-Path -LiteralPath $ResultsDir).Path
$stageXml       = Join-Path $resultsDirFull 'finalize_stage_results.xml'
$dispXml        = Join-Path $resultsDirFull 'copilot_finalize_results.xml'
$assembleXml    = Join-Path $resultsDirFull 'complete_assemble_results.xml'

$stageArgs = Add-SourceSelectorArgs -Target @{
                Throttle   = $Throttle
                Languages  = $Languages
                ResultsXml = $stageXml
              } -Files $Files -Paths $Paths -Manifest $Manifest -SourceRoot $SourceRoot

# Dispatch step does NOT accept -SourceRoot.
$dispArgs = Add-SourceSelectorArgs -Target @{
                Throttle   = $FinalizerThrottle
                Languages  = $Languages
                Agent      = $Agent
                ResultsXml = $dispXml
                DryRun     = [bool]$DryRun
              } -Files $Files -Paths $Paths -Manifest $Manifest
if ($Force) { $dispArgs.Force = $true }

# Deterministic complete.md assembler. Always runs after the LLM dispatch.
$assembleArgs = Add-SourceSelectorArgs -Target @{
                  Throttle   = $Throttle
                  Languages  = $Languages
                  ResultsXml = $assembleXml
                } -Files $Files -Paths $Paths -Manifest $Manifest
if ($Force) { $assembleArgs.Force = $true }

$langList = @($Languages -split '[,;\s]+' | Where-Object { $_ })

exit (Invoke-PhaseBatch -PhaseId E -ResultsXml $dispXml -Action {
  Write-PhaseEvent -Phase E -Event 'step' -Data @{ name = 'stage' }
  & $stageBatch @stageArgs
  if ($LASTEXITCODE -ne 0) { return }
  Write-PhaseEvent -Phase E -Event 'step' -Data @{ name = 'dispatch' }
  & $dispBatch @dispArgs
  if ($LASTEXITCODE -ne 0) { return }
  if ($DryRun) {
    Write-PhaseEvent -Phase E -Event 'step' -Data @{ name = 'assemble-complete'; skipped = 'dry-run' }
    return
  }
  Write-PhaseEvent -Phase E -Event 'step' -Data @{ name = 'assemble-complete' }
  & $assembleBatch @assembleArgs
  if ($LASTEXITCODE -ne 0) { return }

  if ($SkipDocx) {
    Write-PhaseEvent -Phase E -Event 'step' -Data @{ name = 'docx'; skipped = $true }
    return
  }
  Write-PhaseEvent -Phase E -Event 'step' -Data @{ name = 'docx' }
  if (-not (Test-PandocAvailable -PandocPath $PandocPath)) {
    Write-Warning "pandoc not found ('$PandocPath'); skipping DOCX conversion. Markdown editions are complete."
    return
  }
  $mdTargets = New-Object System.Collections.Generic.List[string]
  foreach ($src in $sources) {
    $basename = [System.IO.Path]::GetFileName($src)
    foreach ($lang in $langList) {
      $md = Join-Path $repoRoot ("docs/$lang/$basename/complete.md")
      if (Test-Path -LiteralPath $md) { $mdTargets.Add($md) }
    }
  }
  if ($mdTargets.Count -eq 0) {
    Write-Warning 'No complete.md outputs found to convert to DOCX.'
    return
  }
  $docxResults = Invoke-MdToDocxBatch -MarkdownPaths $mdTargets -PandocPath $PandocPath -Force:$Force
  $docxFail = @($docxResults | Where-Object { $_.Exit -ne 0 })
  $docxResults | Export-Clixml -LiteralPath (Join-Path $resultsDirFull 'complete_docx_results.xml')
  Write-PhaseEvent -Phase E -Event 'step' -Data @{
    name = 'docx-done'; total = $docxResults.Count; failed = $docxFail.Count
  }
  if ($docxFail.Count -gt 0) {
    foreach ($f in $docxFail) { Write-Warning "DOCX failed: $($f.MarkdownPath) :: $($f.Stderr)" }
  }
})
