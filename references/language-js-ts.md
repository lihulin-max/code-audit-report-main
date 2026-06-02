# JavaScript/TypeScript 审计规范要点

参考 OWASP ASVS/Top 10、CWE、Google JavaScript Style Guide、TypeScript 官方实践、主流前端与 Node.js 工程规范。重点关注：

| 维度 | 检查点 |
|---|---|
| 前端安全 | XSS、DOM 注入、CSRF、开放重定向、敏感信息前端硬编码、CSP 和第三方脚本风险 |
| Node.js 安全 | 命令执行、路径穿越、SSRF、原型污染、反序列化、模板注入、上传文件校验 |
| 类型与规范 | 禁止滥用 `any`，开启 `strict`，Promise 错误处理，模块边界，命名一致性 |
| 可靠性 | 请求超时、重试退避、异步竞态、未处理 rejection、状态同步、边界值处理 |
| 供应链 | lock 文件、npm audit/osv、脚本钩子、typosquatting、许可证和构建产物来源 |

高优先级规则：

- 禁止把不可信数据传入 `innerHTML`、`dangerouslySetInnerHTML`、`eval`、`Function`、模板执行或 shell。
- API 鉴权和越权校验必须放在服务端，前端校验只能作为体验增强。
- Node.js 文件路径必须规范化并限制在允许目录内。
- 所有异步入口要处理失败分支和超时。
- 依赖升级、lock 文件和构建脚本变更必须纳入审计。
