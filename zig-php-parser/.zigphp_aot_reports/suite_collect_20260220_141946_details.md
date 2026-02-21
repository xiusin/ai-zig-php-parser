# AOT Suite 采集补充细节报告（仅采集，不修复）

- 时间：2026-02-20 14:49:00
- 基础报告：`.zigphp_aot_reports/suite_collect_20260220_141946.md`
- TSV：`.zigphp_aot_reports/suite_collect_20260220_141946.tsv`
- 运行参数：`MAX_TESTS=56 COMPILE_TIMEOUT=12 RUN_TIMEOUT=4`

## 1. 总览

- 通过：39
- 失败：17
  - 编译失败（AOT_COMPILE_FAIL）：8
  - 运行失败（当前 runner 记为 AOT_RUNTIME_TIMEOUT）：6
  - 输出不匹配（OUTPUT_MISMATCH）：3

> 重要说明：对“运行失败”的 6 个用例做了单独复现后，发现 **5 个是运行时 panic（exit 134，`panic: reached unreachable code`）**，只有 **1 个是真超时被 kill（exit 137）**。因此当前 runner 的分类需要升级（见本文末尾建议）。

---

## 2. 编译失败（AOT_COMPILE_FAIL = 8）

### 2.1 05_foreach_break

- 复现命令：
  - `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/05_foreach_break.php`
- Zig 报错（尾部）：
  - `.zigphp_aot_build/main.zig:211:20: error: incompatible types: 'runtime_lib.Value' and 'i64'`
  - 触发语句：`if (reg_17 == reg_22) { ... }`
- 现象归纳：`php_value` 与 `i64` 直接比较。
- 定位线索：条件比较/比较指令生成没有根据寄存器声明类型做 Value→标量提取或统一封装。

### 2.2 34_bool

- 复现命令：
  - `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/34_bool.php`
- Zig 报错：
  - `.zigphp_aot_build/main.zig:283:36: error: no field or member function named 'toInt' in 'i64'`
  - 触发语句：`reg_55 = reg_54.toInt();`（但 `reg_54` 是 `i64`）
- 现象归纳：对已是 `i64` 的寄存器走了 Value 提取分支。
- 定位线索：cast/move/phi/比较 代码生成里，Value 提取分支缺少“源寄存器是否为 php_value”的门禁。

### 2.3 41_nested_break_levels

- 复现命令：
  - `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/41_nested_break_levels.php`
- Zig 报错：
  - `.zigphp_aot_build/main.zig:283:36: error: no field or member function named 'toInt' in 'i64'`
- 现象归纳：与 34_bool 同类（同一行号强烈暗示同一段通用模板）。

### 2.4 44_do_while_nested

- 复现命令：
  - `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/44_do_while_nested.php`
- Zig 报错：
  - `.zigphp_aot_build/main.zig:155:36: error: no field or member function named 'toInt' in 'i64'`

### 2.5 47_deep_nesting

- 复现命令：
  - `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/47_deep_nesting.php`
- Zig 报错：
  - `.zigphp_aot_build/main.zig:467:37: error: no field or member function named 'toInt' in 'i64'`

### 2.6 50_mixed_break_continue

- 复现命令：
  - `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/50_mixed_break_continue.php`
- Zig 报错：
  - `.zigphp_aot_build/main.zig:351:36: error: no field or member function named 'toInt' in 'i64'`

### 2.7 51_unset_iter_consistency（新增复杂用例）

- 复现命令：
  - `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/51_unset_iter_consistency.php`
- Zig 报错：
  - `.zigphp_aot_build/main.zig:466:22: error: expected type 'i64', found 'runtime_lib.Value'`
  - 触发语句：`reg_54 = reg_36;`（目标为 i64，源为 Value）
- 现象归纳：Value→i64 提取缺失（或 move/phi/cast 生成时源/目标类型不一致）。
- 定位线索：优先检查 `.move`/`.cast`/PHI 初始化与回写路径是否对“目标是 i64”的寄存器插入 `.asInt()`。

