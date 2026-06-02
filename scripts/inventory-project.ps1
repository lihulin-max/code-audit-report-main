param(
  [string]$ProjectPath = ".",
  [string]$OutputJson = "",
  [string[]]$ExcludeDirs = @(".git", ".svn", ".hg", "node_modules", "vendor", "third_party", "build", "cmake-build-debug", "cmake-build-release", "out", "dist", "target", "bin", "obj", ".audit-tools", ".venv", "venv", "__pycache__")
)

$ErrorActionPreference = "Stop"

function Test-Command {
  param([string]$Name)
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ProjectFiles {
  param([string]$RootPath)
  if (Test-Command "rg") {
    try {
      $rgFiles = & rg --files $RootPath 2>$null
      if ($LASTEXITCODE -eq 0) {
        return @($rgFiles | ForEach-Object { [string]$_ } | Sort-Object)
      }
    } catch {
      # Fall through to the PowerShell enumerator when rg is present but cannot run.
    }
  }
  return @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -Force | Sort-Object FullName | ForEach-Object { $_.FullName })
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

function Test-ExcludedPath {
  param(
    [string]$RelativePath,
    [string[]]$Dirs
  )
  $parts = $RelativePath -split '[\\/]'
  foreach ($part in $parts) {
    foreach ($dir in $Dirs) {
      if ($part.Equals($dir, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
      }
    }
  }
  if ($RelativePath -match '\.min\.(js|css)$') {
    return $true
  }
  return $false
}

function Get-TextLineCount {
  param([string]$Path)
  try {
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.Length -gt 5MB) {
      return 0
    }
    return (Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop | Measure-Object -Line).Lines
  } catch {
    return 0
  }
}

function Get-LanguageName {
  param([string]$Extension)
  switch ($Extension.ToLowerInvariant()) {
    ".java" { return "Java" }
    ".c" { return "C++" }
    ".cc" { return "C++" }
    ".cpp" { return "C++" }
    ".cxx" { return "C++" }
    ".h" { return "C++" }
    ".hh" { return "C++" }
    ".hpp" { return "C++" }
    ".hxx" { return "C++" }
    ".cs" { return "C#" }
    ".ps1" { return "PowerShell" }
    ".psm1" { return "PowerShell" }
    ".sh" { return "Shell" }
    ".bash" { return "Shell" }
    ".zsh" { return "Shell" }
    ".ksh" { return "Shell" }
    ".kt" { return "Kotlin" }
    ".kts" { return "Kotlin" }
    ".bat" { return "BAT/CMD" }
    ".cmd" { return "BAT/CMD" }
    ".razor" { return "Blazor" }
    ".cshtml" { return "Blazor" }
    ".xaml" { return "XAML/WPF" }
    ".css" { return "CSS" }
    ".scss" { return "CSS" }
    ".less" { return "CSS" }
    ".lua" { return "Lua" }
    ".php" { return "PHP" }
    ".phtml" { return "PHP" }
    ".py" { return "Python" }
    ".pyw" { return "Python" }
    ".go" { return "Go" }
    ".js" { return "JavaScript" }
    ".jsx" { return "JavaScript" }
    ".mjs" { return "JavaScript" }
    ".cjs" { return "JavaScript" }
    ".ts" { return "TypeScript" }
    ".tsx" { return "TypeScript" }
    ".sql" { return "SQL" }
    ".html" { return "HTML" }
    ".xml" { return "XML" }
    ".yml" { return "YAML" }
    ".yaml" { return "YAML" }
    ".json" { return "JSON" }
    ".md" { return "Markdown" }
    default { return "" }
  }
}

function Add-Unique {
  param(
    [System.Collections.Generic.List[object]]$List,
    [object]$Value
  )
  if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
    if (-not ($List -contains $Value)) {
      $List.Add($Value) | Out-Null
    }
  }
}

$projectFullPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$allFiles = Get-ProjectFiles -RootPath $projectFullPath

$files = New-Object System.Collections.Generic.List[object]
$sourceFiles = New-Object System.Collections.Generic.List[object]
$excludedFiles = New-Object System.Collections.Generic.List[object]
$languageBuckets = @{}
$manifests = New-Object System.Collections.Generic.List[object]
$buildSystems = New-Object System.Collections.Generic.List[object]
$ciFiles = New-Object System.Collections.Generic.List[object]
$configFiles = New-Object System.Collections.Generic.List[object]
$testFiles = New-Object System.Collections.Generic.List[object]
$entryPoints = New-Object System.Collections.Generic.List[object]
$topLevelDirs = New-Object System.Collections.Generic.List[object]

