# 内存泄漏问题排查清单 (2026-01-09)

## 执行摘要

在 Debug/ReleaseSafe 模式下运行 minimal_test.php 时存在 12 处固定内存泄漏，与执行的 PHP 代码无关，推测在 VM 初始化时产生。

---

## 1. 已确认清理完成的组件（应该不是泄漏源）

| 组件 | 文件位置 | 状态 |
|------|----------|------|
| PHPContext | `src/compiler/root.zig:36` | ✅ 已清理 |
| Parser | `src/compiler/parser.zig` | ✅ 已清理 |
| 文件句柄 | `src/runtime/builtin_io.zig:132` | ✅ 已清理 |
| coroutine_manager | `src/runtime/vm.zig:1389-1394` | ✅ 已清理 |
| generator_state | `src/runtime/vm.zig:1396-1401` | ✅ 已清理 |
| ExtensionRegistry | `src/runtime/vm.zig:1295-1299` | ✅ 已清理 |
| BytecodeVM | `src/runtime/vm.zig:1302-1305` | ✅ 已清理 |
| CallFrame locals | `src/runtime/vm.zig:1307-1313` | ✅ 已清理 |
| Environment | `src/runtime/vm.zig:1315` | ✅ 已清理 |
| ErrorContext | `src/runtime/vm.zig:1360` | ✅ 已清理 |
| TryCatchStack | `src/runtime/vm.zig:1360` | ✅ 已清理 |
| StringInternPool | `src/runtime/vm.zig:1376-1385` | ✅ 已清理 |
| MemoryManager | `src/runtime/vm.zig:1402` | ✅ 已清理 |

---

## 2. 待排查的泄漏源（按优先级排序）

### P0 - 高优先级

#### 2.1 ReflectionSystem - 缺少 deinit 函数 ⚠️

**文件**: `src/runtime/reflection.zig:1170`

**问题**: `ReflectionSystem` 结构体没有 `deinit()` 方法，但 VM 初始化时调用了 `init()`

```zig
// src/runtime/vm.zig:1211-1213
.reflection_system = undefined, // Will be initialized after VM creation
// ...
vm.reflection_system = ReflectionSystem.init(allocator, vm);
```

**当前状态**: `ReflectionSystem` 只包含 `allocator` 和 `vm` 指针，可能不需要额外清理，但需验证。

**修复建议**: 添加空的 `deinit()` 方法或确认不需要清理。

---

#### 2.2 ErrorHandler.handlers EnumMap - 未清理 ⚠️

**文件**: `src/runtime/exceptions.zig:268-288`

**问题**: `ErrorHandler.deinit()` 没有清理 `handlers` EnumMap

```zig
pub const ErrorHandler = struct {
    allocator: std.mem.Allocator,
    handlers: std.EnumMap(ErrorType, ?ErrorCallback),
    // ...

    pub fn deinit(self: *ErrorHandler) void {
        if (self.error_log) |log_file| {
            log_file.close();
        }
        // ⚠️ 缺少: self.handlers.deinit() ?
    }
};
```

**当前状态**: EnumMap 是基于数组的，初始化时是空的 `.{}`，但不确定是否需要 deinit。

**修复建议**: 检查 `std.EnumMap` 是否需要显式 deinit，如果需要则添加。

---

#### 2.3 BuiltinClassManager - 遗漏完整清理 ⚠️

**文件**: `src/runtime/builtin_classes.zig:15-44`

**问题**: `BuiltinClassManager.init()` 返回的 manager 只清理了内部的 hashmap，manager 本身没有 destroy

```zig
// src/runtime/vm.zig:1231-1241
var builtin_class_manager = try builtin_classes.BuiltinClassManager.init(allocator);
var class_iter = builtin_class_manager.classes.iterator();
while (class_iter.next()) |entry| {
    try vm.classes.put(entry.key_ptr.*, entry.value_ptr.*);
}
// Only deinit the hashmap container, not the class objects
builtin_class_manager.classes.deinit();
// ⚠️ 缺少: allocator.destroy(builtin_class_manager)
```

