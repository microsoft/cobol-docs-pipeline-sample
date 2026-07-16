#requires -Version 5.1
<#
.SYNOPSIS
  Per-GROUP Copilot CLI dispatcher for phase M (group technical-analysis).

.DESCRIPTION
  Iterates groups from config/grouping.yaml, asserts the staged finalize
  bundle exists at
    docs/_shared/_groups/<group_id>/_ta-group-bundles/_finalize.bundle.json,
  and invokes the Copilot CLI with the `technical-analysis-writer` agent
  (per-group scope) so it authors
    docs/<lang>/_groups/<group_id>/technical-analysis.md
  in one call per group per language.

  Empty grouping.yaml -> exit 0 no-op. Mechanics delegated to
  scripts/lib/Invoke-CopilotDispatch.ps1.
#>
[CmdletBinding()]
param(
  [string]$Manifest = 'config/grouping.yaml',
  [string]$Languages = 'en',
  [string]$Agent = 'technical-analysis-writer',
  [string]$CopilotCli = 'copilot',
  [string]$CopilotSubcommand = '',
  [string]$AgentSwitch = '--agent',
  [string]$PromptSwitch = '--prompt',
  [string[]]$AdditionalCopilotArgs = @(),
  [ValidateRange(1,32)] [int]$Throttle = 10,
  [string]$ResultsXml = 'temp/copilot_ta_group_finalize_results.xml',
  [int]$PerTaskTimeoutSec = 1800,
  [int]$MaxRetries = 2,
  [string]$PromptTemplate = 'config/prompts/ta-group-finalize.prompt.tmpl',
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

$readerScript = Join-Path $PSScriptRoot '../lib/read_groups.py'
$groupsJson = & python $readerScript $manifestPath
if ($LASTEXITCODE -ne 0) { throw "Failed to read groups from $manifestPath" }
$groups = @($groupsJson | ConvertFrom-Json)

if ($groups.Count -eq 0) {
  Write-Host 'run-docs-ta-group-finalize-batch: no groups declared in grouping.yaml — no-op.'
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
  $bundle = Join-Path $repoRoot ("docs/_shared/_groups/$gid/_ta-group-bundles/_finalize.bundle.json")
  if (-not (Test-Path -LiteralPath $bundle)) {
    Write-Warning "Bundle missing for group $gid : $bundle (run ta_group_stage_batch.ps1 first)"
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; GroupId = $gid; BundlePath = $bundle
      Exit = -2; Status = 'missing-bundle'; Command = ''
      Stdout = ''; Stderr = "bundle not found: $bundle"; DurationMs = 0
    })
    continue
  }
  $taFirst = Join-Path $repoRoot ("docs/$firstLang/_groups/$gid/technical-analysis.md")
  $fingerprint = Get-ResumeFingerprint -InputFiles @($bundle) -Agent $Agent -Languages $Languages
  if ($resumeEnabled -and $fingerprint -and (Test-ResumeSidecar -OutputPath $taFirst -Fingerprint $fingerprint)) {
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; GroupId = $gid; BundlePath = $bundle
      Exit = 0; Status = 'skipped-up-to-date'; Command = ''
      Stdout = 'skipped: dispatched sidecar matches fingerprint'
      Stderr = ''; DurationMs = 0
    })
    continue
  }
  if ($resumeEnabled -and (Test-Path -LiteralPath $taFirst)) {
    $bundleStamp = (Get-Item -LiteralPath $bundle).LastWriteTimeUtc
    $taStamp     = (Get-Item -LiteralPath $taFirst).LastWriteTimeUtc
    if ($taStamp -ge $bundleStamp) {
      $skipped.Add([pscustomobject]@{
        TaskId = $taskId; GroupId = $gid; BundlePath = $bundle
        Exit = 0; Status = 'skipped-up-to-date'; Command = ''
        Stdout = "skipped: technical-analysis.md ($taStamp) >= bundle ($bundleStamp)"
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
    OutputPath = $taFirst; ResumeFingerprint = $fingerprint; Prompt = $prompt
  })
}

$exit = Invoke-CopilotDispatchPool `
  -WorkItems $workItems `
  -Skipped $skipped `
  -LabelPrefix 'ta-group' `
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
