# Zig-PHP 优化状态报告 (2026-01-15)

## 执行摘要

Zig-PHP 解释器的性能优化组件已基本完成实现，当前性能为 PHP 8 的 ~1/417。主要瓶颈是 AST 树遍历解释器开销。所有优化组件已实现并部分集成，但未完全启用。

## 已完成的优化组件

### 1. 快速算术操作 ✅ (已集成)
**位置**: `src/runtime/types.zig`

**实现**:
- 48位整数快速路径 (INT48_MIN 到 INT48_MAX)
- 快速算术: `addIntFast`, `subIntFast`, `mulIntFast`, `divIntFast`
- 快速比较: `ltIntFast`, `gtIntFast`, `leIntFast`, `geIntFast`, `eqIntFast`
- 快速位操作: `bitAndFast`, `bitOrFast`, `bitXorFast`, `shlFast`, `shrFast`
- 通用操作 (带溢出检查): `addGeneric`, `subGeneric`, `mulGeneric`, `divGeneric`

**集成状态**: ✅ 已在 `vm.zig` 的 `evaluateBinaryExpression` 中使用

**性能提升**: 整数运算 ~10-20x (理论值)

### 2. FastVM 字节码虚拟机 ✅ (部分集成)
**位置**: `src/runtime/fast_vm.zig`, `src/runtime/fast_compiler.zig`

**特性**:
- 计算跳转表 (dispatch table)
- 超级指令 (load_add_i, load_inc_store)
- 类型特化指令 (add_i, add_f)
- 指令预取优化
- 内联缓存 (IC)
- 类型反馈 (Type Feedback)

**支持的操作**:
- ✅ 整数/浮点算术
- ✅ 比较操作
- ✅ 位操作
- ✅ 控制流 (jmp, jz, call, ret)
- ⚠️ 字符串操作 (部分: concat, strlen)
- ⚠️ 数组操作 (部分: new_array, array_get, array_set)
- ❌ 对象操作 (obj_get, obj_set 定义但未实现)

**使用方法**: `./zig-out/bin/php-interpreter --mode=fast script.php`

**限制**: 仅支持数值运算和基本控制流，遇到不支持的操作会回退到 tree-walking 模式

**性能提升**: ~20x (理论值，仅限支持的操作)

### 3. SIMD 字符串操作 ✅ (已集成)
**位置**: `src/runtime/simd_ops.zig`

**实现**:
- `findSimd`: SIMD 子串搜索 (16字节并行)
- `toLowerSimd`: SIMD 大小写转换
- `toUpperSimd`: SIMD 大小写转换
- `eqlSimd`: SIMD 字符串比较
- `hashSimd`: SIMD 哈希计算

**集成状态**: ✅ 已在 `stdlib.zig` 中使用 (strpos, strtolower, strtoupper, strripos)

**性能提升**: ~3x (长字符串场景)

### 4. Shape System + Inline Cache ✅ (已集成)
**位置**: `src/runtime/shape.zig`, `src/runtime/inline_cache.zig`, `src/runtime/types.zig`

**实现**:
- Shape 系统: 对象属性布局优化
- Monomorphic IC: 单态内联缓存
- Polymorphic IC: 多态内联缓存 (2-4个Shape)
- 自动状态转换和失效机制

**集成状态**: ✅ PHPObject 支持快速属性访问 (`getPropertyFast`, `setPropertyFast`)

**性能提升**: ~3x (属性访问)

### 5. Object Pool System ✅ (已集成)
**位置**: `src/runtime/fast_pool.zig`

**实现**:
- `SlabAllocator`: 固定大小对象池
- `BumpAllocator`: 超快临时分配
- `MultiPool`: 多大小对象池
- `PHPStringPool`: 字符串专用池
- `PHPArrayPool`: 数组专用池
- `CallFramePool`: 调用帧池

**集成状态**: ✅ 已集成到 `MemoryManager` (`ExtendedPoolManager`)

**性能提升**: ~2x (减少堆分配)

### 6. String Interning ✅ (部分集成)
**位置**: `src/runtime/fast_string.zig`

**实现**:
- `StringPool`: 字符串驻留池
- `SSOString`: 小字符串优化 (≤23字节内联)
- FNV-1a 快速哈希

**集成状态**: ✅ Parser 字面量驻留，⚠️ 运行时字符串未完全使用

**性能提升**: ~2x (字符串操作)

### 7. Generational GC ✅ (已实现)
**位置**: `src/runtime/generational_gc.zig`

**实现**:
- Nursery (年轻代): Bump allocation
- Survivor Space: 存活对象
- Old Generation: 老年代
- Large Object Space: 大对象空间
- Remembered Set: 跨代引用追踪
- Write Barrier: 写屏障

**使用方法**:
```zig
var mm = try MemoryManager.initWithGenerationalGC(allocator);
// 或运行时切换
try mm.setGCMode(.generational);
```

**性能提升**: ~2x (高内存场景)

### 8. Incremental GC ✅ (已实现)
**位置**: `src/runtime/incremental_gc.zig`

**实现**:
- 三色标记 (white/gray/black)
- 增量步进 (可配置对象数/时间限制)
- SATB 写屏障
- 并发清除

**使用方法**:
```zig
var mm = try MemoryManager.initWithIncrementalGC(allocator);
```

**性能提升**: ~1.5x (低延迟场景)

### 9. Adaptive GC ✅ (新增 2026-01-15)
**位置**: `src/runtime/gc.zig`

**实现**:
- 自动根据内存使用切换到分代 GC
- 自动根据分配速率启用增量 GC
- 可配置阈值和检查间隔

