# AOT编译器完整实现 - 设计文档

## 1. 架构设计

### 1.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                     AOT Compilation Pipeline                 │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  PHP Source Code                                             │
│         ↓                                                     │
│  ┌──────────────┐                                           │
│  │   Parser     │  (已完成)                                 │
│  └──────┬───────┘                                           │
│         ↓                                                     │
│  ┌──────────────┐                                           │
│  │     AST      │  (已完成)                                 │
│  └──────┬───────┘                                           │
│         ↓                                                     │
│  ┌──────────────┐                                           │
│  │ IR Generator │  (已完成)                                 │
│  └──────┬───────┘                                           │
│         ↓                                                     │
│  ┌──────────────┐                                           │
│  │  IR Module   │  (已完成)                                 │
│  └──────┬───────┘                                           │
│         ↓                                                     │
│  ┌──────────────────────────────────┐                       │
│  │   Native Linker (待完善)         │ ← 核心实现区域        │
│  │  ┌────────────────────────────┐  │                       │
│  │  │ Code Generator             │  │                       │
│  │  │  - IR → Zig Code           │  │                       │
│  │  │  - Register Allocation     │  │                       │
│  │  │  - Control Flow Generation │  │                       │
│  │  └────────────────────────────┘  │                       │
│  │  ┌────────────────────────────┐  │                       │
│  │  │ Runtime Library Generator  │  │                       │
│  │  │  - Value Type              │  │                       │
│  │  │  - Operators               │  │                       │
│  │  │  - Built-in Functions      │  │                       │
│  │  │  - Memory Management       │  │                       │
│  │  └────────────────────────────┘  │                       │
│  └──────────────┬───────────────────┘                       │
│                 ↓                                             │
│  ┌──────────────────────┐                                   │
│  │  Generated Zig Code  │                                   │
│  │  - main.zig          │                                   │
│  │  - runtime_lib.zig   │                                   │
│  └──────────┬───────────┘                                   │
│             ↓                                                 │
│  ┌──────────────────────┐                                   │
│  │  Zig Compiler        │  (系统工具)                       │
│  └──────────┬───────────┘                                   │
│             ↓                                                 │
│  ┌──────────────────────┐                                   │
│  │  Native Executable   │  (最终产物)                       │
│  └──────────────────────┘                                   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 模块职责

#### 1.2.1 NativeLinker (src/aot/native_linker.zig)
**职责**：将IR模块转换为Zig源代码并调用Zig编译器

**核心方法**：
- `generateZigCode()` - 生成完整的Zig源文件
- `generateFunction()` - 生成单个函数
- `generateInstruction()` - **核心待实现** - 将IR指令转换为Zig代码
- `generateGlobalVariable()` - 生成全局变量
- `copyRuntimeLib()` - 生成运行时库
- `invokeZigCompiler()` - 调用Zig编译器

#### 1.2.2 RuntimeLib (生成的runtime_lib.zig)
**职责**：提供PHP运行时支持

**核心组件**：
- `Value` - PHP值类型
- 运算符函数 - `php_add()`, `php_concat()` 等
- 内置函数 - `php_echo()`, `php_strlen()` 等
- 内存管理 - 引用计数、分配器

#### 1.2.3 CodeGenHelpers (src/aot/codegen_helpers.zig) - 新增
**职责**：辅助代码生成

**核心功能**：
- 寄存器分配
- 变量名生成
- 类型推断辅助
- 代码格式化

---

## 2. 核心设计

### 2.1 Value类型设计

#### 2.1.1 类型定义

```zig
pub const ValueType = enum {
    int,
    float,
    string,
    bool,
    null,
    array,
    object,
};

pub const Value = struct {
    type: ValueType,
    data: union {
        int: i64,
        float: f64,
        string: *String,
        bool: bool,
        null: void,
        array: *Array,
        object: *Object,
    },
    refcount: usize,  // 引用计数
    
    // 构造函数
    pub fn initInt(val: i64) Value;
    pub fn initFloat(val: f64) Value;
    pub fn initString(val: []const u8) Value;
    pub fn initBool(val: bool) Value;
    pub fn initNull() Value;
    
    // 类型转换
    pub fn toInt(self: *const Value) !i64;
    pub fn toFloat(self: *const Value) !f64;
    pub fn toString(self: *const Value, allocator: Allocator) ![]const u8;
    pub fn toBool(self: *const Value) bool;
    
    // 引用计数
    pub fn retain(self: *Value) void;
    pub fn release(self: *Value, allocator: Allocator) void;
};
```

