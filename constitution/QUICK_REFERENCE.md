# 快速参考卡片

**用途**: 开发时快速查阅关键标准和检查清单

---

## 🎯 性能目标速查

| 模式 | 指标 | 目标 |
|------|------|------|
| **解释器** | 函数调用 | < 50ns |
| | 对象创建 | < 200ns |
| | 数组操作 | < 10ns/元素 |
| **JIT** | 编译时间 | < 10ms/函数 |
| | 执行速度 | AOT的80-90% |
| **AOT** | 编译速度 | < 5s/1000行 |
| | 执行速度 | C的90-95% |
| **GC** | Minor停顿 | < 1ms |
| | Major停顿 | < 10ms |
| | 吞吐量 | > 95% |
| **并发** | 协程创建 | < 100ns |
| | 上下文切换 | < 50ns |

---

## ✅ 代码提交前检查清单

### 性能检查
- [ ] 基准测试通过（达到目标）
- [ ] 无性能回归（< 5%）
- [ ] 使用最优算法（O(?)标注）
- [ ] 热点路径优化（SIMD/缓存）

### 安全检查
- [ ] Valgrind无泄漏
- [ ] AddressSanitizer通过
- [ ] ThreadSanitizer通过
- [ ] 所有权明确标注

### 质量检查
- [ ] 测试覆盖率 ≥ 90%
- [ ] 所有测试通过
- [ ] 代码格式化（zig fmt）
- [ ] 文档完整

### 代码审查
- [ ] 函数 < 200行
- [ ] 嵌套 < 4层
- [ ] 无魔法数字
- [ ] 错误处理完整

---

## 📝 必需注释模板

```zig
/// [一句话功能描述]
/// 
/// 算法: [算法名称]
/// 时间复杂度: O(?)
/// 空间复杂度: O(?)
/// @thread-safety [ISOLATED/SYNCHRONIZED/LOCK_FREE/UNSAFE]
/// @ownership [OWNING/NON-OWNING/SHARED]
/// 
/// 参数:
///   - param: [说明]
/// 返回: [说明]
/// 错误: [可能的错误]
pub fn function(param: Type) !ReturnType {
    // 实现
}
```

---

## 🚫 严禁事项速查

### 性能
- ❌ 低效算法（O(n²) vs O(n log n)）
- ❌ 不必要的分配
- ❌ 未测试的性能声明

### 内存
- ❌ 内存泄漏
- ❌ 悬空指针
- ❌ 双重释放

### 并发
- ❌ 数据竞争
- ❌ 死锁
- ❌ 未保护的共享状态

### 代码
- ❌ 未注释的复杂算法
- ❌ 魔法数字
- ❌ 未处理的错误

### 脚本保护
- ❌ 删除 PHP 原始脚本文件（`.php`）——任何时候都不可删除

---

## 🤖 AI协作决策树

```
任务复杂度评估
    ↓
< 200行？ ──YES──> 单代理实现
    ↓ NO
200-500行？ ──YES──> 单代理 + 审查
    ↓ NO
500-1000行？ ──YES──> 多代理协作
    ↓ NO
> 1000行？ ──YES──> 多代理 + 分阶段
```

**多代理触发条件**:
- 代码量 > 500行
- 核心架构修改
- 性能影响 > 5%
- 方案不确定

---

## 🔧 常用命令速查

### 编译与测试
```bash
# 编译
zig build

# 运行测试
zig build test

# 性能测试
zig build benchmark

# 格式化
zig fmt src/
```

### 安全检查
```bash
# 内存泄漏检查
valgrind --leak-check=full ./zig-out/bin/php-interpreter test.php

# AddressSanitizer
zig build -Doptimize=Debug -fsanitize=address

# ThreadSanitizer
zig build -Doptimize=Debug -fsanitize=thread
```

### 性能分析
```bash
# CPU性能分析
perf record -g ./zig-out/bin/php-interpreter test.php
perf report

# 缓存分析
perf stat -e cache-references,cache-misses ./zig-out/bin/php-interpreter test.php
```

---

## 📐 算法复杂度速查

