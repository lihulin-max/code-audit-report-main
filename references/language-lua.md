# Lua Audit Reference

Use for Lua scripts, embedded Lua, OpenResty/Nginx Lua, game scripts, and plugin logic. Refer to Lua official guidance, OpenResty best practices when applicable, OWASP, and project-local conventions.

## Coding Standards

- Keep global variables explicit; use `local` by default.
- Avoid monkey-patching shared tables without clear ownership.
- Keep module return values explicit and side effects minimal.
- Validate nil handling because missing fields fail late.
- Avoid stringly typed protocols without parser validation.

## Security Hotspots

- `load`, `loadstring`, `dofile`, and dynamic code execution.
- Shell execution through `os.execute` and `io.popen`.
- Path traversal in file APIs.
- OpenResty request input used in SQL/Redis/shell calls.
- Shared dictionary misuse, missing rate limits, and unsafe caching.
- Secrets in config scripts.

## Reliability

- Handle coroutine errors and pcall/xpcall boundaries.
- Avoid unbounded table growth in long-running embedded processes.
- Keep timeouts explicit for network, Redis, and HTTP calls.
- Ensure module initialization is idempotent.

## Tooling

Recommended tools:

- luacheck
- stylua
- busted for tests
- Semgrep and Gitleaks
- OpenResty test harness where applicable
