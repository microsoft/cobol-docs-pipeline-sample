function Resolve-EffectiveGroupingManifest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$RepoRoot,
    [Parameter(Mandatory)] [string]$Manifest,
    [string]$GeneratedDir = 'temp/_generated'
  )

  $repoRootPath = (Resolve-Path -LiteralPath $RepoRoot).Path
  $manifestPath = if ([System.IO.Path]::IsPathRooted($Manifest)) { $Manifest } else { Join-Path $repoRootPath $Manifest }
  $derivePy = Join-Path $repoRootPath 'scripts/lib/derive_groups.py'
  if (-not (Test-Path -LiteralPath $derivePy)) {
    throw "derive_groups.py not found at $derivePy"
  }

  $generatedPath = if ([System.IO.Path]::IsPathRooted($GeneratedDir)) { $GeneratedDir } else { Join-Path $repoRootPath $GeneratedDir }
  New-Item -ItemType Directory -Path $generatedPath -Force | Out-Null
  $outManifest = Join-Path $generatedPath 'grouping.derived.yaml'

  $resultJson = & python $derivePy --manifest $manifestPath --repo-root $repoRootPath --out $outManifest
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to resolve effective grouping manifest from $manifestPath"
  }

  $result = $resultJson | ConvertFrom-Json
  return [pscustomobject]@{
    ManifestPath = $result.effective_manifest
    Derived      = [bool]$result.derived
    GroupCount   = [int]$result.group_count
    Groups       = $result.groups
  }
}