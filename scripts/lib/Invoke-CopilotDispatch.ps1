# Shared Copilot CLI dispatcher: runspace-pool fan-out used by every
# scripts/run-docs-*-batch.ps1 wrapper. Replaces the ~150 lines of
# duplicated worker / arg-quoting / pool-setup logic that previously
# lived in each batch script.
#
# Contract:
#  - Each work item is a [pscustomobject] with at least TaskId and Prompt;
#    any additional properties (e.g. SourceName, GroupId, SectionId) are
#    propagated verbatim onto the result record so the caller can keep
#    its existing XML schema.
#  - Skipped records are produced by the caller and must already carry the
#    full result shape (TaskId, Exit, Status, Stdout, Stderr, DurationMs).
#  - On return: results are written to -ResultsXml (Export-Clixml) sorted
#    by TaskId. The function returns an int exit code (0 success / only
#    skipped, 1 any failures).
#  - Per-task timeout: when -PerTaskTimeoutSec > 0 a long-running Copilot
#    call is killed and reported with Status='timeout', Exit=-3.
#  - Retry: -MaxRetries > 0 retries timeouts and transient stderr matches
#    (rate limit, 5xx, connection reset) with exponential backoff.
#  - Resume gate (content-hash): callers stamp Test-ResumeSidecar before
#    queueing a work item and Write-ResumeSidecar runs automatically on
#    Status='ok'. Sidecar = <output>.dispatched.json with sha256 of every
#    input file + agent + langs. mtime-proof.
#  - OnTaskComplete: scriptblock invoked on the orchestrator thread after
#    each task (success/failure/skipped) with the result record. Enables
#    per-task journaling, OTEL post-processing, etc. without forking.

$script:CopilotDispatchRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:CopilotModelSelections = @{}