$manifestRules = @(
  @{ pattern = "pom.xml"; type = "Java/Maven" },
  @{ pattern = "build.gradle"; type = "Java/Kotlin Gradle" },
  @{ pattern = "build.gradle.kts"; type = "Java/Kotlin Gradle" },
  @{ pattern = "settings.gradle"; type = "Gradle settings" },
  @{ pattern = "settings.gradle.kts"; type = "Gradle settings" },
  @{ pattern = "CMakeLists.txt"; type = "C/C++ CMake" },
  @{ pattern = "conanfile.*"; type = "C/C++ Conan" },
  @{ pattern = "vcpkg.json"; type = "C/C++ vcpkg" },
  @{ pattern = "*.sln"; type = ".NET solution" },
  @{ pattern = "*.csproj"; type = ".NET project" },
  @{ pattern = "package.json"; type = "Node package" },
  @{ pattern = "package-lock.json"; type = "Node lock" },
  @{ pattern = "pnpm-lock.yaml"; type = "Node lock" },
  @{ pattern = "yarn.lock"; type = "Node lock" },
  @{ pattern = "requirements.txt"; type = "Python requirements" },
  @{ pattern = "pyproject.toml"; type = "Python project" },
  @{ pattern = "Pipfile"; type = "Python Pipfile" },
  @{ pattern = "composer.json"; type = "PHP Composer" },
  @{ pattern = "composer.lock"; type = "PHP lock" },
  @{ pattern = "Dockerfile"; type = "Container" },
  @{ pattern = "docker-compose*.yml"; type = "Container" },
  @{ pattern = "docker-compose*.yaml"; type = "Container" }
)

$configPatterns = @("*.properties", "*.ini", "*.conf", "*.config", "*.yml", "*.yaml", "*.json", "*.xml", ".env", ".env.*", "appsettings*.json", "application*.yml", "application*.yaml")
$ciPatterns = @(".github/workflows/*", ".gitlab-ci.yml", "Jenkinsfile", "azure-pipelines.yml", "gitee-pipeline.yml", ".gitee/workflows/*")
$entryNames = @("main.cpp", "main.c", "main.cc", "Program.cs", "Startup.cs", "app.py", "main.py", "index.php", "Application.java")

foreach ($path in $allFiles) {
  $full = (Resolve-Path -LiteralPath $path).Path
  $rel = Get-RelativePath -BasePath $projectFullPath -FullPath $full
  if (Test-ExcludedPath -RelativePath $rel -Dirs $ExcludeDirs) {
    $excludedFiles.Add($rel) | Out-Null
    continue
  }

  $leaf = Split-Path -Leaf $rel
  $dir = Split-Path -Parent $rel
  if (-not [string]::IsNullOrWhiteSpace($dir)) {
    $first = ($dir -split '[\\/]')[0]
    Add-Unique -List $topLevelDirs -Value $first
  }

  $ext = [System.IO.Path]::GetExtension($rel).ToLowerInvariant()
  $language = Get-LanguageName -Extension $ext
  if ([string]::IsNullOrWhiteSpace($language)) {
    switch -Regex ($leaf) {
      '^(Dockerfile|Containerfile)(\..*)?$' { $language = "Config"; break }
      '^(Jenkinsfile|Makefile)$' { $language = "Config"; break }
    }
  }
  $lineCount = 0
  if (-not [string]::IsNullOrWhiteSpace($language)) {
    $lineCount = Get-TextLineCount -Path $full
    if (-not $languageBuckets.ContainsKey($language)) {
      $languageBuckets[$language] = [ordered]@{
        language = $language
        files = 0
        lines = 0
        extensions = New-Object System.Collections.Generic.List[object]
      }
    }
    $bucket = $languageBuckets[$language]
    $bucket["files"] = [int]$bucket["files"] + 1
    $bucket["lines"] = [int]$bucket["lines"] + $lineCount
    Add-Unique -List $bucket["extensions"] -Value $ext
    $sourceFiles.Add([ordered]@{
      path = $rel
      language = $language
      lines = $lineCount
    }) | Out-Null
  }

  $files.Add([ordered]@{
    path = $rel
    extension = $ext
    language = $language
    lines = $lineCount
  }) | Out-Null

  foreach ($rule in $manifestRules) {
    if ($leaf -like $rule.pattern -or $rel -like $rule.pattern) {
      $manifests.Add([ordered]@{ path = $rel; type = $rule.type }) | Out-Null
      Add-Unique -List $buildSystems -Value $rule.type
    }
  }

  foreach ($pattern in $configPatterns) {
    if ($leaf -like $pattern) {
      $configFiles.Add($rel) | Out-Null
      break
    }
  }

  foreach ($pattern in $ciPatterns) {
    $normalizedRel = $rel -replace '\\', '/'
    if ($normalizedRel -like $pattern) {
      $ciFiles.Add($rel) | Out-Null
      break
    }
  }

  if ($rel -match '(^|[\\/])(test|tests|__tests__)([\\/]|$)' -or $leaf -match '(?i)(test|tests|spec)\.') {
    $testFiles.Add($rel) | Out-Null
  }

  if ($entryNames -contains $leaf) {
    $entryPoints.Add($rel) | Out-Null
  }
}

