#requires -Version 5.1
<#
.SYNOPSIS
  Deterministic Markdown -> DOCX conversion helper (pandoc, plain default
  styling).

.DESCRIPTION
  Thin wrapper around `pandoc` used by phases L/M to emit a Word edition of
  each authored technical-analysis.md. No reference-doc is supplied, so
  pandoc applies its built-in default Word styling. The function is
  idempotent and resume-aware: it skips conversion when the .docx is newer
  than its .md source unless -Force is given.

  Dot-source this file and call Convert-MdToDocx (single file) or
  Invoke-MdToDocxBatch (many files).
#>

function Test-PandocAvailable {
  [CmdletBinding()]
  param([string]$PandocPath = 'pandoc')
  $cmd = Get-Command $PandocPath -ErrorAction SilentlyContinue
  return [bool]$cmd
}

function Test-UnusedFootnotes {
  <#
  .SYNOPSIS
    Validate that all footnote definitions in a Markdown file are referenced.
  .DESCRIPTION
    Scans the Markdown file for footnote definitions ([^key]: ...) and
    verifies that each key is referenced somewhere in the document body
    using [^key]. Returns $true if all footnotes are used, $false if any
    are unused. Unused footnotes cause Pandoc warnings and should be
    removed from the source.
  .PARAMETER MarkdownPath
    Absolute or repo-relative path to the .md file.
  .OUTPUTS
    [pscustomobject] with properties:
    - Valid: [bool] - true if all footnotes are referenced
    - UnusedKeys: [string[]] - array of unused footnote keys (empty if valid)
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory)] [string]$MarkdownPath)

  if (-not (Test-Path -LiteralPath $MarkdownPath)) {
    return [pscustomobject]@{ Valid = $false; UnusedKeys = @("error: file not found") }
  }

  $content = Get-Content -Raw -LiteralPath $MarkdownPath -Encoding UTF8
  
  # Find all footnote definitions: [^key]: at start of line or after whitespace
  # This pattern matches the actual pandoc footnote syntax
  $definitions = [regex]::Matches(
    $content, 
    '\n\[\^([^\]]+)\]:[ \t]',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
  )
  
  # Also check for definitions at the very start of file
  if ($content -match '^\[\^([^\]]+)\]:[ \t]') {
    $startDef = [regex]::Match($content, '^\[\^([^\]]+)\]:[ \t]')
    if ($startDef.Success -and -not ($definitions | Where-Object { $_.Groups[1].Value -eq $startDef.Groups[1].Value })) {
      $definitions = @($definitions) + @($startDef)
    }
  }
  
  # Find all footnote references: [^key] that are NOT definitions.
  # A definition is [^key]: (followed by a colon), so the negative lookahead
  # (?!:) excludes definition lines from being counted as references. Without
  # this, every definition would count as a reference to itself and no unused
  # footnote would ever be detected.
  $references = [regex]::Matches($content, '\[\^([^\]]+)\](?!:)')
  
  $definedKeys = @($definitions | ForEach-Object { $_.Groups[1].Value })
  $referencedKeys = @($references | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
  
  # Find keys that are defined but never referenced
  $unusedKeys = @($definedKeys | Where-Object { $_ -notin $referencedKeys })
  
  return [pscustomobject]@{
    Valid = ($unusedKeys.Count -eq 0)
    UnusedKeys = $unusedKeys
  }
}

function Test-DuplicateFootnotes {
  <#
  .SYNOPSIS
    Detect duplicate footnote definitions in a Markdown file.
  .DESCRIPTION
    Scans the Markdown file for footnote definitions ([^key]: ...) and
    identifies any keys that are defined more than once. Pandoc will reject
    documents with duplicate footnote keys. Returns $true if all keys are
    unique, $false if duplicates found.
  .PARAMETER MarkdownPath
    Absolute or repo-relative path to the .md file.
  .OUTPUTS
    [pscustomobject] with properties:
    - Valid: [bool] - true if all footnote keys are unique
    - DuplicateKeys: [hashtable] - key->count mapping for duplicates
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory)] [string]$MarkdownPath)

  if (-not (Test-Path -LiteralPath $MarkdownPath)) {
    return [pscustomobject]@{ Valid = $false; DuplicateKeys = @{} }
  }

  $content = Get-Content -Raw -LiteralPath $MarkdownPath -Encoding UTF8
  
  # Find all footnote definitions: [^key]: at start of line or after whitespace
  $definitions = [regex]::Matches(
    $content, 
    '\n\[\^([^\]]+)\]:[ \t]',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
  )
  
  # Also check for definitions at the very start of file
  if ($content -match '^\[\^([^\]]+)\]:[ \t]') {
    $startDef = [regex]::Match($content, '^\[\^([^\]]+)\]:[ \t]')
    if ($startDef.Success -and -not ($definitions | Where-Object { $_.Groups[1].Value -eq $startDef.Groups[1].Value })) {
      $definitions = @($definitions) + @($startDef)
    }
  }
  
  # Count occurrences of each key
  $keyCounts = @{}
  foreach ($def in $definitions) {
    $key = $def.Groups[1].Value
    $keyCounts[$key] = [int]$keyCounts[$key] + 1
  }
  
  # Find keys with count > 1
  $duplicates = @{}
  foreach ($key in $keyCounts.Keys) {
    if ($keyCounts[$key] -gt 1) {
      $duplicates[$key] = $keyCounts[$key]
    }
  }
  
  return [pscustomobject]@{
    Valid = ($duplicates.Count -eq 0)
    DuplicateKeys = $duplicates
  }
}

