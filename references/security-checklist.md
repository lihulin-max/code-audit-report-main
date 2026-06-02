# Security Checklist

Use this reference for security-focused audits or as the security dimension of a full audit.

## Evidence Rules

- Confirm tainted input source, propagation path, sink, and missing mitigation where possible.
- Distinguish exploitable vulnerabilities from hardening suggestions.
- Mark uncertain exploitability as `待复核`.
- Include data sensitivity, runtime privilege, tenant boundary, and authorization context in impact.
- Tool findings must be manually reviewed before final severity is assigned.

## OWASP/CWE Areas

- Broken access control: missing object-level checks, role confusion, tenant isolation failure.
- Cryptographic failures: weak algorithms, insecure random, hardcoded keys, missing TLS validation.
- Injection: SQL/NoSQL/LDAP/OS command/template expression injection.
- Insecure design: missing idempotency, replay protection, abuse controls, rate limits.
- Security misconfiguration: debug mode, permissive CORS, exposed management endpoints.
- Vulnerable/outdated components: known CVEs and unsupported libraries. Record broad dependency governance, license, lock-file, and SBOM issues under `依赖与供应链风险`.
- Identification/authentication failures: weak session/JWT/cookie/token handling.
- Software/data integrity failures: unsafe deserialization, untrusted plugin/update paths.
- Logging/monitoring failures: missing audit logs for sensitive operations.
- SSRF: user-controlled URL fetches, metadata endpoint access, missing allowlist.

## Common Review Hotspots

- Authentication and authorization boundaries.
- Public APIs, controllers, IPC methods, CLI commands, scheduled jobs.
- File upload/download, path construction, archive extraction.
- Shell/process execution and native command wrappers.
- SQL/ORM/query builders and dynamic filters.
- HTML/JavaScript output, template rendering, markdown rendering.
- Serialization/deserialization, reflection, plugin loading.
- Secrets in configs, logs, source history, test fixtures.
- Dependency manifests, lock files, container images, base images.
- Audit logs for sensitive operations.

## Common Finding Fields

- attack precondition
- vulnerable source and sink
- exploit path or realistic misuse scenario
- impact: confidentiality, integrity, availability, compliance
- recommended mitigation
- validation approach after fix
