# Python Audit Reference

Use for Python applications, scripts, services, data tooling, automation, and tests. Refer to PEP 8, Google Python Style Guide, Python Packaging User Guide, OWASP, and framework-specific security guidance.

## Coding Standards

- Follow PEP 8 and project-local formatting.
- Use type hints for public APIs and complex data structures.
- Keep functions small and avoid broad utility modules.
- Avoid mutable default arguments.
- Use structured logging instead of print in services.
- Prefer pathlib and standard parsers over ad hoc path/string parsing.

## Security Hotspots

- Command injection from `os.system`, `subprocess(..., shell=True)`, and string-built commands.
- Unsafe deserialization: pickle, yaml.load without SafeLoader, marshal on untrusted data.
- SQL injection from string formatting.
- Path traversal in file reads/writes/uploads.
- SSRF in URL fetchers.
- Secrets in source, notebooks, configs, environment dumps, and logs.
- Insecure crypto and weak random generation.

## Reliability

- Handle timeouts for network, DB, subprocess, and queue operations.
- Avoid swallowing exceptions with bare `except`.
- Validate inputs at module and service boundaries.
- Use context managers for files, locks, DB connections, and temporary resources.
- Ensure idempotency for automation scripts.

## Tooling

Recommended tools:

- ruff
- black
- mypy or pyright
- pytest
- bandit
- pip-audit
- safety
- Semgrep and Gitleaks