function Remove-DuplicateFootnotes {
  <#
  .SYNOPSIS
    Remove duplicate footnote definitions, keeping only the first occurrence.
  .DESCRIPTION
    Finds all footnote keys that are defined more than once and removes
    all but the first definition. Updates the file in-place. Returns the
    count of removed duplicate footnotes and a list of affected keys.
  .PARAMETER MarkdownPath
    Absolute or repo-relative path to the .md file.
  .OUTPUTS
    [pscustomobject] with properties:
    - RemovedCount: [int] - number of duplicate footnote definitions removed
    - RemovedKeys: [string[]] - array of keys that had duplicates removed
    - Modified: [bool] - true if the file was modified
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory)] [string]$MarkdownPath)

  if (-not (Test-Path -LiteralPath $MarkdownPath)) {
    return [pscustomobject]@{ RemovedCount = 0; RemovedKeys = @(); Modified = $false }
  }

  $validation = Test-DuplicateFootnotes -MarkdownPath $MarkdownPath
  if ($validation.Valid) {
    return [pscustomobject]@{ RemovedCount = 0; RemovedKeys = @(); Modified = $false }
  }

  $lines = @(Get-Content -LiteralPath $MarkdownPath -Encoding UTF8)
  $seenKeys = @{}  # Tracks keys we've already kept (first occurrence)
  $removedKeys = @()
  $totalRemoved = 0
  
  # Process lines and remove duplicate footnote definitions
  $newLines = New-Object System.Collections.Generic.List[string]
  $skipUntilNextDef = $false

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    
    # Check if this line starts a footnote definition
    if ($line -match '^\[\^([^\]]+)\]:') {
      $key = $matches[1]
      
      if ($seenKeys.ContainsKey($key)) {
        # This is a duplicate definition, start skipping it
        $skipUntilNextDef = $true
        if ($removedKeys -notcontains $key) {
          $removedKeys += $key
        }
        $totalRemoved++
        continue
      } else {
        # First occurrence of this key, keep it
        $seenKeys[$key] = $true
        $skipUntilNextDef = $false
        $newLines.Add($line)
      }
    }
    elseif ($skipUntilNextDef) {
      # Continue skipping continuation lines of the duplicate footnote
      # (lines that start with spaces/tabs, or blank lines before the next definition)
      if ($line -match '^\s' -or $line -match '^\s*$') {
        $totalRemoved++
        continue
      } else {
        # We've hit a non-continuation line, stop skipping
        $skipUntilNextDef = $false
        $newLines.Add($line)
      }
    } else {
      # Normal line, keep it
      $newLines.Add($line)
    }
  }

  if ($totalRemoved -gt 0) {
    # Write back the modified content
    $newLines | Set-Content -LiteralPath $MarkdownPath -Encoding UTF8
  }

  return [pscustomobject]@{
    RemovedCount = $totalRemoved
    RemovedKeys = $removedKeys
    Modified = $totalRemoved -gt 0
  }
}

