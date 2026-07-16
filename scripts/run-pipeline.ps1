#requires -Version 5.1
<#
.SYNOPSIS
  Skinny orchestrator for DAG phases A -> B -> C -> D -> E -> F -> G -> H -> I -> J -> K -> L -> M -> N.

.DESCRIPTION
  Each phase is a standalone, autoconsistent script under scripts/phases/.
  This orchestrator only selects the subset of phases to run, splats the
  matching parameters, invokes them in order, and stops on the first
  non-zero exit code.

  Phase selectors:
    -Phases   explicit subset (e.g. -Phases A,B,C)
    -From/-To inclusive range (e.g. -From C -To E)
    -Skip     phase ids to drop from the selected set

  When -Phases is given, -From / -To / -Skip are ignored.

  Legacy switches (-RunCopilotDocs, -RunSectionFinalizer,
  -RunFunctionalAnalysis, -RunWorkspaceXrefPass) remain supported and
  map onto the new phase model so existing CI invocations keep working.

.PARAMETER Files
  Explicit list of source paths (repo-relative or absolute).

.PARAMETER Paths
  One or more directories or globs to expand.

.PARAMETER Manifest
  Optional JSON/CSV manifest with at least a 'path' column/property.

.PARAMETER SourceRoot
  Optional source root passed to all child scripts.

.PARAMETER Throttle
  Parallel degree for each batch step.

.PARAMETER ResultsDir
  Folder where XML result files are written.

.PARAMETER MaxPhaseRetries
  Maximum retries after a phase failure. Defaults to 3; use 0 to disable retries.

.PARAMETER Phases
  Explicit subset of phases to run. Defaults to the full pipeline.

.PARAMETER From
  Run phases starting at this id (inclusive). Ignored if -Phases is set.

.PARAMETER To
  Run phases up to this id (inclusive). Ignored if -Phases is set.

.PARAMETER Skip
  Phase ids to drop from the selected set.

.PARAMETER RunWorkspaceXrefPass
  Legacy: when $false, passes -SkipXrefPass to phase B.

.PARAMETER RunCopilotDocs
  Legacy: when $false, drops phase D from the selected set.

.PARAMETER CopilotDocsDryRun
  Phase D: build dispatch commands without invoking the Copilot CLI.

.PARAMETER CopilotDocsAgent
  Phase D agent. Default: section-doc-writer.

.PARAMETER CopilotDocsThrottle
  Phase D parallel limit. Default: 10.

.PARAMETER CopilotDocsTrackUsage
  Phase D: enable per-task Copilot usage tracking via OTEL file exporter. Default: on.

.PARAMETER CopilotDocsOtelDir
  Phase D: optional output directory for OTEL JSONL task files.

.PARAMETER CopilotDocsPremiumMultiplier
  Phase D: multiplier used to roll up premium requests. Default: 1.

.PARAMETER RunSectionFinalizer
  Legacy: when $false, drops phase E from the selected set.

.PARAMETER SectionFinalizerLanguages
  Phase E languages. Default: en.

.PARAMETER SectionFinalizerAgent
  Phase E agent. Default: section-doc-finalizer.

.PARAMETER SectionFinalizerThrottle
  Phase E Copilot dispatch throttle. Default: 4.

.PARAMETER SectionFinalizerDryRun
  Phase E dry-run.

.PARAMETER SectionFinalizerForce
  Phase E: re-run even if outputs are up to date.

.PARAMETER RunFunctionalAnalysis
  Legacy: when $false, drops phase G from the selected set.

.PARAMETER FunctionalAnalysisLanguages
  Phase G languages. Default: en.

.PARAMETER FunctionalAnalysisProfile
  Phase G profile override.

.PARAMETER FunctionalAnalysisPrune
  Phase G: delete stale section bundles.

.PARAMETER FunctionalAnalysisForce
  Phase G: re-stage even when up-to-date.

.PARAMETER RequirementsLanguages
  Phase F languages. Default: en.

.PARAMETER RequirementsProfile
  Phase F profile override.

