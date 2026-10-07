#requires -Version 5.1
<#
.SYNOPSIS
  Phase N — Build the documentation portal (web + offline editions).

.DESCRIPTION
  Independent, autoconsistent entry point for phase N. Wraps:
    scripts/portal/build-portal-offline.ps1

  This is a workspace-scoped phase (no per-file inputs). It builds the
  static web portal under docs/_portal/site and an offline, file://-browsable
  copy under docs/_portal/site-offline. Run it after the per-file and group
  documentation phases have produced their Markdown deliverables.

.PARAMETER SourceRoot
  Optional source tree forwarded to the portal builder to populate the
  side-by-side source viewer (e.g. repos/sample1).

.PARAMETER SkipBuild
  Reuse the existing docs/_portal/site instead of rebuilding it; only the
  offline copy is (re)generated. Language selection must still match.

.PARAMETER Languages
  Optional comma-separated portal languages. Defaults to output.languages
  in config/pipeline.yaml when this phase is invoked independently.

.PARAMETER Site
  Input static site directory. Defaults to docs/_portal/site.

.PARAMETER Out
  Offline output directory. Defaults to docs/_portal/site-offline.

.PARAMETER Open
  Open the generated offline index.html in the default browser on success.

.EXAMPLE
  pwsh -File scripts/phases/phase-N-portal.ps1 -SourceRoot repos/sample1
#>
[CmdletBinding()]
param(
  [string]$ResultsDir = 'temp',
  [string]$SourceRoot,
  [switch]$SkipBuild,
  [string]$Site,
  [string]$Out,
  [switch]$Open,
  [string]$Languages
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'lib/Resolve-PhaseInputs.ps1')
$repoRoot    = Get-RepoRoot -ScriptPath $PSCommandPath
$portalBuild = Join-Path $repoRoot 'scripts/portal/build-portal-offline.ps1'
if (-not (Test-Path -LiteralPath $portalBuild)) {
  throw "Required script not found: $portalBuild"
}

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null

$buildArgs = @{}
if ($SourceRoot) { $buildArgs.SourceRoot = $SourceRoot }
if ($Languages)  { $buildArgs.Languages = $Languages }
if ($SkipBuild)  { $buildArgs.SkipBuild  = $true }
if ($Site)       { $buildArgs.Site       = $Site }
if ($Out)        { $buildArgs.Out        = $Out }
if ($Open)       { $buildArgs.Open       = $true }

Write-PhaseEvent -Phase N -Event 'start' -Data @{
  sourceRoot = $(if ($SourceRoot) { $SourceRoot } else { '<none>' }); skipBuild = [bool]$SkipBuild
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Write-PhaseEvent -Phase N -Event 'step' -Data @{ name = 'portal-build' }
try {
  & $portalBuild @buildArgs
  $exit = $LASTEXITCODE
  if ($null -eq $exit) { $exit = 0 }
} catch {
  Write-Warning "Portal build failed: $($_.Exception.Message)"
  $exit = 1
}
$sw.Stop()

$elapsed = '{0:N1}s' -f $sw.Elapsed.TotalSeconds
Write-PhaseEvent -Phase N -Event 'end' -Data @{ exit = $exit; elapsed = $elapsed }
Write-Host ("PHASE-DONE phase=N exit={0} elapsed={1}" -f $exit, $elapsed)
exit $exit