function Remove-UnusedFootnotes {
  <#
  .SYNOPSIS
    Remove unused footnote definitions from a Markdown file.
  .DESCRIPTION
    Finds all footnote definitions that are not referenced in the document
    and removes them. Updates the file in-place. Returns the count of 
    removed footnotes and a list of removed keys.
  .PARAMETER MarkdownPath
    Absolute or repo-relative path to the .md file.
  .OUTPUTS
    [pscustomobject] with properties:
    - RemovedCount: [int] - number of footnote definitions removed
    - RemovedKeys: [string[]] - array of removed footnote keys
    - Modified: [bool] - true if the file was modified
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory)] [string]$MarkdownPath)

  if (-not (Test-Path -LiteralPath $MarkdownPath)) {
    return [pscustomobject]@{ RemovedCount = 0; RemovedKeys = @(); Modified = $false }
  }

  $validation = Test-UnusedFootnotes -MarkdownPath $MarkdownPath
  if ($validation.Valid) {
    return [pscustomobject]@{ RemovedCount = 0; RemovedKeys = @(); Modified = $false }
  }

  $lines = @(Get-Content -LiteralPath $MarkdownPath -Encoding UTF8)
  $originalCount = $lines.Count
  $removedKeys = @()
  
  # Build set of unused keys for quick lookup
  $unusedKeySet = @{}
  foreach ($key in $validation.UnusedKeys) {
    $unusedKeySet[$key] = $true
  }

  # Process lines and remove footnote definitions that are unused
  $newLines = New-Object System.Collections.Generic.List[string]
  $skipUntilNextDef = $false
  $currentUnusedKey = $null

  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    
    # Check if this line starts a footnote definition
    if ($line -match '^\[\^([^\]]+)\]:') {
      $key = $matches[1]
      
      if ($unusedKeySet.ContainsKey($key)) {
        # Start skipping this unused footnote definition
        $skipUntilNextDef = $true
        $currentUnusedKey = $key
        $removedKeys += $key
        continue
      } else {
        # This is a used footnote, stop skipping if we were
        $skipUntilNextDef = $false
        $newLines.Add($line)
      }
    }
    elseif ($skipUntilNextDef) {
      # Continue skipping continuation lines of the unused footnote
      # (lines that start with spaces/tabs, or blank lines before the next definition)
      if ($line -match '^\s' -or $line -match '^\s*$') {
        # This is a continuation line of the unused footnote, skip it
        continue
      } else {
        # We've hit a non-continuation line, stop skipping
        $skipUntilNextDef = $false
        $newLines.Add($line)
      }
    } else {
      # Normal line, keep it
      $newLines.Add($line)
    }
  }

  if ($removedKeys.Count -gt 0) {
    # Write back the modified content
    $newLines | Set-Content -LiteralPath $MarkdownPath -Encoding UTF8
  }

  return [pscustomobject]@{
    RemovedCount = $removedKeys.Count
    RemovedKeys = $removedKeys
    Modified = $removedKeys.Count -gt 0
  }
}

