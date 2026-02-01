## 背景与已验证事实（基于源码交叉核对）
- **解释执行入口**：`main.zig → Parser.parse() → VM.run()`；`VM.run()` 在 `tree_walking / bytecode / fast / auto` 四种模式分发，其中 `auto` 目前恒等于 `tree_walking`（`shouldUseBytecode()` 恒 `false`）。
  - 参考：[main.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/main.zig#L318-L357)，[vm.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/runtime/vm.zig#L5057-L5078)，[vm.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/runtime/vm.zig#L5046-L5071)
- **三条“解释器执行模式”覆盖入口**（用于自动抽取功能点覆盖）：
  - Tree：`VM.eval` 的 `switch(node.tag)`：[vm.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/runtime/vm.zig#L5587-L6191)
  - Bytecode：`BytecodeGenerator.visitNode`：[generator.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/bytecode/generator.zig#L303-L342)
  - Fast：`FastCompiler.compileNode`：[fast_compiler.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/runtime/fast_compiler.zig#L132-L161)
- **重要缺口（解释器侧）**：bytecode/fast 对未覆盖 tag 存在“静默跳过”，会产出语义缺失但不报错的结果（这是 Milestone1 需要先量化并纳入差异矩阵的核心风险点）。
- **AOT 编译链路**：当前主链路是 **IR→Zig→调用 zig 编译器**（并非 LLVM 真后端）；LLVM codegen 目前以 `llvm_available=false` 大量 early-return 的 stub 形态存在。
  - 参考：[compiler.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/aot/compiler.zig#L660-L722)，[native_linker.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/aot/native_linker.zig#L8-L16)，[codegen.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/aot/codegen.zig#L494-L577)
- **现有性能框架**：仓库已具备 `.perf_baselines/.perf_reports` 体系与 perf-cli，但 `perf_cli.zig` 目前仍用 mock 结果，未与真实 `bench-all` 闭环；CI 仅有性能工作流。
  - 参考：[performance-check.yml](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/.github/workflows/performance-check.yml#L1-L159)，[perf_cli.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/benchmark/perf_cli.zig#L93-L125)，[build.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/build.zig#L458-L498)

## Milestone 1 目标（两周内交付）
- 输出**“功能点×执行模式”差异矩阵**（Excel）+ **自动更新脚本**（从源码自动生成，避免手工维护）。
- 搭建**性能基线自动化测试框架**（pytest + benchmark + `perf stat`），并可在 CI/本地一键复现。
- 形成可审阅的**文档**：输入输出契约/副作用/异常路径/性能热点与分配热点的“可追溯清单”。

## 交付物清单（Milestone 1 范围内）
- `docs/milestone1/`
  - `callchain_matrix.md`：逐文件逐函数的“功能-实现-调用链”三维矩阵（可链接到源码行）。
  - `mode_diff_matrix.md`：解释器(Tree/Bytecode/Fast) 与 AOT 的覆盖状态与缺口原因。
  - `perf_baseline_methodology.md`：性能基线方法学、统计口径、硬件/内核/编译选项记录格式。
- `artifacts/`
  - `diff_matrix.xlsx`：功能点×执行模式双列表（含状态：已实现/部分/未实现；源码位置链接；缺口原因字段）。
- `tools/`
  - `gen_diff_matrix.py`：从 Zig 源码抽取 AST tag 覆盖（tree/bytecode/fast）+ AOT 覆盖（IRGenerator/NativeLinker）并生成 Excel（同时产出 CSV 便于审阅/差分）。
  - `gen_callchain_matrix.py`：从入口函数出发，抓取关键调用链（解析→执行/编译→输出/错误）并生成矩阵 Markdown。
- `ci/scripts/`
  - `run_perf_baseline.py`：pytest 驱动，执行：解释器(tree/bytecode/fast) + AOT 编译产物；收集 `perf stat`（cycles、instructions、branches、branch-misses、cache-misses）+ wall time。
  - `repro.sh`：一键复现实验（构建、运行、收集、导出报告）。
- `ci/requirements.txt`：固定 pytest/pytest-benchmark 等版本（若环境不允许 pip，则提供 vendor/或替代模式）。

## 关键实现策略（确保 DRY/KISS、避免 fork）
- **功能点来源统一**：以 [ast.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/compiler/ast.zig#L20-L115) 的 `Node.Tag` 枚举为“单一真实源”。
- **覆盖提取统一**：对三个执行模式，统一从其 `switch(node.tag)` 分发点抽取；并把 `else => {}` 静默吞掉视作“未实现（隐性）”，单独标注风险。
- **AOT 覆盖提取**：
  - IR 生成覆盖：从 `ir_generator.zig` 的节点处理分发点抽取（`generate*`/`emit*` 级别），映射到 AST tag/功能点。
  - 后端覆盖：对照 `ir.zig` 的 `Instruction.Op` 与 `native_linker.zig` 的生成分发区，输出 op 覆盖差集，并反向映射到“功能点缺口”。
- **调用链与契约提取**：Milestone1 先覆盖“端到端主链路 + 输出/异常路径”与“显式 switch 分发链”；更深的逐函数副作用/分配次数将在后续里程碑用插桩/采样补齐（Milestone1 先给出可执行的自动化采集框架与字段定义）。

## 性能基线框架设计（pytest+benchmark+perf stat）
- **运行矩阵**：同一 PHP 用例分别跑：Tree/Bytecode/Fast（解释器），以及 `--compile` 产物（AOT）。
- **指标**：wall time（pytest-benchmark）、`perf stat`（cycles、instructions、cache-misses、branch-misses 等），并统一导出 JSON/CSV。
- **一致性检查（Milestone1 先落地小规模）**：对每个用例比对 stdout/stderr（需先把 tree/bytecode/fast 的输出通道差异记录入矩阵；Milestone2 再统一输出策略）。

## 风险与对策（P0/P1/P2 + 影响面 + 落地成本）
| 优先级 | 风险/问题 | 影响面 | 落地成本 |
|---|---|---|---|
| P0 | bytecode/fast “静默跳过 tag”导致差异矩阵被低估 | 差异矩阵可信度 | 低（脚本中强制标注为未实现） |
| P0 | AOT 主链路为 IR→Zig→zig，LLVM codegen stub 造成“LLVM 优化策略”暂无法实证 | AOT 叙述一致性/后续路线 | 低（文档先如实标注现状与缺口） |
| P0 | `perf-cli` 仍 mock，CI 性能回归不可用 | Milestone1 基线可信度 | 中（把真实 bench 结果接入 perf-cli 或在 pytest 侧直接产出基线文件） |
| P1 | build.zig 对 PCRE2 路径偏 macOS，CI/Ubuntu 可能构建失败 | 自动化落地 | 中 |
| P1 | 输出通道不一致（tree 直接 debug.print；bytecode/fast buffer 再 print） | 一致性验证 | 低（先记录差异；后续统一） |

## 验收标准（Milestone 1）
- `diff_matrix.xlsx` 可由 `tools/gen_diff_matrix.py` 一键重建，且与源码分发点一致（可复验）。
- `run_perf_baseline.py` 能在本地/CI 跑通至少一组代表性用例（字符串/数组/函数调用/控制流），并产出 `perf stat` + 统计摘要。
- 文档中每条差异均附**源码位置链接**（至少到函数级/分发点级）。

## 合并请求（MR）策略
- 一个 MR 交付 Milestone1 全部文档与脚本；CI 侧先保证“可运行”与“产出报告”，更严格门禁（clang-tidy/ASan/Valgrind/1e8 随机差分）放到后续里程碑逐步加严。

如果你确认该计划，我将开始：
1) 只增不改地落地 `tools/` 与 `ci/scripts/`；
2) 生成并提交 `diff_matrix.xlsx` 与 docs；
3) 在本仓库新增对应 CI（或复用现有性能工作流）以确保可重复运行。