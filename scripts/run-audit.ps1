param(
  [string]$ProjectPath = ".",
  [string]$OutputDir = "",
  [string]$ProjectName = "",
  [string[]]$Languages = @(),
  [switch]$InstallMissing,
  [switch]$SkipToolBootstrap,
  [switch]$SkipExternalTools,
  [string]$Auditor = "Codex",
  [int]$MinScore = 0,
  [string]$ConfigPath = "",
  [switch]$ChangedOnly,
  [string]$DiffBase = "",
  [string]$DiffTarget = "HEAD",
  [string]$BaselinePath = "",
  [string]$ExportBaselinePath = "",
  [switch]$FailOnHigh,
  [switch]$RedactReport,
  [switch]$DisableSca,
  [switch]$DisableSbom
)

$ErrorActionPreference = "Stop"

function Test-Command {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $cmd) {
    return $false
  }
  $source = [string]$cmd.Source
  if ($source -like "*\Microsoft\WindowsApps\python.exe" -or $source -like "*\Microsoft\WindowsApps\python3.exe" -or $source -like "*\Microsoft\WindowsApps\py.exe") {
    return $false
  }
  return $true
}

function Get-RelativePath {
  param(
    [string]$BasePath,
    [string]$FullPath
  )
  $base = $BasePath.TrimEnd([char[]]@('\', '/'))
  if ($FullPath.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $FullPath.Substring($base.Length).TrimStart([char[]]@('\', '/'))
  }
  return $FullPath
}

function Get-Version {
  param(
    [string]$Name,
    [string[]]$Args = @("--version")
  )
  try {
    $output = & $Name @Args 2>&1 | Select-Object -First 2
    return (($output -join " ") -replace "\s+", " ").Trim()
  } catch {
    return ""
  }
}

function Convert-ConfigValue {
  param([string]$Value)
  $text = ([string]$Value).Trim()
  if ($text -eq "[]") { return @() }
  if ($text -eq '""' -or $text -eq "''") { return "" }
  if (($text.StartsWith('"') -and $text.EndsWith('"')) -or ($text.StartsWith("'") -and $text.EndsWith("'"))) {
    $text = $text.Substring(1, $text.Length - 2)
  }
  switch -Regex ($text) {
    "^(?i:true)$" { return $true }
    "^(?i:false)$" { return $false }
    "^-?\d+$" { return [int]$text }
    default { return $text }
  }
}

function Read-AuditConfig {
  param([string]$Path)
  $config = [ordered]@{}
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return $config
  }

  $section = ""
  $arrayKey = ""
  foreach ($rawLine in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
    $line = [string]$rawLine
    if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith("#")) {
      continue
    }
    $line = [regex]::Replace($line, '\s+#.*$', '')
    if ($line -match '^(\s*)([A-Za-z0-9_.-]+):\s*(.*)$') {
      $indent = $matches[1].Length
      $key = $matches[2]
      $value = $matches[3].Trim()
      if ($indent -eq 0) {
        if ([string]::IsNullOrWhiteSpace($value)) {
          $section = $key
          $arrayKey = ""
          if (-not $config.Contains($section)) {
            $config[$section] = [ordered]@{}
          }
        } else {
          $section = ""
          $arrayKey = ""
          $config[$key] = Convert-ConfigValue $value
        }
      } elseif (-not [string]::IsNullOrWhiteSpace($section)) {
        if ([string]::IsNullOrWhiteSpace($value)) {
          $config[$section][$key] = New-Object System.Collections.Generic.List[object]
          $arrayKey = $key
        } else {
          $config[$section][$key] = Convert-ConfigValue $value
          $arrayKey = ""
        }
      }
      continue
    }
    if ($line -match '^\s*-\s*(.+)$' -and -not [string]::IsNullOrWhiteSpace($section) -and -not [string]::IsNullOrWhiteSpace($arrayKey)) {
      $config[$section][$arrayKey].Add((Convert-ConfigValue $matches[1])) | Out-Null
    }
  }
  return $config
}

function Get-ConfigValue {
  param(
    [object]$Config,
    [string]$Path,
    [AllowNull()][object]$Default = $null
  )
  if ($null -eq $Config -or $Config.Count -eq 0) {
    return $Default
  }
  $parts = $Path.Split(".")
  $current = $Config
  foreach ($part in $parts) {
    if ($current -is [System.Collections.IDictionary] -and $current.Contains($part)) {
      $current = $current[$part]
    } elseif ($null -ne $current -and $current.PSObject.Properties[$part]) {
      $current = $current.$part
    } else {
      return $Default
    }
  }
  if ($current -is [System.Collections.Generic.List[object]]) {
    return @($current.ToArray())
  }
  return $current
}

function Get-ConfigBool {
  param(
    [object]$Config,
    [string]$Path,
    [bool]$Default = $false
  )
  $value = Get-ConfigValue -Config $Config -Path $Path -Default $Default
  if ($value -is [bool]) { return $value }
  return ([string]$value).ToLowerInvariant() -eq "true"
}

function New-ToolRecord {
  param(
    [string]$Name,
    [string]$Status,
    [string]$Command = "",
    [string]$Summary = "",
    [string]$Version = "",
    [int]$ExitCode = 0,
    [int]$DurationMs = 0,
    [string]$Output = ""
  )
  return [ordered]@{
    name = $Name
    version = $Version
    command = $Command
    status = $Status
    exitCode = $ExitCode
    durationMs = $DurationMs
    summary = $Summary
    output = $Output
  }
}

function Invoke-AuditCommand {
  param(
    [string]$Name,
    [string]$Command,
    [string[]]$Arguments,
    [string]$OutputPath = ""
  )
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $status = "success"
  $exitCode = 0
  $summary = ""
  try {
    $output = & $Command @Arguments 2>&1
    if ($null -ne $LASTEXITCODE) {
      $exitCode = $LASTEXITCODE
    }
    if ($exitCode -ne 0) {
      $status = "failed"
    }
    $summary = (($output | Select-Object -First 20) -join "`n").Trim()
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
      [System.IO.File]::WriteAllText($OutputPath, (($output -join "`n")), [System.Text.UTF8Encoding]::new($false))
    }
  } catch {
    $status = "failed"
    $exitCode = -1
    $summary = $_.Exception.Message
  }
  $sw.Stop()
  return [ordered]@{
    name = $Name
    version = if (Test-Command $Command) { Get-Version $Command } else { "" }
    command = "$Command $($Arguments -join ' ')"
    status = $status
    exitCode = $exitCode
    durationMs = [int]$sw.ElapsedMilliseconds
    summary = $summary
    output = $OutputPath
  }
}

function Find-LineMatches {
  param(
    [string]$Root,
    [array]$SourceFiles,
    [string[]]$Languages,
    [string]$Pattern,
    [int]$MaxExamples = 5,
    [switch]$IncludeTests
  )
  $regex = [regex]::new($Pattern)
  $results = New-Object System.Collections.Generic.List[object]
  foreach ($src in @($SourceFiles | Sort-Object { [string]$_.path })) {
    if ($Languages.Count -gt 0 -and -not ($Languages -contains [string]$src.language)) {
      continue
    }
    $relativePath = [string]$src.path
    if (-not $IncludeTests -and ($relativePath -match '(^|[\\/])(test|tests|__tests__)([\\/]|$)' -or (Split-Path -Leaf $relativePath) -match '(?i)(test|tests|spec)\.')) {
      continue
    }
    $full = Join-Path $Root ([string]$src.path)
    try {
      $lines = Get-Content -LiteralPath $full -Encoding UTF8 -ErrorAction Stop
    } catch {
      continue
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $text = [string]$lines[$i]
      $trimmed = $text.Trim()
      if ($trimmed.StartsWith("//") -or $trimmed.StartsWith("#")) {
        continue
      }
      if ($trimmed -match 'Find-LineMatches' -and $trimmed -match '-Pattern') {
        continue
      }
      if ($regex.IsMatch($text)) {
        $results.Add([ordered]@{
          location = "$($src.path):$($i + 1)"
          text = $trimmed
        }) | Out-Null
        if ($results.Count -ge $MaxExamples) {
          return @($results.ToArray())
        }
      }
    }
  }
  return @($results.ToArray())
}

function Format-Evidence {
  param([array]$Matches)
  return (($Matches | ForEach-Object { "$($_.location) => $($_.text)" }) -join "`n")
}

function Get-Array {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return $Value }
  return @($Value)
}

