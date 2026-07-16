#requires -Version 5.1
<#
.SYNOPSIS
  Phase C — Extract per-chunk raw source text (docs/_shared/<file>/chunks/*.txt).

.DESCRIPTION
  Independent, autoconsistent entry point for phase C. Wraps
  .github/skills/chunk-text-extraction/scripts/extract_chunks_batch.ps1.

  Prereqs: every input source must have a chunk-manifest.json from phase A.
  On a missing prereq, exits with code 4.

.EXAMPLE
  pwsh -File scripts/phases/phase-C-extract-text.ps1 -Paths repos/sample1/COBOL/*.CBL
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsDir = 'temp'
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-PhaseInputs.ps1')
$repoRoot = Get-RepoRoot -ScriptPath $PSCommandPath
$batch    = Join-Path $repoRoot '.github/skills/chunk-text-extraction/scripts/extract_chunks_batch.ps1'
if (-not (Test-Path $batch)) { throw "Required script not found: $batch" }
if (-not $Files -and -not $Paths -and -not $Manifest) {
  throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
}

$sources = Get-PhaseInputs -Files $Files -Paths $Paths -Manifest $Manifest
Assert-PhasePrereqs -RepoRoot $repoRoot -Sources $sources -PhaseId C `
  -RequiredArtifacts @('docs/_shared/<basename>/chunk-manifest.json')

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsXml = Join-Path (Resolve-Path -LiteralPath $ResultsDir).Path 'chunk_text_results.xml'
$splat      = Add-SourceSelectorArgs -Target @{ Throttle = $Throttle; ResultsXml = $resultsXml } `
                -Files $Files -Paths $Paths -Manifest $Manifest -SourceRoot $SourceRoot

exit (Invoke-PhaseBatch -PhaseId C -ResultsXml $resultsXml -Action { & $batch @splat })
