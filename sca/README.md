# SCA 与 SBOM

`run-audit.ps1` 会在本地工具存在时自动运行：

- `trivy fs --format json`
- `grype dir:<project> -o json`
- `osv-scanner --recursive --format json`
- `syft dir:<project> -o cyclonedx-json`

工具缺失时不会中断审计，报告会在“工具与命令记录”和“供应链与 SBOM”中标记为 `missing`。

建议在 CI 中固定工具版本和漏洞库更新时间，并归档原始 JSON 输出，便于复测和审计追踪。
