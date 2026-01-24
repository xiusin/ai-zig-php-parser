# Zig-PHP AOT编译器 - 函数定义和调用实现计划

**日期**: 2025-01-24  
**版本**: v1.6 规划  
**优先级**: P0（最高优先级）  
**预计工作量**: 12-16小时

---

## 📊 当前状态分析

### 1.1 已实现的基础设施

#### ✅ IR层面（src/aot/ir.zig）
- **CallOp结构已定义**（第728-737行）
  ```zig
  pub const CallOp = struct {
      func_name: []const u8,
      args: []const Register,
      return_type: Type,
  };
  ```
- **Function结构完整**（第189-268行）
  - 支持参数列表（params）
  - 支持返回类型（return_type）
  - 支持基本块管理（blocks）
  - 支持SSA寄存器分配（newRegister）

#### ✅ IR生成器（src/aot/ir_generator.zig）
- **函数声明生成已实现**（generateFunctionDecl）
- **函数调用生成已实现**（generateFunctionCall，第2151-2177行）
  ```zig
  fn generateFunctionCall(self: *Self, node: *const Node) !Register {
      // 获取函数名
      // 生成参数
      // 发射call指令
  }
  ```

#### ⚠️ 代码生成器（src/aot/native_linker.zig）
- **函数调用代码生成已部分实现**（第2873-2940行）
  - ✅ 支持内置函数调用（php_echo, php_count等）
  - ❌ **不支持用户自定义函数调用**
  - ❌ **缺少函数定义的代码生成**


### 1.2 核心问题识别

#### 🔴 问题1：函数定义未生成Zig代码
**现状**：
- IR生成器创建Function对象并添加到Module
- 但native_linker的`generateFunction`只处理`__main__`函数
- 用户定义的函数没有生成对应的Zig函数

**影响**：
- 无法调用用户定义的函数
- 编译时会报"未定义函数"错误

#### 🔴 问题2：函数调用生成的代码不正确
**现状**（第2930行）：
```zig
// 当前代码
try writer.print("        {s} = try @\"{s}\"({s});\n", .{ r, op.func_name, args_list.items });
```

**问题**：
- 使用`@"函数名"`语法，但函数可能未定义
- 没有处理函数作用域和命名空间

#### 🔴 问题3：缺少函数上下文管理
**现状**：
- 没有全局函数表
- 无法验证函数是否存在
- 无法处理函数重载

---

## 🎯 实现目标

### 2.1 核心功能
1. ✅ 支持函数定义（带参数、返回值）
2. ✅ 支持函数调用（传参、接收返回值）
3. ✅ 支持递归函数
4. ✅ 支持多个函数相互调用
5. ✅ 支持函数作用域和局部变量

### 2.2 非目标（暂不实现）
- ❌ 函数重载
- ❌ 可变参数
- ❌ 默认参数
- ❌ 引用传递
- ❌ 闭包和匿名函数
- ❌ 生成器函数

---

## 📝 详细实现计划

### 阶段1：函数定义代码生成（4-5小时）

#### 任务1.1：修改native_linker.zig的generateFunction
**文件**：`src/aot/native_linker.zig`  
**位置**：第1800-2100行（generateFunction函数）

**当前问题**：
```zig
// 当前只处理__main__函数
fn generateFunction(self: *Self, func: *const IR.Function, writer: anytype) !void {
    // 只生成__main__的代码
}
```

**修改方案**：
```zig
fn generateFunction(self: *Self, func: *const IR.Function, writer: anytype) !void {
    // 1. 生成函数签名
    if (std.mem.eql(u8, func.name, "__main__")) {
        try writer.writeAll("pub fn main() !void {\n");
    } else {
        // 用户定义函数
        try self.generateFunctionSignature(func, writer);
    }
    
    // 2. 生成函数体（现有逻辑）
    // ...
    
    try writer.writeAll("}\n\n");
}
```


#### 任务1.2：实现generateFunctionSignature
**新增函数**：

