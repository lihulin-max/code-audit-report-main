# Report Style From Reference Examples

The reference materials under `F:\AI审计开发\参考资料` show the expected deliverable style: direct, evidence-based, and suitable for engineering整改.

## Report Shape

- Title: `代码审查报告` or `代码审计报告`.
- Start with audit scope, score, risk level, and overall conclusion.
- Group detailed findings by severity first, then by audit dimension when needed.
- For each issue, include:
  - issue title and location
  - 问题描述 / evidence
  - 影响
  - 优化建议
  - priority, confidence, and optional fix example
- End with 评分明细、整改路线图、工具与命令记录、未覆盖范围。
- Keep the 10 score dimensions stable unless the report explicitly records a domain-specific weight adjustment.

## Preferred Tone

- Use direct engineering language.
- Avoid generic statements such as “代码不规范” unless backed by concrete evidence.
- Make recommendations executable: name the function, config key, tool, or code pattern to change.
- For tool-only findings, state whether the finding was manually verified.
- For uncertain findings, use `待复核` and explain what evidence is missing.

## Finding Example Shape

```text
1. 外部命令执行缺少参数边界（src/log_export/exporter.cpp:40）

问题描述
命令字符串由工作目录和工具路径拼接后交给 shell 执行，缺少白名单和参数数组边界。

影响
异常配置或可控路径可能改变命令语义，导致命令注入或日志导出失败。

优化建议
改用参数数组接口，校验工具路径，输出目录使用规范化路径并限制在允许目录下。
```

## HTML Report Layout

- summary cards for score, risk level, and finding counts
- project inventory section for languages, build systems, manifests, tests, and risk hints
- tables for dimension scores and tool records
- optional supply-chain section for dependency scan, license/SBOM status, and lock-file coverage
- color-coded severity badges
- separate sections for high, medium, low, and pending-review findings
- collapsible per-finding details with compact summary rows and expand/collapse controls
- print-friendly CSS
