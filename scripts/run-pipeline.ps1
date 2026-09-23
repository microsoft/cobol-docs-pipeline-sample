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

  Without explicit phase/range selectors, output.generate in config/pipeline.yaml
  selects outputs and their prerequisites. Explicit selectors override it.
  When -Phases is given, -From / -To are ignored. -Skip is always applied last.

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
  Source root passed to all child scripts. The config/pipeline.yaml
  include/exclude rules apply to selected files below this root. When no
  Files, Paths, or Manifest selector is supplied, the runner recursively
  discovers files below this root. When omitted, source_root is read from
  config/pipeline.yaml for discovery and filtering.

.PARAMETER Throttle
  Parallel degree for deterministic batch steps; independent of Copilot concurrency.

.PARAMETER CopilotThrottle
  Shared Copilot concurrency for phases D-M (1-32). Defaults to
  pipeline.copilot_parallelism in config/pipeline.yaml, or 16 when omitted.

.PARAMETER CopilotModel
  Copilot CLI model ID for this run, overriding copilot.default_model in
  config/pipeline.yaml, then agent model frontmatter, then automatic selection.
  Use 'auto' to explicitly request automatic selection.

.PARAMETER ResultsDir
  Folder where XML result files are written.

.PARAMETER MaxPhaseRetries
  Maximum retries after a phase failure. Defaults to 3; use 0 to disable retries.

.PARAMETER Phases
  Explicit subset, overriding output.generate without adding prerequisites.

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
  Phase D parallel limit (1-32). Defaults to the shared Copilot limit.

.PARAMETER CopilotDocsTrackUsage
  Phase D: enable per-task Copilot usage tracking via OTEL file exporter. Default: on.

.PARAMETER CopilotDocsOtelDir
  Phase D: optional output directory for OTEL JSONL task files.

.PARAMETER CopilotDocsPremiumMultiplier
  Phase D: multiplier used to roll up premium requests. Default: 1.

.PARAMETER RunSectionFinalizer
  Legacy: when $false, drops phase E from the selected set.

.PARAMETER Languages
  Shared documentation languages for phases D/E/F/G/I/J/K/L/M.
  Defaults to output.languages in config/pipeline.yaml, then en.
  Only requested languages are included. Explicit phase language options take precedence.

.PARAMETER SectionFinalizerLanguages
  Phase D section authoring and phase E finalization language override.
  Defaults to -Languages / output.languages.

.PARAMETER SectionFinalizerAgent
  Phase E agent. Default: section-doc-finalizer.

.PARAMETER SectionFinalizerThrottle
  Phase E Copilot dispatch throttle (1-32). Defaults to the shared Copilot limit.

.PARAMETER SectionFinalizerDryRun
  Phase E dry-run.

.PARAMETER SectionFinalizerForce
  Phase E: re-run even if outputs are up to date.

.PARAMETER RunFunctionalAnalysis
  Legacy: when $false, drops phase G from the selected set.

.PARAMETER FunctionalAnalysisLanguages
  Phase G language override. Defaults to -Languages / output.languages.

.PARAMETER FunctionalAnalysisProfile
  Phase G profile override.

.PARAMETER FunctionalAnalysisPrune
  Phase G: delete stale section bundles.

.PARAMETER FunctionalAnalysisForce
  Phase G: re-stage even when up-to-date.

.PARAMETER RequirementsLanguages
  Phase F language override. Defaults to -Languages / output.languages.

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
  Phase H parallel limit (1-32). Defaults to the shared Copilot limit.

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
  [string]$Languages,
  [int]$Throttle = [Environment]::ProcessorCount,
  [string]$CopilotThrottle,
  [string]$CopilotModel,
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
  [string]$CopilotDocsThrottle,
  [bool]$CopilotDocsTrackUsage = $true,
  [string]$CopilotDocsOtelDir,
  [double]$CopilotDocsPremiumMultiplier = 1,

  # Phase E
  [string]$SectionFinalizerLanguages,
  [string]$SectionFinalizerAgent     = 'section-doc-finalizer',
  [string]$SectionFinalizerThrottle,
  [switch]$SectionFinalizerDryRun,
  [switch]$SectionFinalizerForce,

  # Phase H
  [switch]$RunDiagrams              = $true,
  [string]$DiagramsAgent            = 'diagram-renderer',
  [string]$DiagramsThrottle,
  [switch]$DiagramsDryRun,
  [switch]$DiagramsForce,

  # Phase G
  [string]$FunctionalAnalysisLanguages,
  [string]$FunctionalAnalysisProfile,
  [switch]$FunctionalAnalysisPrune,
  [switch]$FunctionalAnalysisForce,

  # Phase F
  [string]$RequirementsLanguages,
  [string]$RequirementsProfile,
  [switch]$RequirementsPrune,
  [switch]$RequirementsForce,

  # DOCX conversion of complete.md / requirements.md / functional-analysis.md
  # (phases E/F/G per-file and I/J/K per-group). Markdown is always emitted;
  # the DOCX step is best-effort and skipped when pandoc is unavailable.
  [switch]$SkipDocx,

  # Phase L (per-file technical analysis / ATE + DOCX)
  [switch]$RunTechnicalAnalysis        = $true,
  [string]$TechnicalAnalysisLanguages,
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
  [string]$GroupLanguages,
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
$phaseNames = @{
  A = 'Chunk sources'
  B = 'Extract facts and cross-references'
  C = 'Extract chunk text'
  D = 'Author section documentation'
  E = 'Finalize file documentation'
  F = 'Generate technical requirements'
  G = 'Generate functional analysis'
  H = 'Generate overview diagrams'
  I = 'Finalize group documentation'
  J = 'Generate group requirements'
  K = 'Generate group functional analysis'
  L = 'Generate file technical analysis'
  M = 'Generate group technical analysis'
  N = 'Build documentation portal'
}