```zig
/// 生成函数签名
/// @pre func 必须是有效的Function对象
/// @post 生成形如 "pub fn funcName(param1: Type, ...) !ReturnType {" 的代码
fn generateFunctionSignature(self: *Self, func: *const IR.Function, writer: anytype) !void {
    // 1. 函数可见性和名称
    try writer.print("pub fn @\"{}\"(", .{std.zig.fmtEscapes(func.name)});
    
    // 2. 参数列表
    for (func.params.items, 0..) |param, i| {
        if (i > 0) try writer.writeAll(", ");
        
        // 参数名
        try writer.print("{s}: ", .{param.name});
        
        // 参数类型
        const param_type = self.irTypeToZigType(param.type_);
        try writer.writeAll(param_type);
    }
    
    // 3. 返回类型
    try writer.writeAll(") !");
    const return_type = self.irTypeToZigType(func.return_type);
    try writer.writeAll(return_type);
    
    try writer.writeAll(" {\n");
}

/// IR类型转Zig类型字符串
fn irTypeToZigType(self: *const Self, ir_type: IR.Type) []const u8 {
    _ = self;
    return switch (ir_type) {
        .void => "void",
        .i64 => "i64",
        .f64 => "f64",
        .bool => "bool",
        .php_value => "runtime.Value",
        .php_string => "runtime.Value",
        .php_array => "runtime.Value",
        else => "runtime.Value",
    };
}
```

#### 任务1.3：修改compile函数生成所有函数
**文件**：`src/aot/native_linker.zig`  
**位置**：第400-500行（compile函数）

**当前问题**：
```zig
// 只生成__main__函数
const main_func = module.findFunction("__main__") orelse return error.NoMainFunction;
try self.generateFunction(main_func, code_writer);
```

**修改方案**：
```zig
// 1. 先生成所有用户定义函数
for (module.functions.items) |func| {
    if (!std.mem.eql(u8, func.name, "__main__")) {
        try self.generateFunction(func, code_writer);
    }
}

// 2. 最后生成main函数
const main_func = module.findFunction("__main__") orelse return error.NoMainFunction;
try self.generateFunction(main_func, code_writer);
```

**验证方法**：
```bash
# 测试用例
cat > test_function_def.php << 'EOF'
<?php
function add($a, $b) {
    return $a + $b;
}
EOF

./zig-out/bin/php-interpreter --compile test_function_def.php
# 应该生成包含 pub fn @"add"(a: runtime.Value, b: runtime.Value) !runtime.Value 的代码
```

---

### 阶段2：函数调用代码生成（3-4小时）

#### 任务2.1：修复call指令的代码生成
**文件**：`src/aot/native_linker.zig`  
**位置**：第2873-2940行

**当前代码问题**：
```zig
.call => |op| {
    // ...
    if (is_builtin) {
        try writer.print("        {s} = try runtime.{s}({s});\n", ...);
    } else {
        // ❌ 问题：使用@"函数名"但可能未定义
        try writer.print("        {s} = try @\"{s}\"({s});\n", ...);
    }
}
```

**修改方案**：
```zig
.call => |op| {
    // 格式化参数列表
    var args_list = std.ArrayList(u8){};
    defer args_list.deinit(self.allocator);
    const args_writer = args_list.writer(self.allocator);
    
    for (op.args, 0..) |arg, i| {
        if (i > 0) try args_writer.writeAll(", ");
        const arg_str = try self.formatRegister(arg);
        defer self.allocator.free(arg_str);
        try args_writer.writeAll(arg_str);
    }
    
    // 检查是否是内置函数
    const is_builtin = self.isBuiltinFunction(op.func_name);
    
    // 生成函数调用
    if (result_reg) |r| {
        if (is_builtin) {
            const runtime_name = self.mapToRuntimeFunction(op.func_name);
            try writer.print("        {s} = try runtime.{s}({s});\n", 
                .{ r, runtime_name, args_list.items });
        } else {
            // 用户定义函数：使用@"函数名"语法
            try writer.print("        {s} = try @\"{s}\"({s});\n", 
                .{ r, op.func_name, args_list.items });
        }
    } else {
        // 无返回值的调用
        if (is_builtin) {
            const runtime_name = self.mapToRuntimeFunction(op.func_name);
            try writer.print("        _ = try runtime.{s}({s});\n", 
                .{ runtime_name, args_list.items });
        } else {
            try writer.print("        _ = try @\"{s}\"({s});\n", 
                .{ op.func_name, args_list.items });
        }
    }
}
```


#### 任务2.2：实现辅助函数
**新增函数**：

