---
name: code-audit-report
description: Comprehensive source-code audit and review skill for generating deliverable HTML audit reports. Use when Codex needs to review Java, C++, C#, Shell scripts, Kotlin, Windows BAT/CMD scripts, Blazor, XAML/WPF, CSS, Lua, PHP, Python, Go, JavaScript/TypeScript, SQL/configuration files, or mixed-language codebases for architecture, functional correctness, coding standards, security, reliability, maintainability, observability/operations, performance, tests, documentation, supply-chain risk, commit quality, CI readiness, SARIF/tool-result import, or HTML audit report generation.
---

# Code Audit Report

Perform evidence-based code audits and generate a standalone HTML report. Cover architecture rationality, functional correctness, coding standards, security, reliability, maintainability/evolvability, observability/operations, performance/resource usage, test quality, supply-chain risk, and commit clarity.

## Core Rules

- Base every finding on inspected source code, configuration, dependency metadata, tool output, commit data, or design material.
- Do not invent issues. If evidence is credible but incomplete, mark the finding as `待复核` and explain what evidence is missing.
- Prefer exact file paths and line numbers. If line numbers are unavailable, include a precise symbol, class, method, configuration key, or command.
- Prioritize security, correctness, reliability, and architecture issues over style-only comments.
- Group repeated findings by root cause and keep a stable `fingerprint` when possible.
- Do not silently modify the audited project source, production configuration, dependency versions, or CI files unless the user explicitly asks for fixes.

## Language References

For coding-standard review, load only relevant references:

- Java: `references/language-java.md`
- C++: `references/language-cpp.md`
- C#: `references/language-csharp.md`
- Shell/Bash/sh: `references/language-shell.md`
- Kotlin: `references/language-kotlin.md`
- BAT/CMD: `references/language-bat.md`
- Blazor/Razor components: `references/language-blazor.md`
- XAML/WPF: `references/language-xaml-wpf.md`
- CSS/SCSS/LESS: `references/language-css.md`
- Lua: `references/language-lua.md`
- PHP: `references/language-php.md`
- Python: `references/language-python.md`
- Go: `references/language-go.md`
- JavaScript/TypeScript: `references/language-js-ts.md`
- SQL: `references/language-sql.md`
- Configuration/CI/containers: `references/language-config.md`

For security-focused audits, also load `references/security-checklist.md`. For scoring, baseline handling, and report generation, load `references/scoring-rubric.md`, `references/false-positive-handling.md`, `references/report-schema.md`, and `references/report-style-from-examples.md`.

## Rule Packs

Use structured rule packs when they match the project:

- Common security: `rules/common-security.json`
- Common reliability/maintainability: `rules/common-reliability.json`
- Common correctness: `rules/common-correctness.json`
- Common observability/operations: `rules/common-observability.json`
- Common supply chain: `rules/common-supply-chain.json`
- C++/Google/Core Guidelines: `rules/cpp-google-core.json`
- Java/Alibaba: `rules/java-alibaba.json`
- Python/PEP 8/Bandit: `rules/python-pep8-bandit.json`

Rule packs are evidence guides, not automatic truth. Tool findings and heuristic findings still need source-context review before final report.

## Workflow

