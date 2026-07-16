#requires -Version 5.1
<#
.SYNOPSIS
  Phase H — Per-file file-level overview diagrams (call-graph, control-flow,
  jcl-steps, cics-calls, cursor-lifecycle, er-fragment).
  Two steps: H.1 stage diagram bundles, H.2 dispatch Copilot diagram-renderer.

.DESCRIPTION
  Independent, autoconsistent entry point for phase H. Wraps:
    H.1  .github/skills/diagram-renderer/scripts/diagrams_stage_batch.ps1
    H.2  scripts/dispatchers/run-docs-diagrams-batch.ps1

  Prereqs per source: docs/_shared/<basename>/facts.json. On a missing
  prereq, exits with code 4.

.PARAMETER Agent
  Copilot agent identifier. Default: diagram-renderer.

.PARAMETER DiagramsThrottle
  Parallel limit for the Copilot dispatch step. Default: 4.

.PARAMETER DryRun
  Build dispatch commands without invoking the Copilot CLI.

.PARAMETER Force
  Re-render even if diagrams are up to date.

.EXAMPLE
  pwsh -File scripts/phases/phase-H-diagrams.ps1 -Paths repos/sample1/COBOL/*.CBL -DryRun
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsDir = 'temp',
  [string]$Agent = 'diagram-renderer',
  [int]$DiagramsThrottle = 4,
  [switch]$DryRun,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-PhaseInputs.ps1')
$repoRoot   = Get-RepoRoot -ScriptPath $PSCommandPath
$stageBatch = Join-Path $repoRoot '.github/skills/diagram-renderer/scripts/diagrams_stage_batch.ps1'
$dispBatch  = Join-Path $repoRoot 'scripts/dispatchers/run-docs-diagrams-batch.ps1'
foreach ($p in @($stageBatch, $dispBatch)) {
  if (-not (Test-Path $p)) { throw "Required script not found: $p" }
}
if (-not $Files -and -not $Paths -and -not $Manifest) {
  throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
}

$sources = Get-PhaseInputs -Files $Files -Paths $Paths -Manifest $Manifest
Assert-PhasePrereqs -RepoRoot $repoRoot -Sources $sources -PhaseId H `
  -RequiredArtifacts @('docs/_shared/<basename>/facts.json')

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsDirFull = (Resolve-Path -LiteralPath $ResultsDir).Path
$stageXml       = Join-Path $resultsDirFull 'diagrams_stage_results.xml'
$dispXml        = Join-Path $resultsDirFull 'copilot_diagrams_results.xml'

$stageArgs = Add-SourceSelectorArgs -Target @{
                Throttle   = $Throttle
                ResultsXml = $stageXml
              } -Files $Files -Paths $Paths -Manifest $Manifest -SourceRoot $SourceRoot

# Dispatch step does NOT accept -SourceRoot.
$dispArgs = Add-SourceSelectorArgs -Target @{
                Throttle   = $DiagramsThrottle
                Agent      = $Agent
                ResultsXml = $dispXml
                DryRun     = [bool]$DryRun
              } -Files $Files -Paths $Paths -Manifest $Manifest
if ($Force) { $dispArgs.Force = $true }

exit (Invoke-PhaseBatch -PhaseId H -ResultsXml $dispXml -Action {
  Write-PhaseEvent -Phase H -Event 'step' -Data @{ name = 'stage' }
  & $stageBatch @stageArgs
  if ($LASTEXITCODE -ne 0) { return }
  Write-PhaseEvent -Phase H -Event 'step' -Data @{ name = 'dispatch' }
  & $dispBatch @dispArgs
})
