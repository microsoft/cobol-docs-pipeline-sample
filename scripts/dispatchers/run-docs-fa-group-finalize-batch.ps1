#requires -Version 5.1
<#
.SYNOPSIS
  Per-group Copilot finalizer dispatch wrapper for phase K (group functional analysis).

.DESCRIPTION
  Simplified single-call (phase-I style) dispatcher. Iterates groups from
  config/grouping.yaml, asserts the staged finalize bundle exists at
    docs/_shared/_groups/<group_id>/_fa-group-bundles/_finalize.bundle.json,
  and invokes the Copilot CLI with the `functional-analysis-group-writer`
  agent so it authors docs/<lang>/_groups/<group_id>/functional-analysis.md in
  one call per group per language.

  Empty grouping.yaml -> exit 0 no-op. Mechanics (runspace pool, arg quoting,
  record schema, results XML) are delegated to
  scripts/lib/Invoke-CopilotDispatch.ps1.
#>
[CmdletBinding()]
param(
  [string]$Manifest = 'config/grouping.yaml',
  [string]$Languages = 'en',
  [string]$Agent = 'functional-analysis-group-writer',
  [string]$CopilotCli = 'copilot',
  [string]$CopilotSubcommand = '',
  [string]$AgentSwitch = '--agent',
  [string]$PromptSwitch = '--prompt',
  [string[]]$AdditionalCopilotArgs = @(),
  [ValidateRange(1,32)] [int]$Throttle = 10,
  [string]$ResultsXml = 'temp/copilot_fa_group_finalize_results.xml',
  [int]$PerTaskTimeoutSec = 1800,
  [int]$MaxRetries = 2,
  [string]$PromptTemplate = 'config/prompts/fa-group-finalize.prompt.tmpl',
  [switch]$Resume,
  [switch]$Force,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../lib/Invoke-CopilotDispatch.ps1')

$resumeEnabled = if ($PSBoundParameters.ContainsKey('Resume')) { [bool]$Resume } else { -not $Force }
if ($Force) { $resumeEnabled = $false }

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$manifestPath = if ([System.IO.Path]::IsPathRooted($Manifest)) {
  $Manifest
} else {
  Join-Path $repoRoot $Manifest
}
if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Grouping manifest not found: $manifestPath"
}

$templatePath = if ([System.IO.Path]::IsPathRooted($PromptTemplate)) {
  $PromptTemplate
} else {
  Join-Path $repoRoot $PromptTemplate
}
$promptTemplateText = Read-PromptTemplate -RepoRoot $repoRoot -TemplatePath $templatePath

# Read groups via a sidecar script (no string interpolation of paths into Python).
$readerScript = Join-Path $PSScriptRoot '../lib/read_groups.py'
$groupsJson = & python $readerScript $manifestPath
if ($LASTEXITCODE -ne 0) { throw "Failed to read groups from $manifestPath" }
$groups = @($groupsJson | ConvertFrom-Json)

if ($groups.Count -eq 0) {
  Write-Host 'run-docs-fa-group-finalize-batch: no groups declared in grouping.yaml — no-op.'
  @() | Export-Clixml -LiteralPath $ResultsXml
  exit 0
}

$firstLang = Resolve-FirstLanguage -Languages $Languages
$workItems = New-Object System.Collections.Generic.List[object]
$skipped   = New-Object System.Collections.Generic.List[object]
$taskId = 0

foreach ($g in $groups) {
  $taskId++
  $gid    = $g.id
  $bundle = Join-Path $repoRoot ("docs/_shared/_groups/$gid/_fa-group-bundles/_finalize.bundle.json")
  if (-not (Test-Path -LiteralPath $bundle)) {
    Write-Warning "Bundle missing for group $gid : $bundle (run fa_group_stage_batch.ps1 first)"
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; GroupId = $gid; BundlePath = $bundle
      Exit = -2; Status = 'missing-bundle'; Command = ''
      Stdout = ''; Stderr = "bundle not found: $bundle"; DurationMs = 0
    })
    continue
  }
  $faFirst = Join-Path $repoRoot ("docs/$firstLang/_groups/$gid/functional-analysis.md")
  $fingerprint = Get-ResumeFingerprint -InputFiles @($bundle) -Agent $Agent -Languages $Languages
  if ($resumeEnabled -and $fingerprint -and (Test-ResumeSidecar -OutputPath $faFirst -Fingerprint $fingerprint)) {
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; GroupId = $gid; BundlePath = $bundle
      Exit = 0; Status = 'skipped-up-to-date'; Command = ''
      Stdout = 'skipped: dispatched sidecar matches fingerprint'
      Stderr = ''; DurationMs = 0
    })
    continue
  }
  if ($resumeEnabled -and (Test-Path -LiteralPath $faFirst)) {
    $bundleStamp = (Get-Item -LiteralPath $bundle).LastWriteTimeUtc
    $faStamp     = (Get-Item -LiteralPath $faFirst).LastWriteTimeUtc
    if ($faStamp -ge $bundleStamp) {
      $skipped.Add([pscustomobject]@{
        TaskId = $taskId; GroupId = $gid; BundlePath = $bundle
        Exit = 0; Status = 'skipped-up-to-date'; Command = ''
        Stdout = "skipped: functional-analysis.md ($faStamp) >= bundle ($bundleStamp)"
        Stderr = ''; DurationMs = 0
      })
      continue
    }
  }
  $prompt = Expand-PromptTemplate -Template $promptTemplateText -Tokens @{
    GROUP_ID    = $gid
    BUNDLE_PATH = $bundle
  }
  $workItems.Add([pscustomobject]@{
    TaskId = $taskId; GroupId = $gid; BundlePath = $bundle
    OutputPath = $faFirst; ResumeFingerprint = $fingerprint; Prompt = $prompt
  })
}

$exit = Invoke-CopilotDispatchPool `
  -WorkItems $workItems `
  -Skipped $skipped `
  -LabelPrefix 'fa-group' `
  -KeyField 'GroupId' `
  -Agent $Agent `
  -CopilotCli $CopilotCli `
  -CopilotSubcommand $CopilotSubcommand `
  -AgentSwitch $AgentSwitch `
  -PromptSwitch $PromptSwitch `
  -AdditionalCopilotArgs $AdditionalCopilotArgs `
  -Throttle $Throttle `
  -ResultsXml $ResultsXml `
  -WorkingDirectory $repoRoot `
  -PerTaskTimeoutSec $PerTaskTimeoutSec `
  -MaxRetries $MaxRetries `
  -OutputPathField 'OutputPath' `
  -ResumeFingerprintField 'ResumeFingerprint' `
  -DryRun:$DryRun

exit $exit
