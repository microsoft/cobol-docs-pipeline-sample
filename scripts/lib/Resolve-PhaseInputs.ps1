# Shared helpers for scripts/phases/phase-*.ps1 and scripts/run-pipeline.ps1.
#
# Responsibilities:
#   1. Resolve repo root from any phase script (Get-RepoRoot).
#   2. Expand -Files / -Paths / -Manifest into an enumerable source list,
#      used ONLY for fail-fast prereq checks; downstream batch wrappers
#      perform their own canonical expansion (Get-PhaseInputs).
#   3. Assert per-source upstream artifacts exist before a phase runs
#      (Assert-PhasePrereqs).
#   4. Merge selector args into a child-script splat (Add-SourceSelectorArgs).
#   5. Run a phase's batch action with timing, XML tally, structured event
#      emission and stable-copy results-XML stamping (Invoke-PhaseBatch).
#   6. Emit one structured log line per phase event (Write-PhaseEvent).
#
# Default-strict for every dot-source caller.
$ErrorActionPreference = 'Stop'

# Exclude extensions used by Get-PhaseInputs MUST mirror the filter inside
# skill-owned batch runners used by phases A-C. Keep both in sync.
$script:DefaultExcludeExtensions = @('.cob', '.inp', '.itt')

# Single source of truth for phase script paths. Relative to repo root.
$script:PhaseScriptMap = [ordered]@{
  A = 'scripts/phases/phase-A-chunk.ps1'
  B = 'scripts/phases/phase-B-facts.ps1'
  C = 'scripts/phases/phase-C-extract-text.ps1'
  D = 'scripts/phases/phase-D-section-docs.ps1'
  E = 'scripts/phases/phase-E-finalize.ps1'
  F = 'scripts/phases/phase-F-requirements.ps1'
  G = 'scripts/phases/phase-G-functional-analysis.ps1'
  H = 'scripts/phases/phase-H-diagrams.ps1'
  I = 'scripts/phases/phase-I-group-docs.ps1'
  J = 'scripts/phases/phase-J-group-requirements.ps1'
  K = 'scripts/phases/phase-K-group-functional-analysis.ps1'
  L = 'scripts/phases/phase-L-technical-analysis.ps1'
  M = 'scripts/phases/phase-M-group-technical-analysis.ps1'
  N = 'scripts/phases/phase-N-portal.ps1'
}

function Get-RepoRoot {
  <#
    .SYNOPSIS
      Resolve the repo root from a phase script located at
      scripts/phases/phase-*.ps1 (three levels up from $PSCommandPath).
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory)] [string]$ScriptPath)
  Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ScriptPath))
}

function Get-PhaseScriptMap {
  [CmdletBinding()] param()
  return $script:PhaseScriptMap
}

function Get-PhaseInputs {
  [CmdletBinding()]
  param(
    [string[]]$Files,
    [string[]]$Paths,
    [string]$Manifest,
    [string[]]$ExcludeExtensions = $script:DefaultExcludeExtensions
  )
  $excludeSet = @{}
  foreach ($e in $ExcludeExtensions) {
    if ($e) { $excludeSet[$e.ToLowerInvariant()] = $true }
  }
  $out = [System.Collections.Generic.List[string]]::new()
  if ($Manifest) {
    if (-not (Test-Path -LiteralPath $Manifest)) {
      throw "Manifest not found: $Manifest"
    }
    $raw = Get-Content -Raw -LiteralPath $Manifest
    # Sniff format from first non-whitespace char ({ / [ = JSON); fall back to extension.
    $trim   = $raw.TrimStart()
    $isJson = ($trim.Length -gt 0 -and ($trim[0] -eq '{' -or $trim[0] -eq '['))
    if (-not $isJson -and ($Manifest -match '\.(json|jsonl)$')) { $isJson = $true }
    $items = if ($isJson) { $raw | ConvertFrom-Json } else { $raw | ConvertFrom-Csv }
    foreach ($i in $items) { [void]$out.Add([string]$i.path) }
  }
  if ($Files) { foreach ($f in $Files) { [void]$out.Add($f) } }
  if ($Paths) {
    foreach ($p in $Paths) {
      $recurse = Test-Path -LiteralPath $p -PathType Container
      Get-ChildItem -Path $p -File -Recurse:$recurse -ErrorAction Stop |
        Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
        ForEach-Object { [void]$out.Add($_.FullName) }
    }
  }
  $resolved = @($out | Where-Object { $_ } | Select-Object -Unique | Sort-Object)
  if ($resolved.Count -eq 0) {
    $hint = @()
    if ($Files)    { $hint += "Files=$($Files -join ',')" }
    if ($Paths)    { $hint += "Paths=$($Paths -join ',')" }
    if ($Manifest) { $hint += "Manifest=$Manifest" }
    throw "No source files resolved from inputs ($($hint -join ' ; ')). Check the paths, glob patterns, and configured exclusions."
  }
  return ,$resolved
}

