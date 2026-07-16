#requires -Version 5.1
<#
.SYNOPSIS
  Threaded orchestrator that invokes Copilot CLI once per chunk for documentation.

.DESCRIPTION
  For each selected source file:
  1. Optionally pre-stage section-doc bundles.
  2. Read chunk-manifest.json and chunks/index.json.
  3. Build one work item per chunk.
  4. Fan out work items via a RunspacePool (works on PowerShell 5.1 and 7+).
  5. For each chunk, call Copilot CLI with agent + prompt.

  Results are persisted to an XML file for post-run analysis.

.PARAMETER Files
  Explicit list of source paths or directories (repo-relative or absolute).

.PARAMETER Paths
  One or more directories or globs to expand.

.PARAMETER Manifest
  Path to a JSON/CSV list with at least a path field. Overrides Files/Paths.

.PARAMETER SourceRoot
  Optional source root override.

.PARAMETER Languages
  Languages used when staging bundles. Default: en.

.PARAMETER EnsureBundles
  If set, run write_sections_batch.ps1 first to pre-stage bundles.

.PARAMETER EnsureFactsSlices
  If set, run slice_facts_batch.ps1 before staging bundles.

.PARAMETER Agent
  Copilot agent identifier to pass to the CLI.

.PARAMETER PromptTemplate
  Prompt template. Supported tokens:
  {chunkId} {sourcePath} {bundlePath}

.PARAMETER CopilotCli
  Copilot CLI executable name/path.

.PARAMETER CopilotSubcommand
  Copilot CLI subcommand. Default: chat.

.PARAMETER AgentSwitch
  CLI argument name used for the agent. Default: --agent.

.PARAMETER PromptSwitch
  CLI argument name used for prompt text. Default: --prompt.

.PARAMETER AdditionalCopilotArgs
  Additional args appended as-is to each Copilot CLI invocation.

.PARAMETER Throttle
  Max parallel chunk threads. Defaults to 12. Use `-Throttle <n>` to override
  (e.g. `-Throttle 4` to throttle the Copilot CLI calls, `-Throttle 20` to push
  harder when the machine has spare CPU/IO and quota allows it).
  Aliases: `-Threads`, `-ConcurrentThreads`, `-MaxThreads`.
  Allowed range: 1..64 (WaitHandle.WaitAny limit on Windows/.NET).

.PARAMETER AllowLowerThrottle
  By default, effective throttle is clamped to a minimum of 10 to avoid
  accidental low parallelism from inherited/wrapper defaults. Pass this switch
  only when you intentionally want fewer than 10 concurrent workers.

.PARAMETER ResultsXml
  Path for XML results.

.PARAMETER ExcludeExtensions
  File extensions to skip when expanding folders/globs.

.PARAMETER DryRun
  Build work and commands but do not invoke Copilot CLI.

.PARAMETER TaskLogging
  If set (default), emits per-task START/END logs during dispatch.

.PARAMETER TaskLogPath
  Optional path to the task execution log file. Defaults to
  <ResultsXml directory>/copilot_doc_tasks.log.

.PARAMETER TaskLogPreviewCount
  Number of queued tasks to print before dispatch. Default: 10.

.PARAMETER Resume
  If set, skip chunks whose last recorded state in the state file is `ok`
  AND whose bundle file SHA-256 still matches. Use to continue a crashed
  batch without re-running successful chunks.

.PARAMETER Force
  If set, ignore any recorded state and re-run every chunk. Implies
  `-Resume:$false`.

.PARAMETER Status
  If set and a plan file exists, print a full progress report (counts
  ok/failed/pending/stale, per-source rollup, recent failures, next
  pending tasks) from the plan and journal, then exit. If no plan
  exists, falls back to previewing the chunks that would run.

.PARAMETER StatePath
  Path to the JSONL state file. Defaults to
  <ResultsXml directory>/copilot_doc_state.jsonl. One JSON object per
  completed task is appended after each invocation.

.PARAMETER PlanPath
  Path to the JSON plan snapshot file. Defaults to
  <ResultsXml directory>/copilot_doc_plan.json. The plan is materialized
  before dispatch and lists every chunk the run intends to process.

.PARAMETER Restart
  If set, archive any existing plan + state file (suffix `.archive-<stamp>`)
  and run from scratch. Skips the interactive prompt.

.PARAMETER NonInteractive
  If set, never prompt. When a plan already exists you must also pass one
  of -Resume / -Restart / -Force / -Status, otherwise the run aborts.

.PARAMETER TrackUsage
  On by default. Pass `-TrackUsage:$false` to opt out of per-task OTEL token /
  premium-request tracking via the Copilot CLI file exporter. Adds a
  small per-task parse cost; not recommended for large parallel runs.
  Requires Copilot CLI >= 1.0.55.

.PARAMETER OtelDir
  Directory for per-task OTEL JSONL files. Defaults to
  <ResultsXml directory>/otel. One file `task-<id>.jsonl` per chunk.

.PARAMETER PremiumMultiplier
  Premium-request multiplier for the model in use (e.g. Claude Sonnet 4.5 = 1).
  Used only for the rollup line `premium_requests = tasks * multiplier`.
  Default: 1.

.PARAMETER UsageLogPath
  Optional usage log path. Defaults to `logs/copilot-usage.csv`.
  Supported formats: `.csv` (default) and `.jsonl`.

.EXAMPLE
  pwsh -File scripts/dispatchers/run-docs-copilot-batch.ps1 `
    -Paths repos/sample1 `
    -Agent section-agent `
    -EnsureBundles `
    -Throttle 6
#>
[CmdletBinding()]
param(
  [string[]]$Files,
  [string[]]$Paths,
  [string]$Manifest,
  [string]$SourceRoot,
  [string]$Languages = 'en',
  [switch]$EnsureFactsSlices,
  [switch]$EnsureBundles,
  [string]$Agent = 'section-agent',
  [string]$PromptTemplate = @'
Document chunk {chunkId} for source {sourcePath}.
Read the bundle Markdown view at {bundlePath} as the single source of truth. It is a deterministic projection of the `.bundle.json` sibling (same `chunk`, `chunk_text`, `facts_slice`, `languages`, `output_paths`, plus all SHAs in the Metadata table) rendered into headed sections and tables for easier consumption. Then read the authoring template file at the path listed under Metadata `template_path` — the bundle MD links to it under `## Template` and does NOT inline its body. Obey that template verbatim; `template_sha` in Metadata pins the exact bytes. The bundle's `## Profile` block links to the active profile YAML at Metadata `profile_path` (pinned by `profile_sha`); read it only if the template tells you to — it is primarily the policy file the qa-reviewer enforces. Write the section documentation for every language listed under Metadata `languages`.
'@,
  [string]$CopilotCli = 'copilot',
  [string]$CopilotSubcommand = '',
  [string]$AgentSwitch = '--agent',
  [string]$PromptSwitch = '--prompt',
  [string[]]$AdditionalCopilotArgs = @(),
  [ValidateRange(1,64)]
  [Alias('Threads','ConcurrentThreads','MaxThreads')]
  [int]$Throttle = 12,
  [switch]$AllowLowerThrottle,
  [string]$ResultsXml = 'temp/copilot_doc_results.xml',
  [string]$LogsDir = 'logs',
  [string[]]$ExcludeExtensions = @('.cob', '.inp', '.itt'),
  [switch]$DryRun,
  [switch]$TaskLogging,
  [string]$TaskLogPath,
  [int]$TaskLogPreviewCount = 10,
  [switch]$Resume,
  [switch]$Force,
  [switch]$Status,
  [string]$StatePath,
  [switch]$Restart,
  [switch]$NonInteractive,
  [string]$PlanPath,
  [switch]$TrackUsage,
  [string]$OtelDir,
  [double]$PremiumMultiplier = 1,
  [string]$UsageLogPath
)

$ErrorActionPreference = 'Stop'

