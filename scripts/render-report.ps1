param(
  [Parameter(Mandatory = $true)]
  [string]$InputJson,

  [Parameter(Mandatory = $true)]
  [string]$OutputHtml,

  [string]$TemplatePath = ""
)

$ErrorActionPreference = "Stop"

function ConvertTo-HtmlText {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return "" }
  return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-HtmlBlock {
  param([AllowNull()][object]$Value)
  $text = ConvertTo-HtmlText $Value
  return ($text -replace "`r?`n", "<br>")
}

function Get-Array {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return $Value }
  return @($Value)
}

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

function Get-BadgeClass {
  param([string]$Severity)
  switch ($Severity) {
    "高" { return "high" }
    "中" { return "medium" }
    "低" { return "low" }
    "待复核" { return "review" }
    "成功" { return "ok" }
    default { return "review" }
  }
}

function New-Badge {
  param([string]$Text)
  $class = Get-BadgeClass $Text
  return "<span class=`"badge $class`">$(ConvertTo-HtmlText $Text)</span>"
}

function ConvertTo-StatusLabel {
  param([string]$Status)
  switch ($Status) {
    "open" { return "已确认/待处理" }
    "accepted" { return "暂不修复" }
    "false_positive" { return "误报" }
    "fixed" { return "已修复" }
    default {
      if ([string]::IsNullOrWhiteSpace($Status)) { return "未标记" }
      return $Status
    }
  }
}

function New-Tag {
  param([AllowNull()][object]$Text)
  if ($null -eq $Text -or [string]::IsNullOrWhiteSpace([string]$Text)) {
    return ""
  }
  return "<span class=`"tag`">$(ConvertTo-HtmlText $Text)</span>"
}

function New-Table {
  param(
    [array]$Headers,
    [array]$Rows
  )
  if ($Rows.Count -eq 0) { return "<div class=`"empty`">无记录。</div>" }
  $html = "<table><thead><tr>"
  foreach ($header in $Headers) {
    $html += "<th>$(ConvertTo-HtmlText $header)</th>"
  }
  $html += "</tr></thead><tbody>"
  foreach ($row in $Rows) {
    $html += "<tr>"
    foreach ($cell in $row) {
      $html += "<td>$cell</td>"
    }
    $html += "</tr>"
  }
  $html += "</tbody></table>"
  return $html
}

function Assert-ReportSchema {
  param([object]$Report)
  foreach ($required in @("project", "repository", "auditTime", "summary", "findings")) {
    if (-not $Report.PSObject.Properties[$required]) {
      throw "审计 JSON 缺少必填字段：$required"
    }
  }
  $allowedSeverity = @("高", "中", "低", "待复核")
  foreach ($finding in (Get-Array $Report.findings)) {
    if ([string]::IsNullOrWhiteSpace([string](Get-Prop $finding "title"))) {
      throw "审计 JSON 存在缺少 title 的 finding。"
    }
    $severity = [string](Get-Prop $finding "severity")
    if (-not ($allowedSeverity -contains $severity)) {
      throw "finding '$((Get-Prop $finding "title"))' 的 severity 非法：$severity"
    }
  }
}

function New-InventorySection {
  param([AllowNull()][object]$Inventory)
  if ($null -eq $Inventory) {
    return "<h2 id=`"inventory`">项目盘点</h2><div class=`"empty`">未提供项目盘点数据。</div>"
  }

  $html = "<h2 id=`"inventory`">项目盘点</h2>"
  $html += "<section><div class=`"kv`">"
  $html += "<div><strong>文件数</strong><span>$(ConvertTo-HtmlText (Get-Prop $Inventory "fileCount" "0"))</span></div>"
  $html += "<div><strong>源码文件</strong><span>$(ConvertTo-HtmlText (Get-Prop $Inventory "sourceFileCount" "0"))</span></div>"
  $html += "<div><strong>源码行数</strong><span>$(ConvertTo-HtmlText (Get-Prop $Inventory "totalSourceLines" "0"))</span></div>"
  $html += "<div><strong>测试文件</strong><span>$(ConvertTo-HtmlText (Get-Prop $Inventory "testFileCount" "0"))</span></div>"
  $html += "</div>"

  $langRows = @()
  foreach ($lang in (Get-Array (Get-Prop $Inventory "languageStats" @()))) {
    $langRows += ,@(
      (ConvertTo-HtmlText (Get-Prop $lang "language")),
      (ConvertTo-HtmlText (Get-Prop $lang "files")),
      (ConvertTo-HtmlText (Get-Prop $lang "lines")),
      (ConvertTo-HtmlText ((Get-Array (Get-Prop $lang "extensions" @())) -join "、"))
    )
  }
  $html += "<h3>语言分布</h3>"
  $html += New-Table -Headers @("语言", "文件数", "行数", "扩展名") -Rows $langRows

  $manifestRows = @()
  foreach ($manifest in (Get-Array (Get-Prop $Inventory "manifests" @()))) {
    $manifestRows += ,@(
      (ConvertTo-HtmlText (Get-Prop $manifest "path")),
      (ConvertTo-HtmlText (Get-Prop $manifest "type"))
    )
  }
  $html += "<h3>构建与依赖清单</h3>"
  $html += New-Table -Headers @("路径", "类型") -Rows $manifestRows

  $riskRows = @()
  foreach ($risk in (Get-Array (Get-Prop $Inventory "riskHints" @()))) {
    $examples = (Get-Array (Get-Prop $risk "examples" @()) | Select-Object -First 3 | ForEach-Object {
      "$(Get-Prop $_ "location") => $(Get-Prop $_ "text")"
    }) -join "`n"
    $riskRows += ,@(
      (ConvertTo-HtmlText (Get-Prop $risk "name")),
      (ConvertTo-HtmlText (Get-Prop $risk "dimension")),
      (ConvertTo-HtmlText (Get-Prop $risk "count")),
      (ConvertTo-HtmlBlock $examples)
    )
  }
  $html += "<h3>风险面提示</h3>"
  $html += New-Table -Headers @("风险面", "维度", "命中数", "示例") -Rows $riskRows
  $html += "</section>"
  return $html
}