function Assert-PhasePrereqs {
  <#
    .SYNOPSIS
      Fail-fast prereq check. For each source file, every artifact path
      template in -RequiredArtifacts must resolve to an existing file.
      Templates support tokens: <basename>.

    .NOTES
      Exits the calling script with code 4 on missing artifacts.
      Glob templates (containing '*') are resolved with Get-ChildItem
      under -ErrorAction Stop so that ACL/permission failures are NOT
      silently treated as "no matches".
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$RepoRoot,
    [Parameter(Mandatory)] [string[]]$Sources,
    [Parameter(Mandatory)] [string]$PhaseId,
    [Parameter(Mandatory)] [string[]]$RequiredArtifacts
  )
  $missing = [System.Collections.Generic.List[string]]::new()
  foreach ($src in $Sources) {
    $basename = [System.IO.Path]::GetFileName($src)
    foreach ($tpl in $RequiredArtifacts) {
      $rel  = $tpl.Replace('<basename>', $basename)
      $full = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $RepoRoot $rel }
      if ($rel -match '\*') {
        try {
          $globHits = @(Get-ChildItem -Path $full -ErrorAction Stop)
        } catch [System.Management.Automation.ItemNotFoundException] {
          $globHits = @()
        }
        if ($globHits.Count -eq 0) { [void]$missing.Add($full) }
      }
      elseif (-not (Test-Path -LiteralPath $full)) {
        [void]$missing.Add($full)
      }
    }
  }
  if ($missing.Count -gt 0) {
    [Console]::Error.WriteLine("phase=$PhaseId : missing $($missing.Count) upstream artifact(s):")
    foreach ($m in $missing) { [Console]::Error.WriteLine("  $m") }
    [Console]::Error.WriteLine("Run upstream phases first or pass -Force to bypass (where supported).")
    exit 4
  }
}

function Add-SourceSelectorArgs {
  <#
    .SYNOPSIS
      Merge the four shared source selectors into a child-script splat
      hashtable. Only non-empty values are added.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [hashtable]$Target,
    [string[]]$Files,
    [string[]]$Paths,
    [string]$Manifest,
    [string]$SourceRoot
  )
  if ($Files)      { $Target.Files      = $Files }
  if ($Paths)      { $Target.Paths      = $Paths }
  if ($Manifest)   { $Target.Manifest   = $Manifest }
  if ($SourceRoot) { $Target.SourceRoot = $SourceRoot }
  return $Target
}

function Write-PhaseEvent {
  <#
    .SYNOPSIS
      Emit one structured single-line event for phase activity. Format:
        [phase=A event=end ok=12 failed=0 elapsed=4.2s exit=0]
      Written via Write-Information so callers can suppress with
      -InformationAction SilentlyContinue.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Phase,
    [Parameter(Mandatory)] [ValidateSet('start','end','skip','step','retry')] [string]$Event,
    [hashtable]$Data = @{}
  )
  $parts = [System.Collections.Generic.List[string]]::new()
  [void]$parts.Add("phase=$Phase")
  [void]$parts.Add("event=$Event")
  foreach ($k in $Data.Keys) {
    $v = $Data[$k]
    [void]$parts.Add("$k=$v")
  }
  Write-Information ("[{0}]" -f ($parts -join ' ')) -InformationAction Continue
}