```zig
/// 检查是否是内置函数
fn isBuiltinFunction(self: *const Self, func_name: []const u8) bool {
    _ = self;
    const builtins = [_][]const u8{
        "echo", "print", "var_dump",
        "strlen", "substr", "strpos", "strtoupper", "strtolower", "trim",
        "count", "array_push", "array_pop", "in_array",
        "abs", "sqrt", "round", "floor", "ceil", "min", "max",
        "is_null", "is_bool", "is_int", "is_float", "is_string", "is_array",
        "intval", "floatval", "strval", "boolval",
    };
    
    for (builtins) |builtin| {
        if (std.mem.eql(u8, func_name, builtin)) return true;
    }
    
    return std.mem.startsWith(u8, func_name, "php_");
}

/// 映射PHP函数名到运行时函数名
fn mapToRuntimeFunction(self: *const Self, func_name: []const u8) []const u8 {
    _ = self;
    
    // 已经是php_前缀的直接返回
    if (std.mem.startsWith(u8, func_name, "php_")) {
        return func_name;
    }
    
    // 映射表
    const mappings = .{
        .{ "echo", "php_echo" },
        .{ "print", "php_print" },
        .{ "var_dump", "php_var_dump" },
        .{ "strlen", "php_strlen" },
        .{ "count", "php_count" },
        // ... 其他映射
    };
    
    inline for (mappings) |mapping| {
        if (std.mem.eql(u8, func_name, mapping[0])) {
            return mapping[1];
        }
    }
    
    return func_name;
}
```

**验证方法**：
```bash
# 测试用例
cat > test_function_call.php << 'EOF'
<?php
function add($a, $b) {
    return $a + $b;
}

$result = add(10, 20);
echo $result;
EOF

./zig-out/bin/php-interpreter --compile test_function_call.php
./hello
# 预期输出: 30
```

---

### 阶段3：参数和返回值处理（3-4小时）

#### 任务3.1：处理函数参数的寄存器分配
**问题**：函数参数需要在函数体内可访问

**解决方案**：在generateFunction开始时为参数创建寄存器

```zig
fn generateFunction(self: *Self, func: *const IR.Function, writer: anytype) !void {
    // ... 生成函数签名 ...
    
    // 为参数创建寄存器映射
    if (!std.mem.eql(u8, func.name, "__main__")) {
        for (func.params.items, 0..) |param, i| {
            // 参数直接作为寄存器使用
            try writer.print("    // 参数 {s} 对应寄存器 %{d}\n", .{param.name, i});
        }
    }
    
    // ... 生成函数体 ...
}
```

#### 任务3.2：处理return语句
**文件**：`src/aot/native_linker.zig`  
**位置**：Terminator处理部分

**当前代码**：
```zig
.ret => |maybe_value| {
    if (maybe_value) |value| {
        const val_str = try self.formatRegister(value);
        defer self.allocator.free(val_str);
        try writer.print("    return {s};\n", .{val_str});
    } else {
        try writer.writeAll("    return;\n");
    }
}
```

**问题**：需要确保返回值类型匹配

**修改方案**：
```zig
.ret => |maybe_value| {
    if (maybe_value) |value| {
        const val_str = try self.formatRegister(value);
        defer self.allocator.free(val_str);
        
        // 如果返回类型是void，忽略返回值
        if (current_func.return_type == .void) {
            try writer.writeAll("    return;\n");
        } else {
            try writer.print("    return {s};\n", .{val_str});
        }
    } else {
        try writer.writeAll("    return;\n");
    }
}
```

**验证方法**：
```bash
# 测试用例
cat > test_return.php << 'EOF'
<?php
function multiply($a, $b) {
    return $a * $b;
}

$result = multiply(5, 6);
echo $result;
EOF

./zig-out/bin/php-interpreter --compile test_return.php
./hello
# 预期输出: 30
```

---

### 阶段4：递归和相互调用支持（2-3小时）

#### 任务4.1：确保函数声明顺序
**问题**：Zig要求函数在调用前声明

**解决方案1：前向声明**
```zig
// 在compile函数中，先生成所有函数声明
for (module.functions.items) |func| {
    if (!std.mem.eql(u8, func.name, "__main__")) {
        try self.generateFunctionDeclaration(func, code_writer);
    }
}

// 然后生成所有函数实现
for (module.functions.items) |func| {
    if (!std.mem.eql(u8, func.name, "__main__")) {
        try self.generateFunction(func, code_writer);
    }
}
```

**解决方案2：依赖排序**（推荐）
```zig
// 分析函数调用依赖关系，按拓扑排序生成
const sorted_funcs = try self.topologicalSortFunctions(module);
for (sorted_funcs) |func| {
    try self.generateFunction(func, code_writer);
}
```

