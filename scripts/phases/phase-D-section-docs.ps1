#requires -Version 5.1
<#
.SYNOPSIS
  Phase D — Copilot per-chunk section documentation orchestrator.

.DESCRIPTION
  Independent, autoconsistent entry point for phase D. Wraps
  scripts/dispatchers/run-docs-copilot-batch.ps1 (the heavy per-chunk LLM dispatcher).

  Prereqs per source: chunk-manifest.json, facts.json, and at least one
  chunks/*.txt. On a missing prereq, exits with code 4.

.PARAMETER Agent
  Copilot agent identifier. Default: section-doc-writer.

.PARAMETER Languages
  Comma-separated languages forwarded to section bundle staging. Default: en.
  The pipeline supplies its resolved section languages when invoking this phase.

.PARAMETER DocsThrottle
  Parallel limit for the per-chunk dispatcher. Standalone default: 15.
  Explicit values below 10 are honored; the public runner supplies its resolved limit.

.PARAMETER DryRun
  Build dispatch commands without invoking the Copilot CLI.

.PARAMETER TrackUsage
  Enable per-task Copilot usage tracking (OTEL export). Default: on.

.PARAMETER OtelDir
  Optional output directory for OTEL task JSONL files.

.PARAMETER PremiumMultiplier
  Multiplier used to roll up premium requests. Default: 1.

.EXAMPLE
  pwsh -File scripts/phases/phase-D-section-docs.ps1 -Paths repos/sample1/COBOL/*.CBL -DryRun
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsDir = 'temp',
  [string]$Agent = 'section-doc-writer',
  [string]$Languages = 'en',
  [int]$DocsThrottle = 15,
  [bool]$TrackUsage = $true,
  [string]$OtelDir,
  [double]$PremiumMultiplier = 1,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-PhaseInputs.ps1')
$repoRoot = Get-RepoRoot -ScriptPath $PSCommandPath
$batch    = Join-Path $repoRoot 'scripts/dispatchers/run-docs-copilot-batch.ps1'
if (-not (Test-Path $batch)) { throw "Required script not found: $batch" }
if (-not $Files -and -not $Paths -and -not $Manifest) {
  throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
}

$sources = Get-PhaseInputs -Files $Files -Paths $Paths -Manifest $Manifest
Assert-PhasePrereqs -RepoRoot $repoRoot -Sources $sources -PhaseId D `
  -RequiredArtifacts @(
    'docs/_shared/<basename>/chunk-manifest.json',
    'docs/_shared/<basename>/facts.json',
    'docs/_shared/<basename>/chunks/*.txt'
  )

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsXml = Join-Path (Resolve-Path -LiteralPath $ResultsDir).Path 'copilot_doc_results.xml'
$splat      = Add-SourceSelectorArgs -Target @{
                Throttle      = $DocsThrottle
                AllowLowerThrottle = $true
                EnsureBundles = $true
                Agent         = $Agent
                Languages     = $Languages
                ResultsXml    = $resultsXml
                DryRun        = [bool]$DryRun
              } -Files $Files -Paths $Paths -Manifest $Manifest -SourceRoot $SourceRoot

if ($TrackUsage) {
  $splat.TrackUsage = $true
}
if (-not [string]::IsNullOrWhiteSpace($OtelDir)) {
  $splat.OtelDir = $OtelDir
}
if ($PremiumMultiplier -ne 1) {
  $splat.PremiumMultiplier = $PremiumMultiplier
}

exit (Invoke-PhaseBatch -PhaseId D -ResultsXml $resultsXml -Action { & $batch @splat })