$riskPatterns = @(
  @{ name = "Shell/命令执行"; dimension = "安全性"; pattern = '(std::system\s*\(|\bsystem\s*\(|popen\s*\(|arch::shell::exec\s*\(|Runtime\.getRuntime|ProcessBuilder|shell\s*=\s*True|eval\s*\(|exec\s*\()' },
  @{ name = "并发/异步生命周期"; dimension = "可靠性"; pattern = '(asio::detached|\.detach\s*\(|std::thread|std::jthread|thread_local|std::atomic|Task\.Run|asyncio)' },
  @{ name = "文件/路径操作"; dimension = "安全性"; pattern = '(std::filesystem|std::ofstream|std::ifstream|File\.|Directory\.|open\s*\(|Path\.Combine)' },
  @{ name = "敏感信息关键词"; dimension = "安全性"; pattern = '(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]' },
  @{ name = "反序列化/动态执行"; dimension = "安全性"; pattern = '(pickle\.loads|yaml\.load|BinaryFormatter|ObjectInputStream|unserialize\s*\(|eval\s*\()' },
  @{ name = "业务回退/默认假设"; dimension = "功能正确性"; pattern = '(?i)(assuming\s+\w+|fallback|default|unknown.*return|return\s+ModemType::unknown)' },
  @{ name = "异常日志/可观测性"; dimension = "可观测性与运维性"; pattern = '(catch\s*\(\s*\.\.\.\s*\)|printStackTrace|console\.log|std::cerr|fmt::format\("Exception)' },
  @{ name = "待办/未实现"; dimension = "可维护性"; pattern = '(TODO|FIXME|Not implemented)' }
)

$riskHints = New-Object System.Collections.Generic.List[object]
foreach ($risk in $riskPatterns) {
  $count = 0
  $examples = New-Object System.Collections.Generic.List[object]
  foreach ($src in @($sourceFiles.ToArray() | Sort-Object { [string]$_.path })) {
    $relativePath = [string]$src.path
    if ($relativePath -match '(^|[\\/])(test|tests|__tests__)([\\/]|$)' -or (Split-Path -Leaf $relativePath) -match '(?i)(test|tests|spec)\.') {
      continue
    }
    $full = Join-Path $projectFullPath $src.path
    try {
      $lines = @(Get-Content -LiteralPath $full -Encoding UTF8 -ErrorAction Stop)
    } catch {
      continue
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $text = [string]$lines[$i]
      $trimmed = $text.Trim()
      if ($trimmed.StartsWith("//") -or $trimmed.StartsWith("#")) {
        continue
      }
      if ($text -match $risk.pattern) {
        $count++
        if ($examples.Count -lt 5) {
          $examples.Add([ordered]@{
            location = "$($src.path):$($i + 1)"
            text = $trimmed
          }) | Out-Null
        }
      }
    }
  }
  if ($count -gt 0) {
        $riskHints.Add([ordered]@{
      name = $risk.name
      dimension = $risk.dimension
      count = $count
      examples = @($examples.ToArray())
    }) | Out-Null
  }
}

$languageStats = New-Object System.Collections.Generic.List[object]
foreach ($key in ($languageBuckets.Keys | Sort-Object)) {
  $bucket = $languageBuckets[$key]
  $languageStats.Add([ordered]@{
    language = $bucket["language"]
    files = $bucket["files"]
    lines = $bucket["lines"]
    extensions = @($bucket["extensions"].ToArray())
  }) | Out-Null
}

$totalSourceLines = 0
foreach ($langStat in $languageStats) {
  $totalSourceLines += [int]$langStat["lines"]
}

$inventory = [ordered]@{
  project = Split-Path -Leaf $projectFullPath
  path = $projectFullPath
  generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  fileCount = $files.Count
  sourceFileCount = $sourceFiles.Count
  excludedFileCount = $excludedFiles.Count
  totalSourceLines = $totalSourceLines
  languageStats = @($languageStats.ToArray())
  buildSystems = @($buildSystems.ToArray())
  manifests = @($manifests.ToArray())
  entryPoints = @($entryPoints.ToArray())
  topLevelDirs = @($topLevelDirs.ToArray() | Sort-Object)
  testFiles = @($testFiles.ToArray())
  testFileCount = $testFiles.Count
  ciFiles = @($ciFiles.ToArray())
  configFiles = @($configFiles.ToArray())
  riskHints = @($riskHints.ToArray())
  sourceFiles = @($sourceFiles.ToArray())
  excludedFilesSample = @($excludedFiles.ToArray() | Select-Object -First 50)
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
  $outputFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputJson)
  $outputDir = Split-Path -Parent $outputFullPath
  if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
  }
  $json = $inventory | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($outputFullPath, $json, [System.Text.UTF8Encoding]::new($false))
}

$inventory | ConvertTo-Json -Depth 8
