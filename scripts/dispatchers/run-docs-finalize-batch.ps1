#requires -Version 5.1
<#
.SYNOPSIS
  Per-FILE Copilot CLI dispatcher for the phase-C per-file finalizer
  (composes index.md only; complete.md is stitched deterministically
  by a post-step).

.DESCRIPTION
  One Copilot CLI call per source: reads the staged bundle at
  `docs/_shared/<basename>/_finalize.bundle.json` and invokes the
  `section-doc-finalizer` agent to compose `docs/<lang>/<basename>/index.md`
  for every requested language.

  Mechanics delegated to scripts/lib/Invoke-CopilotDispatch.ps1.
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$Languages = 'en',
  [string]$Agent = 'section-doc-finalizer',
  [string]$CopilotCli = 'copilot',
  [string]$CopilotSubcommand = '',
  [string]$AgentSwitch = '--agent',
  [string]$PromptSwitch = '--prompt',
  [string[]]$AdditionalCopilotArgs = @(),
  [ValidateRange(1,32)] [int]$Throttle = 10,
  [string]$ResultsXml = 'temp/copilot_finalize_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt'),
  [int]$PerTaskTimeoutSec = 1800,
  [int]$MaxRetries = 2,
  [string]$PromptTemplate = 'config/prompts/section-finalize.prompt.tmpl',
  [switch]$Resume,
  [switch]$Force,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../lib/Invoke-CopilotDispatch.ps1')

$resumeEnabled = if ($PSBoundParameters.ContainsKey('Resume')) { [bool]$Resume } else { -not $Force }
if ($Force) { $resumeEnabled = $false }

$repoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$firstLang = Resolve-FirstLanguage -Languages $Languages
$promptTpl = Read-PromptTemplate -RepoRoot $repoRoot -TemplatePath $PromptTemplate

$inputs = Expand-SourceInputs -Files $Files -Paths $Paths -Manifest $Manifest -ExcludeExtensions $ExcludeExtensions

$workItems = New-Object System.Collections.Generic.List[object]
$skipped   = New-Object System.Collections.Generic.List[object]
$taskId = 0

foreach ($src in $inputs) {
  $taskId++
  $basename = [System.IO.Path]::GetFileName($src)
  $bundle   = Join-Path $repoRoot ("docs/_shared/$basename/_finalize.bundle.json")

  if (-not (Test-Path -LiteralPath $bundle)) {
    Write-Warning "Finalize bundle missing for $basename : $bundle (run finalize_stage_batch.ps1 first)"
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; SourcePath = $src; SourceName = $basename
      BundlePath = $bundle; Exit = -2; Status = 'missing-bundle'; Command = ''
      Stdout = ''; Stderr = "bundle not found: $bundle"; DurationMs = 0
    })
    continue
  }

  $indexMd = Join-Path $repoRoot ("docs/$firstLang/$basename/index.md")
  $fingerprint = Get-ResumeFingerprint -InputFiles @($bundle) -Agent $Agent -Languages $Languages
  if ($resumeEnabled -and $fingerprint -and (Test-ResumeSidecar -OutputPath $indexMd -Fingerprint $fingerprint)) {
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; SourcePath = $src; SourceName = $basename
      BundlePath = $bundle; Exit = 0; Status = 'skipped-up-to-date'; Command = ''
      Stdout = "skipped: dispatched sidecar matches fingerprint"
      Stderr = ''; DurationMs = 0
    })
    continue
  }
  if ($resumeEnabled -and (Test-Path -LiteralPath $indexMd)) {
    $bundleStamp = (Get-Item -LiteralPath $bundle).LastWriteTimeUtc
    $indexStamp  = (Get-Item -LiteralPath $indexMd).LastWriteTimeUtc
    if ($indexStamp -ge $bundleStamp) {
      $skipped.Add([pscustomobject]@{
        TaskId = $taskId; SourcePath = $src; SourceName = $basename
        BundlePath = $bundle; Exit = 0; Status = 'skipped-up-to-date'; Command = ''
        Stdout = "skipped: index.md ($indexStamp) >= bundle ($bundleStamp)"
        Stderr = ''; DurationMs = 0
      })
      continue
    }
  }

  $prompt = Expand-PromptTemplate -Template $promptTpl -Tokens @{
    SOURCE_PATH = $src
    SOURCE_NAME = $basename
    BUNDLE_PATH = $bundle
  }
  $workItems.Add([pscustomobject]@{
    TaskId = $taskId; SourcePath = $src; SourceName = $basename
    BundlePath = $bundle; OutputPath = $indexMd
    ResumeFingerprint = $fingerprint; Prompt = $prompt
  })
}

exit (Invoke-CopilotDispatchPool `
  -WorkItems $workItems `
  -Skipped $skipped `
  -LabelPrefix 'finalize' `
  -KeyField 'SourceName' `
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
  -DryRun:$DryRun)
