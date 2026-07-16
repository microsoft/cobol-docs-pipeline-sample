#requires -Version 5.1
<#
.SYNOPSIS
  Deterministically assemble docs/<lang>/<file>/complete.md for many sources.

.DESCRIPTION
  Fans out .github/skills/section-doc-finalizer/scripts/assemble-complete.py
  across the given inputs. For each source it reads
  docs/_shared/<basename>/_finalize.bundle.json and stitches the LLM-authored
  index.md + every per-section MD (with H1->H2 demote and footnote-id
  namespacing) into complete.md per language.

  No LLM is invoked. This replaces the complete.md authoring previously done
  by the section-doc-finalizer agent, saving tokens.
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$Languages = 'en',
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsXml = 'temp/complete_assemble_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt'),
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

$scriptDir  = Split-Path -Parent $PSCommandPath
$assemblePy = Join-Path $scriptDir 'assemble-complete.py'
if (-not (Test-Path $assemblePy)) { throw "assemble-complete.py not found at $assemblePy" }

$entries = [System.Collections.Generic.List[object]]::new()
if ($Manifest) {
  $raw = Get-Content -Raw -LiteralPath $Manifest
  $items =
    if ($Manifest -match '\.csv$') { $raw | ConvertFrom-Csv }
    else                            { $raw | ConvertFrom-Json }
  foreach ($i in $items) {
    $entries.Add([pscustomobject]@{ Path = [string]$i.path })
  }
}
else {
  $collected = @()
  if ($Files) { $collected += $Files }
  if ($Paths) {
    $excludeSet = @{}
    foreach ($e in $ExcludeExtensions) { if ($e) { $excludeSet[$e.ToLowerInvariant()] = $true } }
    foreach ($p in $Paths) {
      $collected += (Get-ChildItem -Path $p -File -ErrorAction Stop |
        Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
        ForEach-Object { $_.FullName })
    }
  }
  if (-not $collected) { throw 'No inputs. Provide -Files, -Paths, or -Manifest.' }
  foreach ($f in $collected | Select-Object -Unique) {
    $entries.Add([pscustomobject]@{ Path = $f })
  }
}

$__helperDir = Split-Path -Parent $PSCommandPath
while ($__helperDir -and -not (Test-Path (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1'))) {
  $__parent = Split-Path -Parent $__helperDir
  if ($__parent -eq $__helperDir) { throw 'Invoke-PythonBatch.ps1 helper not found.' }
  $__helperDir = $__parent
}
. (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1')

$entries = @($entries | Sort-Object Path)
Write-Host "Assembling complete.md for $($entries.Count) file(s) throttle=$Throttle languages=$Languages force=$Force"

$bundleMissing = [System.Collections.Generic.List[object]]::new()
$runnable      = [System.Collections.Generic.List[object]]::new()
foreach ($e in $entries) {
  $basename = [System.IO.Path]::GetFileName($e.Path)
  $bundle   = Join-Path $__helperDir ("docs/_shared/$basename/_finalize.bundle.json")
  if (-not (Test-Path -LiteralPath $bundle)) {
    $bundleMissing.Add([pscustomobject]@{
      Path = $e.Path; Exit = -2; Stdout = ''
      Stderr = "bundle missing: $bundle"
    })
    continue
  }
  $runnable.Add([pscustomobject]@{ Path = $e.Path; Bundle = $bundle })
}

$results = @()
if ($runnable.Count -gt 0) {
  $results = Invoke-PythonBatch -Entries $runnable -Throttle $Throttle `
    -Variables @{ assemblePy = $assemblePy; Languages = $Languages; ForceFlag = [bool]$Force } `
    -BuildArgs {
      param($entry)
      $argv = @($assemblePy, '--bundle', $entry.Bundle, '--languages', $Languages)
      if ($ForceFlag) { $argv += '--force' }
      return ,$argv
    }
}
$results = @($results) + @($bundleMissing)
$results = @($results | Sort-Object Path)

$results | Export-Clixml -LiteralPath $ResultsXml

$failed = @($results | Where-Object { $_.Exit -ne 0 })
$ok     = $results.Count - $failed.Count
Write-Host "DONE total=$($results.Count) ok=$ok failed=$($failed.Count)"
if ($failed.Count -gt 0) {
  Write-Host 'Failures:'
  $failed | ForEach-Object { Write-Host "  [$($_.Exit)] $($_.Path): $($_.Stderr.Trim())" }
  exit 1
}
exit 0