function Convert-MdToDocx {
  <#
  .SYNOPSIS
    Convert one Markdown file to DOCX via pandoc.
  .PARAMETER MarkdownPath
    Absolute or repo-relative path to the source .md.
  .PARAMETER OutputPath
    Optional explicit .docx path. Defaults to the .md path with a .docx
    extension.
  .PARAMETER PandocPath
    pandoc executable. Default 'pandoc'.
  .PARAMETER ReferenceDoc
    Optional reference .docx for styling. Omitted -> pandoc default styling.
  .PARAMETER Force
    Re-convert even when the .docx is newer than the .md.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$MarkdownPath,
    [string]$OutputPath,
    [string]$PandocPath = 'pandoc',
    [string]$ReferenceDoc,
    [switch]$Force
  )

  if (-not (Test-Path -LiteralPath $MarkdownPath)) {
    return [pscustomobject]@{
      MarkdownPath = $MarkdownPath; OutputPath = $OutputPath
      Status = 'missing-source'; Exit = -2; Stderr = "source not found: $MarkdownPath"
    }
  }

  # Validate footnotes before attempting conversion
  $duplicateCheck = Test-DuplicateFootnotes -MarkdownPath $MarkdownPath
  if (-not $duplicateCheck.Valid) {
    $duplicateList = ($duplicateCheck.DuplicateKeys.Keys -join ', ')
    return [pscustomobject]@{
      MarkdownPath = $MarkdownPath; OutputPath = $OutputPath
      Status = 'duplicate-footnotes-found'
      Exit = -4
      Stderr = "Duplicate footnote definitions found (remove duplicates from source): $duplicateList"
    }
  }

  $footnoteCheck = Test-UnusedFootnotes -MarkdownPath $MarkdownPath
  if (-not $footnoteCheck.Valid) {
    $unusedList = $footnoteCheck.UnusedKeys -join ', '
    return [pscustomobject]@{
      MarkdownPath = $MarkdownPath; OutputPath = $OutputPath
      Status = 'footnote-validation-failed'
      Exit = -3
      Stderr = "Unused footnote definitions found (remove from source): $unusedList"
    }
  }

  if (-not $OutputPath) {
    $OutputPath = [System.IO.Path]::ChangeExtension($MarkdownPath, '.docx')
  }

  if (-not $Force -and (Test-Path -LiteralPath $OutputPath)) {
    $srcStamp = (Get-Item -LiteralPath $MarkdownPath).LastWriteTimeUtc
    $dstStamp = (Get-Item -LiteralPath $OutputPath).LastWriteTimeUtc
    if ($dstStamp -ge $srcStamp) {
      return [pscustomobject]@{
        MarkdownPath = $MarkdownPath; OutputPath = $OutputPath
        Status = 'skipped-up-to-date'; Exit = 0; Stderr = ''
      }
    }
  }

  $outDir = Split-Path -Parent $OutputPath
  if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
  }

  $argv = @($MarkdownPath, '--from', 'markdown', '--to', 'docx', '--output', $OutputPath)
  if ($ReferenceDoc) {
    if (Test-Path -LiteralPath $ReferenceDoc) {
      $argv += @('--reference-doc', $ReferenceDoc)
    } else {
      Write-Warning "Reference doc not found, using pandoc default styling: $ReferenceDoc"
    }
  }

  # Redirect pandoc's stderr to a temp file rather than merging it into the
  # success stream with 2>&1. Pandoc emits benign warnings (e.g. an unused
  # footnote key) to stderr while still exiting 0; under a caller's
  # $ErrorActionPreference='Stop' a merged native stderr line is promoted to a
  # terminating NativeCommandError and aborts the phase. Capturing via a file
  # keeps warnings as plain text and lets the exit code decide success.
  $errFile = New-TemporaryFile
  try {
    & $PandocPath @argv 2>$errFile.FullName
    $code = $LASTEXITCODE
    $stderr = Get-Content -Raw -LiteralPath $errFile.FullName
  }
  finally {
    Remove-Item -Force -LiteralPath $errFile.FullName -ErrorAction SilentlyContinue
  }
  return [pscustomobject]@{
    MarkdownPath = $MarkdownPath; OutputPath = $OutputPath
    Status = if ($code -eq 0) { 'converted' } else { 'failed' }
    Exit = $code; Stderr = ($stderr | Out-String).Trim()
  }
}

function Invoke-MdToDocxBatch {
  <#
  .SYNOPSIS
    Convert many Markdown files to DOCX, returning one record per file.
  .DESCRIPTION
    Automatically removes duplicate and unused footnotes from each markdown
    file before conversion to prevent Pandoc errors. Conversion only proceeds
    after cleanup is complete.
  .PARAMETER MarkdownPaths
    The .md files to convert.
  .PARAMETER CleanupUnusedFootnotes
    If $true (default), automatically remove unused footnote definitions
    before conversion. If $false, validate but don't modify.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string[]]$MarkdownPaths,
    [string]$PandocPath = 'pandoc',
    [string]$ReferenceDoc,
    [switch]$Force,
    [bool]$CleanupUnusedFootnotes = $true
  )
  if (-not (Test-PandocAvailable -PandocPath $PandocPath)) {
    throw "pandoc executable not found on PATH ('$PandocPath'). Install pandoc to emit DOCX editions."
  }
  $results = New-Object System.Collections.Generic.List[object]
  foreach ($md in $MarkdownPaths) {
    # Pre-process: remove duplicate footnotes first (these cause Pandoc errors)
    $dupCleanup = Remove-DuplicateFootnotes -MarkdownPath $md
    if ($dupCleanup.RemovedCount -gt 0) {
      Write-Verbose "Removed $($dupCleanup.RemovedCount) duplicate footnote definition(s) from ${md}: $($dupCleanup.RemovedKeys -join ', ')"
    }

    # Pre-process: remove unused footnotes to prevent Pandoc warnings
    if ($CleanupUnusedFootnotes) {
      $cleanup = Remove-UnusedFootnotes -MarkdownPath $md
      if ($cleanup.RemovedCount -gt 0) {
        Write-Verbose "Removed $($cleanup.RemovedCount) unused footnote(s) from ${md}: $($cleanup.RemovedKeys -join ', ')"
      }
    }
    $results.Add((Convert-MdToDocx -MarkdownPath $md -PandocPath $PandocPath -ReferenceDoc $ReferenceDoc -Force:$Force))
  }
  return $results
}
