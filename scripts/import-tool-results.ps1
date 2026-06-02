param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath,

  [string]$Tool = "auto",
  [string]$OutputJson = ""
)

$ErrorActionPreference = "Stop"

function Get-Prop {
  param(
    [AllowNull()][object]$Object,
    [string]$Name,
    [AllowNull()][object]$Default = ""
  )
  if ($null -eq $Object) { return $Default }
  if ($Object.PSObject.Properties[$Name]) { return $Object.$Name }
  return $Default
}

function Get-Array {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return $Value }
  return @($Value)
}

function Convert-Severity {
  param([string]$Level)
  switch -Regex ($Level.ToLowerInvariant()) {
    "error|critical|high" { return "高" }
    "warning|warn|medium" { return "中" }
    "note|info|low" { return "低" }
    default { return "待复核" }
  }
}

function New-ImportedFinding {
  param(
    [string]$RuleId,
    [string]$Title,
    [string]$Severity,
    [string]$Location,
    [string]$Evidence,
    [string]$Source
  )
  return [ordered]@{
    ruleId = $RuleId
    title = $Title
    severity = $Severity
    dimension = "安全性"
    priority = if ($Severity -eq "高") { "P0" } elseif ($Severity -eq "中") { "P1" } else { "P3" }
    confidence = "中"
    confidenceReason = "由 $Source 工具结果导入，进入最终报告前需要人工复核误报。"
    location = $Location
    evidence = $Evidence
    impact = "工具识别到潜在风险，实际影响取决于输入来源、运行权限和部署配置。"
    recommendation = "结合源码上下文复核，并按工具规则说明修复。"
    source = "tool:$Source"
    status = "open"
  }
}

$fullPath = (Resolve-Path -LiteralPath $InputPath).Path
$text = Get-Content -Raw -LiteralPath $fullPath -Encoding UTF8
$json = $text | ConvertFrom-Json
$findings = New-Object System.Collections.Generic.List[object]

if ($Tool -eq "auto") {
  if ($json.PSObject.Properties["runs"]) { $Tool = "sarif" }
  elseif ($json.PSObject.Properties["results"]) { $Tool = "semgrep" }
  elseif ($json -is [System.Array] -or $json.PSObject.TypeNames[0] -match "Object\[\]") { $Tool = "gitleaks" }
}

if ($Tool -eq "sarif") {
  foreach ($run in (Get-Array $json.runs)) {
    $toolName = [string](Get-Prop (Get-Prop $run "tool") "driver").name
    foreach ($result in (Get-Array (Get-Prop $run "results" @()))) {
      $ruleId = [string](Get-Prop $result "ruleId" "SARIF")
      $message = [string](Get-Prop (Get-Prop $result "message") "text" $ruleId)
      $level = [string](Get-Prop $result "level" "warning")
      $location = ""
      $physical = Get-Prop (Get-Array (Get-Prop $result "locations" @()) | Select-Object -First 1) "physicalLocation"
      if ($physical) {
        $artifact = Get-Prop $physical "artifactLocation"
        $region = Get-Prop $physical "region"
        $uri = Get-Prop $artifact "uri"
        $startLine = Get-Prop $region "startLine" ""
        $location = "${uri}:$startLine"
      }
      $findings.Add((New-ImportedFinding -RuleId $ruleId -Title $message -Severity (Convert-Severity $level) -Location $location -Evidence $message -Source $toolName)) | Out-Null
    }
  }
} elseif ($Tool -eq "semgrep") {
  foreach ($result in (Get-Array (Get-Prop $json "results" @()))) {
    $extra = Get-Prop $result "extra"
    $metadata = Get-Prop $extra "metadata"
    $severity = Convert-Severity ([string](Get-Prop $extra "severity" "warning"))
    $path = Get-Prop $result "path"
    $startLine = Get-Prop (Get-Prop $result "start") "line" ""
    $location = "${path}:$startLine"
    $title = [string](Get-Prop $extra "message" (Get-Prop $result "check_id"))
    $finding = New-ImportedFinding -RuleId ([string](Get-Prop $result "check_id" "semgrep")) -Title $title -Severity $severity -Location $location -Evidence $title -Source "semgrep"
    $finding.Add("cwe", [string]((Get-Array (Get-Prop $metadata "cwe" @())) -join ", "))
    $finding.Add("owasp", [string]((Get-Array (Get-Prop $metadata "owasp" @())) -join ", "))
    $findings.Add($finding) | Out-Null
  }
} elseif ($Tool -eq "gitleaks") {
  foreach ($leak in (Get-Array $json)) {
    $file = Get-Prop $leak "File"
    $startLine = Get-Prop $leak "StartLine" ""
    $location = "${file}:$startLine"
    $title = "疑似密钥泄露：$(Get-Prop $leak "RuleID" "gitleaks")"
    $findings.Add((New-ImportedFinding -RuleId ([string](Get-Prop $leak "RuleID" "gitleaks")) -Title $title -Severity "高" -Location $location -Evidence ([string](Get-Prop $leak "Description" $title)) -Source "gitleaks")) | Out-Null
  }
} else {
  throw "不支持的工具结果类型：$Tool"
}

$result = [ordered]@{
  source = $fullPath
  tool = $Tool
  importedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  findings = @($findings)
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
  $outputFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputJson)
  $outputDir = Split-Path -Parent $outputFullPath
  if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
  }
  [System.IO.File]::WriteAllText($outputFullPath, ($result | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
}

$result | ConvertTo-Json -Depth 10