function Normalize-RepoPath {
  param([string]$Path)
  return ([string]$Path).Replace("\", "/").TrimStart("/")
}

function Get-GitChangedFiles {
  param(
    [string]$Root,
    [string]$Base,
    [string]$Target
  )
  $result = [ordered]@{
    enabled = $true
    available = $false
    base = $Base
    target = $Target
    files = @()
    reason = ""
  }
  if (-not (Test-Command "git")) {
    $result.reason = "未找到 git，无法执行增量审计。"
    return $result
  }
  try {
    $inside = & git -C $Root rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]$inside -ne "true") {
      $result.reason = "目标目录不是 Git 工作树，已回退为全量审计。"
      return $result
    }
    if ([string]::IsNullOrWhiteSpace($Target)) {
      $Target = "HEAD"
      $result.target = $Target
    }
    $args = @("-C", $Root, "diff", "--name-only", "--diff-filter=ACMR")
    if (-not [string]::IsNullOrWhiteSpace($Base)) {
      $args += "$Base...$Target"
    } else {
      $args += $Target
    }
    $files = & git @args 2>$null
    if ($LASTEXITCODE -ne 0) {
      $result.reason = "git diff 执行失败，已回退为全量审计。"
      return $result
    }
    $result.available = $true
    $result.files = @($files | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Normalize-RepoPath $_ })
    return $result
  } catch {
    $result.reason = $_.Exception.Message
    return $result
  }
}

function Apply-FindingBaseline {
  param(
    [array]$Findings,
    [string]$Path
  )
  $summary = [ordered]@{
    enabled = $false
    path = $Path
    matched = 0
    falsePositive = 0
    accepted = 0
    fixed = 0
    missing = 0
  }
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $summary
  }
  $summary.enabled = $true
  if (-not (Test-Path -LiteralPath $Path)) {
    $summary.missing = 1
    return $summary
  }
  $baseline = Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json
  $items = @{}
  foreach ($item in (Get-Array (Get-ConfigValue -Config $baseline -Path "items" -Default @()))) {
    $fp = [string](Get-ConfigValue -Config $item -Path "fingerprint" -Default "")
    if (-not [string]::IsNullOrWhiteSpace($fp)) {
      $items[$fp] = $item
    }
  }
  foreach ($finding in $Findings) {
    $fp = [string]$finding["fingerprint"]
    if ($items.ContainsKey($fp)) {
      $baselineItem = $items[$fp]
      $status = [string](Get-ConfigValue -Config $baselineItem -Path "status" -Default "")
      if (-not [string]::IsNullOrWhiteSpace($status)) {
        $finding["status"] = $status
      }
      $finding["baselineReason"] = [string](Get-ConfigValue -Config $baselineItem -Path "reason" -Default "")
      $finding["baselineOwner"] = [string](Get-ConfigValue -Config $baselineItem -Path "owner" -Default "")
      $summary.matched++
      switch ($status) {
        "false_positive" { $summary.falsePositive++ }
        "accepted" { $summary.accepted++ }
        "fixed" { $summary.fixed++ }
      }
    }
  }
  return $summary
}

function Export-FindingBaseline {
  param(
    [array]$Findings,
    [string]$Path
  )
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }
  $items = @($Findings | ForEach-Object {
      [ordered]@{
        fingerprint = $_["fingerprint"]
        ruleId = $_["ruleId"]
        title = $_["title"]
        location = $_["location"]
        status = "open"
        reason = ""
        owner = ""
      }
    })
  $baseline = [ordered]@{
    schemaVersion = "1.0"
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    items = $items
  }
  $outputFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
  $outputDir = Split-Path -Parent $outputFullPath
  if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
  }
  [System.IO.File]::WriteAllText($outputFullPath, ($baseline | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
}

function Get-ScaSummaryFromFile {
  param(
    [string]$Tool,
    [string]$Path
  )
  $summary = [ordered]@{
    tool = $Tool
    vulnerabilities = 0
    high = 0
    medium = 0
    low = 0
    licenses = 0
    output = $Path
  }
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return $summary
  }
  try {
    $json = Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json
    switch ($Tool) {
      "trivy" {
        foreach ($result in (Get-Array $json.Results)) {
          foreach ($vuln in (Get-Array $result.Vulnerabilities)) {
            $summary.vulnerabilities++
            switch -Regex ([string]$vuln.Severity) {
              "CRITICAL|HIGH" { $summary.high++ }
              "MEDIUM" { $summary.medium++ }
              "LOW" { $summary.low++ }
            }
          }
        }
      }
      "grype" {
        foreach ($match in (Get-Array $json.matches)) {
          $summary.vulnerabilities++
          switch -Regex ([string]$match.vulnerability.severity) {
            "Critical|High" { $summary.high++ }
            "Medium" { $summary.medium++ }
            "Low|Negligible" { $summary.low++ }
          }
        }
      }
      "osv-scanner" {
        foreach ($result in (Get-Array $json.results)) {
          foreach ($package in (Get-Array $result.packages)) {
            foreach ($vuln in (Get-Array $package.vulnerabilities)) {
              $summary.vulnerabilities++
            }
          }
        }
      }
    }
  } catch {
    $summary.note = "无法解析 $Tool 输出：$($_.Exception.Message)"
  }
  return $summary
}

function Import-RulePacks {
  param([string]$RulesDir)
  $index = @{}
  $packs = New-Object System.Collections.Generic.List[object]
  if ([string]::IsNullOrWhiteSpace($RulesDir) -or -not (Test-Path -LiteralPath $RulesDir)) {
    return [ordered]@{ index = $index; packs = @() }
  }
  foreach ($file in (Get-ChildItem -LiteralPath $RulesDir -Filter "*.json" -File | Sort-Object Name)) {
    try {
      $rules = @(Get-Content -Raw -LiteralPath $file.FullName -Encoding UTF8 | ConvertFrom-Json)
      $packs.Add([ordered]@{ path = $file.FullName; name = $file.Name; rules = $rules.Count; status = "loaded" }) | Out-Null
      foreach ($rule in $rules) {
        $ruleId = [string]$rule.ruleId
        if (-not [string]::IsNullOrWhiteSpace($ruleId)) {
          $index[$ruleId] = $rule
        }
      }
    } catch {
      $packs.Add([ordered]@{ path = $file.FullName; name = $file.Name; rules = 0; status = "failed"; error = $_.Exception.Message }) | Out-Null
    }
  }
  return [ordered]@{ index = $index; packs = @($packs.ToArray()) }
}

function Get-RuleMetadata {
  param(
    [hashtable]$RuleIndex,
    [string]$RuleId,
    [string]$DefaultSeverity,
    [string]$DefaultDimension,
    [string]$DefaultRecommendation
  )
  if ($null -ne $RuleIndex -and $RuleIndex.ContainsKey($RuleId)) {
    $rule = $RuleIndex[$RuleId]
    return [ordered]@{
      severity = if (-not [string]::IsNullOrWhiteSpace([string]$rule.severity)) { [string]$rule.severity } else { $DefaultSeverity }
      dimension = if (-not [string]::IsNullOrWhiteSpace([string]$rule.dimension)) { [string]$rule.dimension } else { $DefaultDimension }
      recommendation = if (-not [string]::IsNullOrWhiteSpace([string]$rule.recommendation)) { [string]$rule.recommendation } else { $DefaultRecommendation }
      source = "rulepack"
    }
  }
  return [ordered]@{
    severity = $DefaultSeverity
    dimension = $DefaultDimension
    recommendation = $DefaultRecommendation
    source = "heuristic"
  }
}

function Resolve-AuditPath {
  param(
    [string]$Path,
    [string]$BasePath
  )
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
  }
  return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $BasePath $Path))
}

function Get-DedupedFindings {
  param([array]$Findings)
  $seen = @{}
  $result = New-Object System.Collections.Generic.List[object]
  foreach ($finding in $Findings) {
    $fingerprint = [string]$finding["fingerprint"]
    if ([string]::IsNullOrWhiteSpace($fingerprint)) {
      $fingerprint = "$($finding["ruleId"])|$($finding["location"])|$($finding["title"])"
    }
    if (-not $seen.ContainsKey($fingerprint)) {
      $seen[$fingerprint] = $true
      $result.Add($finding) | Out-Null
    }
  }
  for ($i = 0; $i -lt $result.Count; $i++) {
    $result[$i]["id"] = "F-{0:D3}" -f ($i + 1)
  }
  return @($result.ToArray())
}

