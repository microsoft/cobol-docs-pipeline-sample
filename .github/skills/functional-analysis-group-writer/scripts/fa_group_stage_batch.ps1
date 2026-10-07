#requires -Version 5.1
<#
.SYNOPSIS
  Stage per-group functional-analysis finalize bundles for phase K.

.DESCRIPTION
  Simplified single-call (phase-I style) stager. Iterates groups declared in
  config/grouping.yaml and fans out assemble-inputs.py once per group to
  produce
    docs/_shared/_groups/<group_id>/_fa-group-bundles/_finalize.bundle.{json,md}
  using the existing Invoke-PythonBatch runspace-pool helper.

  If grouping.yaml has zero groups, this phase is a graceful no-op (exit 0).
#>
[CmdletBinding()]
param(
  [string]$Manifest = 'config/grouping.yaml',
  [string]$Languages = 'en',
  [string]$ProfileName,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsXml = 'temp/fa_group_stage_results.xml',
  [switch]$Prune,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

$scriptDir  = Split-Path -Parent $PSCommandPath
$assemblePy = Join-Path $scriptDir 'assemble-inputs.py'
if (-not (Test-Path $assemblePy)) { throw "assemble-inputs.py not found at $assemblePy" }

# Walk up to find the repo root (the parent of .github).
$repoRoot = $scriptDir
while ($repoRoot -and -not (Test-Path (Join-Path $repoRoot '.github'))) {
  $parent = Split-Path -Parent $repoRoot
  if ($parent -eq $repoRoot) { throw 'Unable to locate repo root from fa_group_stage_batch.ps1.' }
  $repoRoot = $parent
}

$manifestPath = if ([System.IO.Path]::IsPathRooted($Manifest)) { $Manifest } else { Join-Path $repoRoot $Manifest }
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Grouping manifest not found: $manifestPath" }

$readerScript = Join-Path $repoRoot 'scripts/lib/read_groups.py'
if (-not (Test-Path -LiteralPath $readerScript)) {
  throw "Group reader helper not found: $readerScript"
}
$groupsJson = & python $readerScript $manifestPath
if ($LASTEXITCODE -ne 0) { throw "Failed to read group ids from $manifestPath" }
$parsedGroups = ConvertFrom-Json -InputObject ($groupsJson -join [Environment]::NewLine)
$groups = @($parsedGroups)

if ($groups.Count -eq 0) {
  Write-Host 'fa_group_stage_batch: no groups declared in grouping.yaml — no-op.'
  @() | Export-Clixml -LiteralPath $ResultsXml
  exit 0
}

$eligibleGroups = New-Object System.Collections.Generic.List[object]
$skipped = New-Object System.Collections.Generic.List[object]
$taskId = 0
foreach ($g in $groups) {
  $taskId++
  $gid = [string]$g.id
  $gid = $gid.Trim()
  if ([string]::IsNullOrWhiteSpace($gid)) {
    continue
  }
  $members = @($g.members | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $allPrc = ($members.Count -gt 0)
  foreach ($m in $members) {
    if ([System.IO.Path]::GetExtension($m).ToLowerInvariant() -ne '.prc') {
      $allPrc = $false
      break
    }
  }
  if ($allPrc) {
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId
      GroupId = $gid
      Path = $gid
      Exit = 0
      Status = 'skipped-prc-only'
      Stdout = "skipped: phase K generation disabled for PRC-only group '$gid'"
      Stderr = ''
    })
    continue
  }
  $eligibleGroups.Add([pscustomobject]@{
    TaskId = $taskId
    GroupId = $gid
    Path = $gid
  })
}

if ($eligibleGroups.Count -eq 0) {
  Write-Host 'fa_group_stage_batch: all groups skipped (PRC-only).'
  @($skipped | Sort-Object TaskId) | Export-Clixml -LiteralPath $ResultsXml
  Write-Host "DONE total=$($skipped.Count) ok=$($skipped.Count) failed=0 skipped_prc_only=$($skipped.Count)"
  exit 0
}

Write-Host "Staging group functional-analysis finalize bundles for $($eligibleGroups.Count) eligible group(s) with throttle=$Throttle (languages=$Languages)"

$helperDir = $scriptDir
while ($helperDir -and -not (Test-Path (Join-Path $helperDir 'scripts/lib/Invoke-PythonBatch.ps1'))) {
  $parent = Split-Path -Parent $helperDir
  if ($parent -eq $helperDir) { throw 'Invoke-PythonBatch.ps1 helper not found (walked to filesystem root).' }
  $helperDir = $parent
}
. (Join-Path $helperDir 'scripts/lib/Invoke-PythonBatch.ps1')

$entries = $eligibleGroups.ToArray()

$runResults = Invoke-PythonBatch -Entries $entries -Throttle $Throttle `
  -Variables @{ assemblePy = $assemblePy; Languages = $Languages; Manifest = $manifestPath; ProfileName = $ProfileName } `
  -BuildArgs {
    param($entry)
    if ([string]::IsNullOrWhiteSpace($entry.GroupId)) {
      throw 'fa_group_stage_batch: encountered empty group id while building python arguments.'
    }
    $out = "docs/_shared/_groups/$($entry.GroupId)/_fa-group-bundles/_finalize.bundle.json"
    $argv = @($assemblePy, '--group-id', $entry.GroupId, '--languages', $Languages,
              '--manifest', $Manifest, '--out', $out)
    if ($ProfileName) { $argv += @('--profile-name', $ProfileName) }
    return ,$argv
  } `
  -BuildResult {
    param($entry, $exitCode, $stdout, $stderr)
    [pscustomobject]@{
      TaskId = $entry.TaskId
      GroupId = $entry.GroupId
      Path = $entry.Path
      Exit = $exitCode
      Status = if ($exitCode -eq 0) { 'ok' } else { 'failed' }
      Stdout = $stdout
      Stderr = $stderr
    }
  }

$results = @($runResults + $skipped | Sort-Object TaskId)
$results | Export-Clixml -LiteralPath $ResultsXml

$failed = @($results | Where-Object { $_.Exit -ne 0 })
$ok = $results.Count - $failed.Count
Write-Host "DONE total=$($results.Count) ok=$ok failed=$($failed.Count) skipped_prc_only=$($skipped.Count)"
if ($failed.Count -gt 0) {
  Write-Host 'Failures:'
  $failed | ForEach-Object { Write-Host "  [$($_.Exit)] $($_.Path) :: $($_.Stderr)" }
  if (@($failed | Where-Object { $_.Exit -eq 4 }).Count -gt 0) { exit 4 }
  exit 1
}
exit 0
