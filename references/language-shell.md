# Shell Script Audit Reference

Use for Bash, POSIX sh, Zsh, and Linux deployment scripts. Refer to Google Shell Style Guide, ShellCheck guidance, GNU Bash practices, CIS/Linux hardening practices, and project-local conventions.

## Coding Standards

- Start scripts with an explicit shebang and document required shell dialect.
- Use `set -euo pipefail` where compatible, and handle intentional non-zero exits explicitly.
- Quote variable expansions unless word splitting is required.
- Prefer arrays for command arguments in Bash; avoid string-built commands.
- Use `mktemp` for temporary files and clean them with `trap`.
- Keep functions small and name actions with verbs.
- Avoid relying on current working directory; resolve script directory explicitly.

## Security Hotspots

- Command injection from unquoted variables, `eval`, backticks, and string-built `sh -c`.
- Unsafe deletion or move operations using unchecked variables.
- Secrets printed to logs or passed through command-line arguments.
- Insecure temporary files under `/tmp`.
- `curl | sh` or remote script execution without checksum/signature validation.
- `sudo` usage without least-privilege boundaries.

## Reliability

- Check external command availability.
- Handle missing files, empty globs, spaces in paths, and failed pipelines.
- Avoid parsing human-oriented command output when structured output is available.
- Make scripts idempotent for deployment and cleanup tasks.

## Tooling

Recommended tools:

- ShellCheck
- shfmt
- Bats for tests
- Gitleaks or trufflehog for secrets
