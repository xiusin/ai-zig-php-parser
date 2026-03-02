# PHP 引用实现总结

## 问题背景

原实现使用 `Reference` 结构体存储引用信息，但存在严重问题：
- 内存布局不匹配（8字节 vs 16字节）
- 指针生命周期管理复杂
- nanbox 编码限制

## 解决方案：哈希映射方案

### 核心思路
完全移除 `Reference` 结构体，直接在 `Value` 中存储引用的哈希值，通过 VM 中的映射表反查 key。

### 关键修改

#### 1. types.zig

**删除**：
```zig
pub const Reference = struct { ... }  // 完全删除
```

**新增**：
```zig
// 创建引用 Value（存储哈希值）
pub fn fromReference(key: []const u8) Value {
    const hash = std.hash.Wyhash.hash(0, key);
    return .{ .val = nanbox_abi.encodePtr(hash, TYPE_REFERENCE) };
}

// 获取引用的哈希值
pub fn asReferenceHash(self: Value) u64 {
    return nanbox_abi.decodePtr(self.val);
}
```

**修改**：
```zig
pub fn retain(self: Value) Value {
    // 引用类型不需要 retain，且必须先检查以避免错误的指针解引用
    if (self.isReference()) {
        return self;
    }
    // ... 其他类型的 retain
}

pub fn release(self: Value, allocator: std.mem.Allocator) void {
    // 引用类型不需要 release
    if (self.isReference()) {
        return;
    }
    // ... 其他类型的 release
}
```

#### 2. vm.zig

**新增字段**：
```zig
ref_hash_to_key: std.AutoHashMap(u64, []const u8),
```

**初始化**：
```zig
.ref_hash_to_key = std.AutoHashMap(u64, []const u8).init(allocator),
```

**创建引用**：
```zig
const ref_value = Value.fromReference(static_key);
const hash = ref_value.asReferenceHash();
try self.ref_hash_to_key.put(hash, static_key);
self.return_value = ref_value;
```

**解引用（getVariable）**：
```zig
if (v.isReference()) {
    const hash = v.asReferenceHash();
    if (self.ref_hash_to_key.get(hash)) |key| {
        return self.static_vars.get(key);
    }
}
```

**赋值（setVariable）**：
```zig
if (existing_ptr.isReference()) {
    const hash = existing_ptr.asReferenceHash();
    if (self.ref_hash_to_key.get(hash)) |key| {
        if (self.static_vars.getPtr(key)) |static_ptr| {
            static_ptr.* = value;
            return;
        }
    }
}
```

**输出（echo_stmt）**：
```zig
var value = try self.eval(expr_idx);
defer self.releaseValue(value);

// 如果是引用，解引用获取实际值
if (value.isReference()) {
    const hash = value.asReferenceHash();
    if (self.ref_hash_to_key.get(hash)) |key| {
        if (self.static_vars.get(key)) |actual_value| {
            value = actual_value;
        }
    }
}

try value.print();
```

**清理**：
```zig
self.ref_hash_to_key.deinit();
```

## 技术细节

### 哈希计算
使用 `std.hash.Wyhash` 计算 static_key 的哈希值：
```zig
const hash = std.hash.Wyhash.hash(0, key);
```

### nanbox 编码
引用 Value 的编码格式：
```
TAG_PTR | TYPE_REFERENCE | hash_value (47 bits)
```

### 生命周期
- static_key 字符串由 `static_vars` HashMap 拥有
- 哈希映射只存储指向这些字符串的指针
- 无需额外的内存管理

## 优势

1. **简单**：无复杂的指针管理
2. **高效**：Value 只存储 8 字节哈希值
3. **安全**：无内存布局问题
4. **可靠**：哈希冲突概率极低（Wyhash 64位）

## 测试结果

✅ test_50.php - 函数返回引用并修改
✅ test_49.php - 变量引用
✅ test_144.php - 字符串引用

## 后续优化建议

1. **性能优化**：考虑使用更快的哈希算法（如 xxHash）
2. **调试支持**：添加引用追踪日志
3. **错误处理**：处理哈希冲突（虽然极少发生）
4. **扩展支持**：支持对象属性引用、数组元素引用
