param(
  [string]$ScriptPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "scripts\run-audit.ps1")
)

$ErrorActionPreference = "Stop"

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )
  if (-not $Condition) {
    throw $Message
  }
}

function New-TestProject {
  $root = Join-Path ([System.IO.Path]::GetTempPath()) ("run-audit-test-" + [System.Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root "scripts") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root "tests") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $root "tests\sample.tests.ps1"), "Write-Output 'test placeholder'`n", [System.Text.UTF8Encoding]::new($false))
  return $root
}

function Invoke-TestAudit {
  param(
    [string]$ProjectPath,
    [switch]$ConstrainPath
  )
  $out = Join-Path $ProjectPath "audit-output"
  $oldPath = $env:PATH
  try {
    if ($ConstrainPath) {
      $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    }
    & $ScriptPath -ProjectPath $ProjectPath -OutputDir $out | Out-Null
  } finally {
    $env:PATH = $oldPath
  }
  return (Get-Content -Raw -LiteralPath (Join-Path $out "$(Split-Path -Leaf $ProjectPath).audit.json") -Encoding UTF8 | ConvertFrom-Json)
}

$tests = @()

$tests += @{
  Name = "audits PowerShell execution and numeric boundaries"
  Run = {
    $project = New-TestProject
    try {
      $script = @'
param([string]$Command, [string]$Value)
Invoke-Expression $Command
$trimmed = $Value.Substring(1, $Value.Length - 2) # 默认中文证据
'@
      [System.IO.File]::WriteAllText((Join-Path $project "scripts\bad.ps1"), $script, [System.Text.UTF8Encoding]::new($false))
      $report = Invoke-TestAudit -ProjectPath $project -ConstrainPath
      $ruleIds = @($report.findings | ForEach-Object { [string]$_.ruleId })
      Assert-True ($ruleIds -contains "GEN-SEC-EXEC-001") "PowerShell dynamic execution was not reported."
      Assert-True ($ruleIds -contains "NUM-004-INDEX-SLICE-UNDERFLOW") "Numeric boundary substring underflow risk was not reported."
      $numericEvidence = [string](($report.findings | Where-Object { $_.ruleId -eq "NUM-004-INDEX-SLICE-UNDERFLOW" } | Select-Object -First 1).evidence)
      Assert-True ($numericEvidence -like "*默认中文证据*") "UTF-8 Chinese evidence was not preserved in run-audit findings."
    } finally {
      if (Test-Path -LiteralPath $project) { Remove-Item -LiteralPath $project -Recurse -Force }
    }
  }
}

$tests += @{
  Name = "reports missing key tools and avoids hardcoded conclusion"
  Run = {
    $project = New-TestProject
    try {
      [System.IO.File]::WriteAllText((Join-Path $project "scripts\plain.ps1"), "Write-Output 'ok'`n", [System.Text.UTF8Encoding]::new($false))
      $report = Invoke-TestAudit -ProjectPath $project -ConstrainPath
      $ruleIds = @($report.findings | ForEach-Object { [string]$_.ruleId })
      Assert-True ($ruleIds -contains "GEN-TOOL-COVERAGE-001") "Missing key audit tools did not produce a finding."
      Assert-True ([int]$report.summary.score -lt 100) "Missing key audit tools did not affect the score."
      Assert-True (-not ([string]$report.summary.conclusion).Contains("AT 命令")) "Conclusion still contains hardcoded C++/embedded risk text."
    } finally {
      if (Test-Path -LiteralPath $project) { Remove-Item -LiteralPath $project -Recurse -Force }
    }
  }
}

$failures = New-Object System.Collections.Generic.List[object]
foreach ($test in $tests) {
  try {
    & $test.Run
    Write-Output "PASS $($test.Name)"
  } catch {
    Write-Output "FAIL $($test.Name): $($_.Exception.Message)"
    $failures.Add($test.Name) | Out-Null
  }
}

if ($failures.Count -gt 0) {
  throw "$($failures.Count) run-audit test(s) failed."
}
