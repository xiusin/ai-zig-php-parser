# AOT 编译器路径问题修复报告

**日期**: 2026-03-01  
**状态**: ✅ 已修复

## 问题描述

AOT 编译器在调用 Zig 编译器时遇到 `FileNotFound` 错误，导致所有测试显示 `AOT_COMPILE_ERROR`。

### 错误现象

```bash
$ ./zig-out/bin/php-interpreter --compile test.php
Error: executable generation failed: FileNotFound
```

### 根本原因

1. **工作目录问题**: Zig 编译器需要在临时目录中运行才能找到运行时库文件
2. **相对路径问题**: `createTempDir()` 返回相对路径，但 `child.cwd` 需要绝对路径
3. **运行时库路径问题**: 运行时库文件使用相对路径读取，但当前工作目录可能不是项目根目录

## 修复方案

### 1. 修改 `createTempDir()` - 返回绝对路径

**文件**: `src/aot/native_linker.zig` (line ~278)

```zig
fn createTempDir(self: *Self) ![]const u8 {
    if (self.temp_dir) |dir| {
        return dir;
    }

    const temp_name = ".zigphp_aot_build";
    std.fs.cwd().deleteTree(temp_name) catch {};
    try std.fs.cwd().makeDir(temp_name);
    
    // 返回绝对路径（修复前返回相对路径）
    const abs_path = try std.fs.cwd().realpathAlloc(self.allocator, temp_name);
    self.temp_dir = abs_path;
    return abs_path;
}
```

### 2. 修改 `invokeZigCompiler()` - 在临时目录中运行

**文件**: `src/aot/native_linker.zig` (line ~11390)

**关键修改**:
- 使用相对路径 `main.zig`（因为在临时目录中运行）
- 设置 `child.cwd = temp_dir`（在临时目录中运行 Zig 编译器）
- 将输出路径转换为绝对路径

```zig
fn invokeZigCompiler(self: *Self, temp_dir: []const u8, output_path: []const u8) !void {
    var args = std.ArrayList([]const u8).init(self.allocator);
    defer args.deinit();

    try args.append("zig");
    try args.append("build-exe");
    try args.append("main.zig");  // 相对路径（在临时目录中）

    // 转换输出路径为绝对路径
    const abs_output_path = if (std.fs.path.isAbsolute(output_path))
        output_path
    else blk: {
        const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(cwd);
        break :blk try std.fs.path.join(self.allocator, &[_][]const u8{ cwd, output_path });
    };
    defer if (!std.fs.path.isAbsolute(output_path)) self.allocator.free(abs_output_path);
    
    const output_arg = try std.fmt.allocPrint(
        self.allocator,
        "-femit-bin={s}",
        .{abs_output_path},
    );
    defer self.allocator.free(output_arg);
    try args.append(output_arg);

    // ... 其他参数 ...

    var child = std.process.Child.init(args.items, self.allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.cwd = temp_dir;  // 在临时目录中运行

    const term = try child.spawnAndWait();
    // ... 错误处理 ...
}
```

### 3. 修改 `copyRuntimeLib()` - 多路径查找

**文件**: `src/aot/native_linker.zig` (line ~11345)

**策略**: 尝试多个可能的基础路径来查找运行时库文件

```zig
fn copyRuntimeLib(self: *Self, temp_dir: []const u8) !void {
    // 尝试多个可能的路径
    const possible_base_paths = [_][]const u8{
        ".",      // 当前目录（项目根目录）
        "..",     // 上一级目录
        "../..",  // 上两级目录
    };
    
    var found = false;
    for (possible_base_paths) |base| {
        const template_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ base, "src/aot/runtime_lib_template.zig" },
        );
        defer self.allocator.free(template_path);
        
        const template_content = std.fs.cwd().readFileAlloc(
            self.allocator,
            template_path,
            10 * 1024 * 1024,
        ) catch continue;  // 失败则尝试下一个路径
        defer self.allocator.free(template_content);

        // 写入运行时库文件
        const runtime_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ temp_dir, "runtime_lib.zig" },
        );
        defer self.allocator.free(runtime_path);

        const file = try std.fs.cwd().createFile(runtime_path, .{});
        defer file.close();
        try file.writeAll(template_content);
        
        // 复制其他运行时文件
        try self.copyOtherRuntimeFiles(temp_dir, base);
        found = true;
        break;
    }
    
    if (!found) {
        return error.FileNotFound;
    }
}
```