function New-AuditMetadataSection {
  param([object]$Report)
  $config = Get-Prop $Report "config" $null
  $options = Get-Prop $Report "reportOptions" $null
  $rows = @()
  $rows += ,@("配置文件", (ConvertTo-HtmlText (Get-Prop $config "path" "未加载")))
  $rows += ,@("启用语言", (ConvertTo-HtmlText ((Get-Array (Get-Prop $config "languages" @())) -join "、")))
  $rows += ,@("增量审计", (ConvertTo-HtmlText (Get-Prop $config "changedOnly" $false)))
  $rows += ,@("评分阈值", (ConvertTo-HtmlText (Get-Prop $config "minScore" 0)))
  $rows += ,@("高危门禁", (ConvertTo-HtmlText (Get-Prop $config "failOnHigh" $false)))
  $rows += ,@("报告脱敏", (ConvertTo-HtmlText (Get-Prop $options "redacted" $false)))
  return "<h2 id=`"audit-meta`">审计配置与交付选项</h2>" + (New-Table -Headers @("项目", "值") -Rows $rows)
}

function New-DiffSection {
  param([AllowNull()][object]$DiffInfo)
  $html = "<h2 id=`"diff`">增量审计信息</h2>"
  if ($null -eq $DiffInfo -or -not (Get-Prop $DiffInfo "enabled" $false)) {
    return $html + "<div class=`"empty`">未启用增量审计。</div>"
  }
  $rows = @()
  $rows += ,@("可用状态", (ConvertTo-HtmlText (Get-Prop $DiffInfo "available" $false)))
  $rows += ,@("基线", (ConvertTo-HtmlText (Get-Prop $DiffInfo "base" "")))
  $rows += ,@("目标", (ConvertTo-HtmlText (Get-Prop $DiffInfo "target" "")))
  $rows += ,@("变更文件数", (ConvertTo-HtmlText (Get-Prop $DiffInfo "changedFileCount" 0)))
  $rows += ,@("纳入审计源码数", (ConvertTo-HtmlText (Get-Prop $DiffInfo "auditedChangedSourceFileCount" 0)))
  $rows += ,@("说明", (ConvertTo-HtmlBlock (Get-Prop $DiffInfo "reason" "")))
  $html += New-Table -Headers @("项目", "值") -Rows $rows
  $files = Get-Array (Get-Prop $DiffInfo "files" @()) | Select-Object -First 30
  if ($files.Count -gt 0) {
    $fileRows = @($files | ForEach-Object { ,@((ConvertTo-HtmlText $_)) })
    $html += "<h3>变更文件样例</h3>"
    $html += New-Table -Headers @("路径") -Rows $fileRows
  }
  return $html
}

function New-BaselineSection {
  param([AllowNull()][object]$Baseline)
  $html = "<h2 id=`"baseline`">误报与基线管理</h2>"
  if ($null -eq $Baseline -or -not (Get-Prop $Baseline "enabled" $false)) {
    return $html + "<div class=`"empty`">未启用误报/风险接受基线。</div>"
  }
  $rows = @()
  $rows += ,@("基线文件", (ConvertTo-HtmlText (Get-Prop $Baseline "path" "")))
  $rows += ,@("匹配数", (ConvertTo-HtmlText (Get-Prop $Baseline "matched" 0)))
  $rows += ,@("误报", (ConvertTo-HtmlText (Get-Prop $Baseline "falsePositive" 0)))
  $rows += ,@("暂不修复", (ConvertTo-HtmlText (Get-Prop $Baseline "accepted" 0)))
  $rows += ,@("已修复", (ConvertTo-HtmlText (Get-Prop $Baseline "fixed" 0)))
  $rows += ,@("缺失", (ConvertTo-HtmlText (Get-Prop $Baseline "missing" 0)))
  $rows += ,@("导出文件", (ConvertTo-HtmlText (Get-Prop $Baseline "exportedPath" "")))
  return $html + (New-Table -Headers @("项目", "值") -Rows $rows)
}

function New-ScaSection {
  param([AllowNull()][object]$Sca)
  $html = "<h2 id=`"sca`">供应链与 SBOM</h2>"
  if ($null -eq $Sca) {
    return $html + "<div class=`"empty`">未提供供应链审计数据。</div>"
  }
  $sbom = Get-Prop $Sca "sbom" $null
  $rows = @()
  $rows += ,@("SCA 启用", (ConvertTo-HtmlText (Get-Prop $Sca "enabled" $false)))
  $rows += ,@("SBOM 启用", (ConvertTo-HtmlText (Get-Prop $Sca "sbomEnabled" $false)))
  $rows += ,@("SBOM 已生成", (ConvertTo-HtmlText (Get-Prop $sbom "generated" $false)))
  $rows += ,@("SBOM 格式", (ConvertTo-HtmlText (Get-Prop $sbom "format" "")))
  $rows += ,@("SBOM 输出", (ConvertTo-HtmlText (Get-Prop $sbom "output" "")))
  $html += New-Table -Headers @("项目", "值") -Rows $rows

  $toolRows = @()
  foreach ($row in (Get-Array (Get-Prop $Sca "vulnerabilityTools" @()))) {
    $toolRows += ,@(
      (ConvertTo-HtmlText (Get-Prop $row "tool")),
      (ConvertTo-HtmlText (Get-Prop $row "vulnerabilities" 0)),
      (ConvertTo-HtmlText (Get-Prop $row "high" 0)),
      (ConvertTo-HtmlText (Get-Prop $row "medium" 0)),
      (ConvertTo-HtmlText (Get-Prop $row "low" 0)),
      (ConvertTo-HtmlText (Get-Prop $row "output" "")),
      (ConvertTo-HtmlBlock (Get-Prop $row "note" ""))
    )
  }
  $html += "<h3>漏洞扫描摘要</h3>"
  $html += New-Table -Headers @("工具", "漏洞数", "高", "中", "低", "输出", "说明") -Rows $toolRows
  return $html
}

function New-FindingSection {
  param(
    [string]$Title,
    [string]$Severity,
    [array]$Findings
  )
  $items = @($Findings | Where-Object { [string](Get-Prop $_ "severity") -eq $Severity })
  $html = "<h2 id=`"findings-$Severity`">$(ConvertTo-HtmlText $Title)</h2>"
  if ($items.Count -eq 0) {
    return $html + "<div class=`"empty`">未发现该级别问题。</div>"
  }

  foreach ($item in $items) {
    $badgeClass = Get-BadgeClass ([string](Get-Prop $item "severity"))
    $status = [string](Get-Prop $item "status" "open")
    $statusLabel = ConvertTo-StatusLabel $status
    $tagLine = ""
    foreach ($tag in @((Get-Prop $item "dimension"), (Get-Prop $item "priority"), ("置信度：" + [string](Get-Prop $item "confidence")), ("状态：" + $statusLabel), (Get-Prop $item "ruleId"), (Get-Prop $item "source"), (Get-Prop $item "cwe"), (Get-Prop $item "owasp"))) {
      $tagLine += New-Tag $tag
    }
    $searchText = "$(Get-Prop $item "id") $(Get-Prop $item "title") $(Get-Prop $item "location") $(Get-Prop $item "dimension") $(Get-Prop $item "ruleId") $(Get-Prop $item "evidence") $(Get-Prop $item "recommendation") $statusLabel"
    $html += "<details class=`"finding $badgeClass-border`" data-severity=`"$(ConvertTo-HtmlText (Get-Prop $item "severity"))`" data-dimension=`"$(ConvertTo-HtmlText (Get-Prop $item "dimension"))`" data-rule=`"$(ConvertTo-HtmlText (Get-Prop $item "ruleId"))`" data-status=`"$(ConvertTo-HtmlText $status)`" data-search=`"$(ConvertTo-HtmlText $searchText)`">"
    $html += "<summary class=`"finding-summary`">"
    $html += "<span class=`"finding-summary-main`">"
    $html += "<span class=`"finding-title`"><strong>$(ConvertTo-HtmlText (Get-Prop $item "id")) $(ConvertTo-HtmlText (Get-Prop $item "title"))</strong>$(New-Badge ([string](Get-Prop $item "severity")))</span>"
    $html += "<span class=`"location`">$(ConvertTo-HtmlText (Get-Prop $item "location"))</span>"
    $html += "<span class=`"tagline`">$tagLine</span>"
    $html += "</span>"
    $html += "<span class=`"summary-indicator`" aria-hidden=`"true`"></span>"
    $html += "</summary>"
    $html += "<div class=`"finding-body`">"
    if (-not [string]::IsNullOrWhiteSpace([string](Get-Prop $item "affectedComponent"))) {
      $html += "<div class=`"meta`">影响组件：$(ConvertTo-HtmlText (Get-Prop $item "affectedComponent"))　整改成本：$(ConvertTo-HtmlText (Get-Prop $item "remediationEffort"))　指纹：$(ConvertTo-HtmlText (Get-Prop $item "fingerprint"))</div>"
    }
    if (-not [string]::IsNullOrWhiteSpace([string](Get-Prop $item "baselineReason"))) {
      $html += "<div class=`"meta`">基线状态：$(ConvertTo-HtmlText $statusLabel)　责任人：$(ConvertTo-HtmlText (Get-Prop $item "baselineOwner"))　说明：$(ConvertTo-HtmlText (Get-Prop $item "baselineReason"))</div>"
    }
    $html += "<div class=`"label`">证据</div><pre class=`"evidence`">$(ConvertTo-HtmlText (Get-Prop $item "evidence"))</pre>"
    $html += "<div class=`"label`">影响</div><div>$(ConvertTo-HtmlBlock (Get-Prop $item "impact"))</div>"
    $html += "<div class=`"label`">整改建议</div><div>$(ConvertTo-HtmlBlock (Get-Prop $item "recommendation"))</div>"
    if (-not [string]::IsNullOrWhiteSpace([string](Get-Prop $item "confidenceReason"))) {
      $html += "<div class=`"label`">置信度说明</div><div>$(ConvertTo-HtmlBlock (Get-Prop $item "confidenceReason"))</div>"
    }
    if (-not [string]::IsNullOrWhiteSpace([string](Get-Prop $item "fixExample"))) {
      $html += "<div class=`"label`">示例修复</div><pre>$(ConvertTo-HtmlText (Get-Prop $item "fixExample"))</pre>"
    }
    $html += "</div></details>"
  }
  return $html
}

$inputPath = (Resolve-Path -LiteralPath $InputJson).Path
if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
  $scriptDir = Split-Path -Parent $PSCommandPath
  $TemplatePath = Join-Path (Split-Path -Parent $scriptDir) "assets\report-template.html"
}
$templateFullPath = (Resolve-Path -LiteralPath $TemplatePath).Path
$template = Get-Content -Raw -LiteralPath $templateFullPath -Encoding UTF8
$json = Get-Content -Raw -LiteralPath $inputPath -Encoding UTF8 | ConvertFrom-Json
Assert-ReportSchema -Report $json

$title = if ($json.project) { "$($json.project) 代码审计报告" } else { "代码审计报告" }
$summary = $json.summary
$stats = Get-Prop $json "stats" ([pscustomobject]@{ high = 0; medium = 0; low = 0; review = 0 })
$findingTotal = (Get-Array $json.findings).Count

$scopeText = (Get-Array $json.scope | ForEach-Object { ConvertTo-HtmlText $_ }) -join "，"
if ([string]::IsNullOrWhiteSpace($scopeText)) { $scopeText = "未说明" }

$body = @"
<header>
  <h1>$(ConvertTo-HtmlText $title)</h1>
  <div class="meta">项目：$(ConvertTo-HtmlText $json.project)　仓库：$(ConvertTo-HtmlText $json.repository)</div>
  <div class="meta">审计时间：$(ConvertTo-HtmlText $json.auditTime)　审计人：$(ConvertTo-HtmlText $json.auditor)　Schema：$(ConvertTo-HtmlText (Get-Prop $json "schemaVersion" "1.0"))</div>
  <div class="meta">审计范围：$scopeText</div>
</header>

<nav class="toc">
  <a href="#summary">总体结论</a>
  <a href="#audit-meta">审计配置</a>
  <a href="#inventory">项目盘点</a>
  <a href="#diff">增量审计</a>
  <a href="#baseline">误报基线</a>
  <a href="#sca">供应链</a>
  <a href="#dimensions">维度评分</a>
  <a href="#findings-高">高风险</a>
  <a href="#findings-中">中风险</a>
  <a href="#findings-低">低风险</a>
  <a href="#tools">工具记录</a>
  <a href="#limitations">限制项</a>
</nav>

<section id="summary">
  <h2>总体结论</h2>
  <div class="grid">
    <div class="card"><div class="metric">总分</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $summary "score"))</div></div>
    <div class="card"><div class="metric">评级</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $summary "rating"))</div></div>
    <div class="card"><div class="metric">风险等级</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $summary "riskLevel"))</div></div>
    <div class="card"><div class="metric">问题数量</div><div class="value">$((Get-Array $json.findings).Count)</div></div>
  </div>
  <p>$(ConvertTo-HtmlBlock (Get-Prop $summary "conclusion"))</p>
