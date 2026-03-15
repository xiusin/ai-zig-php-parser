# Fuzzy Test Regression Report (2026-03-15)

## 1. Overview
- **Scope**: Full fuzzy suite (179 scripts) after fixing namespace imports, named arguments, and minimal `DateTime` runtime.
- **Command**: `zig build && ./compare.sh fuzzy_scripts`
- **Goal**: Validate recent fixes (`test_009`, `test_051`, `test_055`) and identify remaining compiler/runtime gaps.

## 2. Recent Fix Highlights
1. **DateTime Minimal Runtime**
   - Registered `DateTimeInterface`/`DateTime`, implemented `__construct()` + `format('Y-m-d')`.
   - Added `ClassMeta.registerDateTimeClasses()` and wired into runtime init.
2. **Nullsafe Method Call Support**
   - IR: `?->method()` lowers directly to `php_object_call_safe_args_array()`.
   - Runtime: added safe helper + native linker binding.
3. **Named-Argument & `compact()` Enhancements**
   - Constructor calls reorder/fill named args via metadata, padding `const_missing`.
   - `compact()` now collects current locals/globals.
4. **Method `.has_arg` Correction**
   - Accounts for synthetic `this`, matching `.param` semantics and enabling default-value detection.

## 3. Regression Summary
| Status | Count | Notes |
| --- | --- | --- |
| ✅ PASS | 21 | Includes `test_009_namespace_use.php`, `test_051_named_arguments.php`, `test_055_readonly_properties.php`. |
| ⚠️ MISMATCH | 23 | Output diffs (e.g., `test_003` DateTime formatting, `test_064` spread semantics). |
| ⚙️ COMPILE_FAIL | 12 | Function signature mismatches (`php_array_walk`, `php_not`). |
| ❌ PHP_FAIL | 81 | Native PHP errors (division by zero, unsupported language restrictions). |
| 💥 AOT_FAIL | 42 | Missing builtins/classes (`substr_replace`, `stdClass`, `LimitIterator`, etc.) or parser gaps. |
| ⏱ Timeout | 0 | — |

## 4. Representative Outstanding Issues
1. **Missing Builtins / Classes**
   - `substr_replace`, `memory_get_usage`, `shell_exec`, `func_get_args`, `htonl`, `stdClass`, `LimitIterator`, WeakMap family.
2. **Parser Coverage**
   - `reference_pointer`, attribute syntax, partial application still trigger parse errors.
3. **Runtime Helper Signatures**
   - `php_array_walk`, `php_json_decode`, `php_not` require default-arg padding or value deref similar to `str_pad` fix.
4. **Data-Structure Safety**
   - `test_079_anonymous_functions.php` panics at `Value.asArray()` → EventEmitter storage/retain logic bug.
5. **DateTime Formatting Fidelity**
   - Fallback formatting still outputs strings like `+2026-+1-+1`; need better `php_date` support.
6. **Spread / Splat Semantics**
   - `php_args_append_spread` ignores Traversable/generator/object paths → `test_064` mismatches.

## 5. Recommended Next Steps
1. **Builtin Coverage Sprint**: Implement `stdClass`, `substr_replace`, `memory_get_usage`, `func_get_args`, `LimitIterator`. Validate with their corresponding scripts.
2. **Parser Extensions**: Add attribute + partial-application grammar nodes, update IR lowering, rerun targeted scripts.
3. **Runtime Helper Normalization**: Centralize optional-arg padding (array functions, JSON helpers, logical ops).
4. **Stability Hardening**: Audit `Value.asArray()/asObject()` for alignment/retain safety; add regression test for EventEmitter panic.
5. **DateTime/`php_date` Upgrade**: Use `std.time` month/day utilities to support at least `Y-m-d H:i:s` properly.
6. **Spread Engine Rewrite**: Extend merge helpers to handle Traversable/Generators, maintain PHP semantics, ensure perf for >2k elements.

## 6. Appendix
- **Test command**: `zig build && ./compare.sh fuzzy_scripts`
- **Log location**: default `compare.sh` output (last run on 2026-03-15, evening build).
