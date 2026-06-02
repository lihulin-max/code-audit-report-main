# Scoring Rubric

Default total score is 100. Score is evidence-based and should not punish an area that was not covered unless the missing coverage is itself a delivery risk.

## Dimensions

| Dimension | Weight | Audit target |
|---|---:|---|
| 安全性 | 20 | OWASP/CWE、注入、越权、命令执行、路径穿越、反序列化、敏感信息、弱加密、密钥泄露 |
| 功能正确性 | 15 | 业务规则、状态流转、边界条件、异常分支、数据一致性、默认值/fallback 是否安全 |
| 可靠性/健壮性 | 15 | 空值/边界、并发、超时、重试、幂等、降级、失败恢复、关闭清理 |
| 架构合理性 | 15 | 分层、模块边界、依赖方向、循环依赖、状态/事务边界、缓存/分布式设计、配置设计 |
| 编码规范性 | 10 | 命名、注释、复杂度、异常处理、资源释放、魔法值、重复代码、语言规范符合度 |
| 可维护性/可演进性 | 10 | 单一职责、可测试性、抽象质量、配置管理、文档、技术债、全局状态收敛 |
| 测试质量 | 5 | 单元测试、集成测试、边界测试、异常测试、并发测试、回归测试、CI 接入 |
| 性能与资源 | 5 | 内存、I/O、数据库访问、缓存、算法复杂度、阻塞调用、资源生命周期 |
| 依赖与供应链风险 | 3 | 依赖漏洞、许可证、锁文件、SBOM、构建插件、容器镜像、工具链可信度 |
| 可观测性与运维性 | 2 | 日志、指标、链路追踪、错误码、告警、审计日志、健康检查、运行状态暴露 |

## Domain weighting adjustment

For embedded, gateway, daemon, telecom, and device-control systems, consider shifting weight from style/process to reliability and observability:

- 可靠性/健壮性: +5
- 可观测性与运维性: +3
- 性能与资源: +2
- 编码规范性: -5
- 可维护性/可演进性 or process-heavy items: -5

For internet-facing web systems, consider:

- 安全性: +5
- 依赖与供应链风险: +3
- 可观测性与运维性: +2
- 性能与资源: +2
- 编码规范性: -5
- 可维护性/可演进性 or process-heavy items: -7

Any domain-specific reweighting must be recorded in the report.

## Severity

- 高: 可被利用的安全漏洞、数据丢失/损坏、鉴权绕过、重大可用性风险、严重业务结果错误、生产事故高概率触发点。
- 中: 有明确用户影响的正确性/可靠性问题、阻碍安全演进的维护性问题、中等安全加固缺口、关键运维信号缺失。
- 低: 局部可维护性、风格、文档、测试补强、可观测性或小型性能问题，影响范围有限。
- 待复核: 有合理怀疑但证据不足，需要运行环境、业务约束、权限模型或数据样本确认。

## Priority

- P0: 应在发布或上线前修复。
- P1: 应在最近一个修复窗口内处理。
- P2: 应进入迭代计划并有明确负责人。
- P3: 可作为持续改进项处理。

## Confidence

- 高: 证据直接来自源码、配置、依赖清单或可复现工具输出。
- 中: 证据明确，但最终影响依赖运行配置、输入来源、数据样本或部署拓扑。
- 低: 属于风险提示，需要进一步复核。

## Deduction guidance

- Start from each dimension's full weight.
- Deduct by root cause, not by every repeated occurrence.
- Typical deduction per finding:
  - 高: 5-8 points in the affected dimension.
  - 中: 2-4 points in the affected dimension.
  - 低: 0.5-1.5 points in the affected dimension.
  - 待复核: 0-1 point, depending on evidence strength.
- Cap deductions at the dimension weight.
- If a tool cannot run because the local environment lacks dependencies, record it as a limitation and avoid inventing tool findings.

## Final rating

- 90-100: 优秀，只有少量低风险优化。
- 80-89: 良好，存在明确改进项但整体可控。
- 70-79: 一般，存在中风险问题或工程质量短板。
- 60-69: 较差，存在多项中高风险问题。
- <60: 高风险，不建议在未整改前发布。
