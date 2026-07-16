#requires -Version 5.1
<#
.SYNOPSIS
  Phase A — Chunk mainframe and IBM i source files into chunk-manifest.json.

.DESCRIPTION
  Independent, autoconsistent entry point for phase A. Wraps
  .github/skills/cobol-chunking/scripts/chunk_batch.ps1. No upstream prereqs.

  Produces docs/_shared/<basename>/chunk-manifest.json per input.

.EXAMPLE
  pwsh -File scripts/phases/phase-A-chunk.ps1 -Paths repos/sample1/COBOL/*.CBL
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [ValidateSet('auto', 'mainframe', 'ibmi')]
  [string]$PlatformHint,
  [ValidateSet('auto', 'utf-8', 'cp037', 'cp1047', 'cp1140', 'cp1252', 'latin-1')]
  [string]$EncodingHint,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsDir = 'temp'
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-PhaseInputs.ps1')
$repoRoot = Get-RepoRoot -ScriptPath $PSCommandPath
$batch    = Join-Path $repoRoot '.github/skills/cobol-chunking/scripts/chunk_batch.ps1'
if (-not (Test-Path $batch)) { throw "Required script not found: $batch" }
if (-not $Files -and -not $Paths -and -not $Manifest) {
  throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
}

Write-Information "Phase-A-Input: Files=$($Files -join ';') Paths=$($Paths -join ';') Manifest=$Manifest" -InformationAction Continue

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsXml = Join-Path (Resolve-Path -LiteralPath $ResultsDir).Path 'chunk_results.xml'

try {
  $splat      = Add-SourceSelectorArgs -Target @{ Throttle = $Throttle; ResultsXml = $resultsXml } `
                  -Files $Files -Paths $Paths -Manifest $Manifest -SourceRoot $SourceRoot
  if ($PlatformHint) { $splat.PlatformHint = $PlatformHint }
  if ($EncodingHint) { $splat.EncodingHint = $EncodingHint }
  Write-Information "Phase-A-Splat: $($splat | ConvertTo-Json -Depth 3)" -InformationAction Continue
} catch {
  Write-Error "Phase-A-Splat-Error: Failed to build arguments: $($_.Exception.Message)"
  throw
}

exit (Invoke-PhaseBatch -PhaseId A -ResultsXml $resultsXml -Action { & $batch @splat })