$discoverScript = Join-Path $repoRoot 'scripts/tools/discover-sources.py'
$sourcesConfig = Join-Path $repoRoot 'config/pipeline.yaml'
$modelArgs = @(
  (Join-Path $repoRoot 'scripts/tools/resolve-copilot-model.py'),
  '--config', $sourcesConfig
)
if ($PSBoundParameters.ContainsKey('CopilotModel')) { $modelArgs += "--model=$CopilotModel" }
$modelOutput = @(& python @modelArgs)
if ($LASTEXITCODE -ne 0 -or $modelOutput.Count -ne 1) {
  throw 'Copilot model configuration failed. See the preceding error.'
}
$modelSelection = $modelOutput[0] | ConvertFrom-Json
$modelOverride = if ($modelSelection.source -in @('cli', 'config')) { $modelSelection.model } else { '' }
Write-Host ("Copilot model: {0}" -f $(if ($modelOverride) { $modelOverride } else { 'agent frontmatter / auto' }))
$parallelismArgs = @(
  (Join-Path $repoRoot 'scripts/tools/resolve-copilot-parallelism.py'),
  '--config', $sourcesConfig
)
$parallelismOptions = @{
  CopilotThrottle = '--throttle'
  CopilotDocsThrottle = '--sections'
  SectionFinalizerThrottle = '--finalizer'
  DiagramsThrottle = '--diagrams'
}
foreach ($name in $parallelismOptions.Keys) {
  if ($PSBoundParameters.ContainsKey($name)) {
    $parallelismArgs += "$($parallelismOptions[$name])=$($PSBoundParameters[$name])"
  }
}
$resolvedParallelism = @(& python @parallelismArgs)
if ($LASTEXITCODE -ne 0 -or $resolvedParallelism.Count -ne 4) {
  throw 'Copilot concurrency configuration failed. See the preceding error.'
}
$CopilotThrottle, $CopilotDocsThrottle, $SectionFinalizerThrottle, $DiagramsThrottle = $resolvedParallelism
Write-Host ("Copilot concurrency: shared={0}; D={1}; E={2}; H={3}" -f $resolvedParallelism)

$languageArgs = @(
  (Join-Path $repoRoot 'scripts/tools/resolve-output-languages.py'),
  '--config', $sourcesConfig
)
$languageOptions = @{
  Languages = '--languages'
  SectionFinalizerLanguages = '--sections'
  RequirementsLanguages = '--requirements'
  FunctionalAnalysisLanguages = '--functional-analysis'
  TechnicalAnalysisLanguages = '--technical-analysis'
  GroupLanguages = '--groups'
}
foreach ($name in $languageOptions.Keys) {
  if ($PSBoundParameters.ContainsKey($name)) {
    $languageArgs += "$($languageOptions[$name])=$($PSBoundParameters[$name])"
  }
}
$resolvedLanguages = @(& python @languageArgs)
if ($LASTEXITCODE -ne 0 -or $resolvedLanguages.Count -ne 5) {
  throw 'Output language configuration failed. See the preceding error.'
}
$SectionFinalizerLanguages, $RequirementsLanguages, $FunctionalAnalysisLanguages,
  $TechnicalAnalysisLanguages, $GroupLanguages = $resolvedLanguages
Write-Host ("Output languages: sections={0}; requirements={1}; functional={2}; technical={3}; groups={4}" -f $resolvedLanguages)

$configuredPhases = @(& python (Join-Path $repoRoot 'scripts/tools/resolve-output-phases.py') --config $sourcesConfig)
if ($LASTEXITCODE -ne 0) {
  throw 'Output generation configuration failed. See the preceding error.'
}

