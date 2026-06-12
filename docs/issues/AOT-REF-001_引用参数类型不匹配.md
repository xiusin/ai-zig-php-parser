# 引用参数类型不匹配问题记录

**问题ID**: AOT-REF-001  
**优先级**: P1  
**状态**: 🔴 阻塞中  
**发现时间**: 2026-03-30 19:43  
**最后更新**: 2026-03-30 20:09

---

## 问题描述

**脚本**: `test_058_object_graph.php`  
**错误**: 
```
main.zig:823:24: error: expected type 'runtime_lib.Value', found '*runtime_lib.Value'
            reg_21.* = reg_8;
```

**根本原因**: 引用参数的alloca类型声明错误
- 期望: `reg_21: **runtime.Value` (指向指针的指针)
- 实际: `reg_21: *runtime.Value` (单层指针)
- 导致: `reg_21.* = reg_8` 时类型不匹配 (`Value` vs `*Value`)

---

## 已完成的修复尝试

### 1. IR生成层修复 ✅
**文件**: `src/aot/ir_generator.zig:885-910`

```zig
// 修改前
const alloca_type = param_type; // .php_value
const ptr_type = Type{ .ptr = &alloca_type }; // *Value

// 修改后
const ptr_base = try self.allocator.create(Type);
ptr_base.* = param_type;
const alloca_type = Type{ .ptr = ptr_base }; // *Value
const ptr_type = Type{ .ptr = &alloca_type }; // **Value
```

**结果**: IR层类型正确，但代码生成层未生效

### 2. 类型转换函数修复 ✅
**文件**: `src/aot/native_linker.zig:2283-2305`

```zig
fn irTypeToZigTypeString(self: *const Self, ir_type: IR.Type) []const u8 {
    return switch (ir_type) {
        .ptr => |inner| {
            const inner_type_str = self.irTypeToZigTypeString(inner.*);
            if (std.mem.eql(u8, inner_type_str, "runtime.Value")) {
                return "*runtime.Value";
            } else if (std.mem.eql(u8, inner_type_str, "*runtime.Value")) {
                return "**runtime.Value"; // 支持双层指针
            }
            // ...
        },
        // ...
    };
}
```

**结果**: 函数逻辑正确，但未被正确调用

### 3. 寄存器声明生成修复 ✅
**文件**: `src/aot/native_linker.zig:3545-3555`

```zig
if (ref_param_alloca_map.get(reg_id)) |_| {
    const type_str = self.irTypeToZigTypeString(reg_type);
    try code.appendSlice(self.allocator, "    var reg_");
    try code.writer(self.allocator).print("{d}", .{reg_id});
    try code.appendSlice(self.allocator, ": ");
    try code.appendSlice(self.allocator, type_str); // 使用动态类型
    // ...
}
```

**结果**: 代码逻辑正确，但生成的代码仍是 `*runtime.Value`

---

## 问题分析

### 生成的代码
```zig
// 第719行
var reg_21: *runtime.Value = undefined;  // ❌ 应该是 **runtime.Value

// 第823行
reg_21.* = reg_8;  // reg_8 是 *Value，reg_21.* 期望 Value，类型不匹配

// 第876行
reg_21.* = reg_18.*;  // reg_18 是 **Value，解引用后是 *Value
```

### 类型传递链路
```
IR生成 (ir_generator.zig)
  ↓ alloca创建 Type{.ptr = Type{.ptr = .php_value}}
  ↓ 存储到 IR.Function
  ↓
代码生成 (native_linker.zig)
  ↓ all_registers 收集类型
  ↓ ref_param_alloca_map 标记引用参数
  ↓ irTypeToZigTypeString 转换类型
  ↓ 生成寄存器声明
  ❌ 类型信息在某个环节丢失
```

---

## 待验证的假设

1. **假设1**: `all_registers` 中 `reg_21` 的类型已经是 `**Value`
   - 验证方法: 在3533行添加 `std.debug.print("reg_{d} type: {any}\n", .{reg_id, reg_type})`

2. **假设2**: `irTypeToZigTypeString` 被正确调用但返回值错误
   - 验证方法: 在2295行添加 `std.debug.print("Converting {any} -> {s}\n", .{ir_type, result})`

3. **假设3**: `ref_param_alloca_map` 中没有 `reg_21`
   - 验证方法: 在3547行添加 `std.debug.print("Checking reg_{d} in ref_param_alloca_map: {}\n", .{reg_id, ref_param_alloca_map.contains(reg_id)})`

4. **假设4**: 类型在 `all_registers` 收集阶段就错了
   - 验证方法: 检查 `native_linker.zig:3165` 附近的类型收集逻辑

---

## 可能的解决方案

### 方案A: 修复类型收集 (推荐)
在 `all_registers` 收集阶段确保引用参数alloca的类型正确

### 方案B: Store指令特殊处理
在生成store指令时检测引用参数，自动调整代码生成

```zig
// native_linker.zig:14828
if (ptr_inner_tag == value_tag) {
    // 检查是否是引用参数alloca
    if (ref_param_alloca_map.contains(op.ptr.id)) {
        // 特殊处理：不解引用
        try writer.print("        {s} = {s};\n", .{ ptr, value });
    } else {
        try writer.print("        {s}.* = {s};\n", .{ ptr, value });
    }
}
```

### 方案C: 回退到简单方案
引用参数不使用alloca，直接使用寄存器传递

---

## 影响范围

- **直接影响**: 1个脚本 (test_058_object_graph.php)
- **潜在影响**: 所有使用引用参数的函数调用
- **相关问题**: test_010_reference_pointer.php, test_048_foreach_ref.php (P7语义差异)

---

## 下一步行动

1. ⏸️ **暂停当前修复**，转向其他P1任务
2. 📋 **记录到KNOWN_ISSUES.md**
3. 🔍 **后续深入调试**时添加调试输出验证假设
4. 💡 **考虑方案B**作为快速修复方案

---

## 相关文件

- `src/aot/ir_generator.zig:885-910` - 引用参数alloca创建
- `src/aot/native_linker.zig:2283-2305` - 类型转换函数
- `src/aot/native_linker.zig:3545-3620` - 寄存器声明生成
- `src/aot/native_linker.zig:14730-14880` - Store指令代码生成
- `fuzzy_scripts/test_058_object_graph.php` - 测试脚本

---

**备注**: 这是一个深层的类型系统问题，需要完整追踪类型信息的传递链路。建议先完成其他高ROI任务后再回来处理。
