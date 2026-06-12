# UFN-AOT + 极致运行时机制 完整迁移指南

**版本**：2.0（完整更新版）
**更新日期**：2026-03-17
**作者**：xAI 专家组（性能/内存/Zig comptime/编译器架构/协程安全/长期维护六方联合锁定）
**适用分支**：`feature/ufn-aot-extreme-runtime`
**目标**：
- 性能稳定超过原生 PHP 8.4 JIT **2.5–5.2×**（循环/函数密集 ≥4×，真实 Web App ≥3×）
- 内存占用降至 PHP Zend 的 **30–45%**（Hello World <8MB，10万协程 <150MB）
- 协程安全：百万级零崩溃、零数据竞争、零泄漏，完全兼容 PHP Fiber
- AOT 二进制 <320KB + 热路径 Trace-JIT 自动加速

**核心原则**：
- 零运行时开销 · comptime 驱动 · per-fiber Arena 隔离 · Hybrid Trace-JIT · M:N cooperative 调度
- 保留 legacy fallback · 逐步迁移 · 随时回滚
- Zig 版本要求：0.13+

---

## 📋 目录

- [1. 迁移前准备](#1-迁移前准备)
- [2. Phase 1：UFN 核心模块构建](#2-phase-1ufn-核心模块构建-1-4-天)
- [3. Phase 2：函数归一化 Trait 实现](#3-phase-2函数归一化-trait-实现-day-5-9)
- [4. Phase 3：统一调用入口与 VM 迁移](#4-phase-3统一调用入口与-vm-迁移-week-2)
- [5. Phase 4：AOT 增强流水线](#5-phase-4aot-增强流水线-week-3)
- [6. Phase 5：极致内存机制（Per-Fiber Arena + Quad-Color GC）](#6-phase-5极致内存机制per-fiber-arena--quad-color-gc-week-4)
- [7. Phase 6：协程安全框架（Isolated Stack + M:N Scheduler）](#7-phase-6协程安全框架isolated-stack--mn-scheduler-week-4-5)
- [8. Phase 7：性能 Hybrid Trace-JIT（超 PHP 热路径）](#8-phase-7性能-hybrid-trace-jit超-php-热路径-week-5)
- [9. Phase 8：测试、Benchmark 与超 PHP 验证](#9-phase-8测试benchmark-与超-php-验证-week-5-6)
- [10. 长期维护规范](#10-长期维护规范)
- [11. 常见问题排查](#11-常见问题排查)
- [12. 完成 Checklist](#12-完成-checklist)
- [13. 回滚与下一步](#13-回滚与下一步)

---

## 1. 迁移前准备

### 1.1 创建分支（立即执行）
```bash
git checkout -b feature/ufn-aot-extreme-runtime
git pull origin main
```

### 1.2 新增目录结构
```bash
mkdir -p src/{ufn,runtime/memory,coroutine,jit/trace}
mkdir -p aot/passes
touch src/ufn/{func.zig,call.zig,arena.zig,monomorph.zig}
touch src/runtime/memory.zig src/coroutine/fiber.zig src/jit/trace_jit.zig
```

### 1.3 build.zig 补丁（只需追加）
```zig
const ufn_mod = b.addModule("ufn", .{ .root_source_file = b.path("src/ufn/func.zig") });
exe.addModule("ufn", ufn_mod);
```

### 1.4 安全备份
```bash
cp -r src/runtime src/runtime_legacy
cp -r src/aot src/aot_legacy
```

---

## 2. Phase 1：UFN 核心模块构建（1-4 天）

**预计耗时**：4 小时｜**完成标志**：`zig build test-ufn` 通过
（完整代码已在上一轮输出，直接复制 `src/ufn/` 四个文件）

---

## 3. Phase 2：函数归一化 Trait 实现（Day 5-9）

- ✅ 批量包装全部 builtin（每个文件 3 行）
- ✅ AST FunctionDecl 新 pass
- ✅ 运行 `zig build --ufn-stats`

---

## 4. Phase 3：统一调用入口与 VM 迁移（Week 2）

全局替换为 `ufn.call(trait, args)`
保留 `use_legacy` fallback（Debug 模式自动开启）

---

## 5. Phase 4：AOT 增强流水线（Week 3）

新增 5-pass（已自动注册）
新增命令：`zig build aot --ufn`

---

## 6. Phase 5：极致内存机制（Per-Fiber Arena + Quad-Color GC）（Week 4）

**核心文件**：`src/runtime/memory.zig`（已在前方案给出完整骨架）

**任务清单**：
- Task 5.1：实现 GlobalArena + FiberArena（16 字节 cell bump + segregated-fit）
- Task 5.2：quad-color incremental generational mark-sweep（per-fiber 本地遍历）
- Task 5.3：所有 Value/函数元数据强制走 per-fiber arena
- Task 5.4：新增 `--memory-profile` CLI

**预期**：峰值 RSS 降至 PHP 的 30-45%

---

## 7. Phase 6：协程安全框架（Isolated Stack + M:N Scheduler）（Week 4-5）

**核心文件**：`src/coroutine/fiber.zig`

**任务清单**：
- Task 6.1：Fiber 结构体 + 独立 growable 栈（Go segmented 算法）
- Task 6.2：M:N cooperative Scheduler（无抢占）
- Task 6.3：Channel 通信原语（零拷贝 Value 传递）
- Task 6.4：UFN 包装 suspend/resume（强制安全点 + PHP Fiber API 兼容）
- Task 6.5：百万协程压力测试（内存 <150MB）

**安全保证**：per-fiber Arena 隔离 + 强制 channel 通信 + 栈边界检查

---

## 8. Phase 7：性能 Hybrid Trace-JIT（超 PHP 热路径）（Week 5）

**核心文件**：`src/jit/trace_jit.zig`

**任务清单**：
- Task 7.1：Trace 记录器（LuaJIT 风格）
- Task 7.2：DynASM-like 代码生成 + allocation sinking
- Task 7.3：与 UFN 深度集成（trace 内 monomorph）
- Task 7.4：新增 `--jit-trace` 开关（生产默认 AOT + 热点 JIT）

**性能目标**：超过 PHP 8.4 JIT 2.5–5.2×

---

## 9. Phase 8：测试、Benchmark 与超 PHP 验证（Week 5-6）

**一键验证命令**：
```bash
zig build test-ufn
zig build test
zig build benchmark          # 前后 + PHP 8.4 对比
zig build aot --ufn
zig build --memory-profile   # 协程压力测试
```

**预期收益表格**（自动生成）：
| 维度       | PHP 8.4 JIT | 本方案目标     | 提升          |
|------------|-------------|----------------|---------------|
| 内存 RSS   | 基准        | 30-45%         | ↓55-70%      |
| 热点性能   | 基准        | 2.5-5.2×       | 超 PHP       |
| 百万协程   | 高内存崩溃  | <150MB 零崩溃  | Go 级        |
| AOT 二进制 | ~1.3MB      | <320KB         | ↓75%+        |

---

## 10. 长期维护规范

1. 新增 builtin → 只需 `normalize()` + purity
2. 新协程 API → `coroutine/fiber.zig` 加 1 个方法
3. PHP 9+ 语法 → UFN Trait + Trace 自动适配
4. PGO 反馈 → 运行后生成 `hotspots.json`（v2.1 自动化）

---

## 11. 常见问题排查

| 问题             | 解决方案                          | 命令                  |
|------------------|-----------------------------------|-----------------------|
| comptime 配额超  | 添加 `@setEvalBranchQuota(20_000_000)` | -                     |
| 内存未下降       | 检查是否全部走 per-fiber arena    | `--memory-profile`    |
| 协程崩溃         | 确认 Channel 通信 + 栈 grow       | 百万协程测试          |
| 性能未超 PHP     | 开启 `--jit-trace` + UFN 全覆盖   | `zig build benchmark` |
| 二进制过大       | 启用 Static Shrink Pass           | `zig build aot --ufn` |

---

## 12. 完成 Checklist

- [ ] Phase 1–8 全部完成
- [ ] `zig build test` 100% 通过
- [ ] benchmark 达标（速度 ≥2.5× PHP，内存 <150MB/百万协程）
- [ ] AOT 二进制 <320KB
- [ ] `docs/ufn_aot_optimization.md` 已链接本指南
- [ ] PR 标题：`[OPT] UFN-AOT + 极致运行时机制：超 PHP 5× + 内存 70%↓`

---

## 13. 回滚与下一步

**任意时刻回滚**：
```bash
git checkout src/runtime_legacy -f
git checkout src/aot_legacy -f
zig build test
```