$effectiveThrottle = if (-not $AllowLowerThrottle -and $Throttle -lt 10) { 10 } else { $Throttle }
if ($effectiveThrottle -ne $Throttle) {
  Write-Warning ("Requested throttle {0} is below minimum 10. Using effective throttle {1}. Pass -AllowLowerThrottle to opt in to lower values." -f $Throttle, $effectiveThrottle)
}

# Keep switch ergonomics while preserving default-true behavior unless explicitly overridden.
$ensureFactsSlicesEnabled = if ($PSBoundParameters.ContainsKey('EnsureFactsSlices')) { [bool]$EnsureFactsSlices } else { $true }
$taskLoggingEnabled = if ($PSBoundParameters.ContainsKey('TaskLogging')) { [bool]$TaskLogging } else { $true }

function Write-OrchLog {
  param(
    [string]$Message,
    [switch]$NoHost
  )

  $line = "{0} {1}" -f ([DateTime]::UtcNow.ToString('o')), $Message
  if (-not $NoHost) {
    Write-Host $line
  }
  if ($script:TaskLogEnabled) {
    try {
      [System.IO.File]::AppendAllText($script:ResolvedTaskLogPath, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    }
    catch {
      # Best effort logging: do not fail orchestration because of log I/O.
    }
  }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$writeSectionsBatch = Join-Path $repoRoot '.github/skills/section-doc-writer/scripts/write_sections_batch.ps1'
$sliceFactsBatch = Join-Path $repoRoot '.github/skills/facts-slicing/scripts/slice_facts_batch.ps1'
if ($ensureFactsSlicesEnabled -and -not (Test-Path $sliceFactsBatch)) {
  throw "slice_facts_batch.ps1 not found at $sliceFactsBatch"
}
if ($EnsureBundles -and -not (Test-Path $writeSectionsBatch)) {
  throw "write_sections_batch.ps1 not found at $writeSectionsBatch"
}

$resultsXmlPath = if ([System.IO.Path]::IsPathRooted($ResultsXml)) {
  $ResultsXml
}
else {
  Join-Path $repoRoot $ResultsXml
}
$resultsDir = Split-Path -Parent $resultsXmlPath
if (-not (Test-Path $resultsDir)) {
  New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

$logsDir = if ([System.IO.Path]::IsPathRooted($LogsDir)) { $LogsDir } else { Join-Path $repoRoot $LogsDir }
if (-not (Test-Path $logsDir)) {
  New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$resolvedTaskLogPath = if ($TaskLogPath) {
  if ([System.IO.Path]::IsPathRooted($TaskLogPath)) {
    $TaskLogPath
  }
  else {
    Join-Path $repoRoot $TaskLogPath
  }
}
else {
  Join-Path $logsDir 'copilot_doc_tasks.log'
}
$taskLogDir = Split-Path -Parent $resolvedTaskLogPath
if (-not (Test-Path $taskLogDir)) {
  New-Item -ItemType Directory -Path $taskLogDir -Force | Out-Null
}

$script:TaskLogEnabled = [bool]$taskLoggingEnabled
$script:ResolvedTaskLogPath = $resolvedTaskLogPath
if ($script:TaskLogEnabled) {
  Set-Content -LiteralPath $script:ResolvedTaskLogPath -Encoding utf8 -Value ''
}
Write-OrchLog "Task logging enabled=$script:TaskLogEnabled path=$script:ResolvedTaskLogPath"
Write-OrchLog "Throttle requested=$Throttle effective=$effectiveThrottle allowLower=$([bool]$AllowLowerThrottle)"

# --- Resume / state file ------------------------------------------------

$resolvedStatePath = if ($StatePath) {
  if ([System.IO.Path]::IsPathRooted($StatePath)) { $StatePath } else { Join-Path $repoRoot $StatePath }
}
else {
  Join-Path $logsDir 'copilot_doc_state.jsonl'
}
$stateDir = Split-Path -Parent $resolvedStatePath
if (-not (Test-Path $stateDir)) {
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}
if ($Force) { $Resume = $false }

function Get-BundleSha {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-BundleOutputsExist {
  param(
    [string]$BundlePath,
    [string]$RepoRoot
  )

  if (-not (Test-Path -LiteralPath $BundlePath)) {
    return $false
  }

  try {
    $bundleObj = Get-Content -Raw -LiteralPath $BundlePath | ConvertFrom-Json -ErrorAction Stop
  }
  catch {
    return $false
  }

  if ($null -eq $bundleObj.output_paths) {
    return $false
  }

  foreach ($prop in $bundleObj.output_paths.PSObject.Properties) {
    $outRel = [string]$prop.Value
    if (-not $outRel) {
      continue
    }

    $outAbs = if ([System.IO.Path]::IsPathRooted($outRel)) { $outRel } else { Join-Path $RepoRoot $outRel }
    if (-not (Test-Path -LiteralPath $outAbs)) {
      return $false
    }
  }

  return $true
}

function Get-RecordedTaskStatus {
  param(
    $Prev,
    [string]$ExpectedBundleSha,
    [string]$BundlePath,
    [string]$RepoRoot
  )

  if (-not $Prev) {
    return 'pending'
  }

  $prevStatus = [string]$Prev.status
  if ($prevStatus -ne 'ok') {
    return $prevStatus
  }

  if ([string]$Prev.bundle_sha -ne [string]$ExpectedBundleSha) {
    return 'stale'
  }

  if (-not (Test-BundleOutputsExist -BundlePath $BundlePath -RepoRoot $RepoRoot)) {
    return 'missing-output'
  }

  return 'ok'
}

function Read-StateMap {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $map }
  foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
    if (-not $line) { continue }
    try {
      $obj = $line | ConvertFrom-Json -ErrorAction Stop
    }
    catch { continue }
    if (-not $obj.bundle_path) { continue }
    # Last write wins.
    $map[[string]$obj.bundle_path] = $obj
  }
  return $map
}

$script:StateMap = Read-StateMap -Path $resolvedStatePath
Write-OrchLog "State file path=$resolvedStatePath entries=$($script:StateMap.Count) resume=$([bool]$Resume) force=$([bool]$Force)"

# --- Plan file ---------------------------------------------------------

$resolvedPlanPath = if ($PlanPath) {
  if ([System.IO.Path]::IsPathRooted($PlanPath)) { $PlanPath } else { Join-Path $repoRoot $PlanPath }
}
else {
  Join-Path $logsDir 'copilot_doc_plan.json'
}

function Get-ParamsFingerprint {
  return [ordered]@{
    Files      = @($Files)
    Paths      = @($Paths)
    Manifest   = [string]$Manifest
    SourceRoot = [string]$SourceRoot
    Languages  = [string]$Languages
    Agent      = [string]$Agent
  }
}

function Read-Plan {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try { return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -ErrorAction Stop }
  catch { return $null }
}

function Test-ParamsMatch {
  param($PlanParams, $CurrentParams)
  if (-not $PlanParams) { return $false }
  foreach ($k in @('Manifest', 'SourceRoot', 'Languages', 'Agent')) {
    if ([string]$PlanParams.$k -ne [string]$CurrentParams.$k) { return $false }
  }
  foreach ($k in @('Files', 'Paths')) {
    $a = @($PlanParams.$k) | Sort-Object
    $b = @($CurrentParams.$k) | Sort-Object
    if (($a -join '|') -ne ($b -join '|')) { return $false }
  }
  return $true
}

function Move-PlanAndStateToArchive {
  param([string]$Plan, [string]$State)
  $stamp = (Get-Date -Format 'yyyyMMddTHHmmssZ')
  foreach ($p in @($Plan, $State)) {
    if ($p -and (Test-Path -LiteralPath $p)) {
      $dst = "$p.archive-$stamp"
      Move-Item -LiteralPath $p -Destination $dst -Force
      Write-OrchLog "Archived $p -> $dst"
    }
  }
}

function Resolve-PlanAction {
  param([string]$PlanFile, $CurrentParams)

  $existing = Read-Plan -Path $PlanFile
  if (-not $existing) { return 'fresh' }

  $paramsMatch = Test-ParamsMatch -PlanParams $existing.params -CurrentParams $CurrentParams

  if ($Restart) { return 'restart' }
  if ($Force) { return 'restart' }
  if ($Resume) { return 'continue' }
  if ($Status) { return 'status' }

  if ($NonInteractive) {
    throw "A previous plan exists at $PlanFile. In non-interactive mode pass one of -Resume / -Restart / -Force / -Status."
  }

  $journal = Read-StateMap -Path $resolvedStatePath
  $ok = 0; $failed = 0; $pending = 0; $missingOutput = 0; $stale = 0
  foreach ($t in @($existing.tasks)) {
    $prev = $journal[[string]$t.bundle_path]
    $status = Get-RecordedTaskStatus -Prev $prev -ExpectedBundleSha ([string]$t.bundle_sha) -BundlePath ([string]$t.bundle_path) -RepoRoot $repoRoot
    switch ($status) {
      'ok' { $ok++ }
      'failed' { $failed++ }
      'missing-output' { $missingOutput++ }
      'stale' { $stale++ }
      default { $pending++ }
    }
  }

  Write-Host ''
  Write-Host "A previous plan was found at: $PlanFile"
  Write-Host "  Created : $($existing.created_utc)"
  Write-Host "  Tasks   : $($existing.total_tasks)  (ok=$ok  failed=$failed  pending=$pending  missing-output=$missingOutput  stale=$stale)"
  if (-not $paramsMatch) {
    Write-Host '  WARNING : current invocation parameters differ from the plan; continuing may skip new chunks or rerun unexpected ones.' -ForegroundColor Yellow
  }
  Write-Host ''
  Write-Host '  [C] Continue (resume pending + failed; skip ok)  [default]'
  Write-Host '  [R] Restart  (archive old plan + journal; run all)'
  Write-Host '  [S] Status   (print plan and exit)'
  Write-Host '  [A] Abort'
  $choice = (Read-Host 'Choice [C/R/S/A]').Trim().ToUpperInvariant()
  switch ($choice) {
    'R' { return 'restart' }
    'S' { return 'status' }
    'A' { return 'abort' }
    default { return 'continue' }
  }
}

function Write-Plan {
  param([string]$Path, $CurrentParams, $WorkItems, $StateMap)
  $tasks = foreach ($w in $WorkItems) {
    $prev = $StateMap[[string]$w.BundlePath]
    $status = Get-RecordedTaskStatus -Prev $prev -ExpectedBundleSha ([string]$w.BundleSha) -BundlePath ([string]$w.BundlePath) -RepoRoot $repoRoot
    if ($status -eq 'pending') {
      $status = 'planned'
    }
    [ordered]@{
      task_id     = $w.TaskId
      source_path = $w.SourcePath
      source_name = $w.SourceName
      chunk_id    = $w.ChunkId
      bundle_path = $w.BundlePath
      bundle_sha  = $w.BundleSha
      status      = $status
    }
  }
  $plan = [ordered]@{
    plan_version = '1.0'
    run_id       = [Guid]::NewGuid().ToString()
    created_utc  = [DateTime]::UtcNow.ToString('o')
    started_utc  = $null
    finished_utc = $null
    duration_seconds = $null
    repo_root    = $repoRoot
    state_path   = $resolvedStatePath
    params       = $CurrentParams
    total_tasks  = @($WorkItems).Count
    tasks        = @($tasks)
  }
  $json = $plan | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
  Write-OrchLog "Plan written path=$Path tasks=$($plan.total_tasks)"
}

function Update-PlanTimestamp {
  param(
    [string]$Path,
    [ValidateSet('start','end')][string]$Phase
  )
  if (-not (Test-Path -LiteralPath $Path)) { return }
  try {
    $plan = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  } catch {
    Write-Warning "Update-PlanTimestamp: cannot read plan '$Path' ($($_.Exception.Message))"
    return
  }
  $now = [DateTime]::UtcNow.ToString('o')
  if ($Phase -eq 'start') {
    # Always stamp the start of this dispatch (resume restarts the clock).
    $plan | Add-Member -NotePropertyName started_utc -NotePropertyValue $now -Force
    $plan | Add-Member -NotePropertyName finished_utc -NotePropertyValue $null -Force
    $plan | Add-Member -NotePropertyName duration_seconds -NotePropertyValue $null -Force
  }
  else {
    $plan | Add-Member -NotePropertyName finished_utc -NotePropertyValue $now -Force
    $dur = $null
    if ($plan.started_utc) {
      try {
        $start = [DateTime]::Parse([string]$plan.started_utc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $end   = [DateTime]::Parse($now, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $dur   = [math]::Round(($end - $start).TotalSeconds, 2)
      } catch { $dur = $null }
    }
    $plan | Add-Member -NotePropertyName duration_seconds -NotePropertyValue $dur -Force
  }
  $json = $plan | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

$currentParams = Get-ParamsFingerprint
function Show-PlanStatus {
  param([string]$PlanFile, [string]$StateFile)

  $plan = Read-Plan -Path $PlanFile
  if (-not $plan) {
    Write-Host "No plan file found at: $PlanFile"
    return $false
  }
  $journal = Read-StateMap -Path $StateFile

  $rows = foreach ($t in @($plan.tasks)) {
    $prev = $journal[[string]$t.bundle_path]
    $status = Get-RecordedTaskStatus -Prev $prev -ExpectedBundleSha ([string]$t.bundle_sha) -BundlePath ([string]$t.bundle_path) -RepoRoot $repoRoot
    $exit = ''
    $duration = ''
    $finishedAt = ''
    if ($prev) {
      if ($null -ne $prev.exit_code) { $exit = [string]$prev.exit_code }
      if ($null -ne $prev.duration_seconds) { $duration = '{0:N1}s' -f [double]$prev.duration_seconds }
      if ($prev.finished_utc) { $finishedAt = [string]$prev.finished_utc }
    }
    [pscustomobject]@{
      TaskId   = $t.task_id
      Source   = $t.source_name
      ChunkId  = $t.chunk_id
      Status   = $status
      Exit     = $exit
      Duration = $duration
      Finished = $finishedAt
      Bundle   = $t.bundle_path
    }
  }

  $total   = @($rows).Count
  $okCnt   = @($rows | Where-Object Status -EQ 'ok').Count
  $failCnt = @($rows | Where-Object Status -EQ 'failed').Count
  $pendCnt = @($rows | Where-Object Status -EQ 'pending').Count
  $staleCnt= @($rows | Where-Object Status -EQ 'stale').Count
  $missingCnt = @($rows | Where-Object Status -EQ 'missing-output').Count
  $pct = if ($total -gt 0) { [math]::Round((($okCnt) / $total) * 100, 1) } else { 0 }

  Write-Host ''
  Write-Host "Plan      : $PlanFile"
  Write-Host "Journal   : $StateFile"
  Write-Host "Created   : $($plan.created_utc)   RunId: $($plan.run_id)"
  $startedDisp  = if ($plan.started_utc)  { [string]$plan.started_utc }  else { '(not started)' }
  $finishedDisp = if ($plan.finished_utc) { [string]$plan.finished_utc } else { '(running or aborted)' }
  $durDisp = if ($plan.duration_seconds) { '{0:N1}s' -f [double]$plan.duration_seconds } else { '' }
  Write-Host "Started   : $startedDisp"
  Write-Host "Finished  : $finishedDisp   $durDisp"
  Write-Host ("Progress  : {0}/{1} ok ({2}%)  failed={3}  pending={4}  missing-output={5}  stale={6}" -f $okCnt, $total, $pct, $failCnt, $pendCnt, $missingCnt, $staleCnt)
  Write-Host ''
  Write-Host 'Per-source rollup:'
  $rows | Group-Object Source | ForEach-Object {
    $g = $_.Group
    [pscustomobject]@{
      Source  = $_.Name
      Total   = $g.Count
      Ok      = @($g | Where-Object Status -EQ 'ok').Count
      Failed  = @($g | Where-Object Status -EQ 'failed').Count
      Pending = @($g | Where-Object Status -EQ 'pending').Count
      Missing = @($g | Where-Object Status -EQ 'missing-output').Count
      Stale   = @($g | Where-Object Status -EQ 'stale').Count
    }
  } | Sort-Object Source | Format-Table -AutoSize | Out-String | Write-Host

  $failed = @($rows | Where-Object Status -EQ 'failed')
  if ($failed.Count -gt 0) {
    Write-Host "Failed tasks (showing up to 20):"
    $failed | Select-Object -First 20 TaskId, Source, ChunkId, Exit, Duration, Finished |
      Format-Table -AutoSize | Out-String | Write-Host
  }

  $pending = @($rows | Where-Object Status -EQ 'pending')
  if ($pending.Count -gt 0) {
    Write-Host "Pending tasks (showing up to 10):"
    $pending | Select-Object -First 10 TaskId, Source, ChunkId, Bundle |
      Format-Table -AutoSize | Out-String | Write-Host
  }

  $missing = @($rows | Where-Object Status -EQ 'missing-output')
  if ($missing.Count -gt 0) {
    Write-Host "Missing-output tasks (showing up to 10):"
    $missing | Select-Object -First 10 TaskId, Source, ChunkId, Bundle |
      Format-Table -AutoSize | Out-String | Write-Host
  }

  return $true
}

$planAction = Resolve-PlanAction -PlanFile $resolvedPlanPath -CurrentParams $currentParams
Write-OrchLog "Plan action=$planAction plan=$resolvedPlanPath"
switch ($planAction) {
  'abort'   { Write-Host 'Aborted by user.'; exit 0 }
  'restart' {
    Move-PlanAndStateToArchive -Plan $resolvedPlanPath -State $resolvedStatePath
    $script:StateMap = @{}
    $Resume = $false
  }
  'continue' { $Resume = $true }
  'status'   {
    # Full status report from the existing plan + journal; exit without dispatching.
    [void](Show-PlanStatus -PlanFile $resolvedPlanPath -StateFile $resolvedStatePath)
    exit 0
  }
  'fresh'    { }
}
# Refresh state map after a possible archive so the per-chunk gate sees fresh data.
$script:StateMap = Read-StateMap -Path $resolvedStatePath

function Resolve-SourceEntries {
  param(
    [string[]]$InFiles,
    [string[]]$InPaths,
    [string]$InManifest,
    [string[]]$InExcludeExtensions
  )

  $entries = [System.Collections.Generic.List[object]]::new()
  if ($InManifest) {
    $raw = Get-Content -Raw -LiteralPath $InManifest
    $items =
      if ($InManifest -match '\.csv$') { $raw | ConvertFrom-Csv }
      else { $raw | ConvertFrom-Json }
    foreach ($i in $items) {
      $entries.Add([pscustomobject]@{ Path = [string]$i.path })
    }
    return $entries
  }

  $excludeSet = @{}
  foreach ($e in $InExcludeExtensions) {
    if ($e) { $excludeSet[$e.ToLowerInvariant()] = $true }
  }

  $collected = @()
  if ($InFiles) {
    foreach ($f in $InFiles) {
      if ((Test-Path -LiteralPath $f -PathType Container)) {
        $collected += (Get-ChildItem -LiteralPath $f -File -Recurse -ErrorAction Stop |
          Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
          ForEach-Object { $_.FullName })
      }
      else {
        $collected += $f
      }
    }
  }

  if ($InPaths) {
    foreach ($p in $InPaths) {
      if ((Test-Path -LiteralPath $p -PathType Container)) {
        $collected += (Get-ChildItem -LiteralPath $p -File -Recurse -ErrorAction Stop |
          Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
          ForEach-Object { $_.FullName })
      }
      else {
        $collected += (Get-ChildItem -Path $p -File -ErrorAction Stop |
          Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
          ForEach-Object { $_.FullName })
      }
    }
  }

  if (-not $collected) {
    throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
  }

  foreach ($p in ($collected | Select-Object -Unique | Sort-Object)) {
    $entries.Add([pscustomobject]@{ Path = [string]$p })
  }

  return $entries
}

function Resolve-RelativeOrAbsolute {
  param([string]$PathValue)
  try {
    return (Resolve-Path -LiteralPath $PathValue -ErrorAction Stop).Path
  }
  catch {
    return $PathValue
  }
}

$sourceEntries = Resolve-SourceEntries -InFiles $Files -InPaths $Paths -InManifest $Manifest -InExcludeExtensions $ExcludeExtensions

if ($EnsureBundles) {
  if ($ensureFactsSlicesEnabled) {
    Write-Host "Slicing facts for $($sourceEntries.Count) source file(s) before bundle staging..."
    $sliceArgs = @{
      Files = @($sourceEntries | ForEach-Object { $_.Path })
      Throttle = $effectiveThrottle
    }
    if ($SourceRoot) { $sliceArgs.SourceRoot = $SourceRoot }
    & $sliceFactsBatch @sliceArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }

  Write-Host "Staging bundles for $($sourceEntries.Count) source file(s) before Copilot execution..."
  $batchArgs = @{
    Files = @($sourceEntries | ForEach-Object { $_.Path })
    Languages = $Languages
    Throttle = $effectiveThrottle
  }
  if ($SourceRoot) { $batchArgs.SourceRoot = $SourceRoot }
  & $writeSectionsBatch @batchArgs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$workItems = [System.Collections.Generic.List[object]]::new()
$taskIndex = 0
foreach ($entry in $sourceEntries) {
  $srcPath = Resolve-RelativeOrAbsolute -PathValue $entry.Path
  $srcName = [System.IO.Path]::GetFileName($srcPath)
  $docDir = Join-Path $repoRoot "docs/_shared/$srcName"
  $manifestPath = Join-Path $docDir 'chunk-manifest.json'
  $indexPath = Join-Path $docDir 'chunks/index.json'

  if (-not (Test-Path $manifestPath)) {
    throw "Missing prerequisite: $manifestPath"
  }
  if (-not (Test-Path $indexPath)) {
    throw "Missing prerequisite: $indexPath"
  }

  $manifestObj = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  $indexObj = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json

  $fileByChunk = @{}
  foreach ($idx in @($indexObj.chunks)) {
    $fileByChunk[[string]$idx.id] = [string]$idx.file
  }

  foreach ($chunk in @($manifestObj.chunks)) {
    $chunkId = [string]$chunk.id
    if (-not $fileByChunk.ContainsKey($chunkId)) {
      continue
    }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($fileByChunk[$chunkId])
    $bundlePath = Join-Path $docDir "_bundles/$stem.bundle.json"
    if (-not (Test-Path $bundlePath)) {
      throw "Missing bundle for chunk '$chunkId': $bundlePath. Run with -EnsureBundles or stage bundles first."
    }

    $bundleSha = Get-BundleSha -Path $bundlePath
    if ($Resume -and -not $Force) {
      $prev = $script:StateMap[$bundlePath]
      $outputsExist = Test-BundleOutputsExist -BundlePath $bundlePath -RepoRoot $repoRoot
      if ($prev -and ([string]$prev.status -eq 'ok') -and ([string]$prev.bundle_sha -eq $bundleSha) -and $outputsExist) {
        Write-OrchLog ("SKIP chunk='{0}' bundle='{1}' reason=resume" -f $chunkId, $bundlePath) -NoHost
        continue
      }
      if ($prev -and ([string]$prev.status -eq 'ok') -and ([string]$prev.bundle_sha -eq $bundleSha) -and -not $outputsExist) {
        Write-OrchLog ("REQUEUE chunk='{0}' bundle='{1}' reason=missing-output" -f $chunkId, $bundlePath) -NoHost
      }
    }

    # Pre-create output directories declared by bundle.output_paths so the
    # Copilot CLI invocation can write its files without race conditions.
    $bundleObj = Get-Content -Raw -LiteralPath $bundlePath | ConvertFrom-Json
    if ($null -eq $bundleObj.output_paths) {
      throw "Bundle missing output_paths: $bundlePath"
    }
    foreach ($prop in $bundleObj.output_paths.PSObject.Properties) {
      $outRel = [string]$prop.Value
      if (-not $outRel) { continue }
      $outAbs = if ([System.IO.Path]::IsPathRooted($outRel)) { $outRel } else { Join-Path $repoRoot $outRel }
      $outDir = Split-Path -Parent $outAbs
      if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        Write-OrchLog "Created output dir for chunk='$chunkId' key='$($prop.Name)': $outDir" -NoHost
      }
      if (Test-Path -LiteralPath $outAbs) {
        Remove-Item -LiteralPath $outAbs -Force -ErrorAction SilentlyContinue
        Write-OrchLog "Deleted existing output for chunk='$chunkId' key='$($prop.Name)': $outAbs" -NoHost
      }
    }

    # LLM consumes the rendered Markdown view (`.bundle.md`); the `.bundle.json`
    # sibling stays authoritative for SHA tracking, output_paths parsing, and
    # the mechanical qa-reviewer checker. assemble-inputs.py writes both.
    $bundleMdPath = [System.IO.Path]::ChangeExtension($bundlePath, 'md')
    if (-not (Test-Path -LiteralPath $bundleMdPath)) {
      throw "Missing bundle MD view for chunk '$chunkId': $bundleMdPath. Re-stage bundles (assemble-inputs.py writes the .md alongside the .json) or run render-bundle-md.py --in $bundlePath --out $bundleMdPath."
    }
    $prompt = $PromptTemplate
    $prompt = $prompt.Replace('{chunkId}', $chunkId)
    $prompt = $prompt.Replace('{sourcePath}', $srcPath)
    $prompt = $prompt.Replace('{bundlePath}', $bundleMdPath)

    $taskIndex += 1

    $workItems.Add([pscustomobject]@{
      TaskId = $taskIndex
      SourcePath = $srcPath
      SourceName = $srcName
      ChunkId = $chunkId
      BundlePath = $bundlePath
      BundleSha = $bundleSha
      Prompt = $prompt
    })
  }
}

if ($workItems.Count -eq 0) {
  if ($Resume) {
    Write-Host 'Nothing to do: every chunk is already recorded ok in the state file. Use -Force to re-run.'
    exit 0
  }
  throw 'No chunk work items found. Ensure chunk-manifest and chunks/index exist and contain chunks.'
}

if (-not $Status) {
  Write-Plan -Path $resolvedPlanPath -CurrentParams $currentParams -WorkItems $workItems -StateMap $script:StateMap
}

if ($Status) {
  Write-Host "Resume plan: $($workItems.Count) chunk(s) would run (state=$resolvedStatePath, plan=$resolvedPlanPath, resume=$([bool]$Resume), force=$([bool]$Force))"
  $workItems | Select-Object TaskId, SourceName, ChunkId, BundlePath | Format-Table -AutoSize
  exit 0
}

Write-Host "Dispatching $($workItems.Count) chunk task(s) with throttle=$effectiveThrottle (dryRun=$([bool]$DryRun) resume=$([bool]$Resume) force=$([bool]$Force))"
Write-Host "State file: $resolvedStatePath (re-run with -Resume to continue, -Status to preview, -Force to ignore state)"
Write-OrchLog "Dispatch start totalTasks=$($workItems.Count) throttle=$effectiveThrottle dryRun=$([bool]$DryRun) resume=$([bool]$Resume) force=$([bool]$Force) state=$resolvedStatePath"
Update-PlanTimestamp -Path $resolvedPlanPath -Phase start
if ($TaskLogPreviewCount -gt 0) {
  $preview = $workItems | Select-Object -First $TaskLogPreviewCount
  foreach ($p in $preview) {
    Write-OrchLog ("Queue task #{0}: source={1} chunk={2}" -f $p.TaskId, $p.SourceName, $p.ChunkId) -NoHost
  }
}

$totalTasks = $workItems.Count
$taskLogEnabled = [bool]$taskLoggingEnabled
$taskLogPath = $resolvedTaskLogPath
$statePath = $resolvedStatePath
$stateMutexName = 'Global\CopilotDocBatch-State-' + ([System.IO.Path]::GetFileName($statePath))

# --- Usage tracking (OTEL file exporter) -------------------------------
$resolvedOtelDir = if ($OtelDir) {
  if ([System.IO.Path]::IsPathRooted($OtelDir)) { $OtelDir } else { Join-Path $repoRoot $OtelDir }
}
else {
  Join-Path $resultsDir 'otel'
}
if ($TrackUsage -and -not (Test-Path -LiteralPath $resolvedOtelDir)) {
  New-Item -ItemType Directory -Path $resolvedOtelDir -Force | Out-Null
}
$trackUsage = if ($PSBoundParameters.ContainsKey('TrackUsage')) { [bool]$TrackUsage } else { $true }
$otelDirResolved = $resolvedOtelDir
$premiumMultiplier = [double]$PremiumMultiplier
Write-OrchLog "Usage tracking enabled=$trackUsage otelDir=$otelDirResolved premiumMultiplier=$premiumMultiplier"

$resolvedUsageLogPath = if ($UsageLogPath) {
  if ([System.IO.Path]::IsPathRooted($UsageLogPath)) { $UsageLogPath } else { Join-Path $repoRoot $UsageLogPath }
}
else {
  Join-Path $repoRoot 'logs/copilot-usage.csv'
}
$usageLogIsCsv = ([System.IO.Path]::GetExtension($resolvedUsageLogPath).ToLowerInvariant() -eq '.csv')
if ($trackUsage) {
  $usageLogDir = Split-Path -Parent $resolvedUsageLogPath
  if ($usageLogDir -and -not (Test-Path -LiteralPath $usageLogDir)) {
    New-Item -ItemType Directory -Path $usageLogDir -Force | Out-Null
  }
  if ($usageLogIsCsv -and -not (Test-Path -LiteralPath $resolvedUsageLogPath)) {
    $usageCsvHeader = 'timestamp,task_id,source_name,source_path,chunk_id,exit,status,duration_ms,ai_credits,tokens_in,tokens_out,tokens_total,cost_usd,tool_calls,agent_turns,premium_requests,otel_path'
    [System.IO.File]::WriteAllText($resolvedUsageLogPath, $usageCsvHeader + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
  }
}
Write-OrchLog "Usage detail log path=$resolvedUsageLogPath format=$(if($usageLogIsCsv){'csv'}else{'jsonl'})"

# Resolve the actual Copilot CLI source (typically a .ps1 shim) so we can
# spawn it with System.Diagnostics.Process and set per-child env vars without
# polluting the shared runspace env (RunspacePool shares the parent $env:).
$copilotCommand = Get-Command $CopilotCli -ErrorAction Stop
$copilotSourcePath = $copilotCommand.Source
$copilotIsPs1 = $copilotSourcePath -match '\.ps1$'
# Prefer the same host that started the script; fall back gracefully on PS5.
$pwshExePath = try { (Get-Process -Id $PID).Path } catch { $null }
if (-not $pwshExePath) { $pwshExePath = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Path }
Write-OrchLog "Copilot CLI resolved: source=$copilotSourcePath isPs1=$copilotIsPs1 host=$pwshExePath"

# --- Ctrl+C / cancellation ---------------------------------------------
# Track every spawned child PID so a single Ctrl+C kills the whole process
# tree (Copilot CLI + any node/python descendants). Without this, Ctrl+C
# only signals the parent runspace; child processes keep running because
# they aren't in a Windows job object.
$childPids = [System.Collections.Concurrent.ConcurrentDictionary[int, byte]]::new()
$cancelRequested = [ref]$false
$cancelHandler = [ConsoleCancelEventHandler]{
  param($s, $e)
  if ($cancelRequested.Value) { return }   # already handling
  $cancelRequested.Value = $true
  $e.Cancel = $true                          # don't let CLR abort immediately
  Write-Host ''
  Write-Host 'Ctrl+C received - killing in-flight child processes...' -ForegroundColor Yellow
  foreach ($childPid in @($childPids.Keys)) {
    try { & taskkill.exe /F /T /PID $childPid 2>$null | Out-Null }
    catch { }
  }
  # Give kill a moment to propagate, then exit hard.
  Start-Sleep -Milliseconds 250
  [Environment]::Exit(130)
}
[Console]::add_CancelKeyPress($cancelHandler)
Write-OrchLog 'Ctrl+C handler installed (kills tracked child PIDs).'

# Per-task worker script block. Receives the work item via -ArgumentList; all
# other inputs are injected as session-state variables by the RunspacePool
# (so this body has no $using: references and runs identically on PS5/PS7).
$workerScript = {
  param($wi)

  $otelPath = if ($trackUsage) { Join-Path $otelDir ("task-{0}.jsonl" -f $wi.TaskId) } else { $null }

  $parseUsage = {
    param([string]$Path, [double]$Mult)
    $result = [ordered]@{
      ai_credits      = 0.0
      tokens_in       = 0
      tokens_out      = 0
      tokens_total    = 0
      cost_usd        = 0.0
      tool_calls      = 0
      agent_turns     = 0
      premium_requests = 0.0
      otel_path       = $Path
    }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $result }
    $lines = $null
    try {
      $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
      try {
        $sr = New-Object System.IO.StreamReader($fs)
        try { $lines = $sr.ReadToEnd() -split "`r?`n" } finally { $sr.Dispose() }
      }
      finally { $fs.Dispose() }
    }
    catch {
      Write-Warning ("OTEL parse: skipping '{0}' ({1})" -f $Path, $_.Exception.Message)
      return $result
    }
    if ($null -eq $lines) { return $result }
    foreach ($line in $lines) {
      if (-not $line) { continue }
      try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
      $name = [string]$obj.name
      $val  = 0.0
      foreach ($k in 'value','sum','count') {
        if ($null -ne $obj.$k) { $val = [double]$obj.$k; break }
      }
      $attrType = [string]$obj.attributes.'gen_ai.token.type'
      switch -Wildcard ($name) {
        '*token.usage*' {
          if ($attrType -eq 'input' -or $attrType -eq 'prompt') { $result.tokens_in += [long]$val }
          elseif ($attrType -eq 'output' -or $attrType -eq 'completion') { $result.tokens_out += [long]$val }
          else { $result.tokens_total += [long]$val }
        }
        '*tool.call.count*' { $result.tool_calls += [long]$val }
        '*agent.turn.count*' { $result.agent_turns += [long]$val }
        '*cost*' { $result.cost_usd += [double]$val }
      }
    }
    if ($result.tokens_total -eq 0) { $result.tokens_total = $result.tokens_in + $result.tokens_out }
    $turns = if ($result.agent_turns -gt 0) { $result.agent_turns } else { 1 }
    $result.premium_requests = [math]::Round($turns * $Mult, 4)
    return $result
  }

  $parseCliUsage = {
    param([string]$Text, [double]$Mult)
    $result = [ordered]@{
      ai_credits      = 0.0
      tokens_in        = 0
      tokens_out       = 0
      tokens_total     = 0
      cost_usd         = 0.0
      tool_calls       = 0
      agent_turns      = 0
      premium_requests = 0.0
      otel_path        = ''
    }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $result }

    $parseTokenCount = {
      param([string]$Raw)
      if ([string]::IsNullOrWhiteSpace($Raw)) { return 0 }
      $m = [regex]::Match($Raw.Trim(), '(?i)^([\d.]+)\s*([kmg]?)$')
      if (-not $m.Success) { return 0 }
      $n = 0.0
      if (-not [double]::TryParse($m.Groups[1].Value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$n)) {
        return 0
      }
      switch ($m.Groups[2].Value.ToLowerInvariant()) {
        'k' { $n *= 1e3 }
        'm' { $n *= 1e6 }
        'g' { $n *= 1e9 }
      }
      return [long][Math]::Round($n)
    }

    $tokenLines = [regex]::Matches($Text, '(?im)^[^\r\n]*Tokens[^\r\n]*$')
    if ($tokenLines.Count -gt 0) {
      $line = $tokenLines[$tokenLines.Count - 1].Value
      $bare = [regex]::Replace($line, '\([^)]*\)', '')
      $bare = $bare -replace '(?i)Tokens', ''
      $nums = [regex]::Matches($bare, '([\d.]+\s*[kmg]?)')
      if ($nums.Count -ge 1) { $result.tokens_in = & $parseTokenCount $nums[0].Value }
      if ($nums.Count -ge 2) { $result.tokens_out = & $parseTokenCount $nums[1].Value }
      $result.tokens_total = $result.tokens_in + $result.tokens_out
    }

    $credits = [regex]::Matches($Text, '(?i)AI\s+Credits\s+([\d.]+)\s*\(([^)]*)\)')
    if ($credits.Count -gt 0) {
      $v = 0.0
      if ([double]::TryParse($credits[$credits.Count - 1].Groups[1].Value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$v)) {
        $result.ai_credits = $v
      }
    }

    $turnMatches = [regex]::Matches($Text, '(?i)agent\s+turn|assistant\s+turn')
    if ($turnMatches.Count -gt 0) { $result.agent_turns = [long]$turnMatches.Count }
    $turns = if ($result.agent_turns -gt 0) { $result.agent_turns } else { 1 }
    $result.premium_requests = [math]::Round($turns * $Mult, 4)
    return $result
  }

  $logTask = {
    param([string]$Message)
    if (-not $taskLogging) { return }
    $line = "{0} {1}" -f ([DateTime]::UtcNow.ToString('o')), $Message
    Write-Host $line
    try {
      [System.IO.File]::AppendAllText($taskLogFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    }
    catch { }
  }

  $writeState = {
    param([int]$ExitCode, [long]$DurationMs, $Usage)
    $status = if ($ExitCode -eq 0) { 'ok' } else { 'failed' }
    $payload = [ordered]@{
      timestamp    = [DateTime]::UtcNow.ToString('o')
      task_id      = $wi.TaskId
      source_path  = $wi.SourcePath
      source_name  = $wi.SourceName
      chunk_id     = $wi.ChunkId
      bundle_path  = $wi.BundlePath
      bundle_sha   = $wi.BundleSha
      exit         = $ExitCode
      status       = $status
      duration_ms  = $DurationMs
      dry_run      = $dry
      usage        = $Usage
    } | ConvertTo-Json -Compress -Depth 6
    $mutex = New-Object System.Threading.Mutex($false, $stateMutex)
    $csvEscape = {
      param($v)
      $s = if ($null -eq $v) { '' } else { [string]$v }
      if ($s -match '[",\r\n]') { '"' + ($s -replace '"', '""') + '"' } else { $s }
    }
    try {
      [void]$mutex.WaitOne()
      [System.IO.File]::AppendAllText($stateFile, $payload + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
      if ($trackUsage -and $usageLogFile) {
        if ($usageLogIsCsv) {
          $row = @(
            [DateTime]::UtcNow.ToString('o')
            $wi.TaskId
            $wi.SourceName
            $wi.SourcePath
            $wi.ChunkId
            $ExitCode
            $status
            $DurationMs
            $Usage.ai_credits
            $Usage.tokens_in
            $Usage.tokens_out
            $Usage.tokens_total
            $Usage.cost_usd
            $Usage.tool_calls
            $Usage.agent_turns
            $Usage.premium_requests
            $Usage.otel_path
          ) | ForEach-Object { & $csvEscape $_ }
          $usageLine = ($row -join ',') + [Environment]::NewLine
          [System.IO.File]::AppendAllText($usageLogFile, $usageLine, [System.Text.Encoding]::UTF8)
        }
        else {
          $usagePayload = [ordered]@{
            timestamp   = [DateTime]::UtcNow.ToString('o')
            task_id     = $wi.TaskId
            source_name = $wi.SourceName
            source_path = $wi.SourcePath
            chunk_id    = $wi.ChunkId
            exit        = $ExitCode
            status      = $status
            duration_ms = $DurationMs
            usage       = $Usage
          } | ConvertTo-Json -Compress -Depth 6
          [System.IO.File]::AppendAllText($usageLogFile, $usagePayload + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
        }
      }
    }
    catch { }
    finally {
      try { $mutex.ReleaseMutex() } catch {}
      $mutex.Dispose()
    }
  }

  # Build the full native argv (including host args when wrapping a .ps1 shim).
  $argv = New-Object System.Collections.Generic.List[string]
  if ($copilotPs1) {
    [void]$argv.Add('-NoLogo')
    [void]$argv.Add('-NoProfile')
    [void]$argv.Add('-File')
    [void]$argv.Add($copilotSrc)
  }
  if ($copilotSub) { [void]$argv.Add($copilotSub) }
  [void]$argv.Add('--yolo')
  #[void]$argv.Add('--remote')
  if ($agentSwitch -and $agent) {
    [void]$argv.Add($agentSwitch)
    [void]$argv.Add($agent)
  }
  if ($promptSwitch) {
    [void]$argv.Add($promptSwitch)
    [void]$argv.Add([string]$wi.Prompt)
  }
  if ($extra) { foreach ($a in $extra) { [void]$argv.Add([string]$a) } }

  # CommandLineToArgvW-compatible quoting (works for both PS5 and PS7 since
  # PS5's ProcessStartInfo lacks the typed ArgumentList collection).
  $formatNativeArg = {
    param([string]$Value)
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $i = 0
    while ($i -lt $Value.Length) {
      $bs = 0
      while ($i -lt $Value.Length -and $Value[$i] -eq '\') { $bs++; $i++ }
      if ($i -eq $Value.Length) {
        [void]$sb.Append('\' * ($bs * 2))
        break
      }
      elseif ($Value[$i] -eq '"') {
        [void]$sb.Append('\' * ($bs * 2 + 1))
        [void]$sb.Append('"')
      }
      else {
        [void]$sb.Append('\' * $bs)
        [void]$sb.Append($Value[$i])
      }
      $i++
    }
    [void]$sb.Append('"')
    return $sb.ToString()
  }

  $quotedArgs = foreach ($a in $argv) { & $formatNativeArg ([string]$a) }
  $argumentsString = ($quotedArgs -join ' ')
  $fileName = if ($copilotPs1) { $pwshExe } else { $copilotSrc }
  $displayCommand = ('{0} {1}' -f $fileName, $argumentsString).Trim()

  $taskHeader = "[task $($wi.TaskId)/$total][$($wi.SourceName)][$($wi.ChunkId)]"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $logTask "$taskHeader START dryRun=$dry cmd=$displayCommand"

  if ($dry) {
    $sw.Stop()
    $usage = & $parseUsage $null $premiumMult
    & $logTask "$taskHeader END exit=0 durationMs=$($sw.ElapsedMilliseconds)"
    & $writeState 0 $sw.ElapsedMilliseconds $usage
    [pscustomobject]@{
      TaskId = $wi.TaskId
      SourcePath = $wi.SourcePath
      ChunkId = $wi.ChunkId
      BundlePath = $wi.BundlePath
      Exit = 0
      Command = $displayCommand
      Stdout = "DRY-RUN: skipped"
      Stderr = ''
      DurationMs = $sw.ElapsedMilliseconds
      Usage = $usage
    }
    return
  }

  $proc = $null
  try {
    if ($trackUsage -and $otelPath -and (Test-Path -LiteralPath $otelPath)) {
      try { Remove-Item -LiteralPath $otelPath -Force -ErrorAction Stop }
      catch { Write-Warning ("OTEL pre-clean: skipping '{0}' ({1})" -f $otelPath, $_.Exception.Message) }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $fileName
    $psi.Arguments              = $argumentsString
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.WorkingDirectory       = $childCwd
    if ($trackUsage -and $otelPath) {
      $psi.EnvironmentVariables['COPILOT_OTEL_ENABLED']            = 'true'
      $psi.EnvironmentVariables['COPILOT_OTEL_FILE_EXPORTER_PATH'] = $otelPath
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $sync  = New-Object object
    $outHandler = {
      if ($null -ne $EventArgs.Data) {
        [System.Threading.Monitor]::Enter($Event.MessageData.Sync)
        try {
          $Event.MessageData.Lines.Add($EventArgs.Data)
          Write-Host ("{0} {1}" -f $Event.MessageData.Header, $EventArgs.Data)
        }
        finally { [System.Threading.Monitor]::Exit($Event.MessageData.Sync) }
      }
    }
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true
    $msgData = [pscustomobject]@{ Lines = $lines; Sync = $sync; Header = $taskHeader }
    $regOut = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $outHandler -MessageData $msgData
    $regErr = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived  -Action $outHandler -MessageData $msgData
    [void]$proc.Start()
    [void]$pidSet.TryAdd($proc.Id, 0)
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    $proc.WaitForExit()
    $removed = [byte]0
    [void]$pidSet.TryRemove($proc.Id, [ref]$removed)
    Start-Sleep -Milliseconds 50
    Unregister-Event -SourceIdentifier $regOut.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $regErr.Name -ErrorAction SilentlyContinue
    Remove-Job -Job $regOut -Force -ErrorAction SilentlyContinue
    Remove-Job -Job $regErr -Force -ErrorAction SilentlyContinue

    $combinedOutput = ($lines -join "`n")
    $nativeExit = $proc.ExitCode
    $errorText = if ($nativeExit -ne 0) { $combinedOutput } else { '' }
    $sw.Stop()
    $usage = & $parseUsage $otelPath $premiumMult
    $fallback = & $parseCliUsage $combinedOutput $premiumMult
    if ($fallback.ai_credits -gt 0) {
      $usage.ai_credits = $fallback.ai_credits
    }
    if ($trackUsage -and ($usage.tokens_total -eq 0) -and ($usage.cost_usd -eq 0)) {
      if (($fallback.tokens_total -gt 0) -or ($fallback.cost_usd -gt 0)) {
        $usage.tokens_in = $fallback.tokens_in
        $usage.tokens_out = $fallback.tokens_out
        $usage.tokens_total = $fallback.tokens_total
        $usage.cost_usd = $fallback.cost_usd
        $usage.premium_requests = $fallback.premium_requests
      }
    }
    & $logTask ("{0} END exit={1} durationMs={2} aiCredits={3} tokensIn={4} tokensOut={5} cost={6} premiumReq={7}" -f $taskHeader, $nativeExit, $sw.ElapsedMilliseconds, $usage.ai_credits, $usage.tokens_in, $usage.tokens_out, $usage.cost_usd, $usage.premium_requests)
    & $writeState $nativeExit $sw.ElapsedMilliseconds $usage
    [pscustomobject]@{
      TaskId = $wi.TaskId
      SourcePath = $wi.SourcePath
      ChunkId = $wi.ChunkId
      BundlePath = $wi.BundlePath
      Exit = $nativeExit
      Command = $displayCommand
      Stdout = $combinedOutput
      Stderr = $errorText
      DurationMs = $sw.ElapsedMilliseconds
      Usage = $usage
    }
  }
  catch {
    $sw.Stop()
    $usage = & $parseUsage $otelPath $premiumMult
    & $logTask "$taskHeader END exit=1 durationMs=$($sw.ElapsedMilliseconds) error=$($_.Exception.Message)"
    & $writeState 1 $sw.ElapsedMilliseconds $usage
    [pscustomobject]@{
      TaskId = $wi.TaskId
      SourcePath = $wi.SourcePath
      ChunkId = $wi.ChunkId
      BundlePath = $wi.BundlePath
      Exit = 1
      Command = $displayCommand
      Stdout = ''
      Stderr = $_.Exception.Message
      DurationMs = $sw.ElapsedMilliseconds
      Usage = $usage
    }
  }
  finally {
    $global:LASTEXITCODE = 0
    if ($proc) { try { $proc.Dispose() } catch {} }
  }
}

# Bundle inputs that need to be visible inside each runspace.
$sharedState = @{
  copilotCli   = $CopilotCli
  copilotSub   = $CopilotSubcommand
  agent        = $Agent
  agentSwitch  = $AgentSwitch
  promptSwitch = $PromptSwitch
  extra        = $AdditionalCopilotArgs
  dry          = [bool]$DryRun
  taskLogging  = [bool]$taskLogEnabled
  taskLogFile  = $taskLogPath
  stateFile    = $statePath
  stateMutex   = $stateMutexName
  total        = [int]$totalTasks
  trackUsage   = [bool]$trackUsage
  otelDir      = $otelDirResolved
  usageLogFile = $resolvedUsageLogPath
  usageLogIsCsv = [bool]$usageLogIsCsv
  premiumMult  = [double]$premiumMultiplier
  copilotSrc   = $copilotSourcePath
  copilotPs1   = [bool]$copilotIsPs1
  pwshExe      = $pwshExePath
  pidSet       = $childPids
  childCwd     = $repoRoot
}

# RunspacePool fan-out (PS5- and PS7-compatible substitute for `-Parallel`).
$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
foreach ($key in $sharedState.Keys) {
  $entry = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry($key, $sharedState[$key], '')
  $iss.Variables.Add($entry)
}
$pool = [runspacefactory]::CreateRunspacePool(1, [int]$effectiveThrottle, $iss, $Host)
$pool.ApartmentState = 'MTA'
$pool.Open()

$collected = New-Object System.Collections.Generic.List[object]
try {
  $queue = New-Object System.Collections.Generic.Queue[object]
  foreach ($wi in $workItems) { $queue.Enqueue($wi) }
  $active = New-Object System.Collections.Generic.List[object]

  # Keep only up to -Throttle active runspaces and harvest completions as they finish.
  while ($queue.Count -gt 0 -or $active.Count -gt 0) {
    while ($queue.Count -gt 0 -and $active.Count -lt [int]$effectiveThrottle) {
      $wi = $queue.Dequeue()
      $ps = [powershell]::Create()
      $ps.RunspacePool = $pool
      [void]$ps.AddScript($workerScript).AddArgument($wi)
      $active.Add([pscustomobject]@{
        WorkItem = $wi
        Pipe  = $ps
        Async = $ps.BeginInvoke()
      })
    }

    if ($active.Count -eq 0) { continue }

    $waitHandles = @($active | ForEach-Object { $_.Async.AsyncWaitHandle })
    $completedIndex = [System.Threading.WaitHandle]::WaitAny($waitHandles, 250)
    if ($completedIndex -eq [System.Threading.WaitHandle]::WaitTimeout) { continue }

    $p = $active[$completedIndex]
    try {
      $output = $p.Pipe.EndInvoke($p.Async)
      foreach ($item in $output) { if ($null -ne $item) { [void]$collected.Add($item) } }
      foreach ($err in $p.Pipe.Streams.Error) { Write-Host ("RUNSPACE ERROR: {0}" -f $err) -ForegroundColor Red }
    }
    catch {
      Write-Host ("RUNSPACE EXCEPTION: {0}" -f $_.Exception.Message) -ForegroundColor Red

      # If a runspace fails before returning a worker result, persist a failed
      # state row and collect a synthetic failed result so final counts remain accurate.
      if ($p -and $p.WorkItem) {
        $wi = $p.WorkItem
        $payload = [ordered]@{
          timestamp    = [DateTime]::UtcNow.ToString('o')
          task_id      = $wi.TaskId
          source_path  = $wi.SourcePath
          source_name  = $wi.SourceName
          chunk_id     = $wi.ChunkId
          bundle_path  = $wi.BundlePath
          bundle_sha   = $wi.BundleSha
          exit         = 1
          status       = 'failed'
          duration_ms  = 0
          dry_run      = [bool]$DryRun
          dispatcher_error = $true
          usage        = $null
          error        = $_.Exception.Message
        } | ConvertTo-Json -Compress -Depth 6

        $mutex = New-Object System.Threading.Mutex($false, $stateMutexName)
        try {
          [void]$mutex.WaitOne()
          [System.IO.File]::AppendAllText($statePath, $payload + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
        }
        catch { }
        finally {
          try { $mutex.ReleaseMutex() } catch {}
          $mutex.Dispose()
        }

        [void]$collected.Add([pscustomobject]@{
          TaskId = $wi.TaskId
          SourcePath = $wi.SourcePath
          ChunkId = $wi.ChunkId
          BundlePath = $wi.BundlePath
          Exit = 1
          Command = ''
          Stdout = ''
          Stderr = $_.Exception.Message
          DurationMs = 0
          Usage = $null
        })
      }
    }
    finally {
      try { $p.Async.AsyncWaitHandle.Close() } catch {}
      $p.Pipe.Dispose()
      $active.RemoveAt($completedIndex)
    }
  }
}
finally {
  $pool.Close()
  $pool.Dispose()
}

$results = @($collected | Sort-Object SourcePath, ChunkId)

$results | Export-Clixml -LiteralPath $ResultsXml

$failed = @($results | Where-Object { $_.Exit -ne 0 })
$ok = $results.Count - $failed.Count

Write-Host "DONE total=$($results.Count) ok=$ok failed=$($failed.Count)"
Write-OrchLog "Dispatch end total=$($results.Count) ok=$ok failed=$($failed.Count)"
Update-PlanTimestamp -Path $resolvedPlanPath -Phase end

if ($trackUsage) {
  $totCredits = 0.0; $totIn = 0L; $totOut = 0L; $totCost = 0.0; $totPrem = 0.0; $totTurns = 0L; $totTools = 0L
  foreach ($r in $results) {
    if ($null -eq $r.Usage) { continue }
    $totCredits += [double]$r.Usage.ai_credits
    $totIn   += [long]$r.Usage.tokens_in
    $totOut  += [long]$r.Usage.tokens_out
    $totCost += [double]$r.Usage.cost_usd
    $totPrem += [double]$r.Usage.premium_requests
    $totTurns += [long]$r.Usage.agent_turns
    $totTools += [long]$r.Usage.tool_calls
  }
  Write-Host ("USAGE tasks={0} aiCredits={1:N2} tokensIn={2} tokensOut={3} tokensTotal={4} cost={5:N4} premiumRequests={6:N2} turns={7} toolCalls={8} otelDir={9} usageLog={10}" -f $results.Count, $totCredits, $totIn, $totOut, ($totIn+$totOut), $totCost, $totPrem, $totTurns, $totTools, $otelDirResolved, $resolvedUsageLogPath)
  Write-OrchLog ("Usage rollup tasks={0} aiCredits={1} tokensIn={2} tokensOut={3} cost={4} premiumRequests={5} usageLog={6}" -f $results.Count, $totCredits, $totIn, $totOut, $totCost, $totPrem, $resolvedUsageLogPath)
}

if ($failed.Count -gt 0) {
  Write-Host 'Failures:'
  $failed | Select-Object -First 25 | ForEach-Object {
    Write-Host "  [$($_.Exit)] $($_.SourcePath) :: $($_.ChunkId)"
  }
  exit 1
}

exit 0