#### 任务4.2：递归函数支持
**测试用例**：
```php
<?php
function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

echo factorial(5);
```

**预期输出**：120

**实现要点**：
- 递归调用与普通调用相同
- 确保栈空间足够（Zig默认处理）
- 尾递归优化（可选，后期优化）

---

### 阶段5：测试和验证（2-3小时）

#### 测试用例1：简单函数
```php
<?php
function greet() {
    echo "Hello";
}

greet();
```
**预期输出**：Hello

#### 测试用例2：带参数的函数
```php
<?php
function add($a, $b) {
    return $a + $b;
}

echo add(10, 20);
```
**预期输出**：30

#### 测试用例3：带返回值的函数
```php
<?php
function square($x) {
    return $x * $x;
}

$result = square(7);
echo $result;
```
**预期输出**：49

#### 测试用例4：递归函数
```php
<?php
function fibonacci($n) {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

echo fibonacci(10);
```
**预期输出**：55

#### 测试用例5：多个函数相互调用
```php
<?php
function isEven($n) {
    if ($n == 0) return 1;
    return isOdd($n - 1);
}

function isOdd($n) {
    if ($n == 0) return 0;
    return isEven($n - 1);
}

echo isEven(4);
echo isOdd(4);
```
**预期输出**：10


---

## 🔧 技术细节

### 5.1 函数签名映射

#### PHP函数 → IR Function
```php
function add($a, $b) {
    return $a + $b;
}
```

**IR表示**：
```
Function {
    name: "add",
    params: [
        Parameter { name: "a", type: php_value },
        Parameter { name: "b", type: php_value },
    ],
    return_type: php_value,
    blocks: [
        BasicBlock {
            label: "entry",
            instructions: [
                %0 = load %a
                %1 = load %b
                %2 = add %0, %1
            ],
            terminator: ret %2
        }
    ]
}
```

#### IR Function → Zig代码
```zig
pub fn @"add"(a: runtime.Value, b: runtime.Value) !runtime.Value {
    var reg_0: runtime.Value = undefined;
    var reg_1: runtime.Value = undefined;
    var reg_2: runtime.Value = undefined;
    
    reg_0 = a;
    reg_1 = b;
    reg_2 = try runtime.php_add(reg_0, reg_1);
    
    return reg_2;
}
```

### 5.2 参数传递机制

#### 值传递（当前实现）
- 所有参数作为`runtime.Value`传递
- 函数内部可以修改参数副本
- 不影响调用者的变量

```zig
// 调用
const result = try @"add"(
    runtime.Value.initInt(10),
    runtime.Value.initInt(20)
);
```

#### 引用传递（未来实现）
- 需要传递指针：`*runtime.Value`
- 函数内部修改会影响调用者
- 需要在IR层面标记引用参数

### 5.3 返回值处理

#### 有返回值
```zig
pub fn @"square"(x: runtime.Value) !runtime.Value {
    // ...
    return result;
}

// 调用
const result = try @"square"(runtime.Value.initInt(7));
```

#### 无返回值
```zig
pub fn @"greet"() !void {
    _ = try runtime.php_echo(runtime.Value.initString("Hello"));
    return;
}

// 调用
try @"greet"();
```

### 5.4 作用域和变量生命周期

#### 函数局部变量
```php
function test() {
    $x = 10;  // 局部变量
    return $x;
}
```

**生成代码**：
```zig
pub fn @"test"() !runtime.Value {
    var reg_0: *runtime.Value = undefined;  // $x的指针
    var reg_1: i64 = undefined;
    var reg_2: runtime.Value = undefined;
    
    // alloca $x
    reg_0 = &reg_2;
    
    // $x = 10
    reg_1 = 10;
    reg_0.* = runtime.Value.initInt(reg_1);
    
    // return $x
    const ret_val = reg_0.*;
    return ret_val;
}
```

#### 全局变量访问（未来实现）
- 需要全局变量表
- 函数内部通过全局表访问
- 需要考虑线程安全

---

## 🚨 潜在问题和解决方案

### 问题1：函数名冲突
**场景**：PHP函数名可能与Zig关键字冲突

**解决方案**：
```zig
// 使用@"函数名"语法
pub fn @"if"() !void { }  // if是Zig关键字
pub fn @"return"() !void { }  // return是Zig关键字
```

### 问题2：函数重载
**场景**：PHP不支持函数重载，但可能有同名函数

**解决方案**：
- 当前不支持，报错
- 未来可以通过命名空间区分