function Resolve-CopilotModelSelection {
  <#
  .SYNOPSIS
    Resolve the runner override, pipeline default, agent frontmatter, then auto.
  .DESCRIPTION
    The runner scopes COBOL_DOCS_COPILOT_MODEL to phase execution. Cache by
    context and input content so repeated task fingerprints do not spawn Python,
    while an edited config or agent invalidates the selection in the same shell.
  #>
  [CmdletBinding()]
  param(
    [string]$RepoRoot = $script:CopilotDispatchRepoRoot,
    [string]$AgentName,
    [string]$ConfigPath
  )
  if (-not $RepoRoot) { $RepoRoot = $script:CopilotDispatchRepoRoot }
  if (-not $ConfigPath) { $ConfigPath = Join-Path $RepoRoot 'config\pipeline.yaml' }
  $agentPath = if ($AgentName) { Join-Path $RepoRoot ('.github\agents\{0}.agent.md' -f $AgentName) } else { '' }
  $override = [string]$env:COBOL_DOCS_COPILOT_MODEL
  $configHash = if (Test-Path -LiteralPath $ConfigPath) { (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash } else { '' }
  $agentHash = if ($agentPath -and (Test-Path -LiteralPath $agentPath)) { (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash } else { '' }
  $key = @($RepoRoot, $ConfigPath, $configHash, $agentPath, $agentHash, $override) | ConvertTo-Json -Compress
  if ($script:CopilotModelSelections.ContainsKey($key)) { return $script:CopilotModelSelections[$key] }

  $resolver = Join-Path $script:CopilotDispatchRepoRoot 'scripts\tools\resolve-copilot-model.py'
  $resolverArgs = @($resolver, '--config', $ConfigPath)
  if ($override.Length -gt 0) { $resolverArgs += @('--model', $override) }
  if ($agentPath) { $resolverArgs += @('--agent-file', $agentPath) }
  $output = & python @resolverArgs 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Copilot model resolution failed: $($output -join [Environment]::NewLine)" }
  $selection = ($output -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
  if (-not $selection.model -or $selection.source -notin @('cli', 'config', 'agent', 'auto') -or
      -not $selection.PSObject.Properties['cli_model']) {
    throw 'Copilot model resolver returned an invalid selection.'
  }
  $script:CopilotModelSelections[$key] = $selection
  return $selection
}

function Assert-CopilotModelArguments {
  [CmdletBinding()]
  param([string[]]$AdditionalCopilotArgs, [string]$CliModel)
  if (-not $CliModel) { return }
  foreach ($argument in $AdditionalCopilotArgs) {
    if ($argument -match '^--model(?:$|[=\s])') {
      throw 'AdditionalCopilotArgs --model conflicts with the selected CLI model; use -CopilotModel on the pipeline runner or copilot.default_model in config.'
    }
  }
}

function Format-NativeArg {
  [CmdletBinding()]
  param([string]$Value)
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  $idx = 0
  while ($idx -lt $Value.Length) {
    $bs = 0
    while ($idx -lt $Value.Length -and $Value[$idx] -eq '\') { $bs++; $idx++ }
    if ($idx -eq $Value.Length) { [void]$sb.Append('\' * ($bs * 2)); break }
    elseif ($Value[$idx] -eq '"') { [void]$sb.Append('\' * ($bs * 2 + 1)); [void]$sb.Append('"') }
    else { [void]$sb.Append('\' * $bs); [void]$sb.Append($Value[$idx]) }
    $idx++
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}

function Get-CopilotExecutable {
  [CmdletBinding()]
  param([string]$CopilotCli = 'copilot')
  $cmd = Get-Command $CopilotCli -ErrorAction Stop
  $src = $cmd.Source
  $isPs1 = $src -match '\.ps1$'
  $pwshExe = try { (Get-Process -Id $PID).Path } catch { $null }
  if (-not $pwshExe) { $pwshExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Path }
  [pscustomobject]@{ Source = $src; IsPs1 = [bool]$isPs1; PwshExe = $pwshExe }
}

function ConvertFrom-CopilotUsage {
  <#
  .SYNOPSIS
    Parse the footer lines the Copilot CLI prints after a call (AI credits,
    elapsed time, token usage, line changes) plus any model-substitution
    warning out of a captured stdout/stderr blob.
  .DESCRIPTION
    The Copilot CLI emits usage lines such as:
        AI Credits 19.4 (2m 34s)
        Tokens     ↑ 413.0k (368.5k cached) • ↓ 5.2k (2.0k reasoning)
        Changes    +118 -0
    and, when an agent's requested model is unavailable, a warning like:
        Warning: Custom agent "x" specifies model "Auto (copilot)" which is
        not available; using "auto" instead
    This helper extracts the LAST occurrence of each (the cumulative totals
    for the call), normalizes elapsed time into seconds and token counts
    (k/M/G suffixes) into integers, and captures the requested / used model.
  .PARAMETER Text
    The combined stdout/stderr captured from a Copilot CLI invocation.
  .OUTPUTS
    [pscustomobject] with:
    - Credits          [nullable double] AI credits consumed
    - TimeRaw           [string] the raw "(1m 45s)" body, without parentheses
    - TimeSeconds       [nullable int] elapsed time normalized to seconds
    - TokensInput       [nullable int] input (↑) tokens
    - TokensCached      [nullable int] cached input tokens
    - TokensOutput      [nullable int] output (↓) tokens
    - TokensReasoning   [nullable int] reasoning tokens
    - LinesAdded        [nullable int] lines added (Changes +N)
    - LinesDeleted      [nullable int] lines deleted (Changes -N)
    - ModelRequested    [string] model the agent asked for (from warning)
    - ModelUsed         [string] model actually used (from warning fallback)
  #>
  [CmdletBinding()]
  param([string]$Text)

  $result = [pscustomobject]@{
    Credits         = $null
    TimeRaw         = ''
    TimeSeconds     = $null
    TokensInput     = $null
    TokensCached    = $null
    TokensOutput    = $null
    TokensReasoning = $null
    LinesAdded      = $null
    LinesDeleted    = $null
    ModelRequested  = ''
    ModelUsed       = ''
  }
  if ([string]::IsNullOrEmpty($Text)) { return $result }

  # Normalize a token count with optional k/M/G suffix into an integer.
  $parseTokens = {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $m = [regex]::Match($Raw.Trim(), '(?i)^([\d.]+)\s*([kmg]?)$')
    if (-not $m.Success) { return $null }
    $num = 0.0
    if (-not [double]::TryParse($m.Groups[1].Value,
          [System.Globalization.NumberStyles]::Float,
          [System.Globalization.CultureInfo]::InvariantCulture, [ref]$num)) { return $null }
    switch ($m.Groups[2].Value.ToLowerInvariant()) {
      'k' { $num *= 1e3 }
      'm' { $num *= 1e6 }
      'g' { $num *= 1e9 }
    }
    return [int][Math]::Round($num)
  }

  # Capture every "AI Credits <n> (<time>)" and keep the last (cumulative) one.
  $matchesFound = [regex]::Matches($Text, '(?i)AI\s+Credits\s+([\d.]+)\s*\(([^)]*)\)')
  if ($matchesFound.Count -gt 0) {
    $last = $matchesFound[$matchesFound.Count - 1]
    $credits = 0.0
    if ([double]::TryParse($last.Groups[1].Value,
          [System.Globalization.NumberStyles]::Float,
          [System.Globalization.CultureInfo]::InvariantCulture, [ref]$credits)) {
      $result.Credits = $credits
    }
    $result.TimeRaw = $last.Groups[2].Value.Trim()
    # Normalize "2h 3m 4s" / "1m 45s" / "45s" / "1m" into total seconds.
    $secs = 0
    $hasAny = $false
    if ($result.TimeRaw -match '(\d+)\s*h') { $secs += [int]$matches[1] * 3600; $hasAny = $true }
    if ($result.TimeRaw -match '(\d+)\s*m') { $secs += [int]$matches[1] * 60;   $hasAny = $true }
    if ($result.TimeRaw -match '(\d+)\s*s') { $secs += [int]$matches[1];        $hasAny = $true }
    if ($hasAny) { $result.TimeSeconds = $secs }
  }

  # Parse the last Tokens line. The line shape varies, e.g.:
  #   Tokens  ↑ 19.0k • ↓ 25 (17 reasoning)
  #   Tokens  ↑ 413.0k (368.5k cached) • ↓ 5.2k (2.0k reasoning)
  # Arrow/bullet glyphs can be re-encoded by the console, so do NOT depend on
  # them. Instead: pull labelled parentheticals (cached / reasoning) out
  # first, then read the two remaining bare numbers as input then output.
  $tokLines = [regex]::Matches($Text, '(?im)^[^\r\n]*Tokens[^\r\n]*$')
  if ($tokLines.Count -gt 0) {
    $line = $tokLines[$tokLines.Count - 1].Value
    $cm = [regex]::Match($line, '(?i)\(\s*([\d.]+\s*[kmg]?)\s*cached\s*\)')
    if ($cm.Success) { $result.TokensCached = & $parseTokens $cm.Groups[1].Value }
    $rm = [regex]::Match($line, '(?i)\(\s*([\d.]+\s*[kmg]?)\s*reasoning\s*\)')
    if ($rm.Success) { $result.TokensReasoning = & $parseTokens $rm.Groups[1].Value }
    # Strip all parentheticals and the literal word "Tokens", then the two
    # leading numbers are input and output in order.
    $bare = [regex]::Replace($line, '\([^)]*\)', '')
    $bare = $bare -replace '(?i)Tokens', ''
    $nums = [regex]::Matches($bare, '([\d.]+\s*[kmg]?)')
    if ($nums.Count -ge 1) { $result.TokensInput  = & $parseTokens $nums[0].Value }
    if ($nums.Count -ge 2) { $result.TokensOutput = & $parseTokens $nums[1].Value }
  }

  # Capture the last "Changes +<added> -<deleted>" line.
  $chg = [regex]::Matches($Text, '(?i)Changes\s*\+(\d+)\s*-(\d+)')
  if ($chg.Count -gt 0) {
    $lastChg = $chg[$chg.Count - 1]
    $added = 0; $deleted = 0
    if ([int]::TryParse($lastChg.Groups[1].Value, [ref]$added))   { $result.LinesAdded = $added }
    if ([int]::TryParse($lastChg.Groups[2].Value, [ref]$deleted)) { $result.LinesDeleted = $deleted }
  }

  # Capture a model-substitution warning, e.g.:
  #   specifies model "Auto (copilot)" which is not available; using "auto" instead
  $mw = [regex]::Match($Text,
    '(?i)specifies model\s*"([^"]*)"\s*which is not available;\s*using\s*"([^"]*)"\s*instead')
  if ($mw.Success) {
    $result.ModelRequested = $mw.Groups[1].Value.Trim()
    $result.ModelUsed      = $mw.Groups[2].Value.Trim()
  }

  return $result
}

function Get-AgentModel {
  <#
  .SYNOPSIS
    Read the configured `model:` value from an agent's `.agent.md` frontmatter.
  .DESCRIPTION
    Best-effort lookup of <RepoRoot>/.github/agents/<AgentName>.agent.md. Used
    to record the agent's configured model in the usage CSV when the CLI did
    not emit a model-substitution warning. Returns '' when not resolvable.
  #>
  [CmdletBinding()]
  param([string]$RepoRoot, [string]$AgentName)
  if (-not $AgentName -or -not $RepoRoot) { return '' }
  $path = Join-Path $RepoRoot (".github/agents/{0}.agent.md" -f $AgentName)
  if (-not (Test-Path -LiteralPath $path)) { return '' }
  try {
    $head = Get-Content -LiteralPath $path -TotalCount 30 -ErrorAction Stop
    foreach ($l in $head) {
      $m = [regex]::Match($l, '^\s*model\s*:\s*(.+?)\s*$')
      if ($m.Success) { return $m.Groups[1].Value.Trim().Trim('"').Trim("'") }
    }
  } catch {}
  return ''
}


function Resolve-FirstLanguage {
  [CmdletBinding()]
  param([Parameter(Mandatory)] [string]$Languages)
  # Callers pass comma-separated codes ('en' or 'en,it'). Strip ALL whitespace
  # (including stray U+00A0 / tabs / newlines that can sneak in via splatting
  # or env coercion) before splitting on commas.
  $clean = ($Languages -replace '\s+', '')
  # @(...) forces array context so `[0]` indexes the FIRST element (not the
  # first character of an unwrapped scalar string).
  $first = @(($clean -split ',') | Where-Object { $_ })[0]
  if (-not $first) { throw "Languages must contain at least one code (got '$Languages')." }
  if ($first.Length -lt 2) {
    throw "Languages first code looks malformed ('$first' from '$Languages'); expected ISO code like 'en'."
  }
  $first
}

function Expand-SourceInputs {
  [CmdletBinding()]
  param(
    [string[]]$Files,
    [string[]]$Paths,
    [string]$Manifest,
    [string[]]$ExcludeExtensions = @()
  )
  $inputs = New-Object System.Collections.Generic.List[string]
  if ($Manifest) {
    $items = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
    foreach ($i in $items) { $inputs.Add([string]$i.path) }
  }
  else {
    if ($Files) { foreach ($f in $Files) { $inputs.Add($f) } }
    if ($Paths) {
      $excludeSet = @{}
      foreach ($e in $ExcludeExtensions) {
        if ($e) { $excludeSet[$e.ToLowerInvariant()] = $true }
      }
      foreach ($p in $Paths) {
        Get-ChildItem -Path $p -File -ErrorAction Stop |
          Where-Object { -not $excludeSet.ContainsKey($_.Extension.ToLowerInvariant()) } |
          ForEach-Object { $inputs.Add($_.FullName) }
      }
    }
  }
  if (-not $inputs) {
    throw 'No inputs. Provide -Files, -Paths, or -Manifest.'
  }
  ,@($inputs | Select-Object -Unique | Sort-Object)
}

function Read-PromptTemplate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$RepoRoot,
    [Parameter(Mandatory)] [string]$TemplatePath
  )
  $resolved = if ([System.IO.Path]::IsPathRooted($TemplatePath)) {
    $TemplatePath
  } else {
    Join-Path $RepoRoot $TemplatePath
  }
  if (-not (Test-Path -LiteralPath $resolved)) {
    throw "Prompt template not found: $resolved"
  }
  Get-Content -Raw -LiteralPath $resolved
}

function Expand-PromptTemplate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Template,
    [Parameter(Mandatory)] [hashtable]$Tokens
  )
  $out = $Template
  foreach ($k in $Tokens.Keys) {
    $out = $out.Replace('{{' + $k + '}}', [string]$Tokens[$k])
  }
  $out
}

function Get-FileSha256 {
  [CmdletBinding()]
  param([Parameter(Mandatory)] [string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ResumeFingerprint {
  # Deterministic content-hash fingerprint independent of file mtimes.
  # Inputs may include the bundle, the prompt template, any auxiliary
  # files. Agent + Languages + selected model are folded in for resume.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string[]]$InputFiles,
    [Parameter(Mandatory)] [string]$Agent,
    [string]$Languages = '',
    [string]$WorkingDirectory
  )
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($f in $InputFiles) {
    $sha = Get-FileSha256 -Path $f
    if (-not $sha) { return $null }
    $parts.Add("$([System.IO.Path]::GetFileName($f))=$sha")
  }
  $parts.Add("agent=$Agent")
  $parts.Add("langs=$Languages")
  $selection = Resolve-CopilotModelSelection -RepoRoot $WorkingDirectory -AgentName $Agent
  $parts.Add("model=$($selection.model)")
  $parts.Add("cli_model=$($selection.cli_model)")
  $joined = ($parts -join ';')
  $bytes  = [System.Text.Encoding]::UTF8.GetBytes($joined)
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  }
  finally { $sha256.Dispose() }
}

function Get-ResumeSidecarPath {
  [CmdletBinding()]
  param([Parameter(Mandatory)] [string]$OutputPath)
  "$OutputPath.dispatched.json"
}

function Test-ResumeSidecar {
  # Returns $true when the sidecar exists, the output exists, and the
  # recorded fingerprint matches the current inputs.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$OutputPath,
    [Parameter(Mandatory)] [string]$Fingerprint
  )
  if (-not (Test-Path -LiteralPath $OutputPath)) { return $false }
  $sidecar = Get-ResumeSidecarPath -OutputPath $OutputPath
  if (-not (Test-Path -LiteralPath $sidecar)) { return $false }
  try {
    $obj = Get-Content -Raw -LiteralPath $sidecar | ConvertFrom-Json
    return ([string]$obj.fingerprint -eq $Fingerprint)
  }
  catch { return $false }
}

function Write-ResumeSidecar {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$OutputPath,
    [Parameter(Mandatory)] [string]$Fingerprint
  )
  $sidecar = Get-ResumeSidecarPath -OutputPath $OutputPath
  $parent = [System.IO.Path]::GetDirectoryName($sidecar)
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    [void](New-Item -ItemType Directory -Path $parent -Force)
  }
  $payload = [ordered]@{
    fingerprint  = $Fingerprint
    output_path  = $OutputPath
    written_utc  = [DateTime]::UtcNow.ToString('o')
  } | ConvertTo-Json -Depth 3
  [System.IO.File]::WriteAllText($sidecar, $payload + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false))
}

function Invoke-CopilotDispatchPool {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [System.Collections.IEnumerable]$WorkItems,
    [System.Collections.IEnumerable]$Skipped,
    [Parameter(Mandatory)] [string]$LabelPrefix,
    [string]$KeyField = 'TaskId',
    [Parameter(Mandatory)] [string]$Agent,
    [string]$CopilotCli = 'copilot',
    [string]$CopilotSubcommand = '',
    [string]$AgentSwitch = '--agent',
    [string]$PromptSwitch = '--prompt',
    [string[]]$AdditionalCopilotArgs = @(),
    [ValidateRange(1,32)] [int]$Throttle = 10,
    [Parameter(Mandatory)] [string]$ResultsXml,
    [string]$WorkingDirectory,
    [int]$PerTaskTimeoutSec = 0,
    [string[]]$NonFailureStatuses = @('skipped-up-to-date','skipped-opt-out','dry-run'),
    [ValidateRange(0,10)] [int]$MaxRetries = 0,
    [int]$RetryBackoffSec = 5,
    [string]$RetryStderrPattern = '(?i)(rate.?limit|429|50[0234]|connection (reset|refused|error)|timeout|temporarily unavailable|ECONNRESET|EAI_AGAIN|CAPIError|transient (api )?error|failed to get response from the ai model)',
    [string]$OutputPathField = '',
    [string]$ResumeFingerprintField = '',
    [scriptblock]$OnTaskComplete,
    [string]$UsageCsvPath = '',
    [switch]$DisableUsageCsv,
    [switch]$DryRun
  )

  $workArr = @($WorkItems)
  $skipArr = @($Skipped)
  $total   = $workArr.Count + $skipArr.Count
  $modelSelection = Resolve-CopilotModelSelection -RepoRoot $WorkingDirectory -AgentName $Agent
  Assert-CopilotModelArguments -AdditionalCopilotArgs $AdditionalCopilotArgs -CliModel $modelSelection.cli_model

  Write-Host ("{0} dispatch: total={1} runnable={2} skipped={3} throttle={4} agent={5}" -f `
              $LabelPrefix, $total, $workArr.Count, $skipArr.Count, $Throttle, $Agent)

  if ($workArr.Count -eq 0) {
    $skipArr | Export-Clixml -LiteralPath $ResultsXml
    Write-Host "DONE total=$total ok=$($skipArr.Count) failed=0"
    return 0
  }

  $copilot = Get-CopilotExecutable -CopilotCli $CopilotCli
  if (-not $WorkingDirectory) { $WorkingDirectory = (Get-Location).Path }
  $dry = [bool]$DryRun

  $workerScript = {
    param($wi)

    function Format-NativeArg([string]$Value) {
      if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
      if ($Value -notmatch '[\s"]') { return $Value }
      $sb = New-Object System.Text.StringBuilder
      [void]$sb.Append('"')
      $idx = 0
      while ($idx -lt $Value.Length) {
        $bs = 0
        while ($idx -lt $Value.Length -and $Value[$idx] -eq '\') { $bs++; $idx++ }
        if ($idx -eq $Value.Length) { [void]$sb.Append('\' * ($bs * 2)); break }
        elseif ($Value[$idx] -eq '"') { [void]$sb.Append('\' * ($bs * 2 + 1)); [void]$sb.Append('"') }
        else { [void]$sb.Append('\' * $bs); [void]$sb.Append($Value[$idx]) }
        $idx++
      }
      [void]$sb.Append('"')
      return $sb.ToString()
    }

    # Clone all caller-supplied metadata onto the result record (minus Prompt).
    $base = [ordered]@{}
    foreach ($p in $wi.PSObject.Properties) {
      if ($p.Name -ne 'Prompt') { $base[$p.Name] = $p.Value }
    }
    $base.SelectedModel = $selectedModel
    $base.ModelSource = $modelSource
    $base.CliModel = $cliModel

    $argv = New-Object System.Collections.Generic.List[string]
    if ($copilotPs1) {
      [void]$argv.Add('-NoLogo'); [void]$argv.Add('-NoProfile')
      [void]$argv.Add('-File');   [void]$argv.Add($copilotSrc)
    }
    if ($copilotSub) { [void]$argv.Add($copilotSub) }
    [void]$argv.Add('--yolo')
    #[void]$argv.Add('--remote')
    if ($agentSwitch -and $agent) { [void]$argv.Add($agentSwitch); [void]$argv.Add($agent) }
    if ($cliModel) { [void]$argv.Add('--model'); [void]$argv.Add($cliModel) }
    if ($promptSwitch) { [void]$argv.Add($promptSwitch); [void]$argv.Add([string]$wi.Prompt) }
    if ($extra) { foreach ($a in $extra) { [void]$argv.Add([string]$a) } }

    $quoted = foreach ($a in $argv) { Format-NativeArg ([string]$a) }
    $argumentsString = ($quoted -join ' ')
    $fileName = if ($copilotPs1) { $pwshExe } else { $copilotSrc }
    $displayCommand = ('{0} {1}' -f $fileName, $argumentsString).Trim()
    $keyVal = if ($wi.PSObject.Properties[$keyField]) { $wi.$keyField } else { $wi.TaskId }
    $taskHeader = "[$labelPrefix $($wi.TaskId)/$total][$keyVal]"
    Write-Host "$taskHeader START dryRun=$dry cmd=$displayCommand"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($dry) {
      $sw.Stop()
      $base.Exit       = 0
      $base.Executed   = $false
      $base.Status     = 'dry-run'
      $base.Command    = $displayCommand
      $base.Stdout     = 'DRY-RUN: skipped'
      $base.Stderr     = ''
      $base.DurationMs = $sw.ElapsedMilliseconds
      $base.Attempts   = 0
      return [pscustomobject]$base
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $fileName
    $psi.Arguments              = $argumentsString
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.WorkingDirectory       = $childCwd

    $timedOut = $false
    $attempts = 0
  $executed = $false
    $maxAttempts = [Math]::Max(1, 1 + $maxRetries)
    while ($true) {
      $attempts++
      $timedOut = $false
      $lines  = New-Object System.Collections.Generic.List[string]
      $sync   = New-Object object
      $handler = {
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
      $attemptHeader = if ($attempts -gt 1) { "$taskHeader[try=$attempts/$maxAttempts]" } else { $taskHeader }
      $msgData = [pscustomobject]@{ Lines = $lines; Sync = $sync; Header = $attemptHeader }
      $regOut = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $handler -MessageData $msgData
      $regErr = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived  -Action $handler -MessageData $msgData

      try {
        [void]$proc.Start()
        $executed = $true
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()
        if ($perTaskTimeoutSec -gt 0) {
          if (-not $proc.WaitForExit($perTaskTimeoutSec * 1000)) {
            $timedOut = $true
            try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
            $proc.WaitForExit()
          }
        }
        else {
          $proc.WaitForExit()
        }
      }
      finally {
        Start-Sleep -Milliseconds 50
        Unregister-Event -SourceIdentifier $regOut.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $regErr.Name -ErrorAction SilentlyContinue
        Remove-Job -Job $regOut -Force -ErrorAction SilentlyContinue
        Remove-Job -Job $regErr -Force -ErrorAction SilentlyContinue
      }
      $exitCode = if ($timedOut) { -3 } else { $proc.ExitCode }
      $combined = ($lines -join "`n")
      $shouldRetry = $false
      if ($attempts -lt $maxAttempts) {
        if ($timedOut) {
          $shouldRetry = $true
        }
        elseif ($exitCode -ne 0 -and $retryStderrPattern -and $combined -match $retryStderrPattern) {
          $shouldRetry = $true
        }
      }
      if (-not $shouldRetry) { break }
      $sleepSec = [Math]::Min(300, $retryBackoffSec * [Math]::Pow(2, $attempts - 1))
      Write-Host "$taskHeader RETRY attempt=$attempts/$maxAttempts sleepSec=$sleepSec exit=$exitCode timedOut=$timedOut"
      Start-Sleep -Seconds $sleepSec
    }
    $sw.Stop()
    $status   = if ($timedOut) { 'timeout' } elseif ($exitCode -eq 0) { 'ok' } else { 'failed' }
    Write-Host "$taskHeader END exit=$exitCode status=$status attempts=$attempts durationMs=$($sw.ElapsedMilliseconds)"

    $base.Exit       = $exitCode
  $base.Executed   = $executed
    $base.Status     = $status
    $base.Command    = $displayCommand
    $base.Stdout     = $combined
    $base.Stderr     = if ($exitCode -ne 0) { $combined } else { '' }
    $base.DurationMs = $sw.ElapsedMilliseconds
    $base.Attempts   = $attempts
    return [pscustomobject]$base
  }

  $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
  $vars = @{
    copilotPs1         = $copilot.IsPs1
    copilotSrc         = $copilot.Source
    copilotSub         = $CopilotSubcommand
    pwshExe            = $copilot.PwshExe
    agent              = $Agent
    selectedModel      = [string]$modelSelection.model
    modelSource        = [string]$modelSelection.source
    cliModel           = [string]$modelSelection.cli_model
    agentSwitch        = $AgentSwitch
    promptSwitch       = $PromptSwitch
    extra              = $AdditionalCopilotArgs
    childCwd           = $WorkingDirectory
    total              = $workArr.Count
    dry                = $dry
    labelPrefix        = $LabelPrefix
    keyField           = $KeyField
    perTaskTimeoutSec  = $PerTaskTimeoutSec
    maxRetries         = $MaxRetries
    retryBackoffSec    = $RetryBackoffSec
    retryStderrPattern = $RetryStderrPattern
  }
  foreach ($k in $vars.Keys) {
    $entry = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry `
      -ArgumentList $k, $vars[$k], $null
    $iss.Variables.Add($entry)
  }

  $pool = [runspacefactory]::CreateRunspacePool(1, [int]$Throttle, $iss, $Host)
  $pool.ApartmentState = 'MTA'
  $pool.Open()

  $results = New-Object System.Collections.Generic.List[object]
  $callbackLock = New-Object object

  # Resolve the per-call usage CSV target. Precedence:
  #   1. explicit -UsageCsvPath
  #   2. $env:COPILOT_USAGE_CSV
  #   3. <WorkingDirectory>/temp/logs/copilot-usage.csv
  # Disabled entirely with -DisableUsageCsv.
  $usageCsvResolved = $null
  if (-not $DisableUsageCsv) {
    $usageCsvResolved =
      if ($UsageCsvPath) { $UsageCsvPath }
      elseif ($env:COPILOT_USAGE_CSV) { $env:COPILOT_USAGE_CSV }
      else { Join-Path $WorkingDirectory 'temp/logs/copilot-usage.csv' }
    if (-not [System.IO.Path]::IsPathRooted($usageCsvResolved)) {
      $usageCsvResolved = Join-Path $WorkingDirectory $usageCsvResolved
    }
    $usageDir = [System.IO.Path]::GetDirectoryName($usageCsvResolved)
    if ($usageDir -and -not (Test-Path -LiteralPath $usageDir)) {
      [void](New-Item -ItemType Directory -Path $usageDir -Force)
    }
    if (-not (Test-Path -LiteralPath $usageCsvResolved)) {
      $usageHeader = 'TimestampUtc,Label,Agent,Model,TaskId,Action,Status,Exit,AiCredits,CreditTimeRaw,CreditTimeSeconds,DurationMs,Attempts,TokensInput,TokensCached,TokensOutput,TokensReasoning,LinesAdded,LinesDeleted'
      [System.IO.File]::WriteAllText($usageCsvResolved, $usageHeader + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false))
    }
  }

  $csvEscape = {
    param($v)
    $s = if ($null -eq $v) { '' } else { [string]$v }
    if ($s -match '[",\r\n]') { '"' + ($s -replace '"', '""') + '"' } else { $s }
  }

  # Append one usage row per Copilot call. Runs on the single orchestrator
  # thread (under $callbackLock), so file appends never interleave.
  $writeUsageRow = {
    param($record)
    if (-not $usageCsvResolved) { return }
    $executed = $false
    if ($record.PSObject.Properties['Executed']) {
      $executed = [bool]$record.Executed
    }
    if (-not $executed) { return }
    try {
      $usage  = ConvertFrom-CopilotUsage -Text ([string]$record.Stdout)
      $keyVal = if ($record.PSObject.Properties[$KeyField]) { $record.$KeyField } else { $record.TaskId }
      $att    = if ($record.PSObject.Properties['Attempts']) { $record.Attempts } else { '' }
      $model  =
        if ($usage.ModelUsed)      { $usage.ModelUsed }
        else { [string]$modelSelection.model }
      $cols = @(
        [DateTime]::UtcNow.ToString('o')
        $LabelPrefix
        $Agent
        $model
        $record.TaskId
        $keyVal
        $record.Status
        $record.Exit
        $usage.Credits
        $usage.TimeRaw
        $usage.TimeSeconds
        $record.DurationMs
        $att
        $usage.TokensInput
        $usage.TokensCached
        $usage.TokensOutput
        $usage.TokensReasoning
        $usage.LinesAdded
        $usage.LinesDeleted
      ) | ForEach-Object { & $csvEscape $_ }
      $line = ($cols -join ',') + [Environment]::NewLine
      for ($try = 0; $try -lt 5; $try++) {
        try {
          [System.IO.File]::AppendAllText($usageCsvResolved, $line, [System.Text.UTF8Encoding]::new($false))
          break
        }
        catch { Start-Sleep -Milliseconds 50 }
      }
    }
    catch { Write-Warning ("Usage CSV row failed: {0}" -f $_.Exception.Message) }
  }

  $invokeCallback = {
    param($record)
    [System.Threading.Monitor]::Enter($callbackLock)
    try {
      & $writeUsageRow $record
      if ($null -ne $OnTaskComplete) {
        try { & $OnTaskComplete $record }
        catch { Write-Warning ("OnTaskComplete failed: {0}" -f $_.Exception.Message) }
      }
    }
    finally { [System.Threading.Monitor]::Exit($callbackLock) }
  }
  foreach ($s in $skipArr) {
    [void]$results.Add($s)
    & $invokeCallback $s
  }

  try {
    $pending = New-Object System.Collections.Generic.List[object]
    foreach ($wi in $workArr) {
      $ps = [powershell]::Create()
      $ps.RunspacePool = $pool
      [void]$ps.AddScript($workerScript).AddArgument($wi)
      $pending.Add([pscustomobject]@{ Wi = $wi; Pipe = $ps; Async = $ps.BeginInvoke() })
    }
    foreach ($p in $pending) {
      try {
        $output = $p.Pipe.EndInvoke($p.Async)
        foreach ($o in $output) {
          if ($null -eq $o) { continue }
          # Write resume sidecar on success when the caller declared an output
          # path field and pre-computed a fingerprint on the work item.
          if ([string]$o.Status -eq 'ok' -and $OutputPathField -and $ResumeFingerprintField) {
            $outVal = if ($p.Wi.PSObject.Properties[$OutputPathField]) { [string]$p.Wi.$OutputPathField } else { '' }
            $fp     = if ($p.Wi.PSObject.Properties[$ResumeFingerprintField]) { [string]$p.Wi.$ResumeFingerprintField } else { '' }
            if ($outVal -and $fp -and (Test-Path -LiteralPath $outVal)) {
              try { Write-ResumeSidecar -OutputPath $outVal -Fingerprint $fp }
              catch { Write-Warning ("Write-ResumeSidecar failed for {0}: {1}" -f $outVal, $_.Exception.Message) }
            }
            elseif ($outVal -and $fp) {
              Write-Warning ("Skipping resume sidecar: agent reported ok but output not found at {0}" -f $outVal)
            }
          }
          [void]$results.Add($o)
          & $invokeCallback $o
        }
      }
      catch {
        $base = [ordered]@{}
        foreach ($prop in $p.Wi.PSObject.Properties) {
          if ($prop.Name -ne 'Prompt') { $base[$prop.Name] = $prop.Value }
        }
        $base.Exit = -1; $base.Status = 'exception'; $base.Command = ''
        $base.Executed = $false
        $base.Stdout = ''; $base.Stderr = $_.Exception.Message; $base.DurationMs = 0
        $base.Attempts = 0
        $record = [pscustomobject]$base
        [void]$results.Add($record)
        & $invokeCallback $record
      }
      finally { $p.Pipe.Dispose() }
    }
  }
  finally {
    $pool.Close(); $pool.Dispose()
  }

  $sortedResults = @($results | Sort-Object -Property { [int]$_.TaskId })
  Microsoft.PowerShell.Utility\Export-Clixml -InputObject $sortedResults -LiteralPath $ResultsXml

  $nonFailureSet = @{}
  foreach ($s in $NonFailureStatuses) { $nonFailureSet[$s] = $true }
  $failedList = @($sortedResults | Where-Object { $_.Exit -ne 0 -and -not $nonFailureSet.ContainsKey([string]$_.Status) })
  $failedCount = $failedList.Count
  $okCount     = $sortedResults.Count - $failedCount
  Write-Host "DONE total=$($sortedResults.Count) ok=$okCount failed=$failedCount"
  if ($failedCount -gt 0) {
    Write-Host 'Failures:'
    foreach ($f in $failedList) {
      $keyVal = if ($f.PSObject.Properties[$KeyField]) { $f.$KeyField } else { $f.TaskId }
      Write-Host ("  [{0}] {1} :: {2}" -f $f.Exit, $keyVal, $f.Status)
    }
    return 1
  }
  return 0
}
