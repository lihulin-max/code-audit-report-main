# Java Audit Reference

Use for Java and JVM projects. Refer to Alibaba Java Development Manual style expectations, OWASP guidance, Spring ecosystem conventions, and common enterprise Java practices.

## Architecture

- Keep controller/service/repository/domain boundaries clear.
- Avoid cross-layer calls, god services, circular module dependencies, and business logic in controllers.
- Validate transaction boundaries on state-changing operations.
- Review cache usage for penetration, breakdown, avalanche, stale data, and missing invalidation.
- Check configuration externalization; avoid hardcoded endpoints, credentials, tenant IDs, and environment-specific values.

## Coding Standards

- Naming: classes use UpperCamelCase; methods/fields use lowerCamelCase; constants use UPPER_SNAKE_CASE.
- Exceptions: do not swallow exceptions, return success on failure, or use `printStackTrace`; preserve context in logs.
- Resources: close streams, JDBC objects, HTTP clients, and executors; prefer try-with-resources.
- Collections: choose correct implementation, avoid unsafe concurrent access, guard nulls and empty collections.
- Complexity: flag oversized methods/classes, deep nesting, repeated branches, magic numbers, and duplicated code.
- Comments: require useful comments for complex business rules; remove misleading or obsolete comments.

## Security Hotspots

- MyBatis `${}` and string-built SQL.
- Missing authorization checks in controllers/services.
- File upload type/path validation.
- Unsafe deserialization and polymorphic JSON configuration.
- SSRF through user-controlled URLs.
- Weak JWT/session validation and missing CSRF protection where applicable.
- Sensitive data in logs, configs, or repository history.

## Tooling

Recommended tools:

- Checkstyle for style rules.
- PMD for code smells and complexity.
- SpotBugs for bug patterns.
- OWASP Dependency-Check for vulnerable dependencies.
- Semgrep for custom security rules.
- Gitleaks for secrets.

Prefer project Maven/Gradle plugins when present. If installing, record plugin/tool versions and commands.
