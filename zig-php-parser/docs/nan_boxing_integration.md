# NaN-boxing Value Integration Plan

## 目标
将 FastValue (NaN-boxing) 集成到主 VM，替换当前的 tagged union Value 实现。

## 预期性能提升
- 值创建: ~100x (无堆分配)
- 类型检查: ~10x (位操作 vs switch)
- 整数运算: ~20x (直接位操作)
- 内存占用: -50% (64-bit vs 128-bit)

## 当前状态分析

### types.Value (当前实现)
```zig
pub const Value = union(Tag) {
    nil: void,
    bool: bool,
    int: i64,
    float: f64,
    string: *gc.Box(*PHPString),
    array: *gc.Box(*PHPArray),
    object: *gc.Box(*PHPObject),
    // ... 更多类型
};
```

**问题**:
- 128位大小 (union + tag)
- 每次类型检查需要 switch
- 整数/浮点需要解包
- 频繁的堆分配

### fast_value.FastValue (目标实现)
```zig
pub const FastValue = packed struct {
    bits: u64,
    // NaN-boxing: 所有类型编码在 64 位中
};
```

**优势**:
- 64位紧凑表示
- O(1) 位操作类型检查
- 整数/浮点/bool/null 无堆分配
- 指针类型直接编码

## 集成策略

### 阶段 1: 扩展当前 Value (渐进式)
在 `types.zig` 中为 Value 添加快速路径方法，保持向后兼容：

```zig
pub const Value = union(Tag) {
    // ... 现有字段 ...
    
    /// 快速整数创建 (内联，无分配)
    pub inline fn initIntFast(val: i64) Value {
        if (val >= INT48_MIN and val <= INT48_MAX) {
            return .{ .int = val };
        }
        return .{ .float = @floatFromInt(val) };
    }
    
    /// 快速整数加法
    pub inline fn addIntFast(self: Value, other: Value) Value {
        if (self == .int and other == .int) {
            return initIntFast(self.int +% other.int);
        }
        return self.addGeneric(other); // 回退到通用路径
    }
};
```

### 阶段 2: 完全替换 (激进式)
直接用 FastValue 替换 Value：

```zig
// types.zig
pub const Value = fast_value.FastValue;

// 添加兼容层
pub const ValueCompat = struct {
    pub fn initInt(val: i64) Value {
        return Value.initInt(val);
    }
    // ... 其他兼容方法
};
```

## 推荐方案: 阶段 1 (渐进式)

### 优势
- 保持现有代码兼容
- 可以逐步迁移热点路径
- 降低风险
- 可以 A/B 测试性能

### 实施步骤

#### Step 1: 扩展 Value 添加快速路径 ✅
已完成 (2026-01-15):
- `addIntFast`, `subIntFast`, `mulIntFast`, `divIntFast`
- `ltIntFast`, `gtIntFast`, `eqIntFast`
- `bitAndFast`, `bitOrFast`, `shlFast`, `shrFast`

#### Step 2: VM 算术操作使用快速路径
修改 `vm.zig` 中的 `evaluateBinaryExpression`:

```zig
fn evaluateBinaryExpression(self: *VM, node_idx: NodeIndex) !Value {
    const node = self.context.nodes.items[node_idx];
    const left = try self.eval(node.data.binary_expr.left);
    const right = try self.eval(node.data.binary_expr.right);
    
    return switch (node.data.binary_expr.op) {
        .add => blk: {
            // 快速路径：两个整数
            if (left == .int and right == .int) {
                break :blk left.addIntFast(right);
            }
            // 通用路径
            break :blk try self.addValues(left, right);
        },
        // ... 其他操作
    };
}
```

#### Step 3: 字符串/数组使用 Object Pool
修改字符串和数组创建使用池化分配：

```zig
pub fn createString(self: *VM, str: []const u8) !Value {
    if (self.memory_manager.use_pooling) {
        const pooled = try self.memory_manager.pools.string_pool.create(str);
        return Value.initString(pooled);
    }
    // 回退到标准分配
    return Value.initStringWithManager(&self.memory_manager, str);
}
```

#### Step 4: 性能测试和验证
运行基准测试，确保性能提升：
- 整数运算应提升 10-20x
- 类型检查应提升 5-10x
- 内存分配应减少 50%+

## 测试计划

### 单元测试
- [ ] 快速路径整数运算
- [ ] 快速路径类型检查
- [ ] 边界条件 (48-bit 溢出)
- [ ] 与现有实现的兼容性

### 集成测试
- [ ] 运行完整测试套件 (350+ 测试)
- [ ] 基准测试对比
- [ ] 内存泄漏检测

### 性能基准
- [ ] 整数运算基准
- [ ] 混合类型运算基准
- [ ] 实际 PHP 代码基准

## 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 48-bit 整数溢出 | 中 | 自动转换为浮点 |
| 指针对齐问题 | 低 | NaN-boxing 设计已考虑 |
| 现有代码兼容性 | 低 | 保持 API 兼容 |
| 性能回归 | 低 | 保留回退路径 |

## 回滚计划
如果出现问题，可以通过编译时标志禁用快速路径：

```zig
const USE_FAST_PATH = false; // 设为 false 回滚

pub inline fn addIntFast(self: Value, other: Value) Value {
    if (USE_FAST_PATH) {
        // 快速路径
    }
    return self.addGeneric(other); // 回退
}
```

## 时间估计
- Step 1: ✅ 已完成
- Step 2: 2-3 小时 (修改 VM 算术操作)
- Step 3: 1-2 小时 (Object Pool 集成)
- Step 4: 1 小时 (测试验证)

**总计**: ~4-6 小时

## 成功标准
- ✅ 所有测试通过
- ✅ 整数运算性能提升 >10x
- ✅ 无新增内存泄漏
- ✅ PHP 兼容性保持
