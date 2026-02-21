# AOT 后续修复与开发计划（2026-02-20）

## 1. 背景与目标
- 基于 `.zigphp_aot_reports/suite_collect_20260220_141946.md/.tsv` 与 `suite_collect_20260220_141946_details.md`，当前 56 个 AOT 用例中有 17 个失败。
- 失败类型：编译失败 8、运行期异常 6（含 5 个 panic）、输出不匹配 3。
- 用户要求：严格区分 AOT 语义问题 vs. 采集工具问题，先收集→规划→确认后再修；同时需要可控时长的 runner。

## 2. 核心策略
### 2.1 S1：`unset($var)` 暂定为生成端 no-op
- `unset($arr[$key])` 已有 IR/Codegen 支持；但 `unset($v)`（断开引用）目前导致生成 `@"unset"` 调用却无实现。
- 采用 S1：在生成端将 `unset($var)` 视作可忽略语句（或最小占位），优先保证编译通过，语义精细化延后到 P1/P2。

### 2.2 生成端优先
- 绝大部分 panic/类型错误发生在 `.zigphp_aot_build/main.zig`，说明 IR→Zig 生成流程缺乏类型/分支保护。
- 修复顺序：优先修 `native_linker.zig`/IR 生成逻辑，确保输出 Zig 源码合法、分支完备；仅在确属运行时库缺陷时才改 runtime。

## 3. 分阶段计划与验收标准
| 阶段 | 目标 | 涉及用例 | 主要改动 | 验收 | 回归脚本 |
| --- | --- | --- | --- | --- | --- |
| **P0-1** | 统一 Value↔标量转换与比较生成，清除编译错误 | 05、34、41、44、47、50、51 | `src/aot/native_linker.zig` move/cast/phi/compare 路径；必要时 IR 层补充寄存器类型提示 | 上述 7 个用例 `--compile` 全部成功 | `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/<name>.php`；完成后跑 `MAX_TESTS=56 COMPILE_TIMEOUT=12 RUN_TIMEOUT=4 tests/aot/run_suite_collect.sh` |
| **P0-2** | 消除 panic (`else => unreachable`) | 42、43、45、46、49 | 结构化控制流生成（for/while/match），确保 switch/default 覆盖；必要时在生成端补充 fallback 分支 | 5 个用例 AOT 运行 exit=0 | `tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile ...` + `ZIGPHP_ALLOC_STATS=1 tests/aot/timeout.sh 4 ./<exe>` |
| **P0-3** | 按 S1 处理 `unset($var)`，保证 `52_foreach_by_ref` 可编译 | 52 | IR/Codegen 对 `unset` 语句的特判；避免生成不存在的函数调用 | `52_foreach_by_ref.php` `--compile` 成功 | 同上 |
| **P1-1** | 修复真实超时 | 31 | do-while 结构化生成，PHI/递增逻辑 | 用例运行 exit=0 且输出匹配 | 同上 |
| **P1-2** | 修复输出不匹配（深度控制流） | 24、56 | break/continue/while 合流块、PHI 回写 | 输出完全匹配 PHP | 同上 |
| **P1-3** | `48_nested_function_calls` 输出恢复 + alloc stats 回零 | 48 | Value 生命周期（retain/release）、concat 输出 | 输出匹配；alloc stats `live_allocs=0` | 同上 |
| **P2-1** | Runner 分类精细化 | 采集脚本 | `tests/aot/run_suite_collect.sh`：区分 timeout(137)/panic(134)/其它错误，并在报告中附回溯摘要 | 报告中“超时 vs panic”正确显示 | `MAX_TESTS=56 ... run_suite_collect.sh` |
| **P2-2** | 扩大 suite 覆盖（仅限当前语义） | 新增/扩展用例 | `tests/aot/suite` | 新增用例能编译运行 | 同上 |

## 4. 每阶段通用流程
1. 创建分支（或保存工作区状态）。
2. 实施最小变更 → 本地 `zig build -Doptimize=ReleaseFast install`。
3. 针对阶段目标中列出的用例逐个 `--compile` / `run` 复现。
4. 执行 `MAX_TESTS=56 COMPILE_TIMEOUT=12 RUN_TIMEOUT=4 tests/aot/run_suite_collect.sh` 收集报告。
5. 更新 `docs/2026-02-20/ai_modify.md`（按时间顺序 append）。
6. 若进入 P2-1：同时更新 `.zigphp_aot_reports` 中的采集脚本说明。

## 5. 关键脚本/命令汇总
```bash
# 单用例编译
tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/<name>.php

# 单用例运行（含 alloc stats & 超时）
ZIGPHP_ALLOC_STATS=1 tests/aot/timeout.sh 4 ./<name>

# 全量受控采集
MAX_TESTS=56 COMPILE_TIMEOUT=12 RUN_TIMEOUT=4 tests/aot/run_suite_collect.sh
```

## 6. 风险与注意事项
- **类型统一**：修复 P0-1 时务必保持“只在需要 Value→标量时调用 `.asInt()`/`.asFloat()`”；避免在纯标量路径重复包装/拆包，防止性能掉队。
- **panic 处理**：生成端如果确实拿不到合法分支，宁可显式返回错误（如 `return error.InvalidState;`）也不要 `unreachable`，方便后续定位。
- **unset 语义**：S1 仅解决编译问题；后续若要匹配 PHP 的引用断开语义，需要引入符号表/引用计数更复杂逻辑，暂不纳入本批计划。
- **采集脚本分类**：P2-1 完成前，TSV 中的 `AOT_RUNTIME_TIMEOUT` 需要结合 `exit_code` 手动识别 panic（详见细节报告）。