# --- Resolve effective phase list -------------------------------------------
if ($Phases) {
  $selected = $phaseOrder | Where-Object { $Phases -contains $_ }
} elseif ($PSBoundParameters.ContainsKey('From') -or $PSBoundParameters.ContainsKey('To')) {
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
} else {
  $selected = $configuredPhases
  Write-Host "Configured output phases (including prerequisites): $($selected -join ',')"
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

if (-not $Files -and -not $Paths -and -not $Manifest) {
  $discoverArgs = @($discoverScript, '--config', $sourcesConfig)
  if ($SourceRoot) { $discoverArgs += @('--source-root', $SourceRoot) }
  $discovered = @(& python @discoverArgs)
  if ($LASTEXITCODE -ne 0) { throw 'Source discovery failed. See the preceding error.' }
  if ($discovered.Count -lt 2) {
    throw 'No source files matched config/pipeline.yaml include/exclude rules.'
  }
  $SourceRoot = $discovered[0]
  $Files = @($discovered[1..($discovered.Count - 1)])
  Write-Host "Discovered $($Files.Count) source file(s) under $SourceRoot"
}
else {
  $resolvedSelectors = @(
    @(Get-PhaseInputs `
      -Files $Files -Paths $Paths -Manifest $Manifest -ExcludeExtensions @()) |
      ForEach-Object { $_ }
  )
  $filterArgs = @($discoverScript, '--config', $sourcesConfig, '--filter-candidates')
  if ($SourceRoot) { $filterArgs += @('--source-root', $SourceRoot) }
  $filteredFiles = @($resolvedSelectors | & python @filterArgs)
  if ($LASTEXITCODE -ne 0) { throw 'Source filtering failed. See the preceding error.' }
  if ($filteredFiles.Count -eq 0) {
    throw 'No selected source files matched config/pipeline.yaml include/exclude rules.'
  }
  $excludedCount = $resolvedSelectors.Count - $filteredFiles.Count
  $Files = $filteredFiles
  $Paths = $null
  $Manifest = $null
  Write-Host "Selected $($Files.Count) source file(s); excluded $excludedCount by config/pipeline.yaml rules."
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
        Languages    = $SectionFinalizerLanguages
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
      $h = @{ Languages = $RequirementsLanguages; PandocPath = $PandocPath
        SectionThrottle = $CopilotThrottle; FinalizerThrottle = $CopilotThrottle }
      if ($RequirementsProfile) { $h.ProfileName = $RequirementsProfile }
      if ($RequirementsPrune)   { $h.Prune       = $true }
      if ($RequirementsForce)   { $h.Force       = $true }
      if ($SkipDocx)            { $h.SkipDocx    = $true }
      $h
    } }
  @{ Id = 'G'; Extra = {
      $h = @{ Languages = $FunctionalAnalysisLanguages; PandocPath = $PandocPath
        SectionThrottle = $CopilotThrottle; FinalizerThrottle = $CopilotThrottle }
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
        FinalizerThrottle = $CopilotThrottle
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
        SectionThrottle = $CopilotThrottle
        FinalizerThrottle = $CopilotThrottle
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
        SectionThrottle = $CopilotThrottle
        FinalizerThrottle = $CopilotThrottle
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
        FinalizerThrottle = $CopilotThrottle
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
        FinalizerThrottle = $CopilotThrottle
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
$selectorSummary =
  if ($Manifest) { "manifest=$Manifest" }
  elseif ($Paths) { "paths=$($Paths.Count)" }
  else { "files=$($Files.Count)" }
Write-Host ("Context: source-root={0} | selector={1} | throttle={2} | results={3}" -f `
  $(if ($SourceRoot) { $SourceRoot } else { '<configured/default>' }), `
  $selectorSummary, $Throttle, $resultsDirFull)

$phaseNumber = 0
$phaseCount = @($phasePlan).Count
foreach ($entry in $phasePlan) {
  $phaseNumber++
  $id          = $entry.Id
  $phaseScript = $phaseScripts[$id]
  $base        = if ($entry.Workspace) { $groupShared } else { $shared }
  $phaseArgs   = $base.Clone()
  foreach ($kv in (& $entry.Extra).GetEnumerator()) {
    $phaseArgs[$kv.Key] = $kv.Value
  }
  $scope = if ($entry.Workspace) { 'workspace' } else { 'per-file' }
  $optionNames = @($phaseArgs.Keys |
    Where-Object { $_ -notin @('Files', 'Paths', 'Manifest', 'SourceRoot') } |
    Sort-Object)
  Write-Host ''
  Write-Host ("=== [{0}/{1}] Phase {2}: {3} ===" -f `
    $phaseNumber, $phaseCount, $id, $phaseNames[$id])
  Write-Host ("Scope: {0} | script={1}" -f $scope, (Split-Path -Leaf $phaseScript))
  Write-Host ("Options: {0}" -f $(if ($optionNames.Count) { $optionNames -join ', ' } else { '<none>' }))
  # Scoped environment transport reaches both in-process and child dispatchers.
  $previousModel = $env:COBOL_DOCS_COPILOT_MODEL
  try {
    $env:COBOL_DOCS_COPILOT_MODEL = $modelOverride
    $phaseExit = Invoke-PhaseWithRetry -PhaseId $id -PhaseScript $phaseScript `
      -PhaseArgs $phaseArgs -MaxRetries $MaxPhaseRetries
  }
  finally { $env:COBOL_DOCS_COPILOT_MODEL = $previousModel }
  if ($phaseExit -ne 0) {
    Write-Host ("=== Pipeline aborted at phase {0} after {1} attempt(s) (exit={2}) ===" -f `
      $id, ($MaxPhaseRetries + 1), $phaseExit)
    exit $phaseExit
  }
}

Write-Host ("=== Pipeline completed successfully ({0}) ===" -f ($selected -join ' -> '))
exit 0
