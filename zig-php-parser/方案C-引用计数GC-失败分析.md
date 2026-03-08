# 方案C: 引用计数GC - 失败分析

**日期**: 2026-03-08 13:15  
**通过率**: 39/48 (81.3%)

---

## 核心发现

### 引用计数已实现 ✅
```zig
// PHPString
pub const PHPString = struct {
    ref_count: usize,  // ✅ 已有
    
    pub fn retain(self: *PHPString) void {
        self.ref_count += 1;
    }
    
    pub fn release(self: *PHPString, allocator: Allocator) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit(allocator);
        }
    }
};

// PHPArray
pub const PHPArray = struct {
    ref_count: usize,  // ✅ 已有
    // 同样的retain/release机制
};

// Value
pub fn release(self: Value, allocator: Allocator) void {
    if (self.isString()) {
        self.asString().release(allocator);  // ✅ 调用底层release
    } else if (self.isArray()) {
        self.asArray().release(allocator);
    }
    // ...
}
```

### 问题不在机制，在调用时机 ❌

**当前生成的代码**:
```zig
reg_10 = try runtime.php_concat(reg_8, reg_9, allocator);  // ref_count=1
_ = try runtime.php_echo(reg_10);                          // 使用但不消耗
// ❌ 没有 reg_10.release(allocator)
```

**需要的代码**:
```zig
reg_10 = try runtime.php_concat(reg_8, reg_9, allocator);  // ref_count=1
_ = try runtime.php_echo(reg_10);                          // 使用
reg_10.release(allocator);                                  // ✅ 释放
```

---

## 尝试的方案

### 方案1: 块级临时值release
```zig
// 在每个块结束前
for (block.instructions.items) |inst| {
    if (inst.result) |reg| {
        if (!alloca && !phi && mayHeap) {
            release(reg);
        }
    }
}
```

**结果**: 40/48 → 28/48 (-25%)  
**原因**: 临时值可能被后续块使用（通过phi）

### 方案2: 单次使用启发式
```zig
// 统计每个寄存器的使用次数
var use_count = countUses(block);
for (block.instructions.items) |inst| {
    if (use_count[reg] <= 1) {
        release(reg);
    }
}
```

**结果**: 40/48 → 28/48 (-25%)  
**原因**: 只统计本块使用，忽略了跨块使用

---

## 根本问题

### 需要全局活跃性分析

**活跃性分析**（Liveness Analysis）:
1. 计算每个寄存器的**最后使用点**
2. 在最后使用点后插入release
3. 考虑所有控制流路径

**示例**:
```
Block 0:
  reg_10 = concat(...)  // 定义
  echo(reg_10)          // 使用
  br Block 1

Block 1:
  phi reg_11 = [reg_10 from Block 0, ...]  // reg_10还在使用！
  // ← 不能在Block 0结束时release reg_10
```

### 为什么简单方案都失败

| 方案 | 问题 | 示例 |
|------|------|------|
| 块级release | 忽略跨块使用 | phi节点 |
| 单次使用 | 只看本块 | 跨块数据流 |
| expression_stmt | 可能被条件使用 | if (expr()) |

---

## 正确的解决方案

### 方案A: 完整活跃性分析 (推荐)

**实施步骤**:
1. **构建CFG**: 控制流图
2. **数据流分析**: 计算每个点的活跃变量集合
3. **插入release**: 在变量死亡点插入

**工作量**: 5-7天  
**预期**: 81.3% → 95%+

**伪代码**:
```zig
// 1. 计算活跃性
fn computeLiveness(func: *Function) LivenessInfo {
    var live_out: HashMap(BlockId, Set(RegId));
    
    // 反向数据流分析
    repeat until fixpoint {
        for each block in reverse {
            live_in[block] = use[block] ∪ (live_out[block] - def[block])
            live_out[block] = ∪ live_in[succ] for succ in successors
        }
    }
    
    return live_out;
}

// 2. 插入release
fn insertReleases(func: *Function, liveness: LivenessInfo) {
    for each block {
        for each inst {
            for each operand {
                if (operand not in live_out[inst]) {
                    insert release(operand) after inst
                }
            }
        }
    }
}
```

### 方案D: Arena Allocator (快速方案)

**思路**: 每个函数使用Arena，函数结束时统一释放

**优点**:
- 实现简单（1天）
- 不需要活跃性分析
- 保证无泄漏

**缺点**:
- 内存占用高（长函数会累积）
- 不适合长时间运行的函数

**实施**:
```zig
pub fn @"function"(...) !Value {
    var arena = std.heap.ArenaAllocator.init(runtime_allocator);
    defer arena.deinit();  // 函数结束时释放所有
    
    const allocator = arena.allocator();
    // 所有临时值使用arena分配
    ...
}
```

**预期**: 81.3% → 90%+

---

## 当前状态

### 通过率历史
```
起始:        26/48 (54.1%)
Phase 1.5:   38/48 (79.2%)  +25%
Phase 2.0:   39/48 (81.3%)  +2.1%
Phase 2.1:   40/48 (83.3%)  +2%
方案B:       28/48 (58.3%)  -25% (回退)
方案C:       28/48 (58.3%)  -25% (回退)
当前:        39/48 (81.3%)  (稳定)
```

### 失败的脚本
- test_0003 - 大量PHPString破坏
- test_0009 - 大量PHPString破坏
- test_0028 - 大量PHPString/PHPArray破坏
- test_0030 - 未知
- test_0033 - 未知
- test_0048 - 未知

---

## 下一步建议

### 短期 (1-2天): 方案D - Arena Allocator
**优先级**: P0  
**理由**: 快速见效，风险低  
**预期**: 81.3% → 90%+

### 中期 (1周): 方案A - 活跃性分析
**优先级**: P1  
**理由**: 正确且高效  
**预期**: 90% → 95%+

### 长期 (2周): 优化
**优先级**: P2  
- 死代码消除
- 常量传播
- 内联优化

---

## 经验教训

1. **引用计数不是银弹**
   - 机制简单，但调用时机复杂
   - 需要编译器分析支持

2. **启发式方法不可靠**
   - 块级分析忽略跨块数据流
   - 单次使用忽略控制流

3. **需要正确的工具**
   - 活跃性分析是标准技术
   - 不要重新发明轮子

4. **快速方案有价值**
   - Arena虽然粗糙，但有效
   - 先解决问题，再优化

---

**结论**: 方案C失败，因为缺少活跃性分析。推荐先实施方案D（Arena），再实施方案A（活跃性分析）。