function Invoke-PhaseWithRetry {
  <#
    .SYNOPSIS
      Invoke one phase script and retry failures up to -MaxRetries times.

    .DESCRIPTION
      A retry is triggered by either a non-zero native/script exit code or a
      terminating PowerShell error, except prerequisite exit code 4, which
      stops immediately. The return value is the final exit code;
      the caller decides whether to abort the pipeline.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$PhaseId,
    [Parameter(Mandatory)] [string]$PhaseScript,
    [Parameter(Mandatory)] [hashtable]$PhaseArgs,
    [ValidateRange(0, 100)] [int]$MaxRetries = 3
  )

  $maxAttempts = $MaxRetries + 1
  $phaseScriptName = Split-Path -Leaf $PhaseScript
  for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    $exitCode = 0
    $attemptWatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host ("--- Phase {0}: attempt {1}/{2} | script={3} ---" -f `
      $PhaseId, $attempt, $maxAttempts, $phaseScriptName)
    Write-PhaseEvent -Phase $PhaseId -Event 'step' -Data @{
      action       = 'attempt-start'
      attempt      = $attempt
      max_attempts = $maxAttempts
      script       = $phaseScriptName
    }
    try {
      $global:LASTEXITCODE = 0
      & $PhaseScript @PhaseArgs | Out-Host
      $exitCode = $LASTEXITCODE
      if ($null -eq $exitCode) { $exitCode = 0 }
    } catch {
      $exitCode = $LASTEXITCODE
      if ($null -eq $exitCode -or $exitCode -eq 0) { $exitCode = 1 }
      [Console]::Error.WriteLine(
        "PHASE-ERROR phase=$PhaseId attempt=$attempt/$maxAttempts message=$($_.Exception.Message)"
      )
    } finally {
      $attemptWatch.Stop()
    }

    $attemptElapsed = [Math]::Round($attemptWatch.Elapsed.TotalSeconds, 2)
    Write-Host ("--- Phase {0}: attempt {1}/{2} completed | exit={3} | elapsed={4}s ---" -f `
      $PhaseId, $attempt, $maxAttempts, $exitCode, $attemptElapsed)
    Write-PhaseEvent -Phase $PhaseId -Event 'step' -Data @{
      action  = 'attempt-end'
      attempt = $attempt
      elapsed = "${attemptElapsed}s"
      exit    = $exitCode
    }

    if ($exitCode -eq 0) {
      return 0
    }
    if ($exitCode -eq 4) {
      Write-PhaseEvent -Phase $PhaseId -Event 'step' -Data @{
        action = 'retry-skipped'; reason = 'missing-prerequisite'; attempt = $attempt; exit = $exitCode
      }
      return [int]$exitCode
    }
    if ($attempt -ge $maxAttempts) {
      return [int]$exitCode
    }

    Write-PhaseEvent -Phase $PhaseId -Event 'retry' -Data @{
      attempt      = $attempt
      exit         = $exitCode
      max_retries  = $MaxRetries
      next_attempt = $attempt + 1
    }
  }
}

