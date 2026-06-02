# Audit Workflow

Use this workflow for full-project or commit-range audits.

## 1. Scope

Capture:

- repository path and branch/commit range
- primary languages and frameworks
- build system and dependency manifests
- audit exclusions, generated files, vendored code, and test fixtures
- requested focus such as security-only, architecture-only, or release readiness
- domain emphasis such as functional correctness, reliability, observability, or supply-chain readiness

## 2. Inventory

Prefer fast commands:

- `rg --files`
- `scripts/inventory-project.ps1 -ProjectPath <repo> -OutputJson <inventory.json>`
- language manifests: `pom.xml`, `build.gradle`, `settings.gradle`, `package.json`, `*.csproj`, `Directory.Build.props`, `CMakeLists.txt`, `conanfile.*`, `vcpkg.json`, `requirements.txt`, `pyproject.toml`, `Pipfile`, `composer.json`, `*.sln`, `*.razor`, `*.xaml`, `*.ps1`, `*.sh`, `*.bat`, `*.cmd`, `*.lua`
- config files: `application*.yml`, `appsettings*.json`, `.env*`, Dockerfiles, CI files
- tests: `src/test`, `tests`, `*Test.*`, `*Tests.*`
- style/config: `.editorconfig`, `.clang-format`, `.stylelintrc*`, `ruff.toml`, `phpstan.neon`, `psalm.xml`, `detekt.yml`, `.shellcheckrc`

Record important counts: files inspected, generated files skipped, tests detected, dependency manifests detected.

For deliverable HTML reports, prefer the automated entry point:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-audit.ps1 `
  -ProjectPath <repo> `
  -OutputDir <out>
```

## 3. Tool Pass

Run applicable tools when available or after approved installation.

Recommended order:

1. build or compile check
2. unit tests
3. language style/static analysis
4. dependency vulnerability, license, and SBOM scan
5. secret scan
6. focused security rules

Do not treat tool output as final truth. Validate high-risk findings against source code and suppress obvious false positives in the final report with a short reason.

If scanners already produced SARIF, Semgrep JSON, or Gitleaks JSON, import them with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\import-tool-results.ps1 `
  -InputPath <tool-output> `
  -OutputJson <imported-findings.json>
```

## 4. Manual Review

Inspect:

- public entry points: controllers, handlers, commands, scheduled jobs
- authentication and authorization boundaries
- input validation, output encoding, serialization
- SQL, ORM, file, process, network, and shell operations
- transaction and retry/fallback behavior
- business-state transitions, default values, fallback behavior, and data consistency
- shared utilities, framework configuration, interceptors, middleware
- core business workflows and money/state-changing operations
- observability and operations: logs, metrics, error codes, health checks, audit logs

## 5. Finding Quality Bar

Every finding should answer:

- What code caused the issue?
- Why is it a real problem?
- What is the impact?
- How should it be fixed?
- How confident is the finding?

Avoid low-signal style comments unless they repeat across the codebase or materially hurt maintainability.
