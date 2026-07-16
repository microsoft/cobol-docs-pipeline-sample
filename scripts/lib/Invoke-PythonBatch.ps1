# PS5.1 + PS7-compatible parallel runner used by the *_batch.ps1 wrappers.
# Replaces `ForEach-Object -ThrottleLimit N -Parallel { ... }` (PS7-only) with
# a RunspacePool fan-out that runs identically under Windows PowerShell 5.1.
#
# Key contract:
#  - $BuildArgs / $BuildResult scriptblocks are serialized to text and re-parsed
#    inside the worker runspace, so they do NOT carry their original session
#    state. Any caller-scope variables they reference must be passed explicitly
#    via -Variables; those entries are injected into each worker's session state.
#  - If a worker throws or produces no output, a synthetic failure row is emitted
#    (Exit=-1) so the caller's $failed filter cannot silently miss drops.
#  - $collected.Count is guaranteed to equal $Entries.Count on return.

function Invoke-PythonBatch {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [object[]]$Entries,
    [Parameter(Mandatory)] [scriptblock]$BuildArgs,
    [scriptblock]$BuildResult,
    [hashtable]$Variables,
    [int]$Throttle = [Environment]::ProcessorCount
  )

  if (-not $BuildResult) {
    $BuildResult = {
      param($entry, $exitCode, $stdout, $stderr)
      [pscustomobject]@{
        Path   = $entry.Path
        Exit   = $exitCode
        Stdout = $stdout
        Stderr = $stderr
      }
    }
  }

  # Serialize scriptblocks to text so they get re-parsed in the worker runspace
  # and bind to THAT runspace's session state (where -Variables are injected).
  $buildArgsText   = $BuildArgs.ToString()
  $buildResultText = $BuildResult.ToString()

  $worker = {
    param($entry, $buildArgsText, $buildResultText)
    $buildArgs   = [scriptblock]::Create($buildArgsText)
    $buildResult = [scriptblock]::Create($buildResultText)
    $argv = @(& $buildArgs $entry)
    $errFile = New-TemporaryFile
    $outFile = New-TemporaryFile
    try {
      # Invoke via the call operator + splatting instead of
      # `Start-Process -ArgumentList`. Under Windows PowerShell 5.1,
      # Start-Process -ArgumentList mis-binds array elements when one of the
      # arguments is a rooted Windows path (e.g. C:\...), failing with
      # "Cannot convert '<value>' to the type 'System.String' required by
      # parameter 'ArgumentList'". `& python @argv` passes each element as a
      # discrete native argument correctly under both PS 5.1 and PS 7.
      & python @argv 1>$outFile.FullName 2>$errFile.FullName
      $exitCode = $LASTEXITCODE
      $stdout = Get-Content -Raw -LiteralPath $outFile.FullName
      $stderr = Get-Content -Raw -LiteralPath $errFile.FullName
      return (& $buildResult $entry $exitCode $stdout $stderr)
    }
    finally {
      Remove-Item -Force -LiteralPath $errFile.FullName, $outFile.FullName -ErrorAction SilentlyContinue
    }
  }

  $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
  if ($Variables) {
    foreach ($key in $Variables.Keys) {
      $entry = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry `
        -ArgumentList $key, $Variables[$key], $null
      $iss.Variables.Add($entry)
    }
  }

  $pool = [runspacefactory]::CreateRunspacePool(1, [int]$Throttle, $iss, $Host)
  $pool.ApartmentState = 'MTA'
  $pool.Open()

  $collected = New-Object System.Collections.Generic.List[object]
  try {
    $pending = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $Entries) {
      $ps = [powershell]::Create()
      $ps.RunspacePool = $pool
      [void]$ps.AddScript($worker).AddArgument($entry).AddArgument($buildArgsText).AddArgument($buildResultText)
      $pending.Add([pscustomobject]@{ Entry = $entry; Pipe = $ps; Async = $ps.BeginInvoke() })
    }
    foreach ($p in $pending) {
      $produced = $false
      try {
        $output = $p.Pipe.EndInvoke($p.Async)
        foreach ($item in $output) {
          if ($null -ne $item) { [void]$collected.Add($item); $produced = $true }
        }
        foreach ($err in $p.Pipe.Streams.Error) {
          [Console]::Error.WriteLine(("RUNSPACE ERROR ({0}): {1}" -f $p.Entry.Path, $err))
        }
        if (-not $produced) {
          $errText = ($p.Pipe.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n"
          if (-not $errText) { $errText = 'worker returned no output' }
          [void]$collected.Add((& $BuildResult $p.Entry -1 '' $errText))
        }
      }
      catch {
        $msg = $_.Exception.Message
        [Console]::Error.WriteLine(("RUNSPACE EXCEPTION ({0}): {1}" -f $p.Entry.Path, $msg))
        [void]$collected.Add((& $BuildResult $p.Entry -1 '' $msg))
      }
      finally { $p.Pipe.Dispose() }
    }
  }
  finally {
    $pool.Close()
    $pool.Dispose()
  }

  if ($collected.Count -ne $Entries.Count) {
    [Console]::Error.WriteLine(
      ("Invoke-PythonBatch: collected={0} expected={1}" -f $collected.Count, $Entries.Count))
  }

  return ,$collected.ToArray()
}