**修复建议**:
```zig
var builtin_class_manager = try allocator.create(builtin_classes.BuiltinClassManager);
builtin_class_manager.* = try builtin_classes.BuiltinClassManager.init(allocator);
// ... transfer classes ...
builtin_class_manager.classes.deinit();
allocator.destroy(builtin_class_manager);
```

---

#### 2.4 TryCatchContext ArrayList - 可能泄漏 ⚠️

**文件**: `src/runtime/exceptions.zig:155`

**问题**: `TryCatchContext` 结构体中的 ArrayList 可能未完全清理

```zig
pub const TryCatchContext = struct {
    // ... 其他字段 ...
    // 需要检查是否有 ArrayList/StringHashMap 等需要清理
};
```

**当前状态**: 需要检查 TryCatchContext 的完整结构。

---

### P1 - 中优先级

#### 2.5 BuiltinRegistry.categories - 指针释放问题

**文件**: `src/runtime/builtin_registry.zig:179-210`

**问题**: `deinit()` 清理了 categories 的 ArrayList，但 ArrayList 里的 `*const BuiltinFunction` 指针可能需要特殊处理

```zig
pub fn deinit(self: *BuiltinRegistry) void {
    self.functions.deinit();
    
    var category_iter = self.categories.iterator();
    while (category_iter.next()) |entry| {
        entry.value.deinit(self.allocator);
        // ⚠️ ArrayList 里的 *const BuiltinFunction 指针是否需要 destroy？
        // 这些指针是常量函数描述符，通常不应该释放
    }
}
```

**分析**: `BuiltinFunction` 是常量描述符，通常是编译期已知或全局分配的，不需要运行时释放。

**状态**: 可能不是泄漏源。

---

#### 2.6 builtin_concurrency 全局状态

**文件**: `src/runtime/builtin_concurrency.zig`

**问题**: 检查是否有模块级 HashMap 或全局状态未清理

```bash
# 检查命令
grep -n "var.*AutoHashMap\|var.*StringHashMap" src/runtime/builtin_concurrency.zig
```

**状态**: 需要检查该文件是否有全局状态。

---

### P2 - 低优先级

#### 2.7 GC.MemoryManager - 清理不完整

**文件**: `src/runtime/gc.zig:687-705`

**问题**: 检查 `MemoryManager.deinit()` 和 `GarbageCollector.deinit()` 是否完全

```zig
pub fn deinit(self: *MemoryManager) void {
    self.gc.deinit();
}
```

**当前状态**: `GarbageCollector.deinit()` 清理了 `gray_list` 和 `write_barrier_buffer`，但可能有遗漏。

**验证**:
```bash
# 编译 AddressSanitizer 版本
zig build -Doptimize=Debug -Dsanitizer=address
```

---

#### 2.8 builtin_http.global_servers - 确认清理完整

**文件**: `src/runtime/builtin_http.zig:9-35`

**状态**: ✅ 已有 `cleanup()` 函数并在 `VM.deinit()` 中调用

**当前实现**:
```zig
pub fn cleanup() void {
    if (global_servers_initialized) {
        global_servers.deinit();
        global_servers_initialized = false;
    }
}
```

**状态**: 应该已正确清理。

---

#### 2.9 VM.stdlib.StandardLibrary - 已清理

**文件**: `src/runtime/stdlib.zig:62-65`

**状态**: ✅ 已有正确清理
```zig
pub fn deinit(self: *StandardLibrary) void {
    self.functions.deinit();
}
```

---

#### 2.10 VM.builtin_registry - 已清理

**文件**: `src/runtime/builtin_registry.zig:202-210`

**状态**: ✅ 已有正确清理

---

#### 2.11 VM.request_arena - 已清理

**文件**: `src/runtime/vm.zig:1374`

