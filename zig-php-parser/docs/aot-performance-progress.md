# AOT 性能优化进度报告

## 当前状态

### 功能完成度
- ✅ Phi 节点支持（三元运算符）
- ✅ 嵌套循环支持
- ✅ 所有测试通过
- ⚠️ 结构化循环生成（需调试）

### 性能基准（2026-02-10）

| 测试项 | PHP-CLI | AOT | 倍数 |
|--------|---------|-----|------|
| Simple loop (100K) | 0.64ms | 2.53ms | 4x 慢 |
| Nested loop (100x100) | 0.08ms | 0.26ms | 3x 慢 |
| Arithmetic (10K) | 0.12ms | 0.40ms | 3x 慢 |
| Array sum (10K) | 0.19ms | 3.40ms | 18x 慢 |
| String concat (1K) | 0.006ms | 13.05ms | **2175x 慢** |
| **总计** | **1.03ms** | **19.64ms** | **19x 慢** |

### 性能瓶颈分析

#### 1. 字符串拼接（最严重）
- **问题**：每次拼接都分配新内存
- **原因**：`"Hello" . " " . "World"` 生成 2 次 `php_concat` 调用
- **优化方案**：
  - 常量字符串编译时折叠
  - 循环不变量提升
  - 字符串构建器（StringBuilder）

#### 2. 数组操作
- **问题**：`array_sum` 调用开销大
- **原因**：运行时函数调用，无内联
- **优化方案**：
  - 内联常见数组函数
  - 特化已知大小的数组

#### 3. 循环开销
- **问题**：状态机模式有额外开销
- **原因**：switch-case 跳转，无结构化循环
- **优化方案**：
  - 修复循环检测逻辑
  - 启用结构化 for/while 生成

## 优化计划

### Phase 1: 修复结构化循环（优先级：高）
- [ ] 调试 CFG 构建逻辑
- [ ] 修复循环检测
- [ ] 验证简单循环生成 `for` 而非状态机
- **预期提升**：2-3x

### Phase 2: 字符串优化（优先级：高）
- [ ] 常量字符串折叠
- [ ] 循环不变量提升
- [ ] StringBuilder 优化
- **预期提升**：100-1000x（字符串操作）

### Phase 3: 数组优化（优先级：中）
- [ ] 内联 `array_sum`, `array_count`
- [ ] 特化固定大小数组
- **预期提升**：5-10x（数组操作）

### Phase 4: 高级优化（优先级：低）
- [ ] 死代码消除
- [ ] 公共子表达式消除
- [ ] 寄存器分配优化
- **预期提升**：1.5-2x

## 之前的优化（已实现但未启用）

以下 15 个优化已实现，但因结构化循环禁用而未生效：

1. ✅ Structured Control Flow
2. ✅ Condition Expression Inlining
3. ✅ Eliminate Alloca Boxing (7.2x)
4. ✅ Loop Invariant Code Motion (1.17x)
5. ✅ Strength Reduction (75% instruction reduction)
6. ✅ Copy Propagation (1.14x)
7. ✅ Dead Code Elimination
8. ✅ Loop Unrolling (4x)
9. ✅ Loop Peeling
10. ✅ Branch Prediction Hints
11. ✅ Register Renaming
12. ✅ Full Loop Unrolling (≤16 iterations)
13. ✅ Dead Store Elimination (10.2x)
14. ✅ Mathematical Simplification (13000x)
15. ✅ Dead Loop Elimination

**重新启用这些优化后，预期性能提升：30-200x**

## 下一步行动

1. **立即**：修复循环检测，启用结构化生成
2. **今天**：实现字符串常量折叠
3. **本周**：完成所有 Phase 1-2 优化
4. **目标**：AOT 性能超越 PHP-CLI 10-100x

## 测试命令

```bash
# PHP-CLI 基准
php tests/aot/benchmark_performance.php

# AOT 基准
./zig-out/bin/php-interpreter --compile tests/aot/benchmark_performance.php
./benchmark_performance
```
