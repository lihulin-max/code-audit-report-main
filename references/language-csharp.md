# C# Audit Reference

Use for C# and .NET projects. Refer to Microsoft C# Coding Conventions, .NET design guidelines, Roslyn analyzer rules, OWASP, and project-local conventions.

## Architecture

- Check controller/service/repository/domain boundaries.
- Validate dependency injection usage, service lifetimes, and hidden static coupling.
- Review async boundaries, cancellation propagation, and background services.
- Check configuration and secrets management in `appsettings*.json`, environment variables, and user secrets.

## Coding Standards

- Use PascalCase for public types/members and camelCase for locals/parameters.
- Prefer nullable reference type annotations where enabled; flag unsafe null assumptions.
- Use `async`/`await` correctly; avoid `.Result` and `.Wait()` on async paths.
- Dispose `IDisposable`/`IAsyncDisposable` resources with `using` or dependency-managed lifetime.
- Avoid broad `catch` blocks, swallowed exceptions, and logging without context.
- Flag magic numbers, duplicated code, oversized classes, and complex LINQ with hidden performance cost.

## Security Hotspots

- Missing authorization policies or endpoint-level checks.
- SQL injection in raw SQL, interpolated strings, or unsafe ORM calls.
- Insecure deserialization and permissive JSON binding.
- Path traversal in file APIs.
- SSRF from user-controlled URLs.
- Sensitive data in logs, configs, or exception responses.
- Weak authentication/session/cookie settings.

## Tooling

Recommended tools:

- `dotnet build` with analyzers enabled.
- `dotnet test`.
- `dotnet format --verify-no-changes` for style.
- Roslyn analyzers, SonarAnalyzer, SecurityCodeScan.
- Semgrep and Gitleaks for security/secret scans.

Prefer project analyzers and local `.NET` tools before global installation.
