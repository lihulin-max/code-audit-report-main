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

## 通用数值边界审查

For all C, C++, and embedded projects, explicitly audit numeric boundaries before accepting code that handles external input, binary protocols, files, database records, hardware registers, or fixed memory layouts.

- Length and capacity: verify that every length field is consistent with the destination buffer capacity, remaining frame bytes, structure size, and allocation size. Reject paths where a trusted-looking `len` can exceed the actual array, `span`, packet, or heap block.
- Bounded APIs: review every `memcpy`, `memmove`, `strcpy`, `strncpy`, `strcat`, `sprintf`, `snprintf`, `malloc`, `calloc`, `realloc`, placement write, and manual pointer loop for an explicit upper bound derived from the destination capacity. Include allocation-size multiplication overflow checks.
- Integer conversions and shifts: check `int`, `unsigned`, `size_t`, `uint32_t`, `uint64_t`, enum, and protocol-width conversions for truncation, sign extension, wraparound, and comparison changes. Verify that right/left shifts use valid ranges and the intended signedness.
- Indexes and counters: inspect array indexes, pointer offsets, loop counters, `length - 1`, `count - 1`, decrement loops, reverse traversal, and retry counters for zero-length underflow, off-by-one access, and unsigned wraparound.
- Protocol frames: validate minimum length before reading each header/field and maximum length before allocating, copying, or iterating. Confirm that declared payload length, checksum length, TLV length, and remaining bytes stay consistent after each parse step.
- Domain numeric fields: check BCD values, dates/times, time zones, durations, offsets, file sizes, sector/block numbers, database `count` values, paging limits, and hardware register fields against documented minimums, maximums, units, and sentinel values.
- Parsing APIs: treat `atoi`, `atol`, `sscanf`, `strtol`, `strtoul`, and custom parsers as failure-prone. Verify return counts, `errno`/end-pointer handling, range limits, base selection, whitespace/sign handling, and behavior on overflow or partial input.
- Fixed structure compatibility: when fixed structs, protocol records, shared-memory blocks, EEPROM layouts, or on-disk records are extended, confirm versioning, `sizeof` assumptions, packing/alignment, reserved fields, endianness, backward compatibility, and safe defaults for absent fields.

Evidence should include the source of the numeric value, the enforced lower/upper bound, the destination capacity or remaining bytes, and the failure behavior when validation rejects the value.

## Tooling

Recommended tools:

- `clang-tidy`
- `cppcheck`
- `cpplint`
- compiler warnings with strict flags
- sanitizers when buildable: AddressSanitizer, UndefinedBehaviorSanitizer, ThreadSanitizer
- Semgrep and Gitleaks for security/secret scans

Record compiler and toolchain versions because findings can vary across versions.
