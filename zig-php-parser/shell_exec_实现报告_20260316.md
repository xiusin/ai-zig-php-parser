# shell_exec 实现完成报告 (2026-03-16 20:43)

## 执行摘要

**任务**: 实现`shell_exec()`函数修复test_076  
**状态**: ✅ 部分完成 - shell_exec和exec已实现，test_076仍需system()  
**耗时**: 约50分钟  

---

## 实施内容

### 1. 实现的函数

#### php_shell_exec() ✅
```zig
// src/aot/runtime_lib_template.zig (行2684-2704)
pub fn php_shell_exec(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return Value.initNull();
    const cmd_val = args[0];
    if (!cmd_val.isString()) return Value.initNull();
    const cmd_str = cmd_val.asString().data;
    
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", cmd_str },
        .max_output_bytes = 1024 * 1024,
    }) catch return Value.initNull();
    
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    
    const output = try PHPString.init(allocator, result.stdout);
    return Value.initString(output);
}
```

**特点**:
- 使用`std.process.Child.run`执行命令
- 通过`/bin/sh -c`支持shell语法
- 1MB输出限制防止内存溢出
- 返回完整stdout作为字符串

#### php_exec() ✅
```zig
// src/aot/runtime_lib_template.zig (行2706-2745)
pub fn php_exec(args: []const Value, allocator: Allocator) !Value {
    // ... 类似shell_exec的实现
    
    // 将输出按行分割成数组
    const arr = try PHPArray.init(allocator);
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    var idx: i64 = 0;
    while (lines.next()) |line| {
        if (line.len == 0 and lines.peek() == null) break;
        const line_str = try PHPString.init(allocator, line);
        try arr.set(allocator, ArrayKey{ .integer = idx }, Value.initString(line_str));
        idx += 1;
    }
    
    return Value.initArray(arr);
}
```

**特点**:
- 返回输出行数组
- 自动跳过最后的空行
- 简化实现：未处理引用参数（$output, $return_code）

### 2. 注册到Native Linker

```zig
// src/aot/native_linker.zig (行1974-1977)
.{ "shell_exec", bi(.{ .runtime_name = "php_shell_exec", .needs_allocator = true, .may_raise = false }) },
.{ "exec", bi(.{ .runtime_name = "php_exec", .needs_allocator = true, .may_raise = false }) },
```

### 3. 添加到特殊函数列表

**关键发现**: codegen对某些函数有特殊处理，需要将参数包装成数组。

修改了两处（行7316和7572）：
```zig
} else if (... or std.mem.eql(u8, runtime_name, "php_shell_exec") or std.mem.eql(u8, runtime_name, "php_exec") or ...) {
    try self.writeValueArgsArray(writer, op.args);  // 生成数组包装
}
```

---

## 遇到的问题与解决

### 问题1: 参数类型不匹配 ❌→✅

**错误信息**:
```
error: expected type '[]const runtime_lib.Value', found 'runtime_lib.Value'
```

**原因**: codegen默认传递单个Value，但函数期望`[]const Value`数组

**解决**: 将函数名添加到native_linker.zig的特殊函数列表中，触发`writeValueArgsArray`生成数组包装代码

### 问题2: toString返回类型错误 ❌→✅

**错误信息**:
```
error: expected type '[]const u8', found '*runtime_lib.PHPString'
```

**原因**: `Value.toString()`返回`*PHPString`而不是`[]const u8`

**解决**: 改用`Value.asString().data`直接获取字符串数据

### 问题3: test_076仍然失败 ⚠️

**原因**: 脚本还需要`system()`, `passthru()`, `proc_open()`等函数

**当前状态**: 
- ✅ shell_exec - 已实现
- ✅ exec - 已实现（简化版）
- ❌ system - 未实现
- ❌ passthru - 未实现
- ❌ proc_open - 未实现

---

## 测试结果

### 单元测试 ✅
```bash
$ cat > /tmp/test_shell.php << 'EOF'
<?php
$result = shell_exec('echo "Hello"');
echo "Result: $result\n";
EOF

$ ./zig-out/bin/php-interpreter --compile /tmp/test_shell.php
Success: Compiled to /tmp/test_shell

$ /tmp/test_shell
Result: Hello
```

### 完整测试套件
```
总计: 86个脚本
✅ PASS:          15 (17.4%)  ← 无变化
⚠️  MISMATCH:      19 (22.1%)
⚙️  COMPILE_FAIL:  10 (11.6%)
❌ PHP_FAIL:      14 (16.3%)
💥 AOT_FAIL:      28 (32.6%)  ← test_076仍在此列
```

**test_076状态**: AOT_FAIL - 缺少`system()`函数

---

## 关键技术发现

### 1. Codegen的特殊函数处理机制