#### 2.1.2 字符串类型

```zig
pub const String = struct {
    data: []const u8,
    len: usize,
    capacity: usize,
    is_static: bool,  // 是否是静态字符串（不需要释放）
    
    pub fn init(allocator: Allocator, str: []const u8) !*String;
    pub fn deinit(self: *String, allocator: Allocator) void;
    pub fn concat(self: *String, other: *String, allocator: Allocator) !*String;
};
```

#### 2.1.3 数组类型

```zig
pub const Array = struct {
    items: std.ArrayList(Value),
    
    pub fn init(allocator: Allocator) !*Array;
    pub fn deinit(self: *Array, allocator: Allocator) void;
    pub fn get(self: *Array, index: usize) !Value;
    pub fn set(self: *Array, index: usize, value: Value) !void;
    pub fn push(self: *Array, value: Value) !void;
    pub fn pop(self: *Array) !Value;
};
```

### 2.2 IR指令到Zig代码映射

#### 2.2.1 常量指令

| IR指令 | Zig代码 | 示例 |
|--------|---------|------|
| `const_int 42` | `const reg_N = Value.initInt(42);` | `const reg_0 = Value.initInt(42);` |
| `const_float 3.14` | `const reg_N = Value.initFloat(3.14);` | `const reg_1 = Value.initFloat(3.14);` |
| `const_string "hello"` | `const reg_N = Value.initString("hello");` | `const reg_2 = Value.initString("hello");` |
| `const_bool true` | `const reg_N = Value.initBool(true);` | `const reg_3 = Value.initBool(true);` |
| `const_null` | `const reg_N = Value.initNull();` | `const reg_4 = Value.initNull();` |

#### 2.2.2 算术指令

| IR指令 | Zig代码 | 示例 |
|--------|---------|------|
| `add %1, %2` | `const reg_N = try php_add(reg_1, reg_2);` | `const reg_5 = try php_add(reg_1, reg_2);` |
| `sub %1, %2` | `const reg_N = try php_sub(reg_1, reg_2);` | `const reg_6 = try php_sub(reg_1, reg_2);` |
| `mul %1, %2` | `const reg_N = try php_mul(reg_1, reg_2);` | `const reg_7 = try php_mul(reg_1, reg_2);` |
| `div %1, %2` | `const reg_N = try php_div(reg_1, reg_2);` | `const reg_8 = try php_div(reg_1, reg_2);` |

#### 2.2.3 字符串指令

| IR指令 | Zig代码 |
|--------|---------|
| `concat %1, %2` | `const reg_N = try php_concat(reg_1, reg_2, allocator);` |

#### 2.2.4 变量指令

| IR指令 | Zig代码 | 说明 |
|--------|---------|------|
| `alloca $var` | `var var_var: Value = undefined;` | 分配栈空间 |
| `store %1, $var` | `var_var = reg_1;` | 存储到变量 |
| `load $var` | `const reg_N = var_var;` | 从变量加载 |

#### 2.2.5 控制流指令

| IR指令 | Zig代码 |
|--------|---------|
| `br label` | `goto label;` (使用block/break模拟) |
| `br_cond %1, then, else` | `if (reg_1.toBool()) { goto then; } else { goto else; }` |
| `ret %1` | `return reg_1;` |
| `ret void` | `return;` |

#### 2.2.6 函数调用指令

| IR指令 | Zig代码 |
|--------|---------|
| `call php_echo, %1` | `try php_echo(reg_1);` |
| `call user_func, %1, %2` | `const reg_N = try @"user_func"(reg_1, reg_2);` |

### 2.3 寄存器分配策略

#### 2.3.1 SSA寄存器映射

每个IR寄存器映射到一个Zig常量：

```zig
// IR: %0 = const_int 42
// Zig: const reg_0 = Value.initInt(42);

// IR: %1 = add %0, %0
// Zig: const reg_1 = try php_add(reg_0, reg_0);
```

#### 2.3.2 变量映射

PHP变量映射到Zig变量：

```zig
// PHP: $name = "Alice";
// IR: alloca $name
//     %0 = const_string "Alice"
//     store %0, $name
// Zig:
var var_name: Value = undefined;
const reg_0 = Value.initString("Alice");
var_name = reg_0;
```

#### 2.3.3 临时变量优化

对于只使用一次的寄存器，可以内联：

