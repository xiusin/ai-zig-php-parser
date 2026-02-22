# Alloca 寄存器代码生成修复 - 技术债务

## 问题描述

`mem2reg` 优化后，某些 alloca 寄存器无法被提升（指针逃逸），保留为 `*runtime.Value` 类型。
所有使用这些寄存器的地方必须使用 `reg_X.*` 而不是 `reg_X`。

## 当前状态

### 已修复（10+ 处）
- ✅ `getOperandRef()` 辅助函数（line 2386）
- ✅ `writeRegRef()` 辅助函数（line 2398）
- ✅ phi 节点初始化（generateWhileLoopStructuredNew line 5813, generateForLoopStructuredNew line 6037）
- ✅ phi 节点赋值（br terminator line 2665）
- ✅ cast 指令（所有分支 line 5095-5130）
- ✅ move 指令（line 5164）
- ✅ store 指令（line 3275）
- ✅ load 指令（line 3369）
- ✅ nested_loop_codegen.zig（添加 alloca_regs 支持）

### 待修复（20+ 处）

所有使用 `writer.print("reg_{d} = reg_{d}", .{dst, src})` 的地方都需要修复。

#### 关键位置

| 行号 | 位置 | 指令类型 | 优先级 |
|------|------|----------|--------|
| 3909 | generateInstructionSimple | select (then) | P0 |
| 3912 | generateInstructionSimple | select (else) | P0 |
| 5979 | generateWhileLoopStructuredNew | phi update | P0 |
| 6758-6773 | generateForLoopStructuredNew | increment | P1 |
| 6833 | generateForLoopStructuredNew | limit | P1 |
| 6913 | generateForLoopStructuredNew | phi init | P0 |
| 7124 | generateForLoopWithChildrenV2 | phi increment | P1 |
| 7137-7147 | generateForLoopWithChildrenV2 | phi update | P0 |
| 7222-7224 | generateForLoopWithChildrenV2 | phi update | P0 |

#### 完整列表

```bash
grep -n 'writer.print.*reg_{d} = reg_{d}' src/aot/native_linker.zig
```

输出：
```
3909:                        try writer.print("        reg_{d} = reg_{d};\n", .{ reg.id, op.then_value.id });
3912:                        try writer.print("        reg_{d} = reg_{d};\n", .{ reg.id, op.else_value.id });
5979:            try writer.print("        reg_{d} = reg_{d};\n", .{ update.phi_reg, update.value_reg });
6758:                                try writer.print("    reg_{d} = reg_{d};\n", .{ inc_reg, ms.loop_count_reg });
6760:                                try writer.print("    reg_{d} = reg_{d}.asInt();\n", .{ inc_reg, ms.loop_count_reg });
6762:                                try writer.print("    reg_{d} = reg_{d};\n", .{ inc_reg, ms.loop_count_reg });
6769:                                try writer.print("    reg_{d} = reg_{d};\n", .{ inc_reg, ms.loop_count_reg });
6773:                            try writer.print("    reg_{d} = reg_{d};\n", .{ inc_reg, ms.loop_count_reg });
6833:                            try writer.print("    reg_{d} = reg_{d};\n", .{ inc_reg, limit_reg });
6913:                                try writer.print("    reg_{d} = reg_{d};\n", .{ res.id, incoming.value.id });
7124:                    try writer.print("        reg_{d} = reg_{d} + 1;\n", .{ update.phi_reg, update.phi_reg });
7137:                    try writer.print("        reg_{d} = reg_{d};\n", .{ update.phi_reg, update.value_reg });
7140:                    try writer.print("        reg_{d} = reg_{d}.asInt();\n", .{ update.phi_reg, update.value_reg });
7142:                    try writer.print("        reg_{d} = reg_{d}.asFloat();\n", .{ update.phi_reg, update.value_reg });
7144:                    try writer.print("        reg_{d} = reg_{d}.toBool();\n", .{ update.phi_reg, update.value_reg });
7147:                    try writer.print("        reg_{d} = reg_{d};\n", .{ update.phi_reg, update.value_reg });
7222:                        try writer.print("        reg_{d} = reg_{d};\n", .{ update.phi_reg, update.value_reg });
7224:                        try writer.print("        reg_{d} = reg_{d}.asInt();\n", .{ update.phi_reg, update.value_reg });
```

## 修复方案

### 方案 A：手动逐个修复（当前方案）
- **优点**：精确控制，理解每个位置的语义
- **缺点**：耗时长（预计 2-3 小时），容易遗漏

### 方案 B：AST 重写工具（推荐）
使用 Zig AST 重写工具批量替换所有模式：

```zig
// 查找模式
writer.print("reg_{d} = reg_{d}", .{dst, src})

// 替换为
var src_buf: [32]u8 = undefined;
const src_ref = try self.getOperandRef(&src_buf, src);
try writer.print("reg_{d} = {s}", .{dst, src_ref})
```

**实现步骤**：
1. 创建 Zig AST 解析器
2. 查找所有 `writer.print` 调用
3. 检测 `reg_{d}` 模式
4. 自动插入 `getOperandRef` 调用
5. 重新生成代码

**预计时间**：4-6 小时（包括工具开发）

### 方案 C：统一寄存器引用 API（长期方案）
重构所有代码生成，统一使用 `writeRegRef(writer, reg_id)` 替代 `writer.print("reg_{d}", .{reg_id})`。

**优点**：
- 彻底解决问题
- 未来易于维护
- 支持其他优化（如寄存器重命名）

**缺点**：
- 需要修改 100+ 处代码
- 预计时间：8-12 小时

## 测试用例

### 当前失败
```bash
./zig-out/bin/php-interpreter --compile tests/aot/test_closures.php
# 错误：.zigphp_aot_build/main.zig:549:18: error: expected type 'runtime_lib.Value', found '*runtime_lib.Value'
```

### 预期成功
```bash
./zig-out/bin/php-interpreter --compile --output=/tmp/test_closures tests/aot/test_closures.php
/tmp/test_closures
# 输出：
# Doubled: [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
# Filtered: [6, 7, 8, 9, 10]
```

## 下一步行动

1. **短期（1-2 小时）**：手动修复 P0 优先级的 10 处关键位置
2. **中期（4-6 小时）**：开发 AST 重写工具，批量修复剩余位置
3. **长期（8-12 小时）**：重构为统一 API

## 相关文件

- `src/aot/native_linker.zig` - 主要代码生成器
- `src/aot/nested_loop_codegen.zig` - 嵌套循环生成器
- `src/aot/optimizer.zig` - mem2reg 优化器
- `tests/aot/test_closures.php` - 测试用例

## 参考

- Git commit: 5d312bb "部分修复 alloca 寄存器代码生成（进行中）"
- 相关 issue: 闭包编译失败（alloca 寄存器类型不匹配）
