param(
  [string]$ScriptPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "scripts\inventory-project.ps1")
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
  $root = Join-Path ([System.IO.Path]::GetTempPath()) ("inventory-project-test-" + [System.Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  return $root
}

function Invoke-Inventory {
  param(
    [string]$ProjectPath,
    [string]$PathOverride = $null
  )
  $output = Join-Path $ProjectPath "inventory.json"
  $oldPath = $env:PATH
  try {
    if ($null -ne $PathOverride) {
      $env:PATH = $PathOverride
    } else {
      $env:PATH = (($env:PATH -split ';') | Where-Object { $_ -notlike '*OpenAI.Codex*' }) -join ';'
    }
    & $ScriptPath -ProjectPath $ProjectPath -OutputJson $output | Out-Null
  } finally {
    $env:PATH = $oldPath
  }
  return (Get-Content -Raw -LiteralPath $output -Encoding UTF8 | ConvertFrom-Json)
}

$tests = @()

$tests += @{
  Name = "includes PowerShell source files"
  Run = {
    $project = New-TestProject
    try {
      New-Item -ItemType Directory -Force -Path (Join-Path $project "scripts") | Out-Null
      [System.IO.File]::WriteAllText((Join-Path $project "scripts\tool.ps1"), "Write-Output 'ok'`n", [System.Text.UTF8Encoding]::new($false))
      $inventory = Invoke-Inventory -ProjectPath $project
      $sourcePaths = @($inventory.sourceFiles | ForEach-Object { [string]$_.path })
      $languages = @($inventory.languageStats | ForEach-Object { [string]$_.language })
      Assert-True ($sourcePaths -contains "scripts\tool.ps1") ".ps1 file was not included in sourceFiles."
      Assert-True ($languages -contains "PowerShell") "PowerShell language bucket was not reported."
    } finally {
      if (Test-Path -LiteralPath $project) { Remove-Item -LiteralPath $project -Recurse -Force }
    }
  }
}

$tests += @{
  Name = "falls back when rg exists but fails"
  Run = {
    $project = New-TestProject
    $fakeBin = Join-Path $project "fake-bin"
    try {
      New-Item -ItemType Directory -Force -Path $fakeBin | Out-Null
      [System.IO.File]::WriteAllText((Join-Path $project "README.md"), "fallback marker`n", [System.Text.UTF8Encoding]::new($false))
      [System.IO.File]::WriteAllText((Join-Path $fakeBin "rg.cmd"), "@echo off`r`nexit /b 1`r`n", [System.Text.UTF8Encoding]::new($false))
      $pathWithoutCodexRg = (($env:PATH -split ';') | Where-Object { $_ -notlike '*OpenAI.Codex*' }) -join ';'
      $inventory = Invoke-Inventory -ProjectPath $project -PathOverride ($fakeBin + ";" + $pathWithoutCodexRg)
      $sourcePaths = @($inventory.sourceFiles | ForEach-Object { [string]$_.path })
      Assert-True ($sourcePaths -contains "README.md") "inventory did not fall back to Get-ChildItem when rg failed."
    } finally {
      if (Test-Path -LiteralPath $project) { Remove-Item -LiteralPath $project -Recurse -Force }
    }
  }
}

$tests += @{
  Name = "preserves UTF-8 Chinese evidence text"
  Run = {
    $project = New-TestProject
    try {
      $text = "$([char]0x9ED8)$([char]0x8BA4) fallback $([char]0x5E94)$([char]0x8BE5)$([char]0x4FDD)$([char]0x7559)$([char]0x4E2D)$([char]0x6587)$([char]0x8BC1)$([char]0x636E)`n"
      $expected = $text.Trim()
      [System.IO.File]::WriteAllText((Join-Path $project "notes.md"), $text, [System.Text.UTF8Encoding]::new($false))
      $inventory = Invoke-Inventory -ProjectPath $project
      $examples = @($inventory.riskHints | ForEach-Object { $_.examples } | ForEach-Object { $_ })
      $matched = $false
      foreach ($example in $examples) {
        if ([string]$example.text -like "*$expected*") {
          $matched = $true
        }
      }
      Assert-True $matched "UTF-8 Chinese evidence text was not preserved in riskHints."
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
  throw "$($failures.Count) inventory-project test(s) failed."
}