</section>

<h2>风险与问题统计</h2>
<div class="grid">
  <div class="card"><div class="metric">高风险</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $stats "high" 0))</div></div>
  <div class="card"><div class="metric">中风险</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $stats "medium" 0))</div></div>
  <div class="card"><div class="metric">低风险</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $stats "low" 0))</div></div>
  <div class="card"><div class="metric">待复核</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $stats "review" 0))</div></div>
  <div class="card"><div class="metric">有效问题</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $stats "active" $findingTotal))</div></div>
  <div class="card"><div class="metric">暂不修复</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $stats "accepted" 0))</div></div>
  <div class="card"><div class="metric">误报</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $stats "falsePositive" 0))</div></div>
  <div class="card"><div class="metric">已修复</div><div class="value">$(ConvertTo-HtmlText (Get-Prop $stats "fixed" 0))</div></div>
</div>
"@

$body += New-AuditMetadataSection -Report $json
$body += New-InventorySection -Inventory (Get-Prop $json "inventory" $null)
$body += New-DiffSection -DiffInfo (Get-Prop $json "diff" $null)
$body += New-BaselineSection -Baseline (Get-Prop $json "baseline" $null)
$body += New-ScaSection -Sca (Get-Prop $json "sca" $null)

$dimensionRows = @()
foreach ($row in (Get-Array $json.dimensionScores)) {
  $dimensionRows += ,@(
    (ConvertTo-HtmlText (Get-Prop $row "dimension")),
    (ConvertTo-HtmlText (Get-Prop $row "weight")),
    (ConvertTo-HtmlText (Get-Prop $row "score")),
    (ConvertTo-HtmlBlock (Get-Prop $row "summary"))
  )
}
$body += "<h2 id=`"dimensions`">维度评分明细</h2>"
$body += New-Table -Headers @("维度", "权重", "得分", "说明") -Rows $dimensionRows

$findings = Get-Array $json.findings
if ($findings.Count -gt 0) {
  $dimensionOptions = "<option value=`"`">全部维度</option>"
  foreach ($dimensionName in @($findings | ForEach-Object { [string](Get-Prop $_ "dimension") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
    $dimensionOptions += "<option value=`"$(ConvertTo-HtmlText $dimensionName)`">$(ConvertTo-HtmlText $dimensionName)</option>"
  }
  $body += "<div class=`"finding-controls`"><input type=`"search`" data-finding-search placeholder=`"检索问题、位置、规则或证据`"><select data-filter-severity><option value=`"`">全部风险</option><option value=`"高`">高</option><option value=`"中`">中</option><option value=`"低`">低</option><option value=`"待复核`">待复核</option></select><select data-filter-dimension>$dimensionOptions</select><span class=`"filter-count`" data-finding-count>$($findings.Count) 条</span><button type=`"button`" data-expand-findings>全部展开</button><button type=`"button`" data-collapse-findings>全部收起</button></div>"
}
$body += New-FindingSection -Title "高风险问题" -Severity "高" -Findings $findings
$body += New-FindingSection -Title "中风险问题" -Severity "中" -Findings $findings
$body += New-FindingSection -Title "低风险问题与优化建议" -Severity "低" -Findings $findings
$body += New-FindingSection -Title "待复核项" -Severity "待复核" -Findings $findings

$roadmapRows = @()
foreach ($row in (Get-Array $json.roadmap)) {
  $roadmapRows += ,@(
    (ConvertTo-HtmlText (Get-Prop $row "priority")),
    (ConvertTo-HtmlBlock (Get-Prop $row "action")),
    (ConvertTo-HtmlText (Get-Prop $row "owner")),
    (ConvertTo-HtmlText (Get-Prop $row "due"))
  )
}
$body += "<h2 id=`"roadmap`">整改优先级与路线图</h2>"
$body += New-Table -Headers @("优先级", "整改事项", "负责人", "建议期限") -Rows $roadmapRows

$toolRows = @()
foreach ($row in (Get-Array $json.tools)) {
  $status = [string](Get-Prop $row "status")
  $toolRows += ,@(
    (ConvertTo-HtmlText (Get-Prop $row "name")),
    (ConvertTo-HtmlText (Get-Prop $row "version")),
    "<code>$(ConvertTo-HtmlText (Get-Prop $row "command" (Get-Prop $row "installMethod")))</code>",
    (ConvertTo-HtmlText $status),
    (ConvertTo-HtmlText (Get-Prop $row "exitCode")),
    (ConvertTo-HtmlText (Get-Prop $row "durationMs")),
    (ConvertTo-HtmlBlock (Get-Prop $row "summary" (Get-Prop $row "note")))
  )
}
$body += "<h2 id=`"tools`">工具与命令记录</h2>"
$body += New-Table -Headers @("工具", "版本", "命令", "状态", "退出码", "耗时(ms)", "摘要") -Rows $toolRows

$limitations = Get-Array $json.limitations
$body += "<h2 id=`"limitations`">未覆盖范围与待复核项</h2>"
if ($limitations.Count -eq 0) {
  $body += "<div class=`"empty`">无未覆盖范围记录。</div>"
} else {
  $body += "<ul>"
  foreach ($item in $limitations) {
    $body += "<li>$(ConvertTo-HtmlBlock $item)</li>"
  }
  $body += "</ul>"
}

$html = $template.Replace("{{TITLE}}", (ConvertTo-HtmlText $title)).Replace("{{BODY}}", $body)
$outputFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputHtml)
$outputDir = Split-Path -Parent $outputFullPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}
[System.IO.File]::WriteAllText($outputFullPath, $html, [System.Text.UTF8Encoding]::new($false))
Write-Output "HTML report written to $outputFullPath"
