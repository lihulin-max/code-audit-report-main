param(
  [string]$ProjectPath = ".",
  [string]$OutputDir = "",
  [string]$ProjectName = "",
  [string]$DiffBase = "origin/main",
  [string]$DiffTarget = "HEAD",
  [string]$ConfigPath = "",
  [string]$BaselinePath = "",
  [int]$MinScore = 0,
  [switch]$FailOnHigh,
  [switch]$RedactReport,
  [switch]$SkipExternalTools
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$runAudit = Join-Path $scriptDir "run-audit.ps1"

$params = @{
  ProjectPath = $ProjectPath
  ChangedOnly = $true
  DiffBase = $DiffBase
  DiffTarget = $DiffTarget
}
if (-not [string]::IsNullOrWhiteSpace($OutputDir)) { $params.OutputDir = $OutputDir }
if (-not [string]::IsNullOrWhiteSpace($ProjectName)) { $params.ProjectName = $ProjectName }
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { $params.ConfigPath = $ConfigPath }
if (-not [string]::IsNullOrWhiteSpace($BaselinePath)) { $params.BaselinePath = $BaselinePath }
if ($MinScore -gt 0) { $params.MinScore = $MinScore }
if ($FailOnHigh) { $params.FailOnHigh = $true }
if ($RedactReport) { $params.RedactReport = $true }
if ($SkipExternalTools) { $params.SkipExternalTools = $true }

& $runAudit @params
exit $LASTEXITCODE
