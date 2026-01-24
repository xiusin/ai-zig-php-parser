# "Switch on Corrupt Value" 错误修复报告

**日期**: 2026-01-22  
**任务**: 修复AOT编译器中的运行时崩溃  
**状态**: 部分完成（80%）

## 问题概述

在运行AOT编译器时，出现"switch on corrupt value"运行时错误，导致程序崩溃。

## 已完成的修复

### 1. ArrayList遍历方式修复 ✅

**问题**: 使用`for (values_to_release.items, 0..) |reg_id, idx|`遍历ArrayList时崩溃

**原因**: Zig 0.15的for循环语法可能在某些情况下导致内存访问问题

**修复**:
```zig
// 修复前
for (values_to_release.items, 0..) |reg_id, idx| {
    // ...
}

// 修复后
const release_count = values_to_release.items.len;
var i: usize = 0;
while (i < release_count) : (i += 1) {
    const reg_id = values_to_release.items[i];
    // ...
}
```

**位置**: `src/aot/native_linker.zig:472-485`

### 2. Store指令类型转换修复 ✅

**问题**: 尝试将i64直接赋值给runtime.Value指针

**错误信息**:
```
error: expected type 'runtime_lib.Value', found 'i64'
    reg_1.* = reg_0;
```

**修复**: 添加类型转换逻辑
```zig
// 获取指针指向的类型
const ptr_inner_type = switch (op.ptr.type_) {
    .ptr => |inner| inner.*,
    else => .php_value,
};

// 类型转换
const ptr_tag = @as(std.meta.Tag(IR.Type), ptr_inner_type);
const value_tag = @as(std.meta.Tag(IR.Type), op.value.type_);

if (ptr_tag == value_tag) {
    // 类型匹配，直接赋值
    try writer.print("        {s}.* = {s};\n", .{ ptr, value });
} else if (ptr_tag == .php_value) {
    // 存储到php_value指针，需要从基本类型转换
    switch (value_tag) {
        .i64 => try writer.print("        {s}.* = runtime.Value.initInt({s});\n", .{ ptr, value }),
        .f64 => try writer.print("        {s}.* = runtime.Value.initFloat({s});\n", .{ ptr, value }),
        .bool => try writer.print("        {s}.* = runtime.Value.initBool({s});\n", .{ ptr, value }),
        else => try writer.print("        {s}.* = {s};\n", .{ ptr, value }),
    }
}
```

**位置**: `src/aot/native_linker.zig:1430-1480`

### 3. Terminator类型比较修复 ✅

**问题**: 直接使用`term == .ret`比较union类型

**修复**:
```zig
// 修复前
const is_simple_return = if (block.terminator) |term| term == .ret else false;

// 修复后
const is_simple_return = if (block.terminator) |term| 
    @as(std.meta.Tag(IR.Terminator), term) == .ret 
else false;
```

**位置**: `src/aot/native_linker.zig:514-516`

### 4. 使用filtered_cleanup而不是values_to_release ✅

**问题**: 传递错误的cleanup列表给generateControlFlow

**修复**:
```zig
// 修复前
try self.generateControlFlow(writer, func, values_to_release.items, &reg_lifetime);

// 修复后
try self.generateControlFlow(writer, func, filtered_cleanup.items, &reg_lifetime);
```

**位置**: `src/aot/native_linker.zig:492`

## 当前阻塞问题

### Writer API问题 ❌

**症状**: 在`generateFunction`中使用writer时崩溃

**错误堆栈**:
```
thread 3183144 panic: switch on corrupt value
/opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/mem/Allocator.zig:428:9
/opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/Io/DeprecatedWriter.zig:19:38
```

**分析**:
1. 错误发生在`DeprecatedWriter.zig`，说明使用了已废弃的API
2. 问题可能与Zig 0.15的ArrayList.writer API变更有关
3. writer在传递给函数时可能存在生命周期问题

**尝试的修复方案**:
1. ✅ 使用`std.fmt.allocPrint`代替`writer.writeAll` - 部分有效
2. ⚠️ 修改generateFunction接受`*std.ArrayList(u8)`而不是writer - 进行中
3. ❌ 重新创建writer - 未尝试

**下一步行动**:
1. 完成将generateFunction改为接受ArrayList指针的修改
2. 或者：使用std.fmt.allocPrint生成所有代码，然后一次性appendSlice
3. 或者：检查IR模块是否有数据损坏问题

## 技术发现

### Zig 0.15 ArrayList API变更

1. **初始化**:
   ```zig
   var list = std.ArrayList(T){};  // 不再使用.init(allocator)
   ```

2. **方法调用**:
   ```zig
   try list.append(allocator, item);  // 所有方法都需要allocator
   try list.deinit(allocator);
   ```

3. **Writer**:
   ```zig
   const writer = list.writer(allocator);  // 返回GenericWriter
   ```

### Union类型比较

在Zig中，union类型不能直接使用`==`比较，需要使用`@as(std.meta.Tag(T), value)`获取tag后再比较。

### 内存安全

1. 使用`while`循环代替`for`循环遍历ArrayList可能更安全
2. 在传递writer时要注意生命周期
3. 使用`std.fmt.allocPrint`可以避免writer的生命周期问题

## 测试结果

### 编译状态
- ✅ `zig build` 成功
- ✅ 所有语法错误已修复
- ✅ 类型检查通过

### 运行时状态
- ❌ 运行时崩溃在generateFunction中
- ✅ 调试信息正常输出
- ✅ IR生成正常

## 相关文档

- `当前问题总结与下一步行动.md` - 详细的问题分析
- `ARRAYLIST_API_FINAL_FIX_REPORT.md` - ArrayList API修复历史
- `AOT_BUG_FIX_FINAL_REPORT.md` - 总体修复报告
- `IR_GENERATOR_TYPE_INFERENCE_FIX.md` - IR生成器修复

## 建议

### 短期（立即执行）
1. 完成generateFunction的ArrayList指针修改
2. 测试修复后的代码
3. 如果仍然失败，考虑使用std.fmt.allocPrint生成所有代码

### 中期（本周内）
1. 添加更多单元测试
2. 使用AddressSanitizer检测内存问题
3. 简化控制流生成逻辑

### 长期（下个月）
1. 重构native_linker.zig
2. 改进错误处理
3. 添加性能测试

---

**最后更新**: 2026-01-22  
**完成度**: 80%  
**阻塞问题**: Writer API生命周期问题  
**预计完成时间**: 今天内
