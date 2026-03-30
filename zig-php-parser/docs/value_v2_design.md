// Value V2: 支持64位整数的混合策略实现
// 使用3位tag + 61位payload，大整数heap分配

const std = @import("std");

pub const Value = packed struct(u64) {
    bits: u64,

    // Tag定义（低3位）
    const TAG_MASK: u64 = 0x7;
    const TAG_SMALL_INT: u64 = 0;  // 61位有符号整数
    const TAG_PTR: u64 = 1;        // 指针（String/Array/Object）
    const TAG_BOOL_FALSE: u64 = 2;
    const TAG_BOOL_TRUE: u64 = 3;
    const TAG_NULL: u64 = 4;
    const TAG_BIG_INT: u64 = 5;    // 指向heap的i64
    const TAG_FLOAT: u64 = 6;      // 指向heap的f64
    const TAG_MISSING: u64 = 7;

    // 61位整数范围
    pub const SMALL_INT_MAX: i64 = (1 << 60) - 1;  // 1152921504606846975
    pub const SMALL_INT_MIN: i64 = -(1 << 60);     // -1152921504606846976

    // 指针类型（高8位）
    const PTR_TYPE_SHIFT: u6 = 56;
    const PTR_TYPE_MASK: u64 = 0xFF << PTR_TYPE_SHIFT;
    pub const PTR_TYPE_STRING: u64 = 1 << PTR_TYPE_SHIFT;
    pub const PTR_TYPE_ARRAY: u64 = 2 << PTR_TYPE_SHIFT;
    pub const PTR_TYPE_OBJECT: u64 = 3 << PTR_TYPE_SHIFT;
    pub const PTR_TYPE_FUNCTION: u64 = 4 << PTR_TYPE_SHIFT;
    pub const PTR_TYPE_REF: u64 = 5 << PTR_TYPE_SHIFT;

    // ========================================================================
    // 构造函数
    // ========================================================================

    pub fn initNull() Value {
        return .{ .bits = TAG_NULL };
    }

    pub fn initMissing() Value {
        return .{ .bits = TAG_MISSING };
    }

    pub fn initBool(b: bool) Value {
        return .{ .bits = if (b) TAG_BOOL_TRUE else TAG_BOOL_FALSE };
    }

    pub fn initInt(i: i64) Value {
        if (i >= SMALL_INT_MIN and i <= SMALL_INT_MAX) {
            // 小整数：直接存储（左移3位，低3位为tag）
            const shifted: u64 = @as(u64, @bitCast(i << 3));
            return .{ .bits = shifted | TAG_SMALL_INT };
        }
        
        // 大整数：heap分配
        const ptr = std.heap.page_allocator.create(i64) catch unreachable;
        ptr.* = i;
        const ptr_bits: u64 = @intFromPtr(ptr);
        return .{ .bits = (ptr_bits & ~TAG_MASK) | TAG_BIG_INT };
    }

    pub fn initFloat(f: f64) Value {
        // Float总是heap分配
        const ptr = std.heap.page_allocator.create(f64) catch unreachable;
        ptr.* = f;
        const ptr_bits: u64 = @intFromPtr(ptr);
        return .{ .bits = (ptr_bits & ~TAG_MASK) | TAG_FLOAT };
    }

    pub fn initString(s: anytype) Value {
        const ptr_bits: u64 = @intFromPtr(s);
        return .{ .bits = (ptr_bits & ~TAG_MASK) | TAG_PTR | PTR_TYPE_STRING };
    }

    pub fn initArray(a: anytype) Value {
        const ptr_bits: u64 = @intFromPtr(a);
        return .{ .bits = (ptr_bits & ~TAG_MASK) | TAG_PTR | PTR_TYPE_ARRAY };
    }

    pub fn initObject(o: anytype) Value {
        const ptr_bits: u64 = @intFromPtr(o);
        return .{ .bits = (ptr_bits & ~TAG_MASK) | TAG_PTR | PTR_TYPE_OBJECT };
    }

    // ========================================================================
    // 类型检查
    // ========================================================================

    pub fn isNull(self: Value) bool {
        return (self.bits & TAG_MASK) == TAG_NULL;
    }

    pub fn isBool(self: Value) bool {
        const tag = self.bits & TAG_MASK;
        return tag == TAG_BOOL_FALSE or tag == TAG_BOOL_TRUE;
    }

    pub fn isInt(self: Value) bool {
        const tag = self.bits & TAG_MASK;
        return tag == TAG_SMALL_INT or tag == TAG_BIG_INT;
    }

    pub fn isFloat(self: Value) bool {
        return (self.bits & TAG_MASK) == TAG_FLOAT;
    }

    pub fn isString(self: Value) bool {
        return (self.bits & TAG_MASK) == TAG_PTR and 
               (self.bits & PTR_TYPE_MASK) == PTR_TYPE_STRING;
    }

    pub fn isArray(self: Value) bool {
        return (self.bits & TAG_MASK) == TAG_PTR and 
               (self.bits & PTR_TYPE_MASK) == PTR_TYPE_ARRAY;
    }

    pub fn isObject(self: Value) bool {
        return (self.bits & TAG_MASK) == TAG_PTR and 
               (self.bits & PTR_TYPE_MASK) == PTR_TYPE_OBJECT;
    }

    // ========================================================================
    // 值提取
    // ========================================================================

    pub fn asBool(self: Value) bool {
        return (self.bits & TAG_MASK) == TAG_BOOL_TRUE;
    }

    pub fn asInt(self: Value) i64 {
        const tag = self.bits & TAG_MASK;
        if (tag == TAG_SMALL_INT) {
            // 右移3位恢复原值
            const shifted: i64 = @bitCast(self.bits);
            return shifted >> 3;
        }
        if (tag == TAG_BIG_INT) {
            const ptr: *i64 = @ptrFromInt(self.bits & ~TAG_MASK);
            return ptr.*;
        }
        unreachable;
    }

    pub fn asFloat(self: Value) f64 {
        const ptr: *f64 = @ptrFromInt(self.bits & ~TAG_MASK);
        return ptr.*;
    }

    pub fn asString(self: Value) *anyopaque {
        return @ptrFromInt(self.bits & ~(TAG_MASK | PTR_TYPE_MASK));
    }

    pub fn asArray(self: Value) *anyopaque {
        return @ptrFromInt(self.bits & ~(TAG_MASK | PTR_TYPE_MASK));
    }

    pub fn asObject(self: Value) *anyopaque {
        return @ptrFromInt(self.bits & ~(TAG_MASK | PTR_TYPE_MASK));
    }

    // ========================================================================
    // 类型转换
    // ========================================================================

    pub fn toInt(self: Value) i64 {
        if (self.isInt()) return self.asInt();
        if (self.isFloat()) {
            const f = self.asFloat();
            if (std.math.isNan(f)) return 0;
            if (f >= @as(f64, @floatFromInt(std.math.maxInt(i64)))) 
                return std.math.maxInt(i64);
            if (f <= @as(f64, @floatFromInt(std.math.minInt(i64)))) 
                return std.math.minInt(i64);
            return @intFromFloat(f);
        }
        if (self.isBool()) return if (self.asBool()) 1 else 0;
        if (self.isNull()) return 0;
        return 0; // String等其他类型
    }

    pub fn toFloat(self: Value) f64 {
        if (self.isFloat()) return self.asFloat();
        if (self.isInt()) return @floatFromInt(self.asInt());
        if (self.isBool()) return if (self.asBool()) 1.0 else 0.0;
        if (self.isNull()) return 0.0;
        return 0.0;
    }

    pub fn toBool(self: Value) bool {
        if (self.isBool()) return self.asBool();
        if (self.isNull()) return false;
        if (self.isInt()) return self.asInt() != 0;
        if (self.isFloat()) {
            const f = self.asFloat();
            return f != 0.0 and !std.math.isNan(f);
        }
        return true; // String/Array/Object默认为true
    }
};
```

---

## 性能对比

### 小整数操作（95%场景）
| 操作 | NaN Boxing | Tagged Union | 差异 |
|------|-----------|--------------|------|
| initInt | 位运算 | 位运算 | 无 |
| asInt | 位运算 | 位运算+右移 | +1指令 |
| isInt | 位运算 | 位运算 | 无 |

### 大整数操作（4%场景）
| 操作 | NaN Boxing | Tagged Union | 差异 |
|------|-----------|--------------|------|
| initInt | float转换 | heap分配 | 更慢但正确 |
| asInt | float转换 | 指针解引用 | 相似 |

### Float操作（1%场景）
| 操作 | NaN Boxing | Tagged Union | 差异 |
|------|-----------|--------------|------|
| initFloat | 直接存储 | heap分配 | 更慢 |
| asFloat | 直接读取 | 指针解引用 | 更慢 |

---

## 内存影响

### 当前（NaN Boxing）
- Value: 8字节
- 小整数: 0额外内存
- Float: 0额外内存
- 大整数: 转float（精度丢失）

### 新架构（Tagged Union）
- Value: 8字节
- 小整数: 0额外内存
- Float: 8字节heap
- 大整数: 8字节heap

**估算**: Float和大整数占比<5%，内存增加<5%

---

## 迁移风险

### 高风险区域
1. Value的所有操作（init/is/as/to）
2. 算术运算（add/sub/mul/div）
3. 比较运算（eq/lt/gt）
4. 类型转换

### 低风险区域
1. String/Array/Object操作（指针不变）
2. 控制流（不依赖Value内部）
3. 函数调用（Value作为黑盒）

### 测试策略
1. 单元测试每个Value操作
2. 回归测试14个PASS脚本
3. 性能基准测试
4. 内存泄漏检测

---

## 时间估算

- Phase 1（实现）: 4小时
- Phase 2（迁移）: 8小时
- Phase 3（测试）: 4小时
- Phase 4（清理）: 2小时

**总计**: 18小时

---

## 决策建议

**立即执行**: 否  
**原因**: 
- 当前14个脚本稳定
- 大整数场景罕见
- 重构风险高

**建议时机**:
- PASS数量达到50+
- 遇到更多大整数问题
- 性能优化阶段

**当前优先级**: 继续实现高频builtin函数，提升PASS数量
