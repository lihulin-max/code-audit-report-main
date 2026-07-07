# code-audit-report

`code-audit-report` 是一个 Codex Skill，用于对程序代码进行多维度审查审计，并生成可交付的离线 HTML 审计报告。

审计范围覆盖架构合理性、功能正确性、编码规范性、安全性、可靠性、可维护性、性能与资源、可观测性与运维性、测试质量、依赖与供应链风险以及工具结果。审计结论必须基于源码、配置、依赖清单、工具输出、提交记录或设计材料；证据不足的问题应标记为“待复核”。

## 支持语言

| 类型 | 参考文件 |
|---|---|
| Java | `references/language-java.md` |
| C++ / C | `references/language-cpp.md` |
| C# / .NET | `references/language-csharp.md` |
| Shell / Bash / sh | `references/language-shell.md` |
| Kotlin | `references/language-kotlin.md` |
| BAT / CMD 批处理 | `references/language-bat.md` |
| Blazor / Razor | `references/language-blazor.md` |
| XAML / WPF | `references/language-xaml-wpf.md` |
| CSS / SCSS / LESS | `references/language-css.md` |
| Lua | `references/language-lua.md` |
| PHP | `references/language-php.md` |
| Python | `references/language-python.md` |
| Go | `references/language-go.md` |
| JavaScript / TypeScript | `references/language-js-ts.md` |
| SQL | `references/language-sql.md` |
| 配置 / CI / 容器 | `references/language-config.md` |

规范参考包括阿里巴巴 Java 开发手册、Google C++/Shell/Python/HTML-CSS 风格建议、Microsoft .NET/Blazor/WPF 指南、Kotlin 官方规范、PSR-12、PEP 8、OWASP、CWE 以及常见大厂工程实践。

## 目录结构

```text
code-audit-report/
  SKILL.md
  README.md
  audit-config.yml
  agents/
  assets/
    report-template.html
  custom-rules/
    README.md
  references/
    detailed-design.md
    audit-workflow.md
    scoring-rubric.md
    security-checklist.md
    report-schema.md
    report-style-from-examples.md
    false-positive-handling.md
    language-*.md
  rules/
    common-correctness.json
    common-observability.json
    common-security.json
    common-reliability.json
    common-supply-chain.json
    cpp-google-core.json
    cpp-numeric-boundaries.json
    java-alibaba.json
    python-pep8-bandit.json
  sca/
    README.md
  scripts/
    bootstrap-tools.ps1
    git-diff-audit.ps1
    inventory-project.ps1
    import-tool-results.ps1
    render-report.ps1
    run-audit.ps1
```

## 设计文档

详细设计说明见 `references/detailed-design.md`。该文档说明 Skill 的系统定位、设计目标、总体架构、核心模块、数据模型、评分体系、配置机制、安全设计、扩展机制、验证方式和演进规划。

## 安装

将整个目录复制到 Codex Skills 目录：

```powershell
Copy-Item -Path .\code-audit-report -Destination "$env:USERPROFILE\.codex\skills\code-audit-report" -Recurse -Force
```

如果当前目录就是 `code-audit-report`：

```powershell
Copy-Item -Path . -Destination "$env:USERPROFILE\.codex\skills\code-audit-report" -Recurse -Force
```

安装后可直接在 Codex 中请求：

```text
使用 code-audit-report 审计这个项目，并生成 HTML 审计报告。
```

## 一键审计

推荐入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-audit.ps1 `
  -ProjectPath "D:\path\to\project" `
  -OutputDir "D:\audit-output"
```

允许自动安装缺失工具时：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-audit.ps1 `
  -ProjectPath "D:\path\to\project" `
  -OutputDir "D:\audit-output" `
  -InstallMissing
```

输出包括：

- `<project>.inventory.json`：项目盘点结果；
- `<project>.audit.json`：结构化审计结果；
- `<project>.audit.html`：最终 HTML 审计报告。

## 配置化审计

脚本会优先读取被审计项目根目录下的 `audit-config.yml`，否则读取 Skill 自带的默认 `audit-config.yml`。常用配置：

```yaml
audit:
  languages: []
  changedOnly: false
  diffBase: ""
  diffTarget: "HEAD"
  minScore: 80
  failOnHigh: true
  baselinePath: ".audit-baseline.json"
  excludeDirs:
    - .git
    - node_modules
    - build

report:
  outputDir: ".audit-output"
  redact: false

sca:
  enabled: true
  sbomEnabled: true