| 算法 | 时间 | 空间 | 适用场景 |
|------|------|------|---------|
| 哈希表 | O(1) | O(n) | 符号查找 |
| 二叉搜索 | O(log n) | O(1) | 有序查找 |
| 快速排序 | O(n log n) | O(log n) | 通用排序 |
| 归并排序 | O(n log n) | O(n) | 稳定排序 |
| 堆排序 | O(n log n) | O(1) | 原地排序 |
| Robin Hood哈希 | O(1) | O(n) | 最坏情况优化 |

---

## 🎨 优化技术速查

### CPU优化
- **缓存对齐**: `align(64)`
- **分支消除**: 查找表、条件移动
- **循环展开**: 手动或编译器
- **预取**: `@prefetch()`

### SIMD优化
```zig
const vec = @Vector(16, u8);
const va = @as(vec, a[0..16].*);
const vb = @as(vec, b[0..16].*);
const result = va + vb;
```

### 内存优化
- **对象池**: 高频对象复用
- **Arena**: 批量分配/释放
- **内存对齐**: 避免跨缓存行
- **紧凑布局**: 减少padding

---

## 📊 基准测试模板

```zig
test "benchmark: [功能名称]" {
    const iterations = 1_000_000;
    var timer = try std.time.Timer.start();
    
    for (0..iterations) |_| {
        _ = functionToTest(args);
    }
    
    const elapsed = timer.read();
    const ns_per_op = elapsed / iterations;
    
    std.debug.print("\n[功能名称]: {d}ns/op\n", .{ns_per_op});
    try std.testing.expect(ns_per_op < TARGET_NS);
}
```

---

## 🔍 调试技巧

### 打印调试
```zig
std.debug.print("Value: {any}\n", .{value});
```

### 断言
```zig
std.debug.assert(condition);
```

### 条件编译
```zig
if (builtin.mode == .Debug) {
    // 调试代码
}
```

### GDB调试
```bash
zig build -Doptimize=Debug
gdb ./zig-out/bin/php-interpreter
```

---

## 🚀 AOT 超越 PHP 解释器的增强特性速查

|| 特性 | PHP 解释器 | AOT 行为 | 详见 |
|------|------|-----------|---------|------|
|| `array_walk` 首参数 | 必须为变量 (by-ref) | 允许数组字面量 `[]` | [PART1 §3.1](./PART1_ARCHITECTURE.md) |
|| `array_walk_recursive` 首参数 | 必须为变量 (by-ref) | 允许数组字面量 `[]` | [PART1 §3.1](./PART1_ARCHITECTURE.md) |

> ⚠️ 增强特性仅限 AOT 模式。字面量参数场景下，回调的引用写回作用于临时副本。

### 发现流程速查

```
AOT 成功 + PHP 报错？ → 可能是超越特性
    ↓
PHP 对比验证 → AOT 编译运行验证 → 边界条件验证
    ↓
记录到宪法 §3 + 添加测试脚本 + 更新速查表
```

**不属于超越特性**：AOT 缺陷 / AOT=PHP 一致 / AOT bug / 非 AOT 更强

---

## ⚖️ AOT 测试容差速查

> **依据**: [PART1 §4](./PART1_ARCHITECTURE.md) · [PART3 §7.4.5](./PART3_DEVELOPMENT.md)

| 编号 | 差异类别 | 典型示例 | 判定 |
|------|---------|---------|------|
| T1 | 栈追踪文件路径/行号不一致 | AOT 无 `in /path/file.php:138` | ✅ 不计为错误 |
| T2 | 栈追踪调用链深度差异 | AOT 仅 `#0 {main}`，PHP 有完整链 | ✅ 不计为错误 |
| T3 | 浮点数末位精度微差 | `2.7182818284591` vs `2.718281828459` | ✅ 不计为错误 |
| T4 | 输出缩进不一致 | 缩进空格数不同 | ✅ 不计为错误 |

**判定原则**: 仅限格式差异 → 容差；语义差异（值/逻辑不同）→ AOT BUG，必须修复

---

## 📚 快速链接

- [第一部分：架构与设计](./PART1_ARCHITECTURE.md)
- [第二部分：性能与优化](./PART2_PERFORMANCE.md)
- [第三部分：流程与质量](./PART3_DEVELOPMENT.md)
- [第四部分：AI协作](./PART4_AI_COLLABORATION.md)
- [主索引](./README.md)

---

**提示**: 将此卡片打印或保存为书签，开发时随时查阅。
