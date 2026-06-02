# 配置、CI/CD 与容器审计规范要点

参考 OWASP、CIS Docker/Kubernetes Benchmark、主流云厂商安全基线和大厂 DevSecOps 实践。适用于 Dockerfile、Compose、Kubernetes YAML、Nginx/Apache、CI/CD、环境变量和应用配置。

| 维度 | 检查点 |
|---|---|
| 密钥与凭据 | `.env`、YAML、CI 变量、镜像构建参数、日志中是否包含 token/password/private key |
| 容器安全 | 非 root 用户、基础镜像版本、健康检查、最小权限、只读文件系统、能力收敛 |
| K8s 安全 | RBAC 最小权限、Secret 管理、NetworkPolicy、资源限制、探针、镜像拉取策略 |
| Web 配置 | TLS、HSTS、CSP、反向代理头、上传大小、目录遍历、默认站点暴露 |
| CI/CD | 受保护分支、依赖缓存可信度、制品签名、脚本注入、供应链扫描、部署审批 |

高优先级规则：

- 禁止提交真实密钥、证书私钥、生产账号和内网访问令牌。
- CI 脚本不得把未转义的分支名、PR 标题、提交信息拼接进 shell。
- 容器镜像应固定版本或 digest，并记录来源与漏洞扫描结果。
- Kubernetes 工作负载必须配置资源限制、健康检查和最小权限 ServiceAccount。
- 对外交付报告启用脱敏，避免暴露内部路径、IP、账号和业务拓扑。
