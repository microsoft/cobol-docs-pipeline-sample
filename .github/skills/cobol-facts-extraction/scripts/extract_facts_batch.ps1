#requires -Version 5.1
<#
.SYNOPSIS
  Run extract-facts.py over many sources in parallel; optionally run the
  workspace-scope incoming-xref pass.

.DESCRIPTION
  Reusable batch wrapper for the cobol-facts-extraction skill. Fans out
  .github/skills/cobol-facts-extraction/scripts/extract-facts.py across
  the given inputs using ForEach-Object -Parallel, captures per-file
  stdout/stderr/exit codes, persists a sorted result set to
  facts_results.xml, and exits non-zero if any child failed.

  With -XrefPass, ignores all input parameters and invokes
  xref-incoming-pass.py once over docs/_shared/**/facts.json. The xref
  pass is single-shot and not parallelizable.

.PARAMETER Files
  Explicit list of source paths (repo-relative or absolute).

.PARAMETER Paths
  One or more directories or globs to expand (e.g. repos/sample1/COBOL/*.CBL).

.PARAMETER Manifest
  Path to a JSON/CSV file describing entries:
    [{ "path": "...", "sourceRoot": "...", "output": "...", "manifest": "..." }, ...]
  Overrides -Files/-Paths.

.PARAMETER SourceRoot
  Optional --source-root applied to every input.

.PARAMETER Throttle
  Parallel degree. Defaults to [Environment]::ProcessorCount.

.PARAMETER ResultsXml
  Path for the Export-Clixml result file. Default: facts_results.xml in CWD.

.PARAMETER ExcludeExtensions
  File extensions to skip when expanding -Paths (case-insensitive). Default:
  .cob, .inp, .itt (copybooks and JCL inline-data are consumed by reference,
  not extracted standalone). Pass an empty array to disable.

.PARAMETER XrefPass
  Run the workspace incoming-xref pass instead of the per-file extractor.
  All other parameters are ignored.

.EXAMPLE
  pwsh -File .github/skills/cobol-facts-extraction/scripts/extract_facts_batch.ps1 `
       -Paths repos/sample1/COBOL/*.CBL

.EXAMPLE
  pwsh -File .github/skills/cobol-facts-extraction/scripts/extract_facts_batch.ps1 -XrefPass
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsXml = 'temp/facts_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt'),
  [switch]$XrefPass
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$extractPy = Join-Path $scriptDir 'extract-facts.py'
$xrefPy    = Join-Path $scriptDir 'xref-incoming-pass.py'
if (-not (Test-Path $extractPy)) { throw "extract-facts.py not found at $extractPy" }

if ($XrefPass) {
  if (-not (Test-Path $xrefPy)) { throw "xref-incoming-pass.py not found at $xrefPy" }
  & python $xrefPy
  exit $LASTEXITCODE
}

# Build entry list: @{ Path; SourceRoot; Output; Manifest }
$entries = [System.Collections.Generic.List[object]]::new()

if ($Manifest) {
  $raw = Get-Content -Raw -LiteralPath $Manifest
  $items =
    if ($Manifest -match '\.csv$') { $raw | ConvertFrom-Csv }
    else                            { $raw | ConvertFrom-Json }
  foreach ($i in $items) {
    $entries.Add([pscustomobject]@{
      Path       = [string]$i.path
      SourceRoot = [string]$i.sourceRoot
      Output     = [string]$i.output
      ManifestIn = [string]$i.manifest
    })
  }
}
else {
  $collected = @()
  $excludeSet = @{}
  foreach ($e in $ExcludeExtensions) {
    if ($e) { $excludeSet[$e.ToLowerInvariant()] = $true }
  }

  if ($Files) {
    foreach ($f in $Files) {
      if ((Test-Path -LiteralPath $f -PathType Container)) {
        $collected += (Get-ChildItem -LiteralPath $f -File -Recurse -ErrorAction Stop |
          Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
          ForEach-Object { $_.FullName })
      }
      else {
        $collected += $f
      }
    }
  }
  if ($Paths) {
    foreach ($p in $Paths) {
      if ((Test-Path -LiteralPath $p -PathType Container)) {
        $collected += (Get-ChildItem -LiteralPath $p -File -Recurse -ErrorAction Stop |
          Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
          ForEach-Object { $_.FullName })
      }
      else {
        $collected += (Get-ChildItem -Path $p -File -ErrorAction Stop |
          Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
          ForEach-Object { $_.FullName })
      }
    }
  }
  if (-not $collected) { throw 'No inputs. Provide -Files, -Paths, -Manifest, or -XrefPass.' }
  foreach ($f in $collected | Select-Object -Unique) {
    $entries.Add([pscustomobject]@{
      Path       = $f
      SourceRoot = $SourceRoot
      Output     = $null
      ManifestIn = $null
    })
  }
}

$entries = @($entries | Sort-Object Path)

Write-Host "Extracting facts for $($entries.Count) file(s) with throttle=$Throttle"

$__helperDir = Split-Path -Parent $PSCommandPath
while ($__helperDir -and -not (Test-Path (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1'))) {
  $__parent = Split-Path -Parent $__helperDir
  if ($__parent -eq $__helperDir) { throw 'Invoke-PythonBatch.ps1 helper not found (walked to filesystem root).' }
  $__helperDir = $__parent
}
. (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1')

$results = Invoke-PythonBatch -Entries $entries -Throttle $Throttle `
  -Variables @{ extractPy = $extractPy } `
  -BuildArgs {
  param($entry)
  $argv = @($extractPy, '--source', $entry.Path)
  if ($entry.SourceRoot) { $argv += @('--source-root', $entry.SourceRoot) }
  if ($entry.Output)     { $argv += @('--output', $entry.Output) }
  if ($entry.ManifestIn) { $argv += @('--manifest', $entry.ManifestIn) }
  return ,$argv
}
$results = @($results | Sort-Object Path)

$results | Export-Clixml -LiteralPath $ResultsXml

$failed = @($results | Where-Object { $_.Exit -ne 0 })
$ok     = $results.Count - $failed.Count

Write-Host "DONE total=$($results.Count) ok=$ok failed=$($failed.Count)"
if ($failed.Count -gt 0) {
  Write-Host 'Failures:'
  $failed | ForEach-Object { Write-Host "  [$($_.Exit)] $($_.Path)" }
  exit 1
}
exit 0
