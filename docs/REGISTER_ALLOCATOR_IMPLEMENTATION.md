# 寄存器分配器实现文档

## 概述

本文档描述了 Zig-PHP JIT 编译器的寄存器分配器实现，包括线性扫描算法、活跃区间计算和寄存器溢出处理。

## 实现位置

- **核心实现**: `src/jit/register_allocator.zig`
- **属性测试**: `src/jit/test_register_allocator_properties.zig`

## 核心功能

### 1. 活跃区间计算

寄存器分配器首先计算每个虚拟寄存器的活跃区间（生命周期）：

```zig
pub const LiveInterval = struct {
    var_id: u32,        // 虚拟寄存器 ID
    start: usize,       // 起始位置（指令索引）
    end: usize,         // 结束位置（指令索引）
    assigned_reg: ?Register,  // 分配的物理寄存器
    spill_slot: ?i32,   // 溢出栈位置
    use_count: u32,     // 使用次数
};
```

活跃区间通过两遍扫描计算：
1. **第一遍**：记录每个变量的首次使用和最后使用位置
2. **第二遍**：创建活跃区间并计算使用次数

### 2. 线性扫描寄存器分配

实现了经典的线性扫描寄存器分配算法：

```zig
pub fn allocate(self: *RegisterAllocator) !RegisterMap {
    // 1. 按起始位置排序活跃区间
    std.mem.sort(LiveInterval, self.live_intervals.items, {}, LiveInterval.compareByStart);
    
    // 2. 线性扫描分配
    for (self.live_intervals.items) |*interval| {
        // 释放已结束的活跃区间
        try self.expireOldIntervals(interval, reg_free);
        
        // 尝试分配物理寄存器
        if (self.tryAllocateRegister(interval, reg_free)) |reg| {
            // 分配成功
            interval.assigned_reg = reg;
            try reg_map.assignReg(interval.var_id, reg);
        } else {
            // 寄存器不足，溢出到栈
            try self.spillVariable(interval, &reg_map);
        }
    }
    
    return reg_map;
}
```

### 3. 寄存器溢出处理

当物理寄存器不足时，变量会被溢出到栈：

```zig
fn spillVariable(
    self: *RegisterAllocator,
    interval: *LiveInterval,
    reg_map: *RegisterMap,
) !void {
    // 分配栈槽（每个槽 8 字节）
    const spill_slot = self.next_spill_slot;
    self.next_spill_slot -= 8;
    
    interval.spill_slot = spill_slot;
    try reg_map.assignSpillSlot(interval.var_id, spill_slot);
}
```

### 4. 可用寄存器

x86-64 架构下可用的 14 个通用寄存器：

```zig
pub const DEFAULT_AVAILABLE_REGS = [_]Register{
    .rax, .rbx, .rcx, .rdx, .rsi, .rdi,
    .r8, .r9, .r10, .r11, .r12, .r13, .r14, .r15,
};
```

注意：`rsp`（栈指针）和 `rbp`（帧指针）保留不用于分配。

## 性能统计

寄存器分配器提供详细的统计信息：

```zig
pub const AllocatorStats = struct {
    total_vars: u32,        // 总虚拟寄存器数
    allocated_regs: u32,    // 分配到物理寄存器的数量
    spilled_vars: u32,      // 溢出到栈的数量
    utilization: f32,       // 寄存器利用率（0.0 - 1.0）
};
```

## 属性测试

实现了 5 个核心属性测试，每个测试运行 100 次迭代：

### 属性 12.1：所有虚拟寄存器都被分配

验证每个虚拟寄存器都被分配到物理寄存器或栈位置。

```zig
// 对于任意虚拟寄存器集合
for (0..num_vars) |id| {
    const has_reg = reg_map.getReg(id) != null;
    const has_spill = reg_map.getSpillSlot(id) != null;
    assert(has_reg or has_spill);  // 必须至少有一个
}
```

### 属性 12.2：重叠区间不共享寄存器

验证重叠的活跃区间不会被分配到同一个物理寄存器。

```zig
// 对于任意两个重叠的区间
if (interval1.overlaps(&interval2)) {
    const reg1 = reg_map.getReg(interval1.var_id);
    const reg2 = reg_map.getReg(interval2.var_id);
    
    // 如果都分配到寄存器，必须不同
    if (reg1 != null and reg2 != null) {
        assert(reg1.? != reg2.?);
    }
}
```

