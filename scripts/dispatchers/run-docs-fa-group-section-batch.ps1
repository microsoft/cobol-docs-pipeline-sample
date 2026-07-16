#requires -Version 5.1
<#
.SYNOPSIS
  Per-section Copilot dispatch wrapper for phase K (group functional analysis).

.DESCRIPTION
  No-op in the simplified single-call (phase-I style) implementation: the
  whole group functional-analysis doc is authored by the per-group finalizer
  in one Copilot call, so there are no intermediate per-section drafts to
  dispatch. Kept as a wired step so the phase-K wrapper's stage -> section ->
  finalize sequence stays intact. Writes an empty results XML and exits 0.
#>
[CmdletBinding()]
param(
  [string]$Manifest = 'config/grouping.yaml',
  [int]$Throttle = 15,
  [string]$Languages = 'en',
  [string]$Agent = 'functional-analysis-group-writer',
  [string]$ResultsXml = 'temp/copilot_fa_group_section_results.xml',
  [switch]$DryRun,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
Write-Host 'run-docs-fa-group-section-batch: simplified single-call mode — no per-section dispatch (no-op).'
@() | Export-Clixml -LiteralPath $ResultsXml
exit 0