### 2.8 52_foreach_by_ref（新增复杂用例）

- 复现命令：
  - `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/52_foreach_by_ref.php`
- Zig 报错：
  - `.zigphp_aot_build/main.zig:291:13: error: use of undeclared identifier 'unset'`
  - 触发语句：`_ = try @"unset"(...);`
- 现象归纳：`unset($v)`（断开引用）未被当作语言结构处理，走了普通函数调用路径，最终生成调用一个不存在的 wrapper。
- 定位线索：现有 unset 特判只覆盖 `unset($arr[$key])`；需将 `unset($var)` 作为单独语义缺口纳入修复计划。

---

## 3. 运行失败复核（原 TSV 标记为 AOT_RUNTIME_TIMEOUT = 6）

> 复核方法：对每个用例先 `--compile`，再用 `ZIGPHP_ALLOC_STATS=1 tests/aot/timeout.sh 4 ./<exe>` 单独运行并记录 `exit_code` 与回溯。

### 3.1 31_do_while

- 复现命令：
  - `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/31_do_while.php`
  - `ZIGPHP_ALLOC_STATS=1 tests/aot/timeout.sh 4 ./31_do_while`
- 退出码：`137`
- 结论：**真超时/被 kill**。
- 定位线索：do-while 结构化生成的 PHI/递增更新路径缺失可能性高。

### 3.2 42_nested_continue_levels

- 退出码：`134`
- 现象：`panic: reached unreachable code`
- 回溯关键点：
  - `.zigphp_aot_build/main.zig:186:17 in test_nested_continue`：`else => unreachable,`
- 结论：运行时崩溃（panic），不是超时。

### 3.3 43_mixed_control_flow

- 退出码：`134`
- 回溯关键点：
  - `.zigphp_aot_build/main.zig:255:17 in test_mixed_control`：`else => unreachable,`

### 3.4 45_match_in_loop

- 退出码：`134`
- 回溯关键点：
  - `.zigphp_aot_build/main.zig:126:17 in test_match_in_loop`：`else => unreachable,`

### 3.5 46_complex_nesting

- 退出码：`134`
- 回溯关键点：
  - `.zigphp_aot_build/main.zig:216:17 in test_complex_nesting`：`else => unreachable,`

### 3.6 49_recursive_with_loops

- 退出码：`134`
- 回溯关键点：
  - `.zigphp_aot_build/main.zig:247:17 in recursive_loop`：`else => unreachable,`

---

## 4. 输出不匹配（OUTPUT_MISMATCH = 3）

### 4.1 24_nested_break

- PHP：`45`
- AOT：`0`（exit 0，且有 alloc stats）
- 结论：逻辑错误（非崩溃）。
- 定位线索：多层 break 的结构化控制流落点/PHI 回写缺失导致累加器丢失。

### 4.2 56_deep_control_flow（新增复杂用例）

- PHP：`DeepCF: 9 (expect 9)`
- AOT：`DeepCF: 0 (expect 9)`（exit 0）
- 定位线索：深层 `continue/break/while` + if/else 组合导致循环体累加链未执行或 PHI 未更新。

### 4.3 48_nested_function_calls

- PHP：`N0:0 [0-0] N1:0 [1-0] `
- AOT：空输出（仅 alloc stats）
- alloc stats：`live_allocs=4`（但 `live_bytes=0`）
- 结论：输出路径缺失 + 疑似引用计数/释放计数不平衡。

---

## 5. 对采集 runner 的改进建议（分类准确性）

当前 `tests/aot/run_suite_collect.sh` 只要 AOT 退出码非 0 就标记为 `AOT_RUNTIME_TIMEOUT`。建议升级为：

- `exit_code==137` 或输出含 `Killed`：标记为 `AOT_RUNTIME_TIMEOUT`
- `exit_code==134` 且输出含 `panic:`：标记为 `AOT_RUNTIME_PANIC`
- 其它非 0：标记为 `AOT_RUNTIME_ERROR`

并在报告中附带 panic 的关键回溯行（main.zig 行号 + 函数名），便于定位。
