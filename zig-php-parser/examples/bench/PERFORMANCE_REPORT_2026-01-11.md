# 内置函数性能测试完整报告

**测试日期**: 2026-01-11

## 目录

1. [测试概述](#测试概述)
2. [PHP 原生性能测试结果](#php-原生性能测试结果)
3. [Zig-PHP 性能测试结果](#zig-php-性能测试结果)
4. [性能对比分析](#性能对比分析)
5. [内存泄漏检测](#内存泄漏检测)
6. [修复建议](#修复建议)

---

## 测试概述

### 测试环境

| 项目 | 值 |
|------|-----|
| PHP 版本 | 8.5.0 |
| 操作系统 | Darwin (macOS) |
| 迭代次数 | 100,000 次/函数 |
| 测试函数 | 7 个 |

### 测试函数列表

| 函数 | 说明 |
|------|------|
| `func_num_args()` | 返回传递给函数的参数数量 |
| `func_get_arg($index)` | 返回函数参数列表中的指定参数 |
| `func_get_args()` | 返回包含函数参数列表的数组 |
| `strtr($str, $from, $to)` | 翻译字符串中的字符 |
| `http_build_query($query_data)` | 生成 URL 编码的查询字符串 |
| `get_loaded_extensions()` | 返回所有已加载扩展的列表 |
| `extension_loaded($extension)` | 检查指定扩展是否已加载 |

---

## PHP 原生性能测试结果

### 汇总

| 函数 | 执行时间(s) | OPS/s | 内存峰值 |
|------|-------------|-------|----------|
| func_num_args | 0.0081 | 12,328,936 | 2.00 MB |
| func_get_arg | 0.0099 | 10,085,613 | 2.00 MB |
| func_get_args | 0.0063 | 15,885,710 | 2.00 MB |
| strtr | 0.0062 | 16,116,442 | 2.00 MB |
| http_build_query | 0.0444 | 2,254,590 | 2.00 MB |
| get_loaded_extensions | 0.1603 | 623,834 | 2.00 MB |
| extension_loaded | 0.0332 | 15,050,286 | 2.00 MB |

### 性能排名 (PHP 原生)

1. **strtr**: 16,116,442 OPS/s (最快)
2. **func_get_args**: 15,885,710 OPS/s
3. **extension_loaded**: 15,050,286 OPS/s
4. **func_num_args**: 12,328,936 OPS/s
5. **func_get_arg**: 10,085,613 OPS/s
6. **http_build_query**: 2,254,590 OPS/s
7. **get_loaded_extensions**: 623,834 OPS/s (最慢)

---

## Zig-PHP 性能测试结果

### 汇总

| 函数 | 执行时间(s) | OPS/s | 内存泄漏 |
|------|-------------|-------|----------|
| func_* | 4.68 | 21,379 | 12 处 |
| strtr | 0.98 | 102,203 | 0 处 |
| http_build_query | 15.56 | 6,428 | 12 处 |
| get_loaded_extensions | 10.14 | 9,858 | 1,800,012 处 |
| extension_loaded | 4.39 | 22,786 | 12 处 |

### ⚠️ 重要警告

**get_loaded_extensions 函数存在严重内存泄漏问题！**

检测到 **1,800,012** 处内存泄漏地址，这表明每次调用 `get_loaded_extensions()` 都会产生大量未释放的内存分配。

---

## 性能对比分析

### OPS/s 对比

| 函数 | PHP 原生 | Zig-PHP | 性能比 (Zig/PHP) |
|------|----------|---------|------------------|
| strtr | 16,116,442 | 102,203 | 0.006x |
| http_build_query | 2,254,590 | 6,428 | 0.003x |
| get_loaded_extensions | 623,834 | 9,858 | 0.016x |
| extension_loaded | 15,050,286 | 22,786 | 0.002x |

### 执行时间对比

| 函数 | PHP 原生(s) | Zig-PHP(s) | 差异 |
|------|-------------|------------|------|
| strtr | 0.0062 | 0.9784 | +0.97s (156x 慢) |
| http_build_query | 0.0444 | 15.5572 | +15.51s (350x 慢) |
| get_loaded_extensions | 0.1603 | 10.1437 | +9.98s (63x 慢) |
| extension_loaded | 0.0332 | 4.3886 | +4.36s (132x 慢) |

### 分析结论

1. **性能差距显著**: Zig-PHP 解释器目前比原生 PHP 慢 **63-350 倍**
2. **性能瓶颈**: 
   - `http_build_query` 最慢 (350x)
   - `strtr` 相对较好 (156x)
3. **主要原因**:
   - 树遍历解释器的解释开销
   - 函数调用开销较高
   - 内存分配模式差异

---

## 内存泄漏检测

### 检测结果汇总

| 函数 | 泄漏严重程度 | 泄漏地址数 | 状态 |
|------|-------------|------------|------|
| get_loaded_extensions | 🔴 严重 | 1,800,012 | 需立即修复 |
| func_* | 🟡 中等 | 12 | 需修复 |
| http_build_query | 🟡 中等 | 12 | 需修复 |
| extension_loaded | 🟡 中等 | 12 | 需修复 |
| strtr | 🟢 正常 | 0 | 无泄漏 |

### 内存泄漏详情

#### 1. get_loaded_extensions (严重)

每次调用产生约 **18 个泄漏地址**（100,000 次 × 18 ≈ 1,800,000）

**问题位置**: `src/runtime/builtin_vars.zig` 中的 `getLoadedExtensionsFn`

**可能原因**:
- `Value.initArrayWithManager()` 创建的数组未正确释放
- 循环中分配的字符串未释放
- 扩展名称字符串的内存未管理

#### 2. func_* (中等)

每个函数 12 个泄漏地址

**问题位置**: `src/runtime/builtin_vars.zig` 中的 `funcNumArgsFn`, `funcGetArgFn`, `funcGetArgsFn`

**可能原因**:
- `vm.current_call_args` 相关的内存分配
- 数组返回值未正确释放

#### 3. http_build_query (中等)

12 个泄漏地址

**问题位置**: `src/runtime/builtin_vars.zig` 中的 `httpBuildQueryFn`

**可能原因**:
- URL 编码结果数组的内存未释放
- `ArrayList` 相关的内存泄漏

---

## 修复建议

### 优先级 1: 严重泄漏 (get_loaded_extensions)

```zig
// 修改 getLoadedExtensionsFn
pub fn getLoadedExtensionsFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    
    // 创建数组
    const arr = try PHPArray.init(vm.allocator);
    defer {
        // 释放数组中的所有元素
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(vm.allocator);
            if (entry.key_ptr.* == .string) {
                entry.key_ptr.string.release(vm.allocator);
            }
        }
        arr.deinit(vm.allocator);
    }
    
    // ... 添加扩展名称逻辑 ...
    
    return Value.initArrayWithObject(vm.allocator, &arr);
}
```

### 优先级 2: 中等泄漏

#### func_* 函数

```zig
// 确保 funcGetArgsFn 正确释放返回的数组
pub fn funcGetArgsFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    const call_args = vm.current_call_args orelse {
        const empty_arr = try PHPArray.init(vm.allocator);
        return Value.initArrayWithObject(vm.allocator, empty_arr);
    };
    
    const result = try vm.allocator.create(PHPArray);
    result.* = PHPArray.init(vm.allocator);
    
    for (call_args) |arg| {
        _ = arg.retain(); // 增加引用计数
        try result.set(vm.allocator, ArrayKey{ .integer = @intCast(result.elements.count()) }, arg);
    }
    
    return Value.initArrayWithObject(vm.allocator, result);
}
```

### 优先级 3: http_build_query

```zig
// 确保正确释放临时字符串
const encoded_key = try urlEncode(vm.allocator, key, enc_val);
defer vm.allocator.free(encoded_key);

const encoded_val = try urlEncode(vm.allocator, val_str, enc_val);
defer vm.allocator.free(encoded_val);
```

---

## 后续优化建议

1. **内存管理**
   - 审查所有 Value 的生命周期
   - 确保 `retain()` 和 `release()` 配对使用
   - 添加自动化内存测试

2. **性能优化**
   - 实现字节码模式以提高性能
   - 添加 JIT 编译支持
   - 优化热点函数的调用开销

3. **测试覆盖**
   - 添加内存泄漏检测到 CI
   - 实现持续性能监控
   - 定期对比测试

---

**报告生成时间**: 2026-01-11
**测试脚本位置**: `examples/bench/`
