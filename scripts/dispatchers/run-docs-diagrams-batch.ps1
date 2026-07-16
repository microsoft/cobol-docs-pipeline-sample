#requires -Version 5.1
<#
.SYNOPSIS
  Per-FILE Copilot CLI dispatcher for the phase-H diagrams stage.

.DESCRIPTION
  One Copilot CLI call per source: reads the staged bundle at
  `docs/_shared/<basename>/_diagrams.bundle.json` and invokes the
  `diagram-renderer` agent to author the file-level overview Mermaid
  diagrams under `docs/_shared/<basename>/diagrams/*.mmd`. Diagrams are
  language-neutral, so no -Languages parameter.

  Mechanics delegated to scripts/lib/Invoke-CopilotDispatch.ps1.
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$Agent = 'diagram-renderer',
  [string]$CopilotCli = 'copilot',
  [string]$CopilotSubcommand = '',
  [string]$AgentSwitch = '--agent',
  [string]$PromptSwitch = '--prompt',
  [string[]]$AdditionalCopilotArgs = @(),
  [ValidateRange(1,32)] [int]$Throttle = 10,
  [string]$ResultsXml = 'temp/copilot_diagrams_results.xml',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt'),
  [int]$PerTaskTimeoutSec = 1800,
  [int]$MaxRetries = 2,
  [string]$PromptTemplate = 'config/prompts/diagrams.prompt.tmpl',
  [switch]$Resume,
  [switch]$Force,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../lib/Invoke-CopilotDispatch.ps1')

$resumeEnabled = if ($PSBoundParameters.ContainsKey('Resume')) { [bool]$Resume } else { -not $Force }
if ($Force) { $resumeEnabled = $false }

$repoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$promptTpl = Read-PromptTemplate -RepoRoot $repoRoot -TemplatePath $PromptTemplate

$inputs = Expand-SourceInputs -Files $Files -Paths $Paths -Manifest $Manifest -ExcludeExtensions $ExcludeExtensions

$workItems = New-Object System.Collections.Generic.List[object]
$skipped   = New-Object System.Collections.Generic.List[object]
$taskId = 0

foreach ($src in $inputs) {
  $taskId++
  $basename = [System.IO.Path]::GetFileName($src)
  $bundle   = Join-Path $repoRoot ("docs/_shared/$basename/_diagrams.bundle.json")

  if (-not (Test-Path -LiteralPath $bundle)) {
    Write-Warning "Diagrams bundle missing for $basename : $bundle (run diagrams_stage_batch.ps1 first)"
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; SourcePath = $src; SourceName = $basename
      BundlePath = $bundle; Exit = -2; Status = 'missing-bundle'; Command = ''
      Stdout = ''; Stderr = "bundle not found: $bundle"; DurationMs = 0
    })
    continue
  }

  $sentinelMmd = Join-Path $repoRoot ("docs/_shared/$basename/diagrams/call-graph.mmd")
  $fingerprint = Get-ResumeFingerprint -InputFiles @($bundle) -Agent $Agent -Languages ''
  if ($resumeEnabled -and $fingerprint -and (Test-ResumeSidecar -OutputPath $sentinelMmd -Fingerprint $fingerprint)) {
    $skipped.Add([pscustomobject]@{
      TaskId = $taskId; SourcePath = $src; SourceName = $basename
      BundlePath = $bundle; Exit = 0; Status = 'skipped-up-to-date'; Command = ''
      Stdout = 'skipped: dispatched sidecar matches fingerprint'
      Stderr = ''; DurationMs = 0
    })
    continue
  }
  if ($resumeEnabled) {
    $diagramsDir = Join-Path $repoRoot ("docs/_shared/$basename/diagrams")
    if (Test-Path -LiteralPath $diagramsDir) {
      $newestMmd = Get-ChildItem -LiteralPath $diagramsDir -Filter '*.mmd' -File -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.StartsWith('section-') } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
      if ($newestMmd) {
        $bundleStamp = (Get-Item -LiteralPath $bundle).LastWriteTimeUtc
        if ($newestMmd.LastWriteTimeUtc -ge $bundleStamp) {
          $skipped.Add([pscustomobject]@{
            TaskId = $taskId; SourcePath = $src; SourceName = $basename
            BundlePath = $bundle; Exit = 0; Status = 'skipped-up-to-date'; Command = ''
            Stdout = "skipped: newest .mmd ($($newestMmd.LastWriteTimeUtc)) >= bundle ($bundleStamp)"
            Stderr = ''; DurationMs = 0
          })
          continue
        }
      }
    }
  }

  $prompt = Expand-PromptTemplate -Template $promptTpl -Tokens @{
    SOURCE_PATH = $src
    SOURCE_NAME = $basename
    BUNDLE_PATH = $bundle
  }
  $workItems.Add([pscustomobject]@{
    TaskId = $taskId; SourcePath = $src; SourceName = $basename
    BundlePath = $bundle; OutputPath = $sentinelMmd
    ResumeFingerprint = $fingerprint; Prompt = $prompt
  })
}

exit (Invoke-CopilotDispatchPool `
  -WorkItems $workItems `
  -Skipped $skipped `
  -LabelPrefix 'diagrams' `
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