### 属性 12.3：寄存器利用率 > 80%

当虚拟寄存器数量不超过可用物理寄存器数量时，利用率应该 > 80%。

```zig
const stats = ra.getStats();
assert(stats.utilization > 0.80);
```

### 属性 12.4：活跃区间计算正确性

验证从指令序列计算的活跃区间正确反映变量的生命周期。

```zig
// 对于任意指令序列
for (ra.live_intervals.items) |interval| {
    // 区间必须有效
    assert(interval.start <= interval.end);
    assert(interval.end < instructions.len);
    
    // 变量在起始位置必须被使用
    const start_inst = instructions[interval.start];
    assert(start_inst.uses(interval.var_id));
}
```

### 属性 12.5：溢出决策最优性

验证溢出决策倾向于溢出使用次数较少的变量。

```zig
// 收集溢出和分配变量的使用次数
const max_spilled = max(spilled_use_counts);
const min_allocated = min(allocated_use_counts);

// 溢出变量的使用次数应该较少
// （允许一定容差，因为线性扫描不保证全局最优）
assert(max_spilled <= min_allocated + tolerance);
```

## 测试结果

所有属性测试均通过 100 次迭代：

```
=== 属性测试结果 ===
属性 12.1 - 所有虚拟寄存器都被分配: 100/100 (100.00%) ✓
属性 12.2 - 重叠区间不共享寄存器: 100/100 (100.00%) ✓
属性 12.3 - 寄存器利用率: 100/100 (100.00%) ✓
属性 12.4 - 活跃区间计算正确性: 100/100 (100.00%) ✓
属性 12.5 - 溢出决策最优性: 100/100 (100.00%) ✓

综合结果:
  总通过: 500/500
  总失败: 0
  总成功率: 100.00%
```

## 算法复杂度

- **活跃区间计算**: O(n × m)，其中 n 是指令数，m 是变量数
- **线性扫描分配**: O(n log n)，其中 n 是活跃区间数
- **空间复杂度**: O(n + r)，其中 r 是可用寄存器数

## 使用示例

```zig
const std = @import("std");
const RegisterAllocator = @import("register_allocator.zig").RegisterAllocator;
const Instruction = @import("register_allocator.zig").Instruction;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 创建寄存器分配器
    var ra = RegisterAllocator.init(allocator);
    defer ra.deinit();
    
    // 定义指令序列
    const instructions = [_]Instruction{
        Instruction.init(0, null, null),    // v0 = ...
        Instruction.init(1, 0, null),       // v1 = v0
        Instruction.init(2, 0, 1),          // v2 = v0 + v1
        Instruction.init(null, 2, null),    // ... = v2
    };
    
    // 计算活跃区间
    try ra.computeLiveIntervals(&instructions);
    
    // 执行寄存器分配
    var reg_map = try ra.allocate();
    defer reg_map.deinit();
    
    // 查询分配结果
    if (reg_map.getReg(0)) |reg| {
        std.debug.print("v0 -> {s}\n", .{reg.name()});
    }
    
    // 打印统计信息
    const stats = ra.getStats();
    stats.print();
}
```

## 未来优化

1. **图着色算法**: 实现更优的全局寄存器分配
2. **寄存器压力感知**: 根据寄存器压力动态调整溢出策略
3. **寄存器重用**: 优化寄存器重用以减少溢出
4. **SIMD 寄存器支持**: 扩展支持 XMM/YMM/ZMM 寄存器
5. **多架构支持**: 扩展支持 ARM64 等其他架构

## 参考文献

1. Poletto, M., & Sarkar, V. (1999). Linear scan register allocation. ACM TOPLAS.
2. Wimmer, C., & Franz, M. (2010). Linear scan register allocation on SSA form. CGO.
3. Appel, A. W. (1998). Modern Compiler Implementation in ML. Cambridge University Press.

## 验证需求

本实现满足需求 2.5 的所有验收标准：

- ✅ 实现活跃区间计算
- ✅ 实现线性扫描寄存器分配算法
- ✅ 实现寄存器溢出处理
- ✅ 确保寄存器利用率 > 80%（当变量数 ≤ 可用寄存器数时）

---

**文档版本**: 1.0  
**最后更新**: 2026-01-18  
**作者**: Kiro AI Assistant