function Invoke-PhaseBatch {
  <#
    .SYNOPSIS
      Execute a phase's batch action with timing, results-XML tally,
      structured event emission and DONE-line back-compat.

    .DESCRIPTION
      The -Action scriptblock invokes the underlying batch wrapper(s)
      and must leave $LASTEXITCODE set. On exit:
        * elapsed wall time is measured
        * the last updated results XML (if present) is parsed: ok/failed counts come
          from the file, not from $LASTEXITCODE, so a degraded run with
          ok>0 failed>0 reports honest totals
          (-StepResultsXml lists intermediate step reports in execution order)
        * a stable copy of the XML is left alongside a timestamped one
          (chunk_results.xml + chunk_results.<utc>.xml) so concurrent runs
          don't overwrite each other
        * a structured event line + back-compat 'PHASE-DONE' line are emitted
        * the action's exit code is returned (use as the script's exit)

      Three reported run states:
        success  : exit=0, failed=0, ok>0
        noop     : exit=0, ok=0, failed=0  (no inputs / all up-to-date)
        degraded : exit=0, failed>0        (some items failed but batch returned 0)
        failure  : exit!=0                 (batch returned non-zero)
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$PhaseId,
    [Parameter(Mandatory)] [string]$ResultsXml,
    [Parameter(Mandatory)] [scriptblock]$Action,
    [string[]]$StepResultsXml = @()
  )

  Write-PhaseEvent -Phase $PhaseId -Event 'start'

  $resultPaths = @($StepResultsXml) + @($ResultsXml)
  $previousStamps = @{}
  foreach ($path in $resultPaths) {
    $previousStamps[$path] = if (Test-Path -LiteralPath $path) {
      (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
    } else { $null }
  }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $childExit = 0
  $caughtError = $null
  try {
    & $Action
    $childExit = $LASTEXITCODE
    if ($null -eq $childExit) { $childExit = 0 }
  } catch {
    $caughtError = $_
    $childExit = $LASTEXITCODE
    if ($null -eq $childExit -or $childExit -eq 0) { $childExit = 1 }
    [Console]::Error.WriteLine("PHASE-ERROR phase=$PhaseId exception=$($caughtError.GetType().Name)")
    [Console]::Error.WriteLine("PHASE-ERROR message: $($caughtError.Exception.Message)")
    if ($caughtError.InvocationInfo) {
      [Console]::Error.WriteLine("PHASE-ERROR location: $($caughtError.InvocationInfo.ScriptName):$($caughtError.InvocationInfo.ScriptLineNumber)")
    }
    [Console]::Error.WriteLine("PHASE-ERROR stacktrace: $($caughtError.ScriptStackTrace)")
  } finally {
    $sw.Stop()
  }
  $elapsed = [Math]::Round($sw.Elapsed.TotalSeconds, 2)

  # Use the last completed step of this attempt, never an old finalizer report.
  $currentResultsXml = $null
  foreach ($path in $resultPaths) {
    if ((Test-Path -LiteralPath $path) -and
        (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks -ne $previousStamps[$path]) {
      $currentResultsXml = $path
    }
  }
  # Stable + timestamped copy so concurrent runs don't clobber each other.
  if ($currentResultsXml) {
    $stamp   = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $dir     = Split-Path -Parent $currentResultsXml
    $base    = [System.IO.Path]::GetFileNameWithoutExtension($currentResultsXml)
    $ext     = [System.IO.Path]::GetExtension($currentResultsXml)
    $stamped = Join-Path $dir ("{0}.{1}{2}" -f $base, $stamp, $ext)
    Copy-Item -LiteralPath $currentResultsXml -Destination $stamped -Force
  }

  # Tally from XML regardless of $childExit (catches degraded runs).
  $ok = 0; $failed = 0
  if ($currentResultsXml) {
    $results = Import-Clixml -LiteralPath $currentResultsXml
    foreach ($r in $results) {
      if ($r.Exit -eq 0) { $ok++ } else { $failed++ }
    }
  }

  $state =
    if ($childExit -ne 0)                  { 'failure' }
    elseif ($failed -gt 0)                 { 'degraded' }
    elseif ($ok -eq 0 -and $failed -eq 0)  { 'noop' }
    else                                   { 'success' }

  Write-PhaseEvent -Phase $PhaseId -Event 'end' -Data @{
    ok      = $ok
    failed  = $failed
    elapsed = "${elapsed}s"
    exit    = $childExit
    state   = $state
  }
  # Back-compat: keep DONE-style line but with distinct PHASE-DONE prefix
  # so it does not collide with batch-emitted 'DONE total=... ok=... failed=...' lines.
  Write-Information `
    ("PHASE-DONE phase={0} ok={1} failed={2} elapsed={3}s exit={4} state={5}" `
      -f $PhaseId, $ok, $failed, $elapsed, $childExit, $state) `
    -InformationAction Continue

  if ($caughtError) {
    [Console]::Error.WriteLine("PHASE-ERROR phase=$PhaseId final-exit=$childExit")
    [Console]::Error.WriteLine("PHASE-ERROR Review the logs above for full exception details.")
  }

  return $childExit
}
