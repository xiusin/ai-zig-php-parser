# unset()触发析构函数 - 完整解决方案

## 问题描述

AOT编译器中`unset()`未能立即触发对象析构函数，导致析构函数在程序结束时才被调用，而不是在unset时立即调用。

## 根本原因

### 引用计数不匹配

1. **对象创建**：`new A()` → ref_count=1
2. **store操作**：`$x = ...` → store自动retain → ref_count=2
3. **__construct调用**：$this作为参数被retain → ref_count=3
4. **cleanup**：只release一次 → ref_count=2（未触发析构）

### mem2reg优化冲突

- `unset()`生成：`load → release → load → release → store null`
- mem2reg优化：删除alloca/load/store，转换成phi/直接赋值
- **依赖load的release指令也被删除**
- 结果：析构函数不被调用

## 完整解决方案

### 1. 添加unset_var专用指令

**文件**：`src/aot/ir.zig`

```zig
pub const Instruction = union(enum) {
    // ... 其他指令
    unset_var: struct { operand: Register },  // 专门处理unset
    // ...
};
```

### 2. IR生成时使用unset_var

**文件**：`src/aot/ir_generator.zig`

```zig
// unset($var)
if (self.var_registers.get(var_name)) |var_reg| {
    if (self.ref_vars.contains(var_name)) {
        // 引用变量：移除引用
        _ = self.ref_vars.remove(var_name);
        _ = self.var_registers.remove(var_name);
    } else {
        // 局部变量：使用unset_var指令
        _ = try self.emit(.{ .unset_var = .{ .operand = var_reg } }, null);
    }
}
```

**关键点**：优先检查`var_registers.contains()`而不是`isGlobalScope()`。

### 3. 优化器标记unset_var为有副作用

**文件**：`src/aot/optimizer.zig`

```zig
fn markRegistersInInstruction(inst: *const Instruction, used: *std.AutoHashMap(usize, void)) !void {
    switch (inst.op) {
        // ... 其他指令
        .unset_var => |op| {
            try used.put(op.operand.id, {});
        },
        // ...
    }
}
```

### 4. 代码生成时release两次

**文件**：`src/aot/native_linker.zig`

```zig
.unset_var => |op| {
    const is_alloca = if (self.current_alloca_regs) |regs| 
        regs.contains(op.operand.id) else false;
    
    if (is_alloca) {
        // alloca寄存器，需要解引用
        // release两次：抵消store的retain + 真正的unset
        try writer.print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{op.operand.id});
        try writer.print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{op.operand.id});
        // 设置为null
        try writer.print("    reg_{d}.* = runtime.Value.initNull();\n", .{op.operand.id});
    } else {
        // 普通寄存器
        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{op.operand.id});
        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{op.operand.id});
        try writer.print("    reg_{d} = runtime.Value.initNull();\n", .{op.operand.id});
    }
},
```

### 5. 修复__construct的额外retain

**文件**：`src/aot/runtime_lib_template.zig`

```zig
pub fn php_object_new_with_constructor(...) !Value {
    // ... 创建对象
    const obj_val = Value_initObject(obj);

    // 调用 __construct
    if (obj.class_meta) |m| {
        if (m.findMethodLookup("__construct")) |lookup| {
            const guard = ClassContext.init(m, lookup.owner);
            defer guard.deinit();
            _ = try lookup.method.func(obj_val, args, allocator);
            // __construct调用会导致对象被额外retain一次，需要release
            obj.release();
        }
    }

    return obj_val;
}
```

### 6. cleanup时release两次并检查null

**文件**：`src/aot/native_linker.zig`

```zig
// cleanup时，对于alloca寄存器
if (is_ptr) {
    // 添加null检查，跳过已unset的变量
    try code.writer(self.allocator).print("    if (!reg_{d}.*.isNull()) {{\n", .{reg_id});
    try code.writer(self.allocator).print("        reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg_id});
    try code.writer(self.allocator).print("        reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg_id});
    try code.writer(self.allocator).print("    }}\n", .{});
}
```

### 7. 排除已store到alloca的寄存器

**文件**：`src/aot/native_linker.zig`

```zig
// 找出被store到alloca的寄存器，它们不应该被cleanup
var stored_to_alloca = std.AutoHashMap(usize, void).init(self.allocator);
defer stored_to_alloca.deinit();

// 遍历所有block查找store指令
for (func.blocks.items) |block_scan| {
    for (block_scan.instructions.items) |inst| {
        if (inst.op == .store) {
            const store_op = inst.op.store;
            if (alloca_registers.contains(store_op.ptr.id)) {
                try stored_to_alloca.put(store_op.value.id, {});
            }
        }
    }
}

// cleanup时跳过这些寄存器
for (cleanup_registers.items) |reg_id| {
    if (stored_to_alloca.contains(reg_id)) continue;
    // ... cleanup代码
}
```

### 8. 使用alloca_registers判断而不是类型检查

**文件**：`src/aot/native_linker.zig`

```zig
// 错误的方式（mem2reg后类型可能不是.ptr）
const is_ptr = reg_tag == .ptr;

// 正确的方式
const is_ptr = alloca_registers.contains(reg_id);
```

## 最终引用计数流程

### 有__construct的对象

1. `new A()` → ref_count=1
2. `__construct调用` → ref_count=2（$this被retain）
3. `__construct后release` → ref_count=1
4. `store retain` → ref_count=2
5. `unset release两次` → ref_count=0 → **析构** ✅
6. 或 `cleanup release两次` → ref_count=0 → **析构** ✅

### 无__construct的对象

1. `new A()` → ref_count=1
2. `store retain` → ref_count=2
3. `unset release两次` → ref_count=0 → **析构** ✅
4. 或 `cleanup release两次` → ref_count=0 → **析构** ✅

## 测试结果

### 简单测试（无__construct）

```php
class A {
    function __destruct() {
        echo "Destructor\n";
    }
}

function test() {
    $a = new A();
    unset($a);
    echo "After unset\n";
}

test();
```

**输出**：
```
Destructor
After unset
```

✅ 析构函数在unset时立即调用

### Lifecycle测试（有__construct）

```php
class A {
    private $id;
    
    function __construct($id) {
        $this->id = $id;
        echo "Construct:" . $id . "\n";
    }
    
    function __destruct() {
        echo "Destructor:" . $this->id . "\n";
    }
}

function test() {
    $a = new A(1);
    $b = new A(2);
    unset($a);
    $c = new A(3);
}

test();
```

**输出**：
```
Construct:1
Construct:2
Destructor:1
Construct:3
Destructor:2
Destructor:3
```

✅ 所有析构函数按正确顺序调用
✅ unset立即触发析构
✅ 函数结束时cleanup触发析构

## 关键要点

1. **unset_var专用指令**：避免被mem2reg优化删除
2. **__construct后release**：抵消$this的额外retain
3. **cleanup release两次**：抵消store的retain + 真正的释放
4. **isNull()检查**：避免double free已unset的变量
5. **排除stored_to_alloca**：避免double free临时寄存器
6. **使用alloca_registers判断**：mem2reg后类型可能改变

## 性能影响

- **最小化**：只在unset和cleanup时增加一次release调用
- **无运行时开销**：所有逻辑在编译时确定
- **内存安全**：通过isNull()检查避免double free

## 向后兼容性

- ✅ 不影响现有代码
- ✅ 符合PHP语义
- ✅ 与解释器行为一致
