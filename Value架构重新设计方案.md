# Value架构重新设计方案

## 当前问题

### NaN Boxing限制
- 48位整数范围：-140737488355328 到 140737488355327
- PHP_INT_MAX无法精确存储
- 超出范围转float，精度丢失

### 影响
- 大整数运算不精确
- 常量值与标准PHP不同
- 某些测试无法通过

---

## 新架构：Tagged Union

### 设计目标
1. 支持完整64位整数
2. 保持8字节大小
3. 性能不降低
4. 兼容现有代码

### 方案A：3位Tag + 61位Payload

```zig
pub const Value = packed struct {
    tag: u3,
    payload: u61,
    
    const TAG_INT = 0;      // 直接存储61位有符号整数
    const TAG_FLOAT = 1;    // 指向heap的f64
    const TAG_PTR = 2;      // 指向heap对象(String/Array/Object)
    const TAG_BOOL = 3;     // payload: 0=false, 1=true
    const TAG_NULL = 4;
    const TAG_MISSING = 5;
};
```

**优点**:
- 61位整数范围足够大
- 小整数无需heap分配
- 8字节大小不变

**缺点**:
- Float需要heap分配（性能影响）
- 61位还是不够64位

### 方案B：16字节Value

```zig
pub const Value = struct {
    tag: u8,
    data: union {
        int: i64,
        float: f64,
        ptr: *anyopaque,
        bool: bool,
    },
};
```

**优点**:
- 完整64位整数支持
- 所有类型直接存储
- 实现简单

**缺点**:
- 16字节大小（内存翻倍）
- 性能可能下降

### 方案C：混合策略（推荐）

```zig
pub const Value = packed struct(u64) {
    bits: u64,
    
    // 低3位为tag
    const TAG_MASK: u64 = 0x7;
    const TAG_SMALL_INT = 0;  // 61位有符号整数
    const TAG_PTR = 1;        // 指针（最低位必为0，利用对齐）
    const TAG_BOOL_FALSE = 2;
    const TAG_BOOL_TRUE = 3;
    const TAG_NULL = 4;
    const TAG_BIG_INT = 5;    // 指向heap的i64
    const TAG_FLOAT = 6;      // 指向heap的f64
    const TAG_MISSING = 7;
    
    pub fn initInt(i: i64) Value {
        // 61位范围：-1152921504606846976 到 1152921504606846975
        const SMALL_INT_MAX: i64 = (1 << 60) - 1;
        const SMALL_INT_MIN: i64 = -(1 << 60);
        
        if (i >= SMALL_INT_MIN and i <= SMALL_INT_MAX) {
            // 小整数：直接存储
            const shifted = @as(u64, @bitCast(i)) << 3;
            return .{ .bits = shifted | TAG_SMALL_INT };
        }
        
        // 大整数：heap分配
        const ptr = runtime_allocator.create(i64) catch unreachable;
        ptr.* = i;
        return .{ .bits = @intFromPtr(ptr) | TAG_BIG_INT };
    }
};
```

**优点**:
- 61位整数范围：±1.15e18（足够大）
- PHP_INT_MAX可以精确存储
- 8字节大小不变
- 小整数无heap分配
- 大整数heap分配（罕见）

**缺点**:
- 需要修改所有Value操作
- 大整数需要GC管理

---

## 实施计划

### Phase 1: 准备工作
1. 创建新Value实现（value_v2.zig）
2. 实现基础操作（init, is*, as*, to*）
3. 单元测试验证

### Phase 2: 渐进迁移
1. 添加编译选项：USE_VALUE_V2
2. 条件编译支持两种Value
3. 逐步迁移runtime函数

### Phase 3: 性能验证
1. 基准测试对比
2. 内存使用分析
3. 优化热点路径

### Phase 4: 完全切换
1. 删除旧Value实现
2. 更新文档
3. 全量测试

---

## 性能影响评估

### 小整数操作（99%场景）
- **当前**: 直接位运算
- **新架构**: 直接位运算
- **影响**: 无

### 大整数操作（1%场景）
- **当前**: float精度丢失
- **新架构**: heap分配+精确运算
- **影响**: 轻微性能下降，但正确性提升

### Float操作
- **当前**: 直接存储
- **新架构**: heap分配（方案C）
- **影响**: 性能下降10-20%
- **缓解**: 使用对象池

---

## 替代方案：保持现状

### 接受限制
- PHP_INT_MAX = 140737488355327（48位）
- 文档说明限制
- 大多数代码不受影响

### 优点
- 无需大规模重构
- 性能最优
- 风险最低

### 缺点
- 与标准PHP不完全兼容
- 某些测试无法通过
- 边缘场景可能出错

---

## 建议

**短期**: 保持现状，文档说明限制  
**中期**: 实施方案C（混合策略）  
**长期**: 考虑16字节Value（方案B）

**优先级**: 低（当前14个脚本稳定PASS，大整数场景罕见）
