#requires -Version 5.1
<#
.SYNOPSIS
  Run chunk.py over many sources in parallel.

.DESCRIPTION
  Reusable batch wrapper for the cobol-chunking skill. Fans out
  .github/skills/cobol-chunking/scripts/chunk.py across the given inputs using
  ForEach-Object -Parallel, captures per-file stdout/stderr/exit codes,
  persists a sorted result set to chunk_results.xml, and exits non-zero if any
  child failed. Deterministic: no timestamps, stable ordering in outputs.

.PARAMETER Files
  Explicit list of source paths (repo-relative or absolute). Mutually
  compatible with -Paths.

.PARAMETER Paths
  One or more directories or globs to expand (e.g. repos/sample1/COBOL/*.CBL).

.PARAMETER KindHint
  Optional --kind-hint applied to every input (cobol|cl|jcl|copybook|bms|proc|auto).
  Per-file hints require -Manifest.

.PARAMETER PlatformHint
  Optional --platform-hint applied to every input (mainframe|ibmi|auto).
  Per-file platform hints require -Manifest using the `platform` property.

.PARAMETER EncodingHint
  Optional --encoding-hint applied to every input. Per-file encoding hints
  require -Manifest using the `encoding` property.

.PARAMETER Manifest
  Path to a JSON/CSV file describing entries: [{ "path": "...", "hint": "...",
  "sourceRoot": "...", "output": "..." }, ...]. Overrides -Files/-Paths.

.PARAMETER SourceRoot
  Optional --source-root applied to every input.

.PARAMETER Throttle
  Parallel degree. Defaults to [Environment]::ProcessorCount.

.PARAMETER ResultsXml
  Path for the Export-Clixml result file. Default: chunk_results.xml in CWD.

.PARAMETER ExcludeExtensions
  File extensions to skip when expanding -Paths (case-insensitive, leading dot
  required). Default: .cob, .inp, .itt — copybooks (.COB live under COBOL/COPY)
  and JCL inline-data / include members (.INP, .ITT) are consumed by reference,
  not chunked as standalone sources. Pass an empty array to disable filtering.
  Does not filter -Files or -Manifest entries.

.EXAMPLE
  pwsh -File .github/skills/cobol-chunking/scripts/chunk_batch.ps1 `
       -Paths repos/sample1/COBOL/*.CBL

.EXAMPLE
  pwsh -File .github/skills/cobol-chunking/scripts/chunk_batch.ps1 `
       -Manifest temp/chunk_inputs.json -Throttle 8
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$KindHint,
  [ValidateSet('auto', 'mainframe', 'ibmi')]
  [string]$PlatformHint,
  [ValidateSet('auto', 'utf-8', 'cp037', 'cp1047', 'cp1140', 'cp1252', 'latin-1')]
  [string]$EncodingHint,
  [string]$Manifest,
  [string]$SourceRoot,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsXml = 'temp/chunk_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt')
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$chunkPy   = Join-Path $scriptDir 'chunk.py'
if (-not (Test-Path $chunkPy)) { throw "chunk.py not found at $chunkPy" }

# Build the entry list. Each entry: @{ Path; Hint; SourceRoot; Output }
$entries = [System.Collections.Generic.List[object]]::new()

if ($Manifest) {
  $raw = Get-Content -Raw -LiteralPath $Manifest
  $items =
    if ($Manifest -match '\.csv$') { $raw | ConvertFrom-Csv }
    else                            { $raw | ConvertFrom-Json }
  foreach ($i in $items) {
    $entries.Add([pscustomobject]@{
      Path       = [string]$i.path
      Hint       = [string]$i.hint
      Platform   = [string]$i.platform
      Encoding   = [string]$i.encoding
      SourceRoot = [string]$i.sourceRoot
      Output     = [string]$i.output
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
  if (-not $collected) { throw 'No inputs. Provide -Files, -Paths, or -Manifest.' }
  foreach ($f in $collected | Select-Object -Unique) {
    $entries.Add([pscustomobject]@{
      Path       = $f
      Hint       = $KindHint
      Platform   = $PlatformHint
      Encoding   = $EncodingHint
      SourceRoot = $SourceRoot
      Output     = $null
    })
  }
}

# Stable order for deterministic results file.
$entries = @($entries | Sort-Object Path)

Write-Host "Chunking $($entries.Count) file(s) with throttle=$Throttle"

$__helperDir = Split-Path -Parent $PSCommandPath
while ($__helperDir -and -not (Test-Path (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1'))) {
  $__parent = Split-Path -Parent $__helperDir
  if ($__parent -eq $__helperDir) { throw 'Invoke-PythonBatch.ps1 helper not found (walked to filesystem root).' }
  $__helperDir = $__parent
}
. (Join-Path $__helperDir 'scripts/lib/Invoke-PythonBatch.ps1')

$results = Invoke-PythonBatch -Entries $entries -Throttle $Throttle `
  -Variables @{ chunkPy = $chunkPy } `
  -BuildArgs {
  param($entry)
  $argv = @($chunkPy, '--source', $entry.Path)
  if ($entry.Hint)       { $argv += @('--kind-hint', $entry.Hint) }
  if ($entry.Platform)   { $argv += @('--platform-hint', $entry.Platform) }
  if ($entry.Encoding)   { $argv += @('--encoding-hint', $entry.Encoding) }
  if ($entry.SourceRoot) { $argv += @('--source-root', $entry.SourceRoot) }
  if ($entry.Output)     { $argv += @('--output', $entry.Output) }
  return ,$argv
} -BuildResult {
  param($entry, $exitCode, $stdout, $stderr)
  [pscustomobject]@{
    Path = $entry.Path; Hint = $entry.Hint; Platform = $entry.Platform; Encoding = $entry.Encoding
    Exit = $exitCode; Stdout = $stdout; Stderr = $stderr
  }
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
