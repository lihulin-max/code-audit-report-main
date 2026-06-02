# 误报与风险接受处理规范

本规范用于 `code-audit-report` 的基线管理，适合复审、CI 门禁豁免和对外交付前的审计痕迹留存。

## 状态定义

| 状态 | 含义 | 是否计入有效风险 | 是否触发高危门禁 |
|---|---|---:|---:|
| `open` | 已确认或待处理的问题 | 是 | 是 |
| `accepted` | 业务确认暂不修复，已有责任人和期限 | 是 | 否 |
| `false_positive` | 经复核为误报 | 否 | 否 |
| `fixed` | 已修复并通过复测 | 否 | 否 |

`accepted` 不是误报，报告仍会保留并计入评分；它只用于 CI 门禁豁免，避免已审批风险阻断流水线。

## 基线文件格式

```json
{
  "schemaVersion": "1.0",
  "generatedAt": "2026-05-27 18:00:00",
  "items": [
    {
      "fingerprint": "e3a1f66aa5bb3310",
      "ruleId": "CPP-SEC-001",
      "title": "外部命令通过字符串拼接执行",
      "location": "src/log_export/exporter.cpp:40",
      "status": "accepted",
      "reason": "仅受可信配置驱动，已在版本计划中替换为参数数组执行接口。",
      "owner": "模块负责人"
    }
  ]
}
```

## 使用建议

- 先运行一次全量审计并使用 `-ExportBaselinePath` 导出初始基线。
- 只修改 `status`、`reason`、`owner`，不要手工改 `fingerprint`。
- `false_positive` 必须说明误报依据；`accepted` 必须有责任人、缓解措施和复审时间。
- 已修复问题标记为 `fixed` 后，下一次审计若不再出现，可从基线中清理。