```

命令行参数优先级高于配置文件。配置文件解析器支持简单 YAML：键值、一级嵌套对象和数组。

## 增量审计与 CI 门禁

只审计 Git 变更文件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-audit.ps1 `
  -ProjectPath "D:\path\to\project" `
  -OutputDir "D:\audit-output" `
  -ChangedOnly `
  -DiffBase "origin/main" `
  -DiffTarget "HEAD"
```

也可以使用增量审计包装脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\git-diff-audit.ps1 `
  -ProjectPath "D:\path\to\project" `
  -OutputDir "D:\audit-output" `
  -DiffBase "origin/main"
```

门禁参数：

- `-MinScore 80`：总分低于阈值时返回非 0；
- `-FailOnHigh`：存在 `open` 状态高危问题时返回非 0；
- `accepted` 状态的问题保留在报告中，但不触发高危门禁。

## 误报基线

导出基线：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-audit.ps1 `
  -ProjectPath "D:\path\to\project" `
  -OutputDir "D:\audit-output" `
  -ExportBaselinePath "D:\audit-output\audit-baseline.json"
```

应用基线：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-audit.ps1 `
  -ProjectPath "D:\path\to\project" `
  -OutputDir "D:\audit-output" `
  -BaselinePath "D:\audit-output\audit-baseline.json"
```

基线支持 `open`、`accepted`、`false_positive`、`fixed` 四类状态，处理规范见 `references/false-positive-handling.md`。

## 供应链审计与 SBOM

一键审计会在本地工具存在时运行 `trivy`、`grype`、`osv-scanner`，并通过 `syft` 生成 CycloneDX JSON SBOM。缺少工具时不会中断审计，报告会记录 `missing` 状态。需要关闭时：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-audit.ps1 `
  -ProjectPath "D:\path\to\project" `
  -OutputDir "D:\audit-output" `
  -DisableSca `
  -DisableSbom
```

## 报告脱敏

对外交付时可启用路径和内网地址脱敏：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-audit.ps1 `
  -ProjectPath "D:\path\to\project" `
  -OutputDir "D:\audit-output" `
  -RedactReport
```

脱敏会替换项目根路径、报告输出路径、用户目录和常见内网 IP。报告仍保留相对文件位置、规则 ID、证据和整改建议。

## 项目盘点

只生成项目清单：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\inventory-project.ps1 `
  -ProjectPath "D:\path\to\project" `
  -OutputJson ".\inventory.json"
```

盘点内容包括语言分布、源码行数、构建系统、依赖清单、入口点、测试文件、配置文件、CI 文件和风险面提示。

## 工具检测和安装

只检测本机或项目已有工具：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-tools.ps1 `
  -ProjectPath "D:\path\to\project" `
  -Languages Java,Cpp,Python,Shell
```

允许安装缺失工具：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-tools.ps1 `
  -ProjectPath "D:\path\to\project" `
  -Languages Java,Cpp,Python,Shell `
  -InstallMissing
```

脚本优先使用项目级或临时工具；确需全局安装时会记录安装方式、版本和失败原因。

## 导入工具结果

支持导入 SARIF、Semgrep JSON 和 Gitleaks JSON：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\import-tool-results.ps1 `
  -InputPath ".\semgrep.json" `
  -Tool semgrep `
  -OutputJson ".\imported-findings.json"
```

导入结果需要人工复核后再进入最终报告。

## 渲染 HTML 报告

已有符合 `references/report-schema.md` 的 JSON 时：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\render-report.ps1 `
  -InputJson .\audit.json `
  -OutputHtml .\audit-report.html
```

报告为离线 HTML，内嵌 CSS，不依赖外部网络。
问题详情默认按单个问题折叠展示，页面提供风险等级筛选、维度筛选、全文检索、“全部展开/全部收起”控制；打印时会自动展开当前筛选出的详情。

## 评分规则

默认 100 分制：

| 维度 | 权重 |
|---|---:|
| 安全性 | 20 |
| 功能正确性 | 15 |
| 可靠性/健壮性 | 15 |
| 架构合理性 | 15 |
| 编码规范性 | 10 |
| 可维护性/可演进性 | 10 |
| 测试质量 | 5 |
| 性能与资源 | 5 |
| 依赖与供应链风险 | 3 |
| 可观测性与运维性 | 2 |

详细规则见 `references/scoring-rubric.md`。

## 注意事项

- 审计结论必须基于证据，禁止编造问题。
- 工具输出不能直接等同于最终结论，需要人工复核误报。
- 缺少构建环境、测试环境、硬件设备或权限时，应在报告中列为限制项。
- 审计过程不应静默修改业务代码、生产配置、依赖版本或 CI 文件。