**状态**: ✅ 已有正确清理

---

#### 2.12 VM.included_files - 已清理

**文件**: `src/runtime/vm.zig:1369-1373`

**状态**: ✅ 已有正确清理

```zig
var included_iter = self.included_files.keyIterator();
while (included_iter.next()) |key| {
    self.allocator.free(key.*);
}
self.included_files.deinit();
```

---

## 3. 泄漏地址模式分析

通过分析 GPA 输出的泄漏地址模式：

| 类别 | 地址模式 | 数量 | 推测来源 |
|------|----------|------|----------|
| 小分配 | 0x109620006-008 | 3 | 某个对象的连续分配（可能是 HashMap 头） |
| HashMap buckets | 0x109400340-380 | 5 | StringHashMap/EnumMap |
| HashMap buckets | 0x109462580-640 | 4 | StringHashMap/EnumMap |

**分析**: 12 处泄漏中有 9 处是 HashMap 相关的，可能是：
1. HashMap 初始化时的内部分配未释放
2. 某个 StringHashMap/EnumMap 没有调用 deinit()

---

## 4. 建议排查步骤

### 步骤 1: 使用 AddressSanitizer 定位

```bash
cd /Users/xiusin/Desktop/zig-php/zig-php-parser

# 构建 AddressSanitizer 版本
zig build -Doptimize=Debug -Dsanitizer=address

# 运行测试
./zig-out/bin/php-interpreter examples/test_empty.php 2>&1
```

AddressSanitizer 会提供精确的泄漏位置和调用栈。

### 步骤 2: 逐一修复高优先级问题

1. 修复 `src/runtime/builtin_classes.zig` - BuiltinClassManager 清理
2. 修复 `src/runtime/reflection.zig` - 添加 deinit
3. 修复 `src/runtime/exceptions.zig` - ErrorHandler 清理

### 步骤 3: 验证修复效果

```bash
# Debug 模式
zig build -Doptimize=Debug
./zig-out/bin/php-interpreter examples/test_empty.php 2>&1 | grep -c "leaked"

# ReleaseSafe 模式
zig build -Doptimize=ReleaseSafe
./zig-out/bin/php-interpreter examples/test_empty.php 2>&1 | grep -c "leaked"
```

---

## 5. 修复优先级总结

| 优先级 | 问题 | 文件 | 预计工作量 |
|--------|------|------|------------|
| P0 | BuiltinClassManager 清理 | `src/runtime/builtin_classes.zig` | 15分钟 |
| P0 | ReflectionSystem deinit | `src/runtime/reflection.zig` | 10分钟 |
| P0 | ErrorHandler 清理 | `src/runtime/exceptions.zig` | 10分钟 |
| P1 | TryCatchContext 检查 | `src/runtime/exceptions.zig` | 20分钟 |
| P1 | builtin_concurrency 检查 | `src/runtime/builtin_concurrency.zig` | 10分钟 |
| P2 | GC 清理验证 | `src/runtime/gc.zig` | 15分钟 |

---

## 6. 相关测试文件

| 文件 | 用途 |
|------|------|
| `test_isolation_1.zig` | PHPContext + Parser 隔离测试（无泄漏） |
| `test_isolation_2.zig` | VM 隔离测试（LLVM 编译错误） |
| `test_simple_alloc.zig` | 基础分配测试（无泄漏） |
| `test_hashmap_leak.zig` | HashMap 清理验证（无泄漏） |
| `test_hashmap_leak2.zig` | 多 HashMap 清理验证（无泄漏） |
| `test_no_vm.zig` | 无 VM 测试（无泄漏） |

**关键发现**: 独立测试显示 StringHashMap 和基本组件无泄漏，但 VM 初始化时有 12 处泄漏，说明问题在 VM.init() 或其调用的初始化函数中。

---

**文档创建时间**: 2026-01-09
**最后更新**: 2026-01-09
**负责人**: iFlow CLI