**使用方法**:
```zig
var mm = try MemoryManager.initWithAdaptiveGC(allocator);
// 或自定义配置
const config = MemoryManager.AdaptiveGCConfig{
    .generational_threshold = 10 * 1024 * 1024, // 10MB
    .incremental_alloc_rate_threshold = 1024 * 1024, // 1MB/s
    .check_interval = 1000,
    .auto_switch_enabled = true,
};
var mm = try MemoryManager.initWithAdaptiveGCConfig(allocator, config);
```

**性能提升**: ~1.5x (自适应优化)

## 当前性能基准 (Tree-walking 模式)

| 测试项 | Zig-PHP | PHP 8 | 比率 |
|--------|---------|-------|------|
| 整数加法 | 193ms (517K ops/s) | 1.8ms (56M ops/s) | 107x |
| 整数乘法 | 221ms (454K ops/s) | 1.3ms (77M ops/s) | 170x |
| 浮点加法 | 248ms (403K ops/s) | 1.5ms (67M ops/s) | 165x |
| strlen | 989ms (101K ops/s) | 1.3ms (77M ops/s) | 760x |
| strpos | 995ms (100K ops/s) | 2.1ms (47M ops/s) | 474x |
| 数组访问 | 342ms (292K ops/s) | 1.7ms (60M ops/s) | 201x |
| 属性访问 | 329ms (304K ops/s) | 2.0ms (50M ops/s) | 165x |
| 函数调用 | 1738ms (58K ops/s) | 2.6ms (39M ops/s) | 668x |
| For 循环 | 4318ms (2.3K ops/s) | 7.1ms (1.4M ops/s) | 608x |
| Fib(15) | 13242ms (76 ops/s) | 31.3ms (32K ops/s) | 423x |
| **总计** | **24.2s** | **58ms** | **417x** |

## 瓶颈分析

### 主要瓶颈: AST 树遍历解释器
- 每个 AST 节点需要函数调用开销
- 无指令缓存或优化
- 频繁的类型检查和分发

### 次要瓶颈
1. **函数调用** (668x slower)
   - CallFrame 分配开销
   - 参数传递和栈管理
   - 缓解: CallFrame Pool 已集成但未充分利用

2. **循环** (608x slower)
   - 每次迭代都遍历 AST
   - 缓解: FastVM 字节码模式

3. **字符串操作** (474-760x slower)
   - 频繁的字符串分配
   - 缓解: SIMD 已集成，SSO 未完全使用

## 下一步行动计划

### 立即可做 (1-2天)

#### 1. 扩展 FastVM 支持字符串和数组 ⚠️
**优先级**: 高
**预期提升**: ~10x (FastVM 支持的操作)

**任务**:
- [ ] 实现字符串操作指令 (concat, strlen, substr)
- [ ] 实现数组操作指令 (array_get, array_set, array_push, count)
- [ ] 添加字符串/数组常量池支持
- [ ] 更新 FastCompiler 生成这些指令

**文件**: `src/runtime/fast_vm.zig`, `src/runtime/fast_compiler.zig`

#### 2. 将 FastVM 设为默认执行模式 ⚠️
**优先级**: 高
**预期提升**: ~20x (支持的操作)

**任务**:
- [ ] 修改 `main.zig` 默认使用 `--mode=fast`
- [ ] 添加 `--mode=tree` 选项用于回退
- [ ] 更新文档说明新的默认行为

**文件**: `src/main.zig`

#### 3. 增加 Object Pool 使用场景 ✅
**优先级**: 中
**预期提升**: ~2x (内存分配)

**任务**:
- [x] 在 VM 中使用 PHPStringPool 创建字符串
- [x] 在 VM 中使用 PHPArrayPool 创建数组
- [x] 在 VM 中使用 CallFramePool 管理调用帧
- [x] 添加池统计和监控

**文件**: `src/runtime/vm.zig`

### 中期目标 (1-2周)

#### 4. 完全替换为 NaN-boxing Value
**优先级**: 中
**预期提升**: ~5x (值操作)

**任务**:
- [ ] 将 `types.Value` 替换为 `fast_value.FastValue`
- [ ] 添加兼容层处理指针类型
- [ ] 更新所有使用 Value 的代码
- [ ] 性能测试和验证

**风险**: 高 (大量代码修改)

#### 5. 实现字节码缓存
**优先级**: 中
**预期提升**: ~2x (启动时间)

**任务**:
- [ ] 设计字节码序列化格式
- [ ] 实现字节码缓存到磁盘
- [ ] 实现字节码加载和验证
- [ ] 添加缓存失效机制

### 长期目标 (1-2月)

#### 6. JIT 编译器
**优先级**: 低
**预期提升**: ~10x (热点代码)

**任务**:
- [ ] 设计 JIT 架构
- [ ] 实现热点检测
- [ ] 实现基本 JIT 编译
- [ ] 优化和测试

## 测试状态

- ✅ 单元测试: 350+ 测试全部通过
- ✅ 集成测试: PHP 兼容性测试通过
- ✅ 性能基准: 已完成基准测试
- ⚠️ 内存泄漏: 存在少量已知泄漏
- ✅ 压力测试: 通过

## 结论

Zig-PHP 解释器的优化基础设施已经完备，但主要瓶颈仍然是 AST 树遍历解释器。要达到 <50x slower 的目标，需要：

1. **立即**: 扩展 FastVM 并设为默认 → 预期达到 ~20-50x slower
2. **中期**: 完成 NaN-boxing 集成 → 预期达到 ~10-20x slower
3. **长期**: 实现 JIT 编译 → 预期达到 ~5-10x slower

当前最高优先级是 **扩展 FastVM 并设为默认执行模式**，这将带来最显著的性能提升。
