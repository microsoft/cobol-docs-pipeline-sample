#requires -Version 5.1
<#
.SYNOPSIS
  Build a file://-browsable offline copy of the documentation portal.

.DESCRIPTION
  Thin PowerShell wrapper around scripts/portal/build-portal-offline.py. It builds
  (or reuses) the static portal under docs/_portal/site and produces an
  offline copy under docs/_portal/site-offline that works when opened
  directly from disk — no web server required.

  On success the generated index.html can optionally be opened in the
  default browser via -Open.

.PARAMETER SourceRoot
  Optional source tree passed through to build-portal-static.py to populate
  the side-by-side source viewer (e.g. repos/sample1).

.PARAMETER SkipBuild
  Do not re-run build-portal-static.py; patch the existing site instead.

.PARAMETER Site
  Input static site directory. Defaults to docs/_portal/site.

.PARAMETER Out
  Offline output directory. Defaults to docs/_portal/site-offline.

.PARAMETER Open
  Open the generated index.html in the default browser when the build
  succeeds.

.EXAMPLE
  ./scripts/portal/build-portal-offline.ps1

.EXAMPLE
  ./scripts/portal/build-portal-offline.ps1 -SourceRoot repos/sample1 -Open

.EXAMPLE
  ./scripts/portal/build-portal-offline.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
    [string]$SourceRoot,
    [switch]$SkipBuild,
    [string]$Site,
    [string]$Out,
    [switch]$Open
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pyScript = Join-Path $PSScriptRoot 'build-portal-offline.py'

if (-not (Test-Path -LiteralPath $pyScript)) {
    throw "Cannot find build-portal-offline.py next to this script ($pyScript)."
}

# Resolve a Python interpreter (prefer 'python', fall back to 'py -3').
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    $pyExe = $python.Source
    $pyArgs = @($pyScript)
} else {
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if (-not $pyLauncher) {
        throw "No Python interpreter found. Install Python or add it to PATH."
    }
    $pyExe = $pyLauncher.Source
    $pyArgs = @('-3', $pyScript)
}

if ($SkipBuild)            { $pyArgs += '--skip-build' }
if ($SourceRoot)          { $pyArgs += @('--source-root', $SourceRoot) }
if ($Site)                { $pyArgs += @('--site', $Site) }
if ($Out)                 { $pyArgs += @('--out', $Out) }

Push-Location $repoRoot
try {
    & $pyExe @pyArgs
    $exit = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($exit -ne 0) {
    throw "build-portal-offline.py failed with exit code $exit."
}

$outRoot = if ($Out) { $Out } else { Join-Path $repoRoot 'docs/_portal/site-offline' }
$indexHtml = Join-Path $outRoot 'index.html'

if (Test-Path -LiteralPath $indexHtml) {
    Write-Host "Offline portal ready: $indexHtml" -ForegroundColor Green
    if ($Open) {
        Start-Process $indexHtml
    }
} else {
    Write-Warning "Build reported success but $indexHtml was not found."
}

exit 0
