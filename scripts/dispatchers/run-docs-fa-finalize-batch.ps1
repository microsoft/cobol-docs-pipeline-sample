#requires -Version 5.1
<#
.SYNOPSIS
  Per-FILE Copilot CLI dispatcher for the phase-F functional-analysis
  per-file finalizer.

.DESCRIPTION
  One Copilot CLI call per source: reads the staged finalizer bundle at
  `docs/_shared/<basename>/_fa-bundles/_finalize.bundle.json` and invokes
  the `functional-analysis-writer` agent (per-file scope) so it can stitch
  the per-section drafts into `docs/<lang>/<basename>/functional-analysis.md`
  for every requested language.

  Mechanics (runspace pool, arg quoting, record schema, results XML) are
  delegated to scripts/lib/Invoke-CopilotDispatch.ps1.
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$Languages = 'en',
  [string]$Agent = 'functional-analysis-writer',
  [string]$CopilotCli = 'copilot',
  [string]$CopilotSubcommand = '',
  [string]$AgentSwitch = '--agent',
  [string]$PromptSwitch = '--prompt',
  [string[]]$AdditionalCopilotArgs = @(),
  [ValidateRange(1,32)] [int]$Throttle = 10,
  [string]$ResultsXml = 'temp/copilot_fa_finalize_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt'),
  [int]$PerTaskTimeoutSec = 1800,
  [int]$MaxRetries = 2,
  [string]$PromptTemplate = 'config/prompts/fa-finalize.prompt.tmpl',
  [switch]$Resume,
  [switch]$Force,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../lib/Invoke-CopilotDispatch.ps1')

$resumeEnabled = if ($PSBoundParameters.ContainsKey('Resume')) { [bool]$Resume } else { -not $Force }
if ($Force) { $resumeEnabled = $false }

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$firstLang = Resolve-FirstLanguage -Languages $Languages
$promptTpl = Read-PromptTemplate -RepoRoot $repoRoot -TemplatePath $PromptTemplate

$inputs = Expand-SourceInputs -Files $Files -Paths $Paths -Manifest $Manifest -ExcludeExtensions $ExcludeExtensions

$workItems = New-Object System.Collections.Generic.List[object]
$skipped   = New-Object System.Collections.Generic.List[object]
$taskId = 0

foreach ($src in $inputs) {
  $taskId++
  $basename   = [System.IO.Path]::GetFileName($src)
  $bundle     = Join-Path $repoRoot ("docs/_shared/$basename/_fa-bundles/_finalize.bundle.json")
  $skipMarker = Join-Path $repoRoot ("docs/_shared/$basename/_fa-bundles/_skipped.json")

  if (Test-Path -LiteralPath $skipMarker) {
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; SourcePath = $src; SourceName = $basename
      BundlePath = $skipMarker; Exit = 0; Status = 'skipped-opt-out'; Command = ''
      Stdout = "skipped: _skipped.json present"; Stderr = ''; DurationMs = 0
    })
    continue
  }
  if (-not (Test-Path -LiteralPath $bundle)) {
    Write-Warning "Finalize bundle missing for $basename : $bundle (run fa_stage_batch.ps1 first)"
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; SourcePath = $src; SourceName = $basename
      BundlePath = $bundle; Exit = -2; Status = 'missing-bundle'; Command = ''
      Stdout = ''; Stderr = "bundle not found: $bundle"; DurationMs = 0
    })
    continue
  }

  $faMd = Join-Path $repoRoot ("docs/$firstLang/$basename/functional-analysis.md")
  $fingerprint = Get-ResumeFingerprint -InputFiles @($bundle) -Agent $Agent -Languages $Languages
  if ($resumeEnabled -and $fingerprint -and (Test-ResumeSidecar -OutputPath $faMd -Fingerprint $fingerprint)) {
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; SourcePath = $src; SourceName = $basename
      BundlePath = $bundle; Exit = 0; Status = 'skipped-up-to-date'; Command = ''
      Stdout = 'skipped: dispatched sidecar matches fingerprint'
      Stderr = ''; DurationMs = 0
    })
    continue
  }
  if ($resumeEnabled -and (Test-Path -LiteralPath $faMd)) {
    $bundleStamp = (Get-Item -LiteralPath $bundle).LastWriteTimeUtc
    $faStamp     = (Get-Item -LiteralPath $faMd).LastWriteTimeUtc
    if ($faStamp -ge $bundleStamp) {
      $skipped.Add([pscustomobject]@{
        TaskId = $taskId; SourcePath = $src; SourceName = $basename
        BundlePath = $bundle; Exit = 0; Status = 'skipped-up-to-date'; Command = ''
        Stdout = "skipped: functional-analysis.md ($faStamp) >= bundle ($bundleStamp)"
        Stderr = ''; DurationMs = 0
      })
      continue
    }
  }

  $prompt = Expand-PromptTemplate -Template $promptTpl -Tokens @{
    SOURCE_PATH = $src
    SOURCE_NAME = $basename
  }
  $workItems.Add([pscustomobject]@{
    TaskId = $taskId; SourcePath = $src; SourceName = $basename
    BundlePath = $bundle; OutputPath = $faMd
    ResumeFingerprint = $fingerprint; Prompt = $prompt
  })
}

exit (Invoke-CopilotDispatchPool `
  -WorkItems $workItems `
  -Skipped $skipped `
  -LabelPrefix 'fa-finalize' `
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
