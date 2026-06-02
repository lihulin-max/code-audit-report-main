# C++ Audit Reference

Use for C and C++ projects. Refer to Google C++ Style Guide, C++ Core Guidelines, CERT C/C++, and project-local conventions.

## Architecture

- Check module boundaries, public headers, include direction, and dependency cycles.
- Avoid large global state, hidden singleton coupling, and build-system side effects.
- Review ABI/API stability for exported interfaces.
- Validate ownership model across modules and threads.

## Coding Standards

- Prefer RAII for resource management.
- Make ownership explicit with values, references, `unique_ptr`, `shared_ptr`, or documented raw pointers.
- Avoid unchecked casts, pointer arithmetic, macro-heavy logic, and hidden control flow.
- Keep headers minimal and include what is used.
- Flag magic numbers, duplicated algorithms, long functions, and complex templates without tests.
- Check exception safety and no-throw assumptions.

## Reliability And Safety

- Bounds checks for arrays, spans, vectors, and string operations.
- Integer overflow/underflow and signed/unsigned conversions.
- Use-after-free, double free, dangling references, and iterator invalidation.
- Data races, lock ordering, missing synchronization, and unsafe static initialization.
- Error-code handling and cleanup on failure paths.

## Tooling

Recommended tools:

- `clang-tidy`
- `cppcheck`
- `cpplint`
- compiler warnings with strict flags
- sanitizers when buildable: AddressSanitizer, UndefinedBehaviorSanitizer, ThreadSanitizer
- Semgrep and Gitleaks for security/secret scans

Record compiler and toolchain versions because findings can vary across versions.