### 4. 新增 `copyOtherRuntimeFiles()` - 批量复制

**文件**: `src/aot/native_linker.zig` (新增函数)

```zig
fn copyOtherRuntimeFiles(self: *Self, temp_dir: []const u8, base_path: []const u8) !void {
    const files = [_]struct { src: []const u8, dst: []const u8 }{
        .{ .src = "src/aot/profiler.zig", .dst = "profiler.zig" },
        .{ .src = "src/aot/flamegraph.zig", .dst = "flamegraph.zig" },
        .{ .src = "src/aot/pprof.zig", .dst = "pprof.zig" },
        .{ .src = "src/aot/concurrency_runtime.zig", .dst = "concurrency_runtime.zig" },
        .{ .src = "src/aot/array_ops_shared.zig", .dst = "array_ops_shared.zig" },
        .{ .src = "src/aot/nanbox_abi.zig", .dst = "nanbox_abi.zig" },
    };

    for (files) |f| {
        const src_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ base_path, f.src },
        );
        defer self.allocator.free(src_path);
        
        const content = std.fs.cwd().readFileAlloc(
            self.allocator,
            src_path,
            10 * 1024 * 1024,
        ) catch continue;  // 跳过不存在的文件
        defer self.allocator.free(content);

        const dest = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ temp_dir, f.dst },
        );
        defer self.allocator.free(dest);

        const dest_file = try std.fs.cwd().createFile(dest, .{});
        defer dest_file.close();
        try dest_file.writeAll(content);
    }
}
```

## 测试结果

### 修复前
```
总测试数: 108
通过: 0
AOT编译错误: 108
```

### 修复后
```
总测试数: 108
通过: 32 (29.6%)
解释器不匹配: 69 (63.9%)
AOT编译错误: 7 (6.5%)
结果不匹配: 0
```

### 成功案例

```bash
# test_1.php - 循环求和
$ ./zig-out/bin/php-interpreter --compile --output=test_1_aot iflow_scripts/test_1.php
Success: Compiled to test_1_aot

$ ./test_1_aot
750

# test_1000000.php - 平方和
$ ./zig-out/bin/php-interpreter --compile --output=test_aot iflow_scripts/test_1000000.php
Success: Compiled to test_aot

$ ./test_aot
2870
```

### 剩余的 AOT 编译错误

以下 7 个测试仍有编译错误，但这些是**功能性问题**（缺少内置函数实现），不是路径问题：

| 测试 | 原因 | 缺少的函数 |
|------|------|-----------|
| test_1000025 | 数组操作 | `array_splice` |
| test_1000031 | 数学函数 | `intdiv` |
| test_1000036 | 数学函数 | `round` |
| test_1000062 | 循环优化 | 编译器优化问题 |
| test_1000071 | 数组操作 | `array_slice` |
| test_1000082 | 数组操作 | `array_count_values` |
| test_1000083 | 数组操作 | `array_count_values` |

## 影响范围

### 修改的文件
- `src/aot/native_linker.zig` (3 个函数修改 + 1 个新函数)

### 不影响的功能
- 解释器模式（完全不受影响）
- 其他 AOT 编译器功能（代码生成、优化等）

## 验证清单

- [x] 从项目根目录编译 PHP 文件
- [x] 从子目录编译 PHP 文件
- [x] 编译后的程序输出正确
- [x] 临时目录正确创建和清理
- [x] 运行时库文件正确复制
- [x] 所有路径问题已解决
- [x] 移除所有调试代码

## 后续工作

### 高优先级
1. 实现缺少的内置函数（`intdiv`, `round`, `array_splice` 等）
2. 修复解释器不匹配问题（69 个测试）

### 中优先级
3. 优化临时目录管理（考虑使用系统临时目录）
4. 添加更详细的错误信息
5. 支持增量编译

### 低优先级
6. 添加 AOT 编译器性能测试
7. 优化编译速度
8. 支持交叉编译

## 总结

✅ **AOT 编译器路径问题已完全修复**

- 修复了临时目录路径问题
- 修复了运行时库文件查找问题
- 修复了 Zig 编译器工作目录问题
- AOT 编译成功率从 0% 提升到 93.5%（101/108）
- 剩余 7 个错误是功能性问题，不是路径问题

**核心改进**: 
1. 使用绝对路径管理临时目录
2. 在临时目录中运行 Zig 编译器
3. 多路径查找运行时库文件
4. 正确处理相对/绝对路径转换