```zig
// 未优化:
const reg_0 = Value.initInt(10);
const reg_1 = Value.initInt(20);
const reg_2 = try php_add(reg_0, reg_1);
try php_echo(reg_2);

// 优化后:
try php_echo(try php_add(Value.initInt(10), Value.initInt(20)));
```

### 2.4 控制流生成

#### 2.4.1 If-Else结构

```zig
// PHP:
// if ($x > 5) {
//     echo "大";
// } else {
//     echo "小";
// }

// 生成的Zig代码:
const cond = try php_gt(var_x, Value.initInt(5));
if (cond.toBool()) {
    try php_echo(Value.initString("大"));
} else {
    try php_echo(Value.initString("小"));
}
```

#### 2.4.2 While循环

```zig
// PHP:
// while ($i < 10) {
//     echo $i;
//     $i++;
// }

// 生成的Zig代码:
while (true) {
    const cond = try php_lt(var_i, Value.initInt(10));
    if (!cond.toBool()) break;
    
    try php_echo(var_i);
    var_i = try php_add(var_i, Value.initInt(1));
}
```

#### 2.4.3 For循环

```zig
// PHP:
// for ($i = 0; $i < 10; $i++) {
//     echo $i;
// }

// 生成的Zig代码:
var var_i = Value.initInt(0);
while (true) {
    const cond = try php_lt(var_i, Value.initInt(10));
    if (!cond.toBool()) break;
    
    try php_echo(var_i);
    var_i = try php_add(var_i, Value.initInt(1));
}
```

### 2.5 内存管理设计

#### 2.5.1 引用计数

```zig
pub const Value = struct {
    refcount: usize,
    
    pub fn retain(self: *Value) void {
        self.refcount += 1;
    }
    
    pub fn release(self: *Value, allocator: Allocator) void {
        self.refcount -= 1;
        if (self.refcount == 0) {
            self.deinit(allocator);
        }
    }
};
```

#### 2.5.2 自动内存管理

在生成的代码中插入适当的retain/release调用：

```zig
// 创建值时自动retain
const reg_0 = Value.initString("hello");  // refcount = 1

// 赋值时retain
var_name = reg_0;
var_name.retain();  // refcount = 2

// 作用域结束时release
defer reg_0.release(allocator);  // refcount = 1
defer var_name.release(allocator);  // refcount = 0, 释放内存
```

#### 2.5.3 字符串池化

对于字符串常量，使用静态分配：

```zig
// 字符串常量表
const string_pool = [_][]const u8{
    "Hello, World!",
    "PHP 8.5 Interpreter",
    // ...
};

// 使用时不需要分配
const reg_0 = Value.initStaticString(&string_pool[0]);
```

---

## 3. 运行时库API设计

### 3.1 核心运算符

```zig
// 算术运算
pub fn php_add(lhs: Value, rhs: Value) !Value;
pub fn php_sub(lhs: Value, rhs: Value) !Value;
pub fn php_mul(lhs: Value, rhs: Value) !Value;
pub fn php_div(lhs: Value, rhs: Value) !Value;
pub fn php_mod(lhs: Value, rhs: Value) !Value;
pub fn php_pow(lhs: Value, rhs: Value) !Value;

// 比较运算
pub fn php_eq(lhs: Value, rhs: Value) !Value;
pub fn php_ne(lhs: Value, rhs: Value) !Value;
pub fn php_lt(lhs: Value, rhs: Value) !Value;
pub fn php_le(lhs: Value, rhs: Value) !Value;
pub fn php_gt(lhs: Value, rhs: Value) !Value;
pub fn php_ge(lhs: Value, rhs: Value) !Value;

// 逻辑运算
pub fn php_and(lhs: Value, rhs: Value) !Value;
pub fn php_or(lhs: Value, rhs: Value) !Value;
pub fn php_not(val: Value) !Value;

// 字符串运算
pub fn php_concat(lhs: Value, rhs: Value, allocator: Allocator) !Value;
```

### 3.2 内置函数

#### 3.2.1 输出函数

```zig
pub fn php_echo(value: Value) !void;
pub fn php_print(value: Value) !i64;
pub fn php_var_dump(value: Value) !void;
```

#### 3.2.2 字符串函数

```zig
pub fn php_strlen(str: Value) !Value;
pub fn php_substr(str: Value, start: Value, len: Value) !Value;
pub fn php_strpos(haystack: Value, needle: Value) !Value;
pub fn php_str_replace(search: Value, replace: Value, subject: Value) !Value;
pub fn php_strtoupper(str: Value) !Value;
pub fn php_strtolower(str: Value) !Value;
pub fn php_trim(str: Value) !Value;
```