1. Identify scope: repository path, target branch or commit range, languages, build system, audit focus, and exclusions.
2. Inventory the project with `scripts/inventory-project.ps1 -ProjectPath <repo> -OutputJson <inventory.json>`.
3. Detect available tools. If useful tools are missing and installation is permitted, run `scripts/bootstrap-tools.ps1 -ProjectPath <repo> -Languages <langs> -InstallMissing`.
4. Load `audit-config.yml` from the audited project when present; otherwise use the skill default. Apply only explicit command-line overrides for languages, output directory, incrementality, baseline, SCA/SBOM, redaction, and CI gate options.
5. Run `scripts/run-audit.ps1 -ProjectPath <repo> -OutputDir <out>` when a full HTML report is requested. It performs inventory, tool bootstrap, selected tool runs, SCA/SBOM capture, heuristic checks, baseline application, JSON generation, and HTML rendering.
6. Use `-ChangedOnly -DiffBase <base> -DiffTarget <target>` for incremental audit, `-BaselinePath <json>` for false-positive/risk-acceptance state, `-ExportBaselinePath <json>` to create a baseline, `-FailOnHigh` and `-MinScore` for CI gates, and `-RedactReport` for external delivery.
7. Import external SARIF/Semgrep/Gitleaks JSON results with `scripts/import-tool-results.ps1` when the project or CI already produced scanner output.
8. Manually inspect high-risk areas: entry points, auth/authz, data access, serialization, file/network/process operations, concurrency, error handling, resource lifecycle, public APIs, and deployment configuration.
9. Classify findings by severity, dimension, priority, confidence, affected component, remediation effort, evidence source, and status.
10. Create or update a structured JSON result matching `references/report-schema.md`.
11. Render the HTML report with `scripts/render-report.ps1 -InputJson <audit.json> -OutputHtml <report.html>`.

## Tool Installation Policy

- First use tools already present in the project or machine.
- If missing tools materially improve audit quality, install them when the user permits or the environment policy allows it.
- Prefer non-global installation:
  - Java: project Maven/Gradle plugins or downloaded CLI tools under a temporary tools directory.
  - C++: existing compiler toolchain first; then `clang-tidy`, `cppcheck`, or `cpplint`.
  - C#: project analyzers or local `.NET` tools before global tools.
  - Shell/BAT/Python/PHP/Kotlin/Lua/CSS: project-local package managers and linters before global tools.
  - Blazor/XAML/WPF: project analyzers, `.NET` local tools, and test projects before global tools.
  - General: `semgrep`, `gitleaks`, `trivy`, `osv-scanner`, `syft`, or `grype` when relevant.
- Record tool name, version, install method, command, exit code, success/failure, duration, and skipped reason in the report.

## Report Expectations

Generate a single offline HTML file with embedded CSS. Use Chinese report text by default unless the user requests another language.

Required sections:

- 审计概况
- 总体结论
- 审计配置与交付选项
- 项目盘点
- 增量审计信息
- 误报与基线管理
- 供应链与 SBOM
- 风险与问题统计
- 维度评分明细
- 高风险问题
- 中风险问题
- 低风险问题与优化建议
- 待复核项
- 整改优先级与路线图
- 工具与命令记录
- 未覆盖范围与待复核项

Each finding should include:

- title, severity, dimension, location, evidence
- impact and recommendation
- priority and confidence
- source, ruleId, fingerprint, status, affected component
- optional CWE/OWASP mapping and fix example

## Practical Audit Focus

- Architecture: layering, dependency direction, cyclic dependency, module boundaries, transaction boundaries, cache design, distributed failure handling, configuration design.
- Functional correctness: business rules, state transitions, boundary conditions, default/fallback behavior, data consistency, error branches.
- Coding standards: naming, comments, complexity, method/class size, exception handling, resource release, magic numbers, duplicated code, language-specific conventions.
- Security: OWASP Top 10, CWE patterns, auth/authz, injection, XSS, SSRF, path traversal, unsafe deserialization, secret leakage, insecure crypto.
- Reliability: null/bounds checks, edge cases, idempotency, concurrency, timeouts, retries, fallback behavior, observability, failure cleanup.
- Maintainability/evolvability: single responsibility, testability, dependency injection, abstraction quality, configuration, documentation, technical debt.
- Observability/operations: logs, metrics, traces, error codes, alerts, audit logs, health checks, runtime state exposure.
- Performance: database access patterns, algorithmic complexity, memory/resource lifecycle, cache usage, blocking calls, large-object handling.
- Test quality: unit, integration, boundary, exception, concurrency, regression, and CI coverage.
- Supply-chain risk: dependency CVEs, licenses, lock files, SBOM, build plugins, container images, toolchain trust.