function Test-ActiveFinding {
  param([object]$Finding)
  $status = [string]$Finding["status"]
  return -not (@("false_positive", "fixed") -contains $status)
}

function Test-GateFinding {
  param([object]$Finding)
  $status = [string]$Finding["status"]
  return ([string]::IsNullOrWhiteSpace($status) -or $status -eq "open")
}

function New-RedactionMap {
  param(
    [string]$ProjectRoot,
    [string]$OutputRoot
  )
  $items = New-Object System.Collections.Generic.List[object]
  foreach ($entry in @(
      @{ path = $ProjectRoot; label = "[PROJECT_ROOT]" },
      @{ path = $OutputRoot; label = "[REPORT_OUTPUT]" },
      @{ path = $env:USERPROFILE; label = "[USER_HOME]" }
    )) {
    if ([string]::IsNullOrWhiteSpace([string]$entry.path)) {
      continue
    }
    $path = ([string]$entry.path).TrimEnd([char[]]@('\', '/'))
    if ([string]::IsNullOrWhiteSpace($path)) {
      continue
    }
    $items.Add([ordered]@{ pattern = [regex]::Escape($path); replacement = $entry.label }) | Out-Null
    $items.Add([ordered]@{ pattern = [regex]::Escape($path.Replace("\", "/")); replacement = $entry.label }) | Out-Null
  }
  return @($items.ToArray())
}

function Redact-Text {
  param(
    [AllowNull()][object]$Value,
    [array]$RedactionMap
  )
  if ($null -eq $Value) {
    return $null
  }
  $text = [string]$Value
  foreach ($entry in $RedactionMap) {
    $text = $text -replace [string]$entry.pattern, [string]$entry.replacement
  }
  $text = $text -replace '(?i)\b(10\.(?:\d{1,3}\.){2}\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b', '[INTERNAL_IP]'
  $text = $text -replace '(?i)\b[A-Z]:\\Users\\[^\\\s<>"'']+', '[USER_PATH]'
  return $text
}

function ConvertTo-RedactedObject {
  param(
    [AllowNull()][object]$Value,
    [array]$RedactionMap
  )
  if ($null -eq $Value) {
    return $null
  }
  if ($Value -is [string]) {
    return Redact-Text -Value $Value -RedactionMap $RedactionMap
  }
  if ($Value -is [ValueType]) {
    return $Value
  }
  if ($Value -is [System.Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in $Value.Keys) {
      $result[$key] = ConvertTo-RedactedObject -Value $Value[$key] -RedactionMap $RedactionMap
    }
    return $result
  }
  if ($Value -is [System.Array]) {
    return @($Value | ForEach-Object { ConvertTo-RedactedObject -Value $_ -RedactionMap $RedactionMap })
  }
  if ($Value.PSObject.Properties.Count -gt 0) {
    $result = [ordered]@{}
    foreach ($prop in $Value.PSObject.Properties) {
      $result[$prop.Name] = ConvertTo-RedactedObject -Value $prop.Value -RedactionMap $RedactionMap
    }
    return $result
  }
  return $Value
}

function Add-Finding {
  param(
    [System.Collections.Generic.List[object]]$Findings,
    [string]$RuleId,
    [string]$Title,
    [string]$Severity,
    [string]$Dimension,
    [string]$Priority,
    [string]$Confidence,
    [array]$Matches,
    [string]$Impact,
    [string]$Recommendation,
    [string]$FixExample = "",
    [string]$Source = "heuristic",
    [string]$Cwe = "",
    [string]$Owasp = "",
    [string]$AffectedComponent = "",
    [string]$RemediationEffort = "中",
    [string]$ConfidenceReason = "基于源码关键语句命中，需要结合业务上下文复核影响范围。"
  )
  if ($Matches.Count -eq 0) {
    return
  }
  $id = "F-{0:D3}" -f ($Findings.Count + 1)
  $primaryLocation = [string]$Matches[0].location
  $fingerprintSeed = "$RuleId|$primaryLocation|$Title"
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $hash = [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fingerprintSeed))).Replace("-", "").Substring(0, 16).ToLowerInvariant()
  $Findings.Add([ordered]@{
    id = $id
    ruleId = $RuleId
    title = $Title
    severity = $Severity
    dimension = $Dimension
    priority = $Priority
    confidence = $Confidence
    confidenceReason = $ConfidenceReason
    location = $primaryLocation
    evidence = Format-Evidence -Matches $Matches
    impact = $Impact
    recommendation = $Recommendation
    fixExample = $FixExample
    source = $Source
    cwe = $Cwe
    owasp = $Owasp
    affectedComponent = $AffectedComponent
    remediationEffort = $RemediationEffort
    fingerprint = $hash
    status = "open"
  }) | Out-Null
}

function Get-DimensionScores {
  param([array]$Findings)
  $dimensions = @(
    [ordered]@{ dimension = "架构合理性"; weight = 15; score = 15; summary = "未发现明确的阻断性架构问题。" },
    [ordered]@{ dimension = "功能正确性"; weight = 15; score = 15; summary = "按业务规则、状态流转、边界条件和数据一致性综合扣分。" },
    [ordered]@{ dimension = "编码规范性"; weight = 10; score = 10; summary = "按语言规范、复杂度、异常处理和可读性综合扣分。" },
    [ordered]@{ dimension = "安全性"; weight = 20; score = 20; summary = "按命令执行、输入边界、权限控制和敏感信息风险综合扣分。" },
    [ordered]@{ dimension = "可靠性/健壮性"; weight = 15; score = 15; summary = "按超时、并发、错误恢复和资源生命周期综合扣分。" },
    [ordered]@{ dimension = "可维护性/可演进性"; weight = 10; score = 10; summary = "按全局状态、重复逻辑、TODO、抽象质量和演进成本综合扣分。" },
    [ordered]@{ dimension = "性能与资源"; weight = 5; score = 5; summary = "按阻塞等待、资源释放和 I/O 行为综合扣分。" },
    [ordered]@{ dimension = "可观测性与运维性"; weight = 2; score = 2; summary = "按日志、指标、错误上下文、告警和运行状态暴露综合扣分。" },
    [ordered]@{ dimension = "测试质量"; weight = 5; score = 5; summary = "按单元测试、集成测试、边界测试、异常测试和 CI 接入综合扣分。" },
    [ordered]@{ dimension = "依赖与供应链风险"; weight = 3; score = 3; summary = "按依赖漏洞、许可证、锁文件、SBOM 和构建链路风险综合扣分。" }
  )

  foreach ($finding in $Findings) {
    $findingDimension = [string]$finding.dimension
    switch ($findingDimension) {
      "可靠性" { $findingDimension = "可靠性/健壮性" }
      "可维护性" { $findingDimension = "可维护性/可演进性" }
      "测试/文档/提交信息" { $findingDimension = "测试质量" }
      "供应链" { $findingDimension = "依赖与供应链风险" }
      "依赖风险" { $findingDimension = "依赖与供应链风险" }
      "可观测性" { $findingDimension = "可观测性与运维性" }
    }
    $target = $dimensions | Where-Object { $_.dimension -eq $findingDimension } | Select-Object -First 1
    if ($null -eq $target) {
      $target = $dimensions | Where-Object { $_.dimension -eq "编码规范性" } | Select-Object -First 1
    }
    $deduct = 0
    switch ([string]$finding.severity) {
      "高" { $deduct = 6 }
      "中" { $deduct = 3 }
      "低" { $deduct = 1 }
      "待复核" { $deduct = 0.5 }
      default { $deduct = 1 }
    }
    $target.score = [Math]::Max(0, [double]$target.score - $deduct)
  }

  foreach ($dimension in $dimensions) {
    $scoreText = [Math]::Round([double]$dimension.score, 1)
    $dimension.score = $scoreText
    $related = @($Findings | Where-Object {
      $findingDimension = [string]$_.dimension
      switch ($findingDimension) {
        "可靠性" { $findingDimension = "可靠性/健壮性" }
        "可维护性" { $findingDimension = "可维护性/可演进性" }
        "测试/文档/提交信息" { $findingDimension = "测试质量" }
        "供应链" { $findingDimension = "依赖与供应链风险" }
        "依赖风险" { $findingDimension = "依赖与供应链风险" }
        "可观测性" { $findingDimension = "可观测性与运维性" }
      }
      $findingDimension -eq $dimension.dimension
    })
    if ($related.Count -gt 0) {
      $dimension.summary = "发现 $($related.Count) 个相关问题，需按优先级整改。"
    }
  }
  return $dimensions
}

$scriptDir = Split-Path -Parent $PSCommandPath
$skillRoot = Split-Path -Parent $scriptDir
$projectFullPath = (Resolve-Path -LiteralPath $ProjectPath).Path
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
  $ProjectName = Split-Path -Leaf $projectFullPath
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $projectConfig = Join-Path $projectFullPath "audit-config.yml"
  $skillConfig = Join-Path $skillRoot "audit-config.yml"
  if (Test-Path -LiteralPath $projectConfig) {
    $ConfigPath = $projectConfig
  } elseif (Test-Path -LiteralPath $skillConfig) {
    $ConfigPath = $skillConfig
  }
}
$config = Read-AuditConfig -Path $ConfigPath
$rulePackState = Import-RulePacks -RulesDir (Join-Path $skillRoot "rules")
$ruleIndex = $rulePackState.index

if ($Languages.Count -eq 0) {
  $configuredLanguages = Get-ConfigValue -Config $config -Path "audit.languages" -Default @()
  if ((Get-Array $configuredLanguages).Count -gt 0) {
    $Languages = @(Get-Array $configuredLanguages)
  }
}
if (-not $PSBoundParameters.ContainsKey("ChangedOnly") -and (Get-ConfigBool -Config $config -Path "audit.changedOnly" -Default $false)) {
  $ChangedOnly = $true
}
if ([string]::IsNullOrWhiteSpace($DiffBase)) {
  $DiffBase = [string](Get-ConfigValue -Config $config -Path "audit.diffBase" -Default "")
}
if (-not $PSBoundParameters.ContainsKey("DiffTarget")) {
  $DiffTarget = [string](Get-ConfigValue -Config $config -Path "audit.diffTarget" -Default $DiffTarget)
}
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
  $BaselinePath = [string](Get-ConfigValue -Config $config -Path "audit.baselinePath" -Default "")
}
if (-not $PSBoundParameters.ContainsKey("MinScore")) {
  $MinScore = [int](Get-ConfigValue -Config $config -Path "audit.minScore" -Default $MinScore)
}
if (-not $PSBoundParameters.ContainsKey("FailOnHigh") -and (Get-ConfigBool -Config $config -Path "audit.failOnHigh" -Default $false)) {
  $FailOnHigh = $true
}
if (-not $PSBoundParameters.ContainsKey("RedactReport") -and (Get-ConfigBool -Config $config -Path "report.redact" -Default $false)) {
  $RedactReport = $true
}

$outputConfiguredFromFile = $false
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $configuredOutputDir = [string](Get-ConfigValue -Config $config -Path "report.outputDir" -Default "")
  if ([string]::IsNullOrWhiteSpace($configuredOutputDir)) {
    $OutputDir = Join-Path $projectFullPath ".audit-output"
  } else {
    $OutputDir = $configuredOutputDir
    $outputConfiguredFromFile = $true
  }
}
if ($outputConfiguredFromFile) {
  $OutputDir = Resolve-AuditPath -Path $OutputDir -BasePath $projectFullPath
}
if (-not [string]::IsNullOrWhiteSpace($BaselinePath)) {
  $BaselinePath = Resolve-AuditPath -Path $BaselinePath -BasePath $projectFullPath
}
if (-not [string]::IsNullOrWhiteSpace($ExportBaselinePath)) {
  $ExportBaselinePath = Resolve-AuditPath -Path $ExportBaselinePath -BasePath $projectFullPath
}
$outputFullDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
New-Item -ItemType Directory -Force -Path $outputFullDir | Out-Null

$inventoryPath = Join-Path $outputFullDir "$ProjectName.inventory.json"
$auditJsonPath = Join-Path $outputFullDir "$ProjectName.audit.json"
$auditHtmlPath = Join-Path $outputFullDir "$ProjectName.audit.html"

$inventoryScript = Join-Path $scriptDir "inventory-project.ps1"
$inventoryParams = @{
  ProjectPath = $projectFullPath
  OutputJson = $inventoryPath
}
$configuredExcludeDirs = Get-ConfigValue -Config $config -Path "audit.excludeDirs" -Default @()
if ((Get-Array $configuredExcludeDirs).Count -gt 0) {
  $inventoryParams.ExcludeDirs = @(Get-Array $configuredExcludeDirs)
}
$inventoryRaw = & $inventoryScript @inventoryParams
$inventory = Get-Content -Raw -LiteralPath $inventoryPath -Encoding UTF8 | ConvertFrom-Json

if ($Languages.Count -eq 0) {
  $Languages = @($inventory.languageStats | Where-Object { $_.language -notin @("JSON", "YAML", "Markdown", "XML", "HTML") } | ForEach-Object { $_.language })
}
if ($Languages.Count -eq 0) {
  $Languages = @("unknown")
}

$tools = New-Object System.Collections.Generic.List[object]
if (-not $SkipToolBootstrap) {
  $bootstrap = Join-Path $scriptDir "bootstrap-tools.ps1"
  if (Test-Path -LiteralPath $bootstrap) {
    $bootstrapParams = @{
      ProjectPath = $projectFullPath
      Languages = $Languages
    }
    if ($InstallMissing) {
      $bootstrapParams.InstallMissing = $true
    }
    try {
      $bootstrapOutput = & $bootstrap @bootstrapParams 2>&1
      $tools.Add([ordered]@{
        name = "bootstrap-tools"
        version = ""
        command = "bootstrap-tools.ps1 -ProjectPath `"$projectFullPath`" -Languages $($Languages -join ',')"
        status = "success"
        exitCode = 0
        durationMs = 0
        summary = (($bootstrapOutput | Select-Object -First 30) -join "`n")
      }) | Out-Null
    } catch {
      $tools.Add([ordered]@{
        name = "bootstrap-tools"
        version = ""
        command = "bootstrap-tools.ps1 -ProjectPath `"$projectFullPath`" -Languages $($Languages -join ',')"
        status = "failed"
        exitCode = -1
        durationMs = 0
        summary = $_.Exception.Message
      }) | Out-Null
    }
  }
}

if (-not $SkipExternalTools) {
  if (($Languages -contains "C++") -and (Test-Command "cppcheck")) {
    $cppcheckOut = Join-Path $outputFullDir "cppcheck.txt"
    $tools.Add((Invoke-AuditCommand -Name "cppcheck" -Command "cppcheck" -Arguments @("--enable=warning,style,performance,portability", "--inline-suppr", "--quiet", $projectFullPath) -OutputPath $cppcheckOut)) | Out-Null
  }
  if ($Languages -contains "PowerShell") {
    if (Test-Command "Invoke-ScriptAnalyzer") {
      $pssaOut = Join-Path $outputFullDir "psscriptanalyzer.txt"
      $tools.Add((Invoke-AuditCommand -Name "PSScriptAnalyzer" -Command "Invoke-ScriptAnalyzer" -Arguments @("-Path", $projectFullPath, "-Recurse") -OutputPath $pssaOut)) | Out-Null
    } else {
      $tools.Add((New-ToolRecord -Name "PSScriptAnalyzer" -Status "missing" -Command "Invoke-ScriptAnalyzer -Path <project> -Recurse" -Summary "未找到 PSScriptAnalyzer，跳过 PowerShell 静态分析。")) | Out-Null
    }
  }
  if (Test-Command "gitleaks") {
    $gitleaksOut = Join-Path $outputFullDir "gitleaks.json"
    $tools.Add((Invoke-AuditCommand -Name "gitleaks" -Command "gitleaks" -Arguments @("detect", "--source", $projectFullPath, "--no-git", "--redact", "--report-format", "json", "--report-path", $gitleaksOut))) | Out-Null
  } else {
    $tools.Add((New-ToolRecord -Name "gitleaks" -Status "missing" -Command "gitleaks detect --source <project>" -Summary "未找到 gitleaks，跳过密钥泄露扫描。")) | Out-Null
  }
  if (Test-Command "semgrep") {
    $semgrepOut = Join-Path $outputFullDir "semgrep.json"
    $tools.Add((Invoke-AuditCommand -Name "semgrep" -Command "semgrep" -Arguments @("scan", "--quiet", "--json", "--output", $semgrepOut, $projectFullPath))) | Out-Null
  } else {
    $tools.Add((New-ToolRecord -Name "semgrep" -Status "missing" -Command "semgrep scan --json <project>" -Summary "未找到 semgrep，跳过通用静态安全规则扫描。")) | Out-Null
  }
}

$scaEnabled = (Get-ConfigBool -Config $config -Path "sca.enabled" -Default $true) -and (-not $DisableSca)
$sbomEnabled = (Get-ConfigBool -Config $config -Path "sca.sbomEnabled" -Default $true) -and (-not $DisableSbom)
$scaSummary = [ordered]@{
  enabled = $scaEnabled
  sbomEnabled = $sbomEnabled
  vulnerabilityTools = @()
  sbom = [ordered]@{
    generated = $false
    format = "CycloneDX JSON"
    output = ""
    tool = "syft"
  }
}
if ($scaEnabled -and -not $SkipExternalTools) {
  if (Test-Command "trivy") {
    $trivyOut = Join-Path $outputFullDir "trivy-fs.json"
    $record = Invoke-AuditCommand -Name "trivy" -Command "trivy" -Arguments @("fs", "--quiet", "--format", "json", "--output", $trivyOut, $projectFullPath) -OutputPath ""
    $tools.Add($record) | Out-Null
    $scaSummary.vulnerabilityTools += Get-ScaSummaryFromFile -Tool "trivy" -Path $trivyOut
  } else {
    $tools.Add((New-ToolRecord -Name "trivy" -Status "missing" -Command "trivy fs" -Summary "未找到 trivy，跳过文件系统依赖漏洞扫描。")) | Out-Null
  }
  if (Test-Command "grype") {
    $grypeOut = Join-Path $outputFullDir "grype.json"
    $record = Invoke-AuditCommand -Name "grype" -Command "grype" -Arguments @("dir:$projectFullPath", "-o", "json", "--file", $grypeOut) -OutputPath ""
    $tools.Add($record) | Out-Null
    $scaSummary.vulnerabilityTools += Get-ScaSummaryFromFile -Tool "grype" -Path $grypeOut
  } else {
    $tools.Add((New-ToolRecord -Name "grype" -Status "missing" -Command "grype dir:<project>" -Summary "未找到 grype，跳过依赖漏洞扫描。")) | Out-Null
  }
  if (Test-Command "osv-scanner") {
    $osvOut = Join-Path $outputFullDir "osv-scanner.json"
    $record = Invoke-AuditCommand -Name "osv-scanner" -Command "osv-scanner" -Arguments @("--recursive", "--format", "json", "--output", $osvOut, $projectFullPath) -OutputPath ""
    $tools.Add($record) | Out-Null
    $scaSummary.vulnerabilityTools += Get-ScaSummaryFromFile -Tool "osv-scanner" -Path $osvOut
  } else {
    $tools.Add((New-ToolRecord -Name "osv-scanner" -Status "missing" -Command "osv-scanner --recursive" -Summary "未找到 osv-scanner，跳过 OSV 漏洞扫描。")) | Out-Null
  }
}
if ($sbomEnabled -and -not $SkipExternalTools) {
  if (Test-Command "syft") {
    $sbomOut = Join-Path $outputFullDir "$ProjectName.sbom.cdx.json"
    $record = Invoke-AuditCommand -Name "syft" -Command "syft" -Arguments @("dir:$projectFullPath", "-o", "cyclonedx-json=$sbomOut") -OutputPath ""
    $tools.Add($record) | Out-Null
    $scaSummary.sbom.generated = ($record.status -eq "success" -and (Test-Path -LiteralPath $sbomOut))
    $scaSummary.sbom.output = $sbomOut
  } else {
    $tools.Add((New-ToolRecord -Name "syft" -Status "missing" -Command "syft dir:<project> -o cyclonedx-json" -Summary "未找到 syft，跳过 SBOM 生成。")) | Out-Null
  }
}

$findings = New-Object System.Collections.Generic.List[object]
$sourceFiles = @($inventory.sourceFiles)
$diffInfo = [ordered]@{
  enabled = [bool]$ChangedOnly
  available = $false
  base = $DiffBase
  target = $DiffTarget
  changedFileCount = 0
  auditedChangedSourceFileCount = 0
  reason = ""
  files = @()
}
if ($ChangedOnly) {
  $diffInfo = Get-GitChangedFiles -Root $projectFullPath -Base $DiffBase -Target $DiffTarget
  if ($diffInfo.available) {
    $changedSet = @{}
    foreach ($file in (Get-Array $diffInfo.files)) {
      $changedSet[(Normalize-RepoPath $file)] = $true
    }
    $sourceFiles = @($sourceFiles | Where-Object { $changedSet.ContainsKey((Normalize-RepoPath ([string]$_.path))) })
    $diffInfo.changedFileCount = (Get-Array $diffInfo.files).Count
    $diffInfo.auditedChangedSourceFileCount = $sourceFiles.Count
  }
}

if (-not $SkipExternalTools) {
  $missingKeyTools = @($tools.ToArray() | Where-Object {
      [string]$_["status"] -eq "missing" -and @("semgrep", "gitleaks", "PSScriptAnalyzer", "trivy", "grype", "osv-scanner", "syft") -contains [string]$_["name"]
    })
  if ($missingKeyTools.Count -gt 0) {
    $missingText = ($missingKeyTools | ForEach-Object { "$($_["name"]): $($_["summary"])" }) -join "; "
    Add-Finding -Findings $findings -RuleId "GEN-TOOL-COVERAGE-001" -Title "关键审计工具缺失，自动审计覆盖度不足" -Severity "中" -Dimension "测试质量" -Priority "P1" -Confidence "高" `
      -Matches @([ordered]@{ location = $projectFullPath; text = $missingText }) `
      -Impact "关键静态分析、密钥扫描、依赖漏洞扫描或 SBOM 工具缺失时，报告不能证明相关风险已经被覆盖；如果仍给出满分，会高估审计可信度。" `
      -Recommendation "在本机或 CI 中安装并固定 semgrep、gitleaks、PSScriptAnalyzer、trivy/grype/osv-scanner、syft 等关键工具；无法安装时应在报告中形成待复核项或降低评分，并说明未覆盖范围。" `
      -AffectedComponent "工具覆盖/审计门禁" -RemediationEffort "中" -Source "tool-coverage" `
      -ConfidenceReason "基于本次审计工具记录中的 missing 状态生成。"
  }
}

Add-Finding -Findings $findings -RuleId "CPP-SEC-001" -Title "外部命令通过字符串拼接执行，存在命令注入和执行边界风险" -Severity "高" -Dimension "安全性" -Priority "P0" -Confidence "高" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++") -Pattern 'std::system\s*\(|(?<!::)\bsystem\s*\(' -MaxExamples 5) `
  -Impact "当命令字符串包含路径、工具名或参数且未做白名单校验/转义时，攻击者或异常配置可能改变命令语义，导致任意命令执行、日志导出失败或权限边界扩大。" `
  -Recommendation "避免 shell 字符串拼接。优先使用 execve/posix_spawn/Boost.Process 等参数数组接口；对工具路径做固定目录白名单和存在性校验；对输出目录使用规范化路径并拒绝特殊字符；记录退出码和 stderr。" `
  -FixExample "boost::process::child child(toolPath, boost::process::std_out > boost::process::null, boost::process::start_dir = slotDir.string());" `
  -Cwe "CWE-78" -Owasp "A03:2021 Injection" -AffectedComponent "日志导出/外部工具调用" -RemediationEffort "中"

Add-Finding -Findings $findings -RuleId "CPP-SEC-002" -Title "代码直接调用 shell 命令，需要收敛命令白名单和失败处理" -Severity "中" -Dimension "安全性" -Priority "P1" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++") -Pattern 'arch::shell::exec\s*\(' -MaxExamples 5) `
  -Impact "即使当前命令为固定值，后续扩展参数或环境变量污染也可能引入注入风险；命令失败、超时和输出异常会影响设备识别可靠性。" `
  -Recommendation "将可执行命令封装为受控适配器，限制可执行名和参数；增加超时、退出码、stderr 记录和降级路径；单元测试覆盖命令失败、空输出和异常输出。" `
  -Cwe "CWE-78" -AffectedComponent "设备探测" -RemediationEffort "中"

Add-Finding -Findings $findings -RuleId "GEN-SEC-EXEC-001" -Title "动态执行或外部进程调用需要校验输入、超时和权限边界" -Severity "高" -Dimension "安全性" -Priority "P0" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("Java", "C#", "Shell", "PowerShell", "Python", "PHP", "Kotlin", "Lua", "JavaScript", "TypeScript", "BAT/CMD", "Go") -Pattern 'Runtime\.getRuntime\(\)\.exec|ProcessBuilder\s*\(|subprocess\.(Popen|run|call|check_output)\s*\(.*shell\s*=\s*True|os\.system\s*\(|child_process\.(exec|execSync)\s*\(|shell_exec\s*\(|passthru\s*\(|proc_open\s*\(|eval\s*\(|Function\s*\(|loadstring\s*\(|io\.popen\s*\(|Invoke-Expression\b|\biex\b|Start-Process\b|Invoke-Command\b|&\s*\$[A-Za-z_][A-Za-z0-9_]*' -MaxExamples 8) `
  -Impact "动态执行入口一旦拼接了用户输入、环境变量或配置值，可能导致命令注入、权限越界或脚本执行链路失控。" `
  -Recommendation "改用参数数组或受控 API；对可执行名、参数、工作目录和环境变量做白名单校验；加入超时、退出码、stderr 记录和失败降级；必要时降低运行权限。" `
  -Cwe "CWE-78" -Owasp "A03:2021 Injection" -AffectedComponent "跨语言动态执行入口" -RemediationEffort "中"

$numericIndexRule = Get-RuleMetadata -RuleIndex $ruleIndex -RuleId "NUM-004-INDEX-SLICE-UNDERFLOW" -DefaultSeverity "高" -DefaultDimension "可靠性/健壮性" -DefaultRecommendation "检查数组、列表、map、字符串、切片和 PowerShell 数组访问；重点复核 length - 1、count - 1、负索引、反向循环和空集合访问。"
$codeLanguages = @("PowerShell", "C++", "C#", "Java", "Shell", "Python", "PHP", "Kotlin", "Lua", "JavaScript", "TypeScript", "BAT/CMD", "Go", "Blazor")
Add-Finding -Findings $findings -RuleId "NUM-004-INDEX-SLICE-UNDERFLOW" -Title "索引、切片或 length/count 运算存在边界下溢风险" -Severity ([string]$numericIndexRule.severity) -Dimension "可靠性/健壮性" -Priority "P1" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages $codeLanguages -Pattern 'Substring\s*\([^`r`n]*(\.Length|\.Count)\s*-\s*\d+|(\.Length|\.Count)\s*-\s*1|\[\s*[^\]`r`n]*(\.Length|\.Count)\s*-\s*1\s*\]' -MaxExamples 10) `
  -Impact "当输入为空、长度不足或集合为空时，length/count 减法、切片和下标访问可能触发运行时异常、越界读取、错误截断或拒绝服务。" `
  -Recommendation ([string]$numericIndexRule.recommendation) `
  -Cwe "CWE-129, CWE-191" -AffectedComponent "通用数值边界/索引切片" -RemediationEffort "低" -Source ([string]$numericIndexRule.source) `
  -ConfidenceReason "基于 common-numeric-boundaries 规则包和源码启发式命中；需结合输入前置校验确认可达性。"

Add-Finding -Findings $findings -RuleId "GEN-WEB-XSS-001" -Title "页面直接写入 HTML 或绕过编码，需要复核 XSS 防护" -Severity "中" -Dimension "安全性" -Priority "P1" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("JavaScript", "TypeScript", "PHP", "Blazor", "HTML") -Pattern 'innerHTML\s*=|outerHTML\s*=|document\.write\s*\(|dangerouslySetInnerHTML|v-html|@Html\.Raw|MarkupString' -MaxExamples 8) `
  -Impact "如果写入内容包含接口返回、URL 参数、富文本或用户输入，可能绕过框架默认编码并形成存储型或反射型 XSS。" `
  -Recommendation "默认使用框架文本绑定和模板自动编码；富文本走可信白名单清洗；补充 XSS 回归测试和 CSP；对确需 Raw/Markup 的位置记录可信来源。" `
  -Cwe "CWE-79" -Owasp "A03:2021 Injection" -AffectedComponent "Web/前端渲染" -RemediationEffort "中"

Add-Finding -Findings $findings -RuleId "GEN-SEC-SECRET-001" -Title "疑似密钥或敏感凭据硬编码，需要立即复核" -Severity "高" -Dimension "安全性" -Priority "P0" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @() -Pattern '(?i)(password|passwd|secret|token|api[_-]?key|private[_-]?key)\s*[:=]\s*\S{8,}' -MaxExamples 10) `
  -Impact "真实密钥进入源码、配置或脚本后，可能被仓库历史、构建日志或制品泄露，导致账号接管、数据泄露或横向移动。" `
  -Recommendation "确认是否为真实凭据；真实凭据应立即轮换并从历史中清理；后续改用密钥管理系统、CI Secret 或运行时注入，并保留脱敏日志。" `
  -Cwe "CWE-798" -Owasp "A02:2021 Cryptographic Failures" -AffectedComponent "配置/源码/脚本凭据" -RemediationEffort "中"

Add-Finding -Findings $findings -RuleId "CPP-REL-001" -Title "异步等待缺少超时保护，可能导致 AT 操作永久挂起" -Severity "中" -Dimension "可靠性/健壮性" -Priority "P1" -Confidence "高" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++") -Pattern '(TODO.*(超时|timeout)|async_wait\(\).*(超时|timeout))' -MaxExamples 5) `
  -Impact "串口无响应、消息丢失或状态机异常时，协程可能长期等待，进而阻塞队列中的后续 AT 操作，影响拨号、重连和故障恢复。" `
  -Recommendation "为每个 AT 命令引入统一 deadline timer；超时后清理当前命令状态、返回 timed_out，并触发可观测日志和重试/重建串口策略。" `
  -FixExample "co_await (command_response_lines.async_wait() || timeout_timer.async_wait());" `
  -AffectedComponent "ATTransceiver" -RemediationEffort "中"

Add-Finding -Findings $findings -RuleId "CPP-REL-002" -Title "存在 detached 异步任务/线程，生命周期和异常传播不可控" -Severity "中" -Dimension "可靠性/健壮性" -Priority "P1" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++") -Pattern '(asio::detached|boost::asio::detached|\.detach\s*\()' -MaxExamples 8) `
  -Impact "detached 任务无法统一 join、取消和收集异常，关闭流程中容易出现后台任务继续访问已释放对象、错误被吞掉或进程退出时资源未清理。" `
  -Recommendation "关键业务协程使用 observer/scope/group 管理生命周期；关闭时先发取消信号，再等待任务完成；对 detached 仅保留无状态、可丢弃任务，并在代码注释中说明边界。" `
  -AffectedComponent "主循环/控制器/线程生命周期" -RemediationEffort "中"

Add-Finding -Findings $findings -RuleId "CPP-REL-003" -Title "catch(...) 吞掉异常，故障原因和恢复动作不明确" -Severity "中" -Dimension "可靠性/健壮性" -Priority "P1" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++") -Pattern 'catch\s*\(\s*\.\.\.\s*\)' -MaxExamples 8) `
  -Impact "异常被无条件忽略会掩盖真实故障，导致状态机重启、modem 获取或控制器退出时缺少诊断信息，也不利于定位线上稳定性问题。" `
  -Recommendation "捕获具体异常类型；至少记录异常上下文、slot、状态和操作名；仅在明确可恢复时继续执行，否则进入错误状态或触发受控重启。" `
  -AffectedComponent "异常处理/状态机恢复" -RemediationEffort "低"

Add-Finding -Findings $findings -RuleId "CPP-REL-004" -Title "槽位参数在硬件路径拼接前缺少统一边界校验" -Severity "中" -Dimension "可靠性/健壮性" -Priority "P1" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++") -Pattern 'fmt::format\((power_pin_path|reset_pin_path).*slot' -MaxExamples 8) `
  -Impact "如果调用方传入非 1/2 槽位，代码可能写入不存在或错误的 sysfs 路径；在硬件控制场景中会造成设备状态异常、误复位或故障难以追踪。" `
  -Recommendation "定义 SlotId 值对象或 validate_slot(slot)；所有 GPIO、日志、控制器、LED 和配置入口统一校验；非法槽位返回明确错误并记录审计日志。" `
  -AffectedComponent "设备电源/GPIO 控制" -RemediationEffort "低"

Add-Finding -Findings $findings -RuleId "CPP-COR-001" -Title "未知设备型号按厂商默认型号处理，可能导致业务状态判断错误" -Severity "中" -Dimension "功能正确性" -Priority "P1" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++") -Pattern 'assuming\s+(RM500U|MT5700|EM360|GD225)' -MaxExamples 8) `
  -Impact "当 USB product_id 未被明确识别时，代码直接回退为厂商默认型号，可能加载错误的 AT 指令集、日志导出器或状态判断逻辑，造成拨号失败、误报在线状态或后续恢复动作错误。" `
  -Recommendation "未知 product_id 应保留为 unknown 或进入受控探测流程；将厂商、product_id、匹配规则和最终型号记录到结构化日志；新增覆盖未知型号、兼容型号和误匹配的测试用例。" `
  -AffectedComponent "设备型号识别/厂商适配" -RemediationEffort "中"

Add-Finding -Findings $findings -RuleId "CPP-MNT-001" -Title "全局可变 map/shared_ptr 状态较多，线程安全和模块边界需要收敛" -Severity "中" -Dimension "可维护性/可演进性" -Priority "P2" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++") -Pattern '(extern\s+std::map|std::map<.*>\s+\w+|extern\s+std::shared_ptr)' -MaxExamples 10) `
  -Impact "全局状态分散在主流程、日志、控制器和检测状态中，后续多线程/多协程访问时难以证明一致性，也增加单元测试隔离和故障复现难度。" `
  -Recommendation "将全局状态收敛到 AppContext/RuntimeContext，明确所有权和访问线程；跨线程共享结构使用 strand/mutex 或消息队列；测试中注入上下文替代直接访问全局变量。" `
  -AffectedComponent "运行时上下文/日志/控制器状态" -RemediationEffort "中"

Add-Finding -Findings $findings -RuleId "CPP-MNT-002" -Title "存在 TODO/未实现逻辑，发布前需区分遗留项和阻断项" -Severity "低" -Dimension "可维护性/可演进性" -Priority "P3" -Confidence "高" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++", "Shell", "Python", "Java", "C#", "PHP", "Kotlin", "Lua") -Pattern '(TODO|FIXME|Not implemented)' -MaxExamples 12) `
  -Impact "TODO 分散在设备管理、AT 行为、等待策略和厂商适配中，如果没有归档为任务，容易在版本发布后变成隐藏的可靠性缺口。" `
  -Recommendation "将 TODO 转为 issue/缺陷单并标注版本；发布阻断项必须落到测试用例；非阻断优化项应说明业务影响和验收条件。" `
  -AffectedComponent "工程待办管理" -RemediationEffort "低"

Add-Finding -Findings $findings -RuleId "CPP-PERF-001" -Title "启动流程存在固定 sleep 等待，影响启动确定性和故障恢复速度" -Severity "低" -Dimension "性能与资源" -Priority "P3" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++") -Pattern 'sleep_for\s*\(\s*8s\s*\)|Waiting for filesystem' -MaxExamples 5) `
  -Impact "固定等待会拉长正常启动时间，也不能保证文件系统一定就绪；异常情况下仍可能进入后续流程并产生级联错误。" `
  -Recommendation "改为轮询明确的挂载点/设备文件可用性，设置最大等待时间和失败日志；测试覆盖已挂载、延迟挂载和超时三类场景。" `
  -AffectedComponent "启动流程" -RemediationEffort "低"

Add-Finding -Findings $findings -RuleId "GEN-OBS-001" -Title "异常上下文未完整进入日志，影响线上定位和运维闭环" -Severity "低" -Dimension "可观测性与运维性" -Priority "P2" -Confidence "中" `
  -Matches (Find-LineMatches -Root $projectFullPath -SourceFiles $sourceFiles -Languages @("C++") -Pattern 'auto\s+msg\s*=\s*fmt::format\("Exception in coroutine' -MaxExamples 5) `
  -Impact "异常信息被格式化后没有写入统一 logger，线上只能看到有限错误输出或完全缺失上下文，不利于排查协程、slot、状态机和设备操作链路中的故障。" `
  -Recommendation "统一异常记录入口，至少包含操作名、slot、状态、异常类型、错误码和协程/线程上下文；关键恢复路径增加指标和告警事件。" `
  -AffectedComponent "异常日志/运行诊断" -RemediationEffort "低"

$scaVulnerabilityCount = 0
$scaHighCount = 0
$scaMediumCount = 0
$scaLowCount = 0
foreach ($scaToolSummary in (Get-Array $scaSummary.vulnerabilityTools)) {
  $scaVulnerabilityCount += [int]$scaToolSummary.vulnerabilities
  $scaHighCount += [int]$scaToolSummary.high
  $scaMediumCount += [int]$scaToolSummary.medium
  $scaLowCount += [int]$scaToolSummary.low
}
if ($scaVulnerabilityCount -gt 0) {
  $scaSeverity = "低"
  $scaPriority = "P2"
  if ($scaHighCount -gt 0) {
    $scaSeverity = "高"
    $scaPriority = "P0"
  } elseif ($scaMediumCount -gt 0) {
    $scaSeverity = "中"
    $scaPriority = "P1"
  }
  Add-Finding -Findings $findings -RuleId "GEN-SCA-002" -Title "SCA 工具发现第三方组件已知漏洞，需要按严重级别复核修复" -Severity $scaSeverity -Dimension "依赖与供应链风险" -Priority $scaPriority -Confidence "中" `
    -Matches @([ordered]@{ location = $projectFullPath; text = "SCA 汇总：漏洞 $scaVulnerabilityCount 个，高危 $scaHighCount 个，中危 $scaMediumCount 个，低危 $scaLowCount 个。" }) `
    -Impact "第三方组件漏洞可能引入远程执行、信息泄露、拒绝服务或供应链合规风险；工具结果仍需结合实际可达性、组件用途和补丁可用性复核。" `
    -Recommendation "逐项复核 SCA 原始输出，优先升级存在高危/中危漏洞的直接依赖；无法升级时记录受影响路径、缓解措施、风险接受人和复测日期。" `
    -AffectedComponent "依赖与供应链" -RemediationEffort "中" -Source "tool"
}

$scaSuccessfulTools = @($tools.ToArray() | Where-Object { @("trivy", "grype", "osv-scanner") -contains [string]$_["name"] -and [string]$_["status"] -eq "success" })
if ((Get-Array $inventory.manifests).Count -gt 0 -and ($scaSuccessfulTools.Count -eq 0 -or -not $scaSummary.sbom.generated)) {
  $supplyChainEvidence = @([ordered]@{
      location = $projectFullPath
      text = "inventory 识别到依赖/构建清单：$(((Get-Array $inventory.manifests | ForEach-Object { $_.path }) -join ', '))"
    })
  Add-Finding -Findings $findings -RuleId "GEN-SCA-001" -Title "依赖与供应链审计证据不足，建议补齐漏洞扫描、锁文件和 SBOM" -Severity "低" -Dimension "依赖与供应链风险" -Priority "P2" -Confidence "中" `
    -Matches $supplyChainEvidence `
    -Impact "项目存在构建和依赖清单，但如果没有稳定锁文件、漏洞扫描结果或 SBOM，发布前难以证明第三方组件版本、许可证和已知 CVE 风险可控。" `
    -Recommendation "在 CI 中接入 osv-scanner/trivy/grype 或生态工具；保留锁文件或明确版本约束；发布产物附带 SBOM，并在报告中记录扫描时间、数据库版本和例外项。" `
    -AffectedComponent "依赖管理/构建供应链" -RemediationEffort "低"
}

if ($inventory.testFileCount -eq 0) {
  Add-Finding -Findings $findings -RuleId "GEN-TST-001" -Title "未发现测试目录或测试文件" -Severity "中" -Dimension "测试质量" -Priority "P2" -Confidence "中" `
    -Matches @([ordered]@{ location = $projectFullPath; text = "inventory 未识别到 tests/test/spec 文件。" }) `
    -Impact "缺少自动化测试会降低重构、修复安全问题和回归验证的可信度。" `
    -Recommendation "至少补充核心业务路径、错误路径和边界条件测试，并将测试接入 CI。" `
    -AffectedComponent "测试体系" -RemediationEffort "中"
}

$findingArray = Get-DedupedFindings -Findings @($findings.ToArray())
$baselineSummary = Apply-FindingBaseline -Findings $findingArray -Path $BaselinePath
if (-not [string]::IsNullOrWhiteSpace($ExportBaselinePath)) {
  Export-FindingBaseline -Findings $findingArray -Path $ExportBaselinePath
  $baselineSummary["exportedPath"] = $ExportBaselinePath
}

$activeFindings = @($findingArray | Where-Object { Test-ActiveFinding -Finding $_ })
$gateFindings = @($findingArray | Where-Object { Test-GateFinding -Finding $_ })

$dimensionScores = Get-DimensionScores -Findings $activeFindings
$totalScoreValue = 0
foreach ($dimensionScore in $dimensionScores) {
  $totalScoreValue += [double]$dimensionScore["score"]
}
$totalScore = [Math]::Round($totalScoreValue, 0)
$high = @($activeFindings | Where-Object { $_["severity"] -eq "高" }).Count
$medium = @($activeFindings | Where-Object { $_["severity"] -eq "中" }).Count
$low = @($activeFindings | Where-Object { $_["severity"] -eq "低" }).Count
$review = @($activeFindings | Where-Object { $_["severity"] -eq "待复核" }).Count
$open = @($findingArray | Where-Object { [string]$_["status"] -eq "open" }).Count
$accepted = @($findingArray | Where-Object { [string]$_["status"] -eq "accepted" }).Count
$falsePositive = @($findingArray | Where-Object { [string]$_["status"] -eq "false_positive" }).Count
$fixed = @($findingArray | Where-Object { [string]$_["status"] -eq "fixed" }).Count

$rating = "优秀"
if ($totalScore -lt 60) { $rating = "高风险" }
elseif ($totalScore -lt 70) { $rating = "较差" }
elseif ($totalScore -lt 80) { $rating = "一般" }
elseif ($totalScore -lt 90) { $rating = "良好" }

$riskLevel = "低"
if ($high -gt 0 -or $totalScore -lt 70) { $riskLevel = "高" }
elseif ($medium -gt 0 -or $totalScore -lt 85) { $riskLevel = "中" }

$roadmap = @()
if ($high -gt 0) {
  $roadmap += [ordered]@{ priority = "P0"; action = "修复高风险安全问题，尤其是外部命令执行、敏感参数拼接和权限边界。"; owner = "核心开发负责人"; due = "1 周内" }
}
if ($medium -gt 0) {
  $roadmap += [ordered]@{ priority = "P1"; action = "补齐超时、生命周期、异常处理和输入边界校验，增加回归测试。"; owner = "模块负责人"; due = "2 周内" }
}
if ($activeFindings.Count -gt 0) {
  $roadmap += [ordered]@{ priority = "P2"; action = "按报告 finding 补齐自动化测试、工具覆盖、日志上下文和供应链证据，并复测已修复项。"; owner = "项目维护人"; due = "1 个迭代内" }
} else {
  $roadmap += [ordered]@{ priority = "P2"; action = "保持工具版本、规则包和测试用例更新，定期复测审计覆盖范围。"; owner = "项目维护人"; due = "持续" }
}

$scope = @("源代码", "构建文件", "依赖清单", "测试目录", "配置文件", "设计文档线索")
if ($ChangedOnly) {
  $scope += "Git 增量变更"
}
$riskTopicText = "未发现当前规则命中的有效问题。"
if ($activeFindings.Count -gt 0) {
  $topIssues = @($activeFindings | Select-Object -First 5 | ForEach-Object { [string]$_["title"] })
  $riskTopicText = "主要问题包括：" + ($topIssues -join "；") + "。"
}
$conclusion = "本次审计覆盖 $($inventory.sourceFileCount) 个源码/配置/文档文件，识别主要语言为 $($Languages -join '、')。总体评分 $totalScore，风险等级 $riskLevel。当前有效问题 $($activeFindings.Count) 个，其中高危 $high 个、中危 $medium 个、低危 $low 个。$riskTopicText"

$limitations = New-Object System.Collections.Generic.List[object]
$limitations.Add("本次审计以静态审计和启发式规则为主；未执行完整运行时验证。") | Out-Null
if ($Languages -contains "C++") {
  $limitations.Add("若项目依赖目标硬件、嵌入式设备或专用运行环境，相关行为仍需在目标环境复核。") | Out-Null
}
$limitations.Add("若本地缺少 cppcheck、semgrep、gitleaks、trivy、grype、osv-scanner、syft 等工具，报告会记录跳过或检测失败，相关结论需在 CI/目标环境复核。") | Out-Null
$limitations.Add("启发式规则命中的问题已按证据生成，但仍建议结合业务输入来源、权限模型和运行拓扑做最终确认。") | Out-Null
if ($ChangedOnly -and -not $diffInfo.available) {
  $limitations.Add("已请求增量审计，但 Git 差分不可用：$($diffInfo.reason)") | Out-Null
}
if ($baselineSummary.enabled -and $baselineSummary.missing -gt 0) {
  $limitations.Add("已配置误报/风险接受基线，但基线文件不存在，未应用历史状态。") | Out-Null
}

$report = [ordered]@{
  schemaVersion = "2.2"
  project = $ProjectName
  repository = $projectFullPath
  auditTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  scope = $scope
  auditor = $Auditor
  config = [ordered]@{
    loaded = -not [string]::IsNullOrWhiteSpace($ConfigPath)
    path = $ConfigPath
    languages = @($Languages)
    changedOnly = [bool]$ChangedOnly
    diffBase = $DiffBase
    diffTarget = $DiffTarget
    minScore = $MinScore
    failOnHigh = [bool]$FailOnHigh
    scaEnabled = [bool]$scaEnabled
    sbomEnabled = [bool]$sbomEnabled
  }
  reportOptions = [ordered]@{
    redacted = [bool]$RedactReport
    generatedBy = "code-audit-report"
  }
  summary = [ordered]@{
    score = $totalScore
    rating = $rating
    riskLevel = $riskLevel
    conclusion = $conclusion
  }
  stats = [ordered]@{
    total = $findingArray.Count
    active = $activeFindings.Count
    high = $high
    medium = $medium
    low = $low
    review = $review
    open = $open
    accepted = $accepted
    falsePositive = $falsePositive
    fixed = $fixed
  }
  inventory = $inventory
  diff = $diffInfo
  baseline = $baselineSummary
  sca = $scaSummary
  rulePacks = @($rulePackState.packs)
  dimensionScores = @($dimensionScores)
  findings = @($findingArray)
  roadmap = $roadmap
  tools = @($tools.ToArray())
  limitations = @($limitations.ToArray())
}

$reportForOutput = $report
if ($RedactReport) {
  $redactionMap = New-RedactionMap -ProjectRoot $projectFullPath -OutputRoot $outputFullDir
  $reportForOutput = ConvertTo-RedactedObject -Value $report -RedactionMap $redactionMap
}

$json = $reportForOutput | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($auditJsonPath, $json, [System.Text.UTF8Encoding]::new($false))

$render = Join-Path $scriptDir "render-report.ps1"
& $render -InputJson $auditJsonPath -OutputHtml $auditHtmlPath | Out-Null

$gateHigh = @($gateFindings | Where-Object { $_["severity"] -eq "高" }).Count
if ($FailOnHigh -and $gateHigh -gt 0) {
  Write-Output "Audit gate failed: $gateHigh open high-severity finding(s)."
  exit 3
}

if ($MinScore -gt 0 -and $totalScore -lt $MinScore) {
  Write-Output "Audit score $totalScore is below threshold $MinScore."
  exit 2
}

[ordered]@{
  auditJson = $auditJsonPath
  auditHtml = $auditHtmlPath
  inventoryJson = $inventoryPath
  score = $totalScore
  riskLevel = $riskLevel
  findings = $findingArray.Count
  activeFindings = $activeFindings.Count
} | ConvertTo-Json -Depth 4