#### 3.2.3 数组函数

```zig
pub fn php_count(arr: Value) !Value;
pub fn php_array_push(arr: *Value, values: []Value) !void;
pub fn php_array_pop(arr: *Value) !Value;
pub fn php_array_merge(arr1: Value, arr2: Value) !Value;
pub fn php_in_array(needle: Value, haystack: Value) !Value;
```

#### 3.2.4 数学函数

```zig
pub fn php_abs(val: Value) !Value;
pub fn php_sqrt(val: Value) !Value;
pub fn php_pow(base: Value, exp: Value) !Value;
pub fn php_round(val: Value) !Value;
pub fn php_floor(val: Value) !Value;
pub fn php_ceil(val: Value) !Value;
```

---

## 4. 代码生成流程

### 4.1 整体流程

```
IR Module
    ↓
遍历所有函数
    ↓
对每个函数:
    1. 生成函数签名
    2. 生成参数声明
    3. 遍历所有基本块
        ↓
    对每个基本块:
        1. 生成块标签
        2. 遍历所有指令
            ↓
        对每条指令:
            1. 分配寄存器/变量
            2. 生成对应的Zig代码
            3. 处理类型转换
        3. 生成终结指令（br, ret等）
    4. 生成函数结尾
    ↓
生成main函数
    ↓
输出完整的Zig文件
```

### 4.2 指令生成伪代码

```zig
fn generateInstruction(
    self: *Self,
    writer: anytype,
    inst: *const IR.Instruction,
    reg_map: *RegisterMap,
) !void {
    const result_reg = if (inst.result) |r| 
        try reg_map.allocate(r) 
    else 
        null;
    
    switch (inst.op) {
        .const_int => |val| {
            try writer.print("const {s} = Value.initInt({d});\n", 
                .{result_reg.?, val});
        },
        
        .add => |op| {
            const lhs = reg_map.get(op.lhs);
            const rhs = reg_map.get(op.rhs);
            try writer.print("const {s} = try php_add({s}, {s});\n",
                .{result_reg.?, lhs, rhs});
        },
        
        .call => |op| {
            const args_str = try formatArgs(op.args, reg_map);
            if (result_reg) |r| {
                try writer.print("const {s} = try {s}({s});\n",
                    .{r, op.func_name, args_str});
            } else {
                try writer.print("try {s}({s});\n",
                    .{op.func_name, args_str});
            }
        },
        
        // ... 其他指令
    }
}
```

---

## 5. 优化策略

### 5.1 编译时优化

#### 5.1.1 常量折叠

```zig
// 优化前:
const reg_0 = Value.initInt(10);
const reg_1 = Value.initInt(20);
const reg_2 = try php_add(reg_0, reg_1);

// 优化后:
const reg_2 = Value.initInt(30);
```

#### 5.1.2 死代码消除

```zig
// 优化前:
const reg_0 = Value.initInt(42);  // 未使用
try php_echo(Value.initInt(10));

// 优化后:
try php_echo(Value.initInt(10));
```

#### 5.1.3 内联小函数

```zig
// 优化前:
fn add_one(x: Value) !Value {
    return try php_add(x, Value.initInt(1));
}
const result = try add_one(var_x);

// 优化后:
const result = try php_add(var_x, Value.initInt(1));
```

### 5.2 运行时优化

#### 5.2.1 小整数缓存

```zig
// 缓存 -128 到 127 的整数
const small_int_cache = [_]Value{
    Value{ .type = .int, .data = .{ .int = -128 }, .refcount = 999999 },
    // ...
    Value{ .type = .int, .data = .{ .int = 127 }, .refcount = 999999 },
};

pub fn initInt(val: i64) Value {
    if (val >= -128 and val <= 127) {
        return small_int_cache[@intCast(usize, val + 128)];
    }
    return Value{ .type = .int, .data = .{ .int = val }, .refcount = 1 };
}
```

#### 5.2.2 字符串池化

```zig
// 全局字符串池
var string_pool: std.StringHashMap(*String) = undefined;

pub fn initString(str: []const u8) !Value {
    if (string_pool.get(str)) |cached| {
        cached.retain();
        return Value{ .type = .string, .data = .{ .string = cached }, .refcount = 1 };
    }
    // 创建新字符串并加入池
    const new_str = try String.init(allocator, str);
    try string_pool.put(str, new_str);
    return Value{ .type = .string, .data = .{ .string = new_str }, .refcount = 1 };
}
```