.PARAMETER RequirementsPrune
  Phase F: delete stale section bundles.

.PARAMETER RequirementsForce
  Phase F: re-stage even when up-to-date.

.PARAMETER RunDiagrams
  Legacy: when $false, drops phase H from the selected set.

.PARAMETER DiagramsAgent
  Phase H agent. Default: diagram-renderer.

.PARAMETER DiagramsThrottle
  Phase H parallel limit. Default: 4.

.EXAMPLE
  pwsh -File scripts/run-pipeline.ps1 -Paths repos/sample1/COBOL/*.CBL

.EXAMPLE
  pwsh -File scripts/run-pipeline.ps1 -Paths repos/sample1/COBOL/*.CBL -Phases A,B,C

.EXAMPLE
  pwsh -File scripts/run-pipeline.ps1 -Paths repos/sample1/COBOL/*.CBL -From C -To E
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$ResultsDir = 'temp',
  [ValidateRange(0, 100)]
  [int]$MaxPhaseRetries = 3,

  # Phase selectors
  [ValidateSet('A','B','C','D','E','F','G','H','I','J','K','L','M','N')]
  [string[]]$Phases,
  [ValidateSet('A','B','C','D','E','F','G','H','I','J','K','L','M','N')]
  [string]$From,
  [ValidateSet('A','B','C','D','E','F','G','H','I','J','K','L','M','N')]
  [string]$To,
  [ValidateSet('A','B','C','D','E','F','G','H','I','J','K','L','M','N')]
  [string[]]$Skip,

  # Legacy full-pipeline toggles. Kept as [switch] (default $true) so that
  # the colon-form `-RunCopilotDocs:$false` used by existing CI keeps working.
  [switch]$RunWorkspaceXrefPass  = $true,
  [switch]$RunCopilotDocs        = $true,
  [switch]$RunSectionFinalizer   = $true,
  [switch]$RunFunctionalAnalysis = $true,

  # Phase D
  [switch]$CopilotDocsDryRun    = $false,
  [string]$CopilotDocsAgent     = 'section-doc-writer',
  [int]   $CopilotDocsThrottle  = 15,
  [bool]$CopilotDocsTrackUsage = $true,
  [string]$CopilotDocsOtelDir,
  [double]$CopilotDocsPremiumMultiplier = 1,

  # Phase E
  [string]$SectionFinalizerLanguages = 'en',
  [string]$SectionFinalizerAgent     = 'section-doc-finalizer',
  [int]   $SectionFinalizerThrottle  = 4,
  [switch]$SectionFinalizerDryRun,
  [switch]$SectionFinalizerForce,

  # Phase H
  [switch]$RunDiagrams              = $true,
  [string]$DiagramsAgent            = 'diagram-renderer',
  [int]   $DiagramsThrottle         = 4,
  [switch]$DiagramsDryRun,
  [switch]$DiagramsForce,

  # Phase G
  [string]$FunctionalAnalysisLanguages = 'en',
  [string]$FunctionalAnalysisProfile,
  [switch]$FunctionalAnalysisPrune,
  [switch]$FunctionalAnalysisForce,

  # Phase F
  [string]$RequirementsLanguages = 'en',
  [string]$RequirementsProfile,
  [switch]$RequirementsPrune,
  [switch]$RequirementsForce,

  # DOCX conversion of complete.md / requirements.md / functional-analysis.md
  # (phases E/F/G per-file and I/J/K per-group). Markdown is always emitted;
  # the DOCX step is best-effort and skipped when pandoc is unavailable.
  [switch]$SkipDocx,

  # Phase L (per-file technical analysis / ATE + DOCX)
  [switch]$RunTechnicalAnalysis        = $true,
  [string]$TechnicalAnalysisLanguages  = 'en',
  [string]$TechnicalAnalysisProfile,
  [string]$PandocPath                  = 'pandoc',
  [switch]$TechnicalAnalysisSkipDocx,
  [switch]$TechnicalAnalysisDryRun,
  [switch]$TechnicalAnalysisForce,

  # Phases I/J/K (workspace/group-scoped; driven by the grouping manifest,
  # not the per-file source selectors).
  [switch]$RunGroupDocs               = $true,
  [switch]$RunGroupRequirements       = $true,
  [switch]$RunGroupFunctionalAnalysis = $true,
  [string]$GroupingManifest           = 'config/grouping.yaml',
  [string]$GroupLanguages             = 'en',
  [string]$GroupRequirementsProfile,
  [string]$GroupFunctionalAnalysisProfile,
  [switch]$GroupPrune,
  [switch]$GroupDryRun,
  [switch]$GroupForce,

  # Phase M (per-group technical analysis / ATE + DOCX)
  [switch]$RunGroupTechnicalAnalysis  = $true,
  [string]$GroupTechnicalAnalysisProfile,

  # Phase N (documentation portal: web + offline editions)
  [switch]$RunPortal       = $true,
  [switch]$PortalSkipBuild,
  [string]$PortalSite,
  [string]$PortalOut,
  [switch]$PortalOpen
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSCommandPath) 'lib/Resolve-PhaseInputs.ps1')
$repoRoot     = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$phaseScripts = @{}
foreach ($k in (Get-PhaseScriptMap).Keys) {
  $phaseScripts[$k] = Join-Path $repoRoot (Get-PhaseScriptMap)[$k]
}
$phaseOrder = @((Get-PhaseScriptMap).Keys)

if (-not $Files -and -not $Paths -and -not $Manifest) {
  throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
}

# --- Resolve effective phase list -------------------------------------------
if ($Phases) {
  $selected = $phaseOrder | Where-Object { $Phases -contains $_ }
} else {
  $startIdx = 0
  $endIdx   = $phaseOrder.Count - 1
  if ($From) {
    $startIdx = [Array]::IndexOf($phaseOrder, $From)
    if ($startIdx -lt 0) { throw "-From '$From' is not a known phase id." }
  }
  if ($To) {
    $endIdx = [Array]::IndexOf($phaseOrder, $To)
    if ($endIdx -lt 0) { throw "-To '$To' is not a known phase id." }
  }
  if ($startIdx -gt $endIdx) {
    throw "-From '$From' is after -To '$To'."
  }
  $selected = $phaseOrder[$startIdx..$endIdx]
}

# Legacy toggles drop phases from the selected set.
if (-not $RunCopilotDocs)              { $selected = $selected | Where-Object { $_ -ne 'D' } }
if (-not $RunSectionFinalizer)         { $selected = $selected | Where-Object { $_ -ne 'E' } }
if (-not $RunDiagrams)                 { $selected = $selected | Where-Object { $_ -ne 'H' } }
if (-not $RunFunctionalAnalysis)       { $selected = $selected | Where-Object { $_ -ne 'G' } }
if (-not $RunGroupDocs)                { $selected = $selected | Where-Object { $_ -ne 'I' } }
if (-not $RunGroupRequirements)        { $selected = $selected | Where-Object { $_ -ne 'J' } }
if (-not $RunGroupFunctionalAnalysis)  { $selected = $selected | Where-Object { $_ -ne 'K' } }
if (-not $RunTechnicalAnalysis)        { $selected = $selected | Where-Object { $_ -ne 'L' } }
if (-not $RunGroupTechnicalAnalysis)   { $selected = $selected | Where-Object { $_ -ne 'M' } }
if (-not $RunPortal)                   { $selected = $selected | Where-Object { $_ -ne 'N' } }

if ($Skip) {
  # Warn on -Skip ids that are outside the selected set (no-op skips).
  $noop = @($Skip | Where-Object { $selected -notcontains $_ })
  foreach ($s in $noop) {
    Write-Warning "-Skip '$s' is outside the selected phase set ($($selected -join ',')); ignored."
  }
  $selected = $selected | Where-Object { $Skip -notcontains $_ }
}

$selected = @($selected)
if ($selected.Count -eq 0) {
  Write-Host 'No phases selected. Nothing to do.'
  exit 0
}

foreach ($id in $selected) {
  $sp = $phaseScripts[$id]
  if (-not (Test-Path $sp)) { throw "Required phase script not found: $sp" }
}

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$resultsDirFull = (Resolve-Path -LiteralPath $ResultsDir).Path

# Shared splat used by every phase.
$shared = @{
  Throttle   = $Throttle
  ResultsDir = $resultsDirFull
}
$shared = Add-SourceSelectorArgs -Target $shared `
  -Files $Files -Paths $Paths -Manifest $Manifest -SourceRoot $SourceRoot

# Group phases (I/J/K) are workspace-scoped: they consume the grouping
# manifest and only understand -ResultsDir from the shared selectors, so
# they get their own minimal base splat instead of $shared.
$groupShared = @{ ResultsDir = $resultsDirFull }

# Data-driven phase table: one entry per phase id, with an -Extra scriptblock
# that returns a hashtable of phase-specific args. The orchestrator never
# special-cases a phase id outside this table — to add a phase, extend it.
# See `scripts/phases/phase-*.ps1` for per-phase param docs.
$phasePlan = @(
  @{ Id = 'A'; Extra = { @{} } }
  @{ Id = 'B'; Extra = {
      $h = @{}
      if (-not $RunWorkspaceXrefPass) { $h.SkipXrefPass = $true }
      $h
    } }
  @{ Id = 'C'; Extra = { @{} } }
  @{ Id = 'D'; Extra = {
      $h = @{
        Agent        = $CopilotDocsAgent
        DocsThrottle = $CopilotDocsThrottle
        DryRun       = [bool]$CopilotDocsDryRun
      }
      if ($CopilotDocsTrackUsage) { $h.TrackUsage = $true }
      if (-not [string]::IsNullOrWhiteSpace($CopilotDocsOtelDir)) {
        $h.OtelDir = $CopilotDocsOtelDir
      }
      if ($CopilotDocsPremiumMultiplier -ne 1) {
        $h.PremiumMultiplier = $CopilotDocsPremiumMultiplier
      }
      $h
    } }
  @{ Id = 'E'; Extra = {
      $h = @{
        Languages         = $SectionFinalizerLanguages
        Agent             = $SectionFinalizerAgent
        FinalizerThrottle = $SectionFinalizerThrottle
        PandocPath        = $PandocPath
      }
      if ($SectionFinalizerDryRun) { $h.DryRun = $true }
      if ($SectionFinalizerForce)  { $h.Force  = $true }
      if ($SkipDocx)               { $h.SkipDocx = $true }
      $h
    } }
  @{ Id = 'F'; Extra = {
      $h = @{ Languages = $RequirementsLanguages; PandocPath = $PandocPath }
      if ($RequirementsProfile) { $h.ProfileName = $RequirementsProfile }
      if ($RequirementsPrune)   { $h.Prune       = $true }
      if ($RequirementsForce)   { $h.Force       = $true }
      if ($SkipDocx)            { $h.SkipDocx    = $true }
      $h
    } }
  @{ Id = 'G'; Extra = {
      $h = @{ Languages = $FunctionalAnalysisLanguages; PandocPath = $PandocPath }
      if ($FunctionalAnalysisProfile) { $h.ProfileName = $FunctionalAnalysisProfile }
      if ($FunctionalAnalysisPrune)   { $h.Prune       = $true }
      if ($FunctionalAnalysisForce)   { $h.Force       = $true }
      if ($SkipDocx)                  { $h.SkipDocx    = $true }
      $h
    } }
  @{ Id = 'H'; Extra = {
      $h = @{
        Agent            = $DiagramsAgent
        DiagramsThrottle = $DiagramsThrottle
      }
      if ($DiagramsDryRun) { $h.DryRun = $true }
      if ($DiagramsForce)  { $h.Force  = $true }
      $h
    } }
  @{ Id = 'I'; Workspace = $true; Extra = {
      $h = @{
        Manifest  = $GroupingManifest
        Languages = $GroupLanguages
        PandocPath = $PandocPath
      }
      if ($GroupDryRun) { $h.DryRun = $true }
      if ($GroupForce)  { $h.Force  = $true }
      if ($SkipDocx)    { $h.SkipDocx = $true }
      $h
    } }
  @{ Id = 'J'; Workspace = $true; Extra = {
      $h = @{
        Manifest  = $GroupingManifest
        Languages = $GroupLanguages
        PandocPath = $PandocPath
      }
      if ($GroupRequirementsProfile) { $h.ProfileName = $GroupRequirementsProfile }
      if ($GroupPrune)  { $h.Prune  = $true }
      if ($GroupDryRun) { $h.DryRun = $true }
      if ($GroupForce)  { $h.Force  = $true }
      if ($SkipDocx)    { $h.SkipDocx = $true }
      $h
    } }
  @{ Id = 'K'; Workspace = $true; Extra = {
      $h = @{
        Manifest  = $GroupingManifest
        Languages = $GroupLanguages
        PandocPath = $PandocPath
      }
      if ($GroupFunctionalAnalysisProfile) { $h.ProfileName = $GroupFunctionalAnalysisProfile }
      if ($GroupPrune)  { $h.Prune  = $true }
      if ($GroupDryRun) { $h.DryRun = $true }
      if ($GroupForce)  { $h.Force  = $true }
      if ($SkipDocx)    { $h.SkipDocx = $true }
      $h
    } }
  @{ Id = 'L'; Extra = {
      $h = @{
        Languages  = $TechnicalAnalysisLanguages
        PandocPath = $PandocPath
      }
      if ($TechnicalAnalysisProfile) { $h.ProfileName = $TechnicalAnalysisProfile }
      if ($TechnicalAnalysisSkipDocx) { $h.SkipDocx = $true }
      if ($TechnicalAnalysisDryRun)   { $h.DryRun   = $true }
      if ($TechnicalAnalysisForce)    { $h.Force    = $true }
      $h
    } }
  @{ Id = 'M'; Workspace = $true; Extra = {
      $h = @{
        Manifest   = $GroupingManifest
        Languages  = $GroupLanguages
        PandocPath = $PandocPath
      }
      if ($GroupTechnicalAnalysisProfile) { $h.ProfileName = $GroupTechnicalAnalysisProfile }
      if ($TechnicalAnalysisSkipDocx) { $h.SkipDocx = $true }
      if ($GroupDryRun) { $h.DryRun = $true }
      if ($GroupForce)  { $h.Force  = $true }
      $h
    } }
  @{ Id = 'N'; Workspace = $true; Extra = {
      $h = @{}
      if ($SourceRoot)     { $h.SourceRoot = $SourceRoot }
      if ($PortalSkipBuild) { $h.SkipBuild = $true }
      if ($PortalSite)     { $h.Site = $PortalSite }
      if ($PortalOut)      { $h.Out  = $PortalOut }
      if ($PortalOpen)     { $h.Open = $true }
      $h
    } }
) | Where-Object { $selected -contains $_.Id }

Write-Host ("=== Pipeline start: {0} (max phase retries: {1}) ===" -f `
  ($selected -join ' -> '), $MaxPhaseRetries)

foreach ($entry in $phasePlan) {
  $id          = $entry.Id
  $phaseScript = $phaseScripts[$id]
  $base        = if ($entry.Workspace) { $groupShared } else { $shared }
  $phaseArgs   = $base.Clone()
  foreach ($kv in (& $entry.Extra).GetEnumerator()) {
    $phaseArgs[$kv.Key] = $kv.Value
  }
  $phaseExit = Invoke-PhaseWithRetry -PhaseId $id -PhaseScript $phaseScript `
    -PhaseArgs $phaseArgs -MaxRetries $MaxPhaseRetries
  if ($phaseExit -ne 0) {
    Write-Host ("=== Pipeline aborted at phase {0} after {1} attempt(s) (exit={2}) ===" -f `
      $id, ($MaxPhaseRetries + 1), $phaseExit)
    exit $phaseExit
  }
}

Write-Host ("=== Pipeline completed successfully ({0}) ===" -f ($selected -join ' -> '))
exit 0