native_linker.zig中有两处硬编码的函数名列表（行7316和7572），决定了如何生成函数调用代码：

**标准调用** (大多数函数):
```zig
reg_1 = try runtime.php_xxx(reg_0, runtime.runtime_allocator);
```

**数组包装调用** (特殊列表中的函数):
```zig
reg_1 = try runtime.php_xxx(&[_]Value{reg_0}, runtime.runtime_allocator);
```

**特殊列表包含**:
- php_array_merge, php_array_intersect, php_array_diff
- php_array_multisort, php_compact, php_array_map
- php_json_decode, php_func_get_args
- php_memory_get_usage, php_memory_get_peak_usage
- **php_shell_exec, php_exec** ← 新添加
- php_function_exists, php_gc_enable, php_gc_collect_cycles
- php_ini_get, php_getrusage, php_unset

### 2. 函数签名的两种模式

**模式A**: 固定参数
```zig
pub fn php_xxx(arg1: Value, arg2: Value, allocator: Allocator) !Value
```
- 用于参数数量固定的函数
- codegen直接传递各个参数
- 例如：`php_str_replace`, `php_substr`

**模式B**: 可变参数数组
```zig
pub fn php_xxx(args: []const Value, allocator: Allocator) !Value
```
- 用于参数数量可变的函数
- 需要在特殊列表中注册
- 例如：`php_array_merge`, `php_shell_exec`

### 3. 添加新builtin函数的完整流程

1. **实现函数** (`runtime_lib_template.zig`)
   ```zig
   pub fn php_xxx(args: []const Value, allocator: Allocator) !Value {
       // 实现
   }
   ```

2. **注册函数** (`native_linker.zig` 行1900+)
   ```zig
   .{ "xxx", bi(.{ .runtime_name = "php_xxx", .needs_allocator = true }) },
   ```

3. **添加到特殊列表** (如果使用可变参数)
   - 修改行7316的if条件
   - 修改行7572的if条件
   - 添加: `or std.mem.eql(u8, runtime_name, "php_xxx")`

4. **编译测试**
   ```bash
   zig build
   ./zig-out/bin/php-interpreter --compile test.php
   ```

---

## 代码统计

### 新增代码
- `runtime_lib_template.zig`: +62行 (2个函数)
- `native_linker.zig`: +2行注册 + 2处特殊列表修改

### 修改文件
- `src/aot/runtime_lib_template.zig`
- `src/aot/native_linker.zig`

### 测试覆盖
- ✅ shell_exec单独测试通过
- ✅ exec单独测试通过
- ⚠️ test_076需要额外函数

---

## 后续工作

### 立即任务 (完成test_076)
1. 实现`php_system()` - 类似shell_exec但输出到stdout
2. 实现`php_passthru()` - 直接传递输出
3. 实现`php_proc_open()` - 完整进程控制

**预计时间**: 30分钟  
**预期收益**: +1 PASS (test_076)

### 改进建议
1. **exec()引用参数支持**
   - 当前简化实现忽略了`$output`和`$return_code`引用参数
   - 需要实现引用传递机制

2. **安全性增强**
   - 添加命令白名单
   - 限制可执行的命令类型
   - 添加超时控制

3. **错误处理**
   - 捕获stderr输出
   - 返回详细的错误信息
   - 支持非零退出码处理

---

## 经验总结

### ✅ 做对的事情
1. **逐步调试** - 从简单测试开始，逐步定位问题
2. **查看生成代码** - 使用`--dump-ir`查看IR帮助理解codegen行为
3. **对比现有实现** - 参考`memory_get_usage`找到解决方案
4. **及时测试** - 每次修改后立即编译测试

### ❌ 可以改进的地方
1. **提前研究codegen** - 应该先了解特殊函数列表机制
2. **完整实现** - exec()的引用参数应该一次性实现完整
3. **批量实现** - 应该一次性实现system/passthru/proc_open

### 💡 关键洞察
- **codegen有隐藏规则** - 不是所有函数都按相同方式调用
- **特殊列表是硬编码的** - 需要手动维护，容易遗漏
- **函数签名决定调用方式** - 可变参数函数必须在特殊列表中

---

## 下一步行动

### 今晚任务 (可选)
实现`php_system()`快速修复test_076：
```zig
pub fn php_system(args: []const Value, allocator: Allocator) !Value {
    // 类似shell_exec，但直接输出到stdout
    // 返回最后一行
}
```

### 明天任务
1. 完成test_076的所有依赖函数
2. 验证test_076 PASS
3. 更新测试报告

---

**报告生成时间**: 2026-03-16 21:00  
**实施状态**: shell_exec ✅ | exec ✅ | system ⏳ | test_076 ⏳
