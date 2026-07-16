#requires -Version 5.1
<#
.SYNOPSIS
  Phase B — Extract facts.json knowledge graph from chunked sources.
  Includes the workspace incoming-xref pass (B.1) by default.

.DESCRIPTION
  Independent, autoconsistent entry point for phase B. Wraps
  .github/skills/cobol-facts-extraction/scripts/extract_facts_batch.ps1.

  Prereqs: every input source must have a chunk-manifest.json from phase A.
  On a missing prereq, exits with code 4.

.PARAMETER SkipXrefPass
  Skip the workspace incoming-xref pass (B.1) that runs after fact extraction.

.EXAMPLE
  pwsh -File scripts/phases/phase-B-facts.ps1 -Paths repos/sample1/COBOL/*.CBL
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsDir = 'temp',
  [switch]$SkipXrefPass
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-PhaseInputs.ps1')
$repoRoot = Get-RepoRoot -ScriptPath $PSCommandPath
$batch    = Join-Path $repoRoot '.github/skills/cobol-facts-extraction/scripts/extract_facts_batch.ps1'
if (-not (Test-Path $batch)) { throw "Required script not found: $batch" }
if (-not $Files -and -not $Paths -and -not $Manifest) {
  throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
}

$sources = Get-PhaseInputs -Files $Files -Paths $Paths -Manifest $Manifest
Assert-PhasePrereqs -RepoRoot $repoRoot -Sources $sources -PhaseId B `
  -RequiredArtifacts @('docs/_shared/<basename>/chunk-manifest.json')

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsXml = Join-Path (Resolve-Path -LiteralPath $ResultsDir).Path 'facts_results.xml'
$splat      = Add-SourceSelectorArgs -Target @{ Throttle = $Throttle; ResultsXml = $resultsXml } `
                -Files $Files -Paths $Paths -Manifest $Manifest -SourceRoot $SourceRoot

exit (Invoke-PhaseBatch -PhaseId B -ResultsXml $resultsXml -Action {
  & $batch @splat
  if ($LASTEXITCODE -ne 0) { return }
  if (-not $SkipXrefPass) {
    Write-PhaseEvent -Phase B -Event 'step' -Data @{ name = 'xref-pass' }
    & $batch -XrefPass
  }
})
