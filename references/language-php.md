# PHP Audit Reference

Use for PHP applications, Laravel, Symfony, WordPress plugins/themes, and plain PHP services. Refer to PSR-1/PSR-12, PHP-FIG guidance, OWASP, framework security documentation, and enterprise backend practices.

## Coding Standards

- Follow PSR-12 formatting and autoloading conventions.
- Use strict types where practical.
- Keep controllers thin and move business logic into services.
- Use dependency injection rather than service locators or globals where possible.
- Avoid mixing templates, SQL, and business logic in one file.

## Security Hotspots

- SQL injection from string-built queries; prefer prepared statements/query builders.
- XSS from unescaped template output.
- CSRF missing on state-changing forms/routes.
- File upload validation, path traversal, and unsafe includes.
- Insecure deserialization with `unserialize`.
- Weak password hashing or custom crypto.
- Secrets committed in `.env`, config, or logs.

## Reliability

- Handle null/false return values from PHP standard library calls.
- Avoid fatal errors from dynamic typing assumptions.
- Validate request input at boundaries.
- Keep transaction boundaries explicit.

## Tooling

Recommended tools:

- PHPStan or Psalm
- PHP_CodeSniffer with PSR-12
- PHP-CS-Fixer
- Composer audit
- PHPUnit
- Semgrep and Gitleaks
