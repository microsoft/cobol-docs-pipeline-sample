#requires -Version 5.1
<#
.SYNOPSIS
  Per-SECTION Copilot CLI dispatcher for phase-F functional-analysis
  per-section drafts.

.DESCRIPTION
  One Copilot CLI call per (source, section): enumerates the per-section
  bundles under `docs/_shared/<basename>/_fa-bundles/*.bundle.json`
  (excluding `_finalize.bundle.json` and any `_`-prefixed file) and
  invokes the `functional-analysis-writer` agent (per-section scope) so it
  co-authors exactly the requested languages in one response.

  Mechanics delegated to scripts/lib/Invoke-CopilotDispatch.ps1.
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
  [ValidateRange(1,64)] [int]$Throttle = 10,
  [string]$ResultsXml = 'temp/copilot_fa_section_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt'),
  [int]$PerTaskTimeoutSec = 1800,
  [int]$MaxRetries = 2,
  [string]$PromptTemplate = 'config/prompts/fa-section.prompt.tmpl',
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
  $basename   = [System.IO.Path]::GetFileName($src)
  $bundlesDir = Join-Path $repoRoot ("docs/_shared/$basename/_fa-bundles")
  if (-not (Test-Path -LiteralPath $bundlesDir)) {
    $taskId++
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; SourcePath = $src; SourceName = $basename; SectionId = ''
      BundlePath = $bundlesDir; Exit = -2; Status = 'missing-bundles-dir'; Command = ''
      Stdout = ''; Stderr = "bundles dir not found: $bundlesDir"; DurationMs = 0
    })
    continue
  }

  $sectionBundles = Get-ChildItem -LiteralPath $bundlesDir -Filter '*.bundle.json' -File |
    Where-Object { $_.Name -ne '_finalize.bundle.json' -and -not $_.Name.StartsWith('_') } |
    Sort-Object Name

  if (-not $sectionBundles) {
    $taskId++
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; SourcePath = $src; SourceName = $basename; SectionId = ''
      BundlePath = $bundlesDir; Exit = 0; Status = 'no-section-bundles'; Command = ''
      Stdout = "no *.bundle.json under $bundlesDir"; Stderr = ''; DurationMs = 0
    })
    continue
  }

  foreach ($b in $sectionBundles) {
    $taskId++
    $sectionId = $b.BaseName -replace '\.bundle$',''
    $bundlePath = $b.FullName
    $draftPath  = Join-Path $repoRoot ("docs/_shared/$basename/_fa-sections/$firstLang/$sectionId.md")
    $fingerprint = Get-ResumeFingerprint -InputFiles @($bundlePath) -Agent $Agent -Languages $Languages

    if ($resumeEnabled -and $fingerprint -and (Test-ResumeSidecar -OutputPath $draftPath -Fingerprint $fingerprint)) {
      $skipped.Add([pscustomobject]@{
        TaskId = $taskId; SourcePath = $src; SourceName = $basename; SectionId = $sectionId
        BundlePath = $bundlePath; Exit = 0; Status = 'skipped-up-to-date'; Command = ''
        Stdout = 'skipped: dispatched sidecar matches fingerprint'
        Stderr = ''; DurationMs = 0
      })
      continue
    }
    if ($resumeEnabled -and (Test-Path -LiteralPath $draftPath)) {
      $bundleStamp = $b.LastWriteTimeUtc
      $draftStamp  = (Get-Item -LiteralPath $draftPath).LastWriteTimeUtc
      if ($draftStamp -ge $bundleStamp) {
        $skipped.Add([pscustomobject]@{
          TaskId = $taskId; SourcePath = $src; SourceName = $basename; SectionId = $sectionId
          BundlePath = $bundlePath; Exit = 0; Status = 'skipped-up-to-date'; Command = ''
          Stdout = "skipped: $sectionId.md ($draftStamp) >= bundle ($bundleStamp)"
          Stderr = ''; DurationMs = 0
        })
        continue
      }
    }

    $prompt = Expand-PromptTemplate -Template $promptTpl -Tokens @{
      SOURCE_PATH = $src
      SOURCE_NAME = $basename
      SECTION_ID  = $sectionId
    }
    $workItems.Add([pscustomobject]@{
      TaskId = $taskId; SourcePath = $src; SourceName = $basename
      SectionId = $sectionId; BundlePath = $bundlePath
      OutputPath = $draftPath; ResumeFingerprint = $fingerprint; Prompt = $prompt
    })
  }
}

exit (Invoke-CopilotDispatchPool `
  -WorkItems $workItems `
  -Skipped $skipped `
  -LabelPrefix 'fa-section' `
  -KeyField 'SectionId' `
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
  -NonFailureStatuses @('skipped-up-to-date','skipped-opt-out','dry-run','missing-bundles-dir','no-section-bundles') `
  -DryRun:$DryRun)
