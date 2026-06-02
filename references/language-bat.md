# Windows Batch Script Audit Reference

Use for `.bat` and `.cmd` files. Refer to Microsoft command-line documentation, Windows deployment hardening practices, and enterprise scripting conventions.

## Coding Standards

- Start with `@echo off` when output noise is not needed.
- Use `setlocal EnableExtensions` and `endlocal` to control variable scope.
- Quote paths and variables, especially `%~dp0`, `%ProgramFiles%`, and user input.
- Use `if errorlevel` or `%ERRORLEVEL%` consistently after critical commands.
- Keep labels and `goto` usage simple; prefer subroutines with `call :label`.
- Avoid hidden environment mutation outside the script.

## Security Hotspots

- Command injection via unquoted `%1`, `%*`, environment variables, or delayed expansion.
- Dangerous recursive delete/move operations with unchecked paths.
- Secrets echoed to console, logs, or process command lines.
- PATH hijacking from relative executable names.
- Download-and-execute flows without checksum/signature validation.

## Reliability

- Validate required arguments and directories before mutation.
- Use `pushd/popd` for directory changes.
- Handle paths containing spaces, `&`, `(`, `)`, `!`, and Unicode.
- Make deployment scripts idempotent and reversible where possible.

## Tooling

Recommended tools:

- Script review with Windows command documentation.
- PSScriptAnalyzer only for PowerShell, not batch.
- Gitleaks for secrets.
- Controlled dry-run test in a disposable directory.
