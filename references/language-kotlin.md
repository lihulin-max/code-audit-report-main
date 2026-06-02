# Kotlin Audit Reference

Use for Kotlin JVM, Android, server-side Kotlin, and mixed Java/Kotlin projects. Refer to Kotlin official coding conventions, Android Kotlin style, JetBrains guidance, OWASP MASVS for Android, and enterprise JVM practices.

## Coding Standards

- Follow Kotlin official formatting and naming conventions.
- Prefer null-safety types over nullable suppression and `!!`.
- Keep coroutine scopes structured; avoid `GlobalScope` in application code.
- Use immutable data (`val`, immutable collections) unless mutation is required.
- Keep extension functions discoverable and avoid hiding domain side effects.
- Avoid large top-level utility files that mix unrelated responsibilities.

## Architecture

- Preserve clear boundaries between presentation, domain, data, and infrastructure layers.
- For Android, keep lifecycle-aware coroutines and avoid leaking Activity/Context.
- For server-side Kotlin, keep transaction and dispatcher boundaries explicit.
- Avoid mixing blocking IO inside default coroutine dispatchers.

## Security Hotspots

- Unsafe deserialization and permissive JSON polymorphism.
- SQL/NoSQL injection in raw queries or string interpolation.
- Android exported components, insecure WebView settings, and weak storage.
- Hardcoded credentials, tokens, endpoints, and debug flags.
- Missing authorization checks in Ktor/Spring controllers.

## Tooling

Recommended tools:

- ktlint
- detekt
- Gradle/Maven test and build
- Android Lint for Android projects
- OWASP Dependency-Check or Gradle dependency vulnerability plugins
- Semgrep and Gitleaks