### 问题3：可变参数
**场景**：`function test(...$args)`

**解决方案**：
- 当前不支持
- 未来可以传递数组：`args: runtime.Value`（数组类型）

### 问题4：默认参数
**场景**：`function test($a = 10)`

**解决方案**：
- 当前不支持
- 未来在函数体开始处理：
  ```zig
  if (a.isNull()) {
      a = runtime.Value.initInt(10);
  }
  ```

### 问题5：递归深度限制
**场景**：深度递归可能导致栈溢出

**解决方案**：
- Zig默认栈大小足够（通常8MB）
- 可以在编译时调整：`-fstack-size=16777216`
- 未来可以实现尾递归优化

---

## 📋 实施检查清单

### 阶段1：函数定义 ✅
- [ ] 修改generateFunction支持用户函数
- [ ] 实现generateFunctionSignature
- [ ] 实现irTypeToZigType
- [ ] 修改compile生成所有函数
- [ ] 测试函数定义生成

### 阶段2：函数调用 ✅
- [ ] 修复call指令代码生成
- [ ] 实现isBuiltinFunction
- [ ] 实现mapToRuntimeFunction
- [ ] 测试函数调用

### 阶段3：参数和返回值 ✅
- [ ] 处理函数参数寄存器
- [ ] 修复return语句生成
- [ ] 测试参数传递
- [ ] 测试返回值

### 阶段4：递归和相互调用 ✅
- [ ] 实现函数依赖排序
- [ ] 测试递归函数
- [ ] 测试相互调用

### 阶段5：测试和验证 ✅
- [ ] 测试用例1：简单函数
- [ ] 测试用例2：带参数
- [ ] 测试用例3：带返回值
- [ ] 测试用例4：递归
- [ ] 测试用例5：相互调用
- [ ] 确保现有12个测试仍然通过

---

## 📊 工作量估算

| 阶段 | 任务 | 预计时间 | 难度 |
|------|------|----------|------|
| 1 | 函数定义代码生成 | 4-5小时 | 中 |
| 2 | 函数调用代码生成 | 3-4小时 | 中 |
| 3 | 参数和返回值处理 | 3-4小时 | 中 |
| 4 | 递归和相互调用 | 2-3小时 | 高 |
| 5 | 测试和验证 | 2-3小时 | 低 |
| **总计** | | **14-19小时** | |

---

## 🎯 成功标准

### 功能标准
1. ✅ 能够定义和调用简单函数
2. ✅ 能够传递参数和接收返回值
3. ✅ 支持递归函数
4. ✅ 支持多个函数相互调用
5. ✅ 所有测试用例通过

### 质量标准
1. ✅ 代码符合Zig语言规范
2. ✅ 无内存泄漏
3. ✅ 无未定义行为
4. ✅ 错误处理完整
5. ✅ 现有测试不受影响

### 性能标准
1. ✅ 函数调用开销最小
2. ✅ 编译时间合理（<5秒）
3. ✅ 生成代码大小合理

---

## 🚀 下一步行动

### 立即开始
1. 创建测试分支：`git checkout -b feature/function-support`
2. 修改`native_linker.zig`的`generateFunction`
3. 运行第一个测试用例

### 开发流程
1. 实现阶段1 → 测试 → 提交
2. 实现阶段2 → 测试 → 提交
3. 实现阶段3 → 测试 → 提交
4. 实现阶段4 → 测试 → 提交
5. 实现阶段5 → 完整测试 → 合并

### 验证方法
```bash
# 每个阶段完成后运行
./test_aot_extended.sh  # 确保现有测试通过
./test_function_suite.sh  # 运行新的函数测试
```

---

## 📚 参考资料

### Zig语言规范
- [Zig函数](https://ziglang.org/documentation/master/#Functions)
- [Zig错误处理](https://ziglang.org/documentation/master/#Errors)
- [Zig标识符](https://ziglang.org/documentation/master/#Identifiers)

### 项目文档
- [AOT_README.md](AOT_README.md) - 当前功能说明
- [AOT_COMPLETE_FEATURES_REPORT.md](AOT_COMPLETE_FEATURES_REPORT.md) - 完整功能报告
- [NEXT_STEPS_ROADMAP.md](NEXT_STEPS_ROADMAP.md) - 路线图

---

**最后更新**: 2025-01-24  
**状态**: 📋 规划完成，待实施  
**负责人**: Zig-PHP开发团队