#### 5.2.3 快速路径优化

```zig
pub fn php_add(lhs: Value, rhs: Value) !Value {
    // 快速路径：两个整数相加
    if (lhs.type == .int and rhs.type == .int) {
        return Value.initInt(lhs.data.int + rhs.data.int);
    }
    
    // 慢速路径：类型转换
    const lhs_num = try lhs.toFloat();
    const rhs_num = try rhs.toFloat();
    return Value.initFloat(lhs_num + rhs_num);
}
```

---

## 6. 错误处理

### 6.1 编译时错误

```zig
// 类型不匹配
if (!isCompatibleType(lhs_type, rhs_type)) {
    return self.diagnostics.reportError(
        inst.location,
        "Type mismatch: cannot add {s} and {s}",
        .{@tagName(lhs_type), @tagName(rhs_type)},
    );
}
```

### 6.2 运行时错误

```zig
pub fn php_div(lhs: Value, rhs: Value) !Value {
    const lhs_num = try lhs.toFloat();
    const rhs_num = try rhs.toFloat();
    
    if (rhs_num == 0.0) {
        return error.DivisionByZero;
    }
    
    return Value.initFloat(lhs_num / rhs_num);
}
```

---

## 7. 测试策略

### 7.1 单元测试

```zig
test "Value.initInt" {
    const val = Value.initInt(42);
    try testing.expectEqual(ValueType.int, val.type);
    try testing.expectEqual(@as(i64, 42), val.data.int);
}

test "php_add integers" {
    const lhs = Value.initInt(10);
    const rhs = Value.initInt(20);
    const result = try php_add(lhs, rhs);
    try testing.expectEqual(@as(i64, 30), result.data.int);
}
```

### 7.2 集成测试

```zig
test "compile and run hello.php" {
    const source = "<?php echo \"Hello, World!\\n\";";
    
    // 编译
    var compiler = try AOTCompiler.init(allocator, .{
        .input_file = "test.php",
    });
    defer compiler.deinit();
    
    const result = try compiler.compileString(source);
    try testing.expect(result.success);
    
    // 运行
    const output = try runExecutable(result.output_path);
    try testing.expectEqualStrings("Hello, World!\n", output);
}
```

---

## 8. 性能目标

### 8.1 基准测试

| 测试项 | 解释器模式 | AOT模式 | 目标倍数 |
|--------|-----------|---------|----------|
| 简单循环 (1M次) | 100ms | < 10ms | > 10x |
| 函数调用 (1M次) | 200ms | < 10ms | > 20x |
| 字符串拼接 (10K次) | 50ms | < 10ms | > 5x |
| 数组操作 (10K次) | 80ms | < 10ms | > 8x |

### 8.2 内存使用

| 指标 | 目标 |
|------|------|
| 可执行文件大小 | < 5MB (简单程序) |
| 运行时内存 | < 10MB (简单程序) |
| 内存泄漏 | 0 bytes |

---

## 9. 实现优先级

### P0 - 核心功能（第1-3天）
1. ✅ 修复root_index问题
2. ⏳ 实现基本Value类型（int, string）
3. ⏳ 实现const_int, const_string指令生成
4. ⏳ 实现php_echo函数
5. ⏳ 实现php_add, php_concat函数
6. ⏳ 实现变量管理（alloca, store, load）
7. ⏳ hello.php能正确运行

### P1 - 扩展功能（第4-7天）
1. ⏳ 完整的Value类型（float, bool, null, array）
2. ⏳ 所有算术运算符
3. ⏳ 所有比较运算符
4. ⏳ 控制流（if-else, while, for）
5. ⏳ 函数定义和调用
6. ⏳ 10个内置函数

### P2 - 优化和完善（第8-14天）
1. ⏳ 引用计数内存管理
2. ⏳ 字符串池化
3. ⏳ 小整数缓存
4. ⏳ 常量折叠
5. ⏳ 死代码消除
6. ⏳ 性能优化
7. ⏳ 完整测试套件

---

## 10. 风险和缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 类型系统复杂 | 高 | 参考解释器实现，逐步迭代 |
| 内存管理bug | 高 | 充分测试，使用Zig安全特性 |
| 性能不达标 | 中 | 早期性能测试，及时优化 |
| 代码生成错误 | 高 | 单元测试每个指令，集成测试 |

---

**文档版本**: 1.0  
**创建日期**: 2026-01-21  
**最后更新**: 2026-01-21
