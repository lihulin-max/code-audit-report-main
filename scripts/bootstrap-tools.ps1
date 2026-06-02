param(
  [string]$ProjectPath = ".",
  [string[]]$Languages = @("Java", "Cpp", "CSharp", "Shell", "Kotlin", "Bat", "Blazor", "Xaml", "Css", "Lua", "Php", "Python", "Go", "JavaScript", "TypeScript", "SQL", "Config"),
  [switch]$InstallMissing,
  [string]$ToolsDir = ""
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

function Get-Version {
  param(
    [string]$Name,
    [string[]]$Args = @("--version")
  )
  try {
    $output = & $Name @Args 2>&1 | Select-Object -First 3
    return (($output -join " ") -replace "\s+", " ").Trim()
  } catch {
    return ""
  }
}

function Add-Result {
  param(
    [string]$Name,
    [string]$Status,
    [string]$Version = "",
    [string]$InstallMethod = "",
    [string]$Note = ""
  )
  [pscustomobject]@{
    name = $Name
    status = $Status
    version = $Version
    installMethod = $InstallMethod
    note = $Note
  }
}

function Invoke-Install {
  param(
    [string]$Name,
    [scriptblock]$Installer
  )
  if (-not $InstallMissing) {
    return Add-Result -Name $Name -Status "missing" -Note "未启用 InstallMissing，跳过安装。"
  }
  try {
    & $Installer
    if (Test-Command $Name) {
      return Add-Result -Name $Name -Status "installed" -Version (Get-Version $Name) -InstallMethod "auto"
    }
    return Add-Result -Name $Name -Status "install_failed" -Note "安装命令执行后仍不可用。"
  } catch {
    return Add-Result -Name $Name -Status "install_failed" -Note $_.Exception.Message
  }
}

$projectFullPath = (Resolve-Path -LiteralPath $ProjectPath).Path
if ([string]::IsNullOrWhiteSpace($ToolsDir)) {
  $ToolsDir = Join-Path $projectFullPath ".audit-tools"
}

$results = New-Object System.Collections.Generic.List[object]

function Ensure-Tool {
  param(
    [string]$Name,
    [scriptblock]$Installer
  )
  if (Test-Command $Name) {
    $results.Add((Add-Result -Name $Name -Status "available" -Version (Get-Version $Name)))
  } else {
    $results.Add((Invoke-Install -Name $Name -Installer $Installer))
  }
}

$normalized = $Languages | ForEach-Object { $_.ToLowerInvariant() }

function Has-Language {
  param([string[]]$Names)
  foreach ($name in $Names) {
    if ($normalized -contains $name.ToLowerInvariant()) {
      return $true
    }
  }
  return $false
}

if (Has-Language @("java")) {
  Ensure-Tool "java" { throw "请先安装 JDK，或使用项目配置的 JDK。" }
  Ensure-Tool "mvn" { throw "未找到 Maven。建议使用项目 Maven Wrapper，或安装 Maven 后重试。" }
  Ensure-Tool "gradle" { throw "未找到 Gradle。建议使用项目 Gradle Wrapper，或安装 Gradle 后重试。" }
}

if (Has-Language @("cpp", "c++", "c")) {
  Ensure-Tool "clang-tidy" {
    if (Test-Command "winget") {
      winget install --id LLVM.LLVM -e --accept-package-agreements --accept-source-agreements
    } else {
      throw "未找到 winget；请安装 LLVM/clang-tidy 后重试。"
    }
  }
  Ensure-Tool "cppcheck" {
    if (Test-Command "winget") {
      winget install --id Cppcheck.Cppcheck -e --accept-package-agreements --accept-source-agreements
    } else {
      throw "未找到 winget；请安装 cppcheck 后重试。"
    }
  }
}

if (Has-Language @("csharp", "c#", "dotnet", "blazor", "xaml", "wpf")) {
  Ensure-Tool "dotnet" { throw "请先安装 .NET SDK。" }
  if (Test-Command "dotnet") {
    try {
      dotnet tool restore | Out-Null
      $results.Add((Add-Result -Name "dotnet local tools" -Status "restored" -InstallMethod "dotnet tool restore"))
    } catch {
      $results.Add((Add-Result -Name "dotnet local tools" -Status "restore_failed" -Note $_.Exception.Message))
    }
  }
}

if (Has-Language @("shell", "bash", "sh", "zsh")) {
  Ensure-Tool "shellcheck" {
    if (Test-Command "winget") {
      winget install --id koalaman.shellcheck -e --accept-package-agreements --accept-source-agreements
    } else {
      throw "未找到 winget；请安装 ShellCheck 后重试。"
    }
  }
  Ensure-Tool "shfmt" {
    if (Test-Command "winget") {
      winget install --id mvdan.shfmt -e --accept-package-agreements --accept-source-agreements
    } else {
      throw "未找到 winget；请安装 shfmt 后重试。"
    }
  }
}

if (Has-Language @("kotlin", "kt")) {
  Ensure-Tool "java" { throw "请先安装 JDK，或使用项目配置的 JDK。" }
  Ensure-Tool "gradle" { throw "未找到 Gradle。建议使用项目 Gradle Wrapper，或安装 Gradle 后重试。" }
  Ensure-Tool "ktlint" {
    if (Test-Command "winget") {
      winget install --id Pinterest.ktlint -e --accept-package-agreements --accept-source-agreements
    } else {
      throw "未找到 winget；请通过 Gradle 插件或手工安装 ktlint。"
    }
  }
}

if (Has-Language @("bat", "cmd", "batch")) {
  $results.Add((Add-Result -Name "Windows batch review" -Status "manual" -Note "BAT/CMD 无通用官方静态分析器，按 references/language-bat.md 做人工审计，并配合 Gitleaks 做密钥扫描。"))
}

if (Has-Language @("css", "scss", "less")) {
  Ensure-Tool "node" { throw "请先安装 Node.js，或使用项目配置的前端工具链。" }
  Ensure-Tool "stylelint" {
    if (Test-Command "npm") {
      npm install --global stylelint
    } else {
      throw "未找到 npm；请通过项目 package.json 或 npm 安装 stylelint。"
    }
  }
  Ensure-Tool "prettier" {
    if (Test-Command "npm") {
      npm install --global prettier
    } else {
      throw "未找到 npm；请通过项目 package.json 或 npm 安装 prettier。"
    }
  }
}

if (Has-Language @("lua")) {
  Ensure-Tool "luacheck" {
    if (Test-Command "luarocks") {
      luarocks install luacheck
    } else {
      throw "未找到 luarocks；请安装 luacheck 或使用项目已有 Lua 工具链。"
    }
  }
  Ensure-Tool "stylua" {
    if (Test-Command "cargo") {
      cargo install stylua
    } else {
      throw "未找到 cargo；请安装 stylua 或使用项目已有格式化工具。"
    }
  }
}

if (Has-Language @("php")) {
  Ensure-Tool "php" { throw "请先安装 PHP CLI，或使用项目容器/CI 中的 PHP。" }
  Ensure-Tool "composer" { throw "请先安装 Composer，或使用项目 vendor/bin 中的工具。" }
  if (Test-Command "composer") {
    $results.Add((Add-Result -Name "composer audit" -Status "available" -InstallMethod "composer audit" -Note "审计时优先运行 composer audit。"))
  }
}

if (Has-Language @("python", "py")) {
  Ensure-Tool "python" { throw "请先安装 Python，或使用项目虚拟环境。" }
  Ensure-Tool "ruff" {
    if (Test-Command "pip") {
      pip install --user ruff
    } else {
      throw "未找到 pip；请通过项目虚拟环境安装 ruff。"
    }
  }
  Ensure-Tool "bandit" {
    if (Test-Command "pip") {
      pip install --user bandit
    } else {
      throw "未找到 pip；请通过项目虚拟环境安装 bandit。"
    }
  }
  Ensure-Tool "pip-audit" {
    if (Test-Command "pip") {
      pip install --user pip-audit
    } else {
      throw "未找到 pip；请通过项目虚拟环境安装 pip-audit。"
    }
  }
}

if (Has-Language @("go", "golang")) {
  Ensure-Tool "go" { throw "请先安装 Go SDK，或使用项目容器/CI 中的 Go 工具链。" }
  Ensure-Tool "gosec" {
    if (Test-Command "go") {
      go install github.com/securego/gosec/v2/cmd/gosec@latest
    } else {
      throw "未找到 go；请安装 gosec 或在 CI 中运行。"
    }
  }
  Ensure-Tool "staticcheck" {
    if (Test-Command "go") {
      go install honnef.co/go/tools/cmd/staticcheck@latest
    } else {
      throw "未找到 go；请安装 staticcheck 或在 CI 中运行。"
    }
  }
}

if (Has-Language @("javascript", "typescript", "js", "ts", "node")) {
  Ensure-Tool "node" { throw "请先安装 Node.js，或使用项目配置的前端/Node 工具链。" }
  Ensure-Tool "npm" { throw "未找到 npm；请使用项目包管理器或安装 Node.js。" }
  Ensure-Tool "eslint" {
    if (Test-Command "npm") {
      npm install --global eslint
    } else {
      throw "未找到 npm；请通过项目 package.json 安装 ESLint。"
    }
  }
}

if (Has-Language @("sql")) {
  $results.Add((Add-Result -Name "SQL review" -Status "manual" -Note "SQL 审计以预编译、权限、事务、索引和迁移脚本人工复核为主；可结合项目数据库工具输出执行计划。"))
}

if (Has-Language @("config", "yaml", "dockerfile", "container", "ci")) {
  Ensure-Tool "trivy" {
    if (Test-Command "winget") {
      winget install --id AquaSecurity.Trivy -e --accept-package-agreements --accept-source-agreements
    } else {
      throw "未找到 winget；请安装 trivy 或在 CI 中运行配置/容器扫描。"
    }
  }
}

Ensure-Tool "semgrep" {
  if (Test-Command "pipx") {
    pipx install semgrep
  } elseif (Test-Command "pip") {
    pip install --user semgrep
  } else {
    throw "未找到 pipx 或 pip，无法自动安装 semgrep。"
  }
}

Ensure-Tool "gitleaks" {
  if (Test-Command "winget") {
    winget install --id Gitleaks.Gitleaks -e --accept-package-agreements --accept-source-agreements
  } else {
    throw "未找到 winget；请安装 gitleaks 后重试。"
  }
}

$results | ConvertTo-Json -Depth 4
