# 优先级修复清单

**创建日期**: 2026-01-19  
**基于**: 任务 21-34 全面审查报告

---

## 🔴 P0 - 立即修复（阻塞性问题）

### ✅ 1. 更新任务 6 状态
- **状态**: ✅ 已完成
- **操作**: 已将任务 6 从 `[-]` 更新为 `[x]`
- **验证**: 类型推断引擎已完全实现并测试通过

---

### ❌ 2. 修复 GC 标记阶段简化实现

#### 问题 2.1: OldGeneration.markPhase
**文件**: `src/runtime/advanced_memory.zig:222-224`

**当前问题**:
```zig
fn markPhase(self: *OldGeneration) void {
    // 简化实现：假设所有对象都是可达的
    for (self.objects.items) |*obj| {
        obj.marked = true;
```

**影响**: 🔴 严重 - 所有对象被标记为可达，无法回收任何垃圾对象

**需求**: 4.6 - 完整的 GC 标记算法

**修复方案**:
```zig
fn markPhase(self: *OldGeneration) !void {
    // 1. 清除所有标记
    for (self.objects.items) |*obj| {
        obj.marked = false;
    }
    
    // 2. 创建工作列表
    var worklist = std.ArrayList(*Object).init(self.allocator);
    defer worklist.deinit();
    
    // 3. 添加根对象
    try self.addRoots(&worklist);
    
    // 4. 标记可达对象（深度优先遍历）
    while (worklist.popOrNull()) |obj| {
        if (obj.marked) continue;
        obj.marked = true;
        
        // 扫描对象的所有引用字段
        try self.scanObjectReferences(obj, &worklist);
    }
}

fn addRoots(self: *OldGeneration, worklist: *std.ArrayList(*Object)) !void {
    // 添加栈上的对象
    // 添加全局变量中的对象
    // 添加寄存器中的对象
    // 添加跨代引用（从年轻代到老年代）
}

fn scanObjectReferences(
    self: *OldGeneration,
    obj: *Object,
    worklist: *std.ArrayList(*Object)
) !void {
    switch (obj.type_) {
        .array => |arr| {
            for (arr.elements) |elem| {
                if (elem.isObject()) {
                    try worklist.append(elem.asObject());
                }
            }
        },
        .object => |o| {
            var iter = o.properties.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.isObject()) {
                    try worklist.append(entry.value_ptr.asObject());
                }
            }
        },
        .closure => |closure| {
            for (closure.captured_vars) |var_| {
                if (var_.isObject()) {
                    try worklist.append(var_.asObject());
                }
            }
        },
        else => {},
    }
}
```

**测试验证**:
```bash
zig test src/runtime/test_generational_gc_properties.zig
zig test src/runtime/test_gc_marking_properties.zig
```

---

#### 问题 2.2: Compactor.markPhase
**文件**: `src/runtime/advanced_memory.zig:764-767`

**当前问题**:
```zig
fn markPhase(self: *Compactor) !void {
    // 标记所有对象（简化：假设所有对象都可达）
    // 在实际实现中，这里会从根集合开始遍历对象图
```

**影响**: 🔴 严重 - 压缩 GC 无法正确识别垃圾对象

**需求**: 4.3 - 完整的压缩 GC

**修复方案**: 与 2.1 类似，实现完整的根集合遍历和对象图追踪

---

### ❌ 3. 修复压缩 GC 引用更新

#### 问题 3.1: Compactor.updateReferences
**文件**: `src/runtime/advanced_memory.zig:793-796`

**当前问题**:
```zig
fn updateReferences(self: *Compactor) !void {
    // 这里是简化实现
    _ = self;
}
```

**影响**: 🔴 严重 - 压缩后所有引用失效，程序崩溃

**需求**: 4.3 - 完整的引用更新

**修复方案**:
```zig
fn updateReferences(self: *Compactor) !void {
    // 1. 更新根集合中的引用
    try self.updateRootReferences();
    
    // 2. 更新所有存活对象内部的引用
    for (self.memory_regions.items) |*region| {
        var ptr: [*]u8 = region.start;
        
        while (@ptrToInt(ptr) < @ptrToInt(region.end)) {
            const obj = @ptrCast(*Object, @alignCast(@alignOf(Object), ptr));
            
            if (obj.marked) {
                // 更新对象内部的所有引用字段
                try self.updateObjectReferences(obj);
            }
            
            ptr += obj.size();
        }
    }
}

fn updateRootReferences(self: *Compactor) !void {
    // 更新栈上的引用
    // 更新全局变量中的引用
    // 更新寄存器中的引用
}

fn updateObjectReferences(self: *Compactor, obj: *Object) !void {
    switch (obj.type_) {
        .array => |*arr| {
            for (arr.elements) |*elem| {
                if (elem.isObject()) {
                    const old_ptr = elem.asObject();
                    if (self.forwarding_map.get(old_ptr)) |new_ptr| {
                        elem.* = Value.initObject(new_ptr);
                    }
                }
            }
        },
        .object => |*o| {
            var iter = o.properties.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.isObject()) {
                    const old_ptr = entry.value_ptr.asObject();
                    if (self.forwarding_map.get(old_ptr)) |new_ptr| {
                        entry.value_ptr.* = Value.initObject(new_ptr);
                    }
                }
            }
        },
        .closure => |*closure| {
            for (closure.captured_vars) |*var_| {
                if (var_.isObject()) {
                    const old_ptr = var_.asObject();
                    if (self.forwarding_map.get(old_ptr)) |new_ptr| {
                        var_.* = Value.initObject(new_ptr);
                    }
                }
            }
        },
        else => {},
    }
}
```

**测试验证**:
```bash
zig test src/runtime/test_compacting_gc_properties.zig
zig test src/runtime/test_compactor_integration.zig
```

---

#### 问题 3.2: CompactingGC 对象扫描
**文件**: `src/runtime/compacting_gc.zig:461-464`

**当前问题**:
```zig
if (obj.alive) {
    // 这里应该扫描对象内部，更新所有引用
    // 暂时简化实现
    _ = obj;
}
```

**影响**: 🔴 严重 - 压缩后对象内部引用失效

**修复方案**: 实现完整的对象内部引用扫描和更新（参考 3.1）

---

### ❌ 4. 修复 AOT 可执行文件生成

**文件**: `src/aot/multi_file_compiler.zig:514-516`

**当前问题**:
```zig
// Write a placeholder (in real implementation, this would be the executable)
try file.writeAll("#!/bin/sh\necho 'Compiled PHP program'\n");
```

**影响**: 🔴 严重 - AOT 编译器无法生成可用的可执行文件

**需求**: 3.1 - AOT 编译器完整实现

**修复方案**:
```zig
pub fn generateExecutable(
    self: *MultiFileCompiler,
    output_path: []const u8
) !void {
    // 1. 生成 LLVM IR
    const llvm_ir = try self.generateLLVMIR();
    defer self.allocator.free(llvm_ir);
    
    // 2. 编译为目标文件
    const obj_file = try self.compileToObject(llvm_ir);
    defer std.fs.cwd().deleteFile(obj_file) catch {};
    
    // 3. 链接生成可执行文件
    try self.linkExecutable(obj_file, output_path);
}

fn compileToObject(self: *MultiFileCompiler, llvm_ir: []const u8) ![]const u8 {
    // 使用 LLVM 后端编译为目标文件
    const obj_path = try std.fmt.allocPrint(
        self.allocator,
        "{s}.o",
        .{self.temp_dir}
    );
    
    // 调用 LLVM API 或 llc 命令
    // llc -filetype=obj -o output.o input.ll
    
    return obj_path;
}

fn linkExecutable(
    self: *MultiFileCompiler,
    obj_file: []const u8,
    output_path: []const u8
) !void {
    // 根据目标平台选择链接器
    const linker = switch (self.target.os) {
        .linux => "ld",
        .macos => "ld",
        .windows => "link.exe",
        else => return error.UnsupportedPlatform,
    };
    
    // 构建链接命令
    var argv = std.ArrayList([]const u8).init(self.allocator);
    defer argv.deinit();
    
    try argv.append(linker);
    try argv.append(obj_file);
    try argv.append("-o");
    try argv.append(output_path);
    
    // 添加运行时库
    try argv.append("-lzigphp_runtime");
    
    // 执行链接
    const result = try std.ChildProcess.exec(.{
        .allocator = self.allocator,
        .argv = argv.items,
    });
    defer self.allocator.free(result.stdout);
    defer self.allocator.free(result.stderr);
    
    if (result.term.Exited != 0) {
        return error.LinkFailed;
    }
}
```

**测试验证**:
```bash
zig test src/aot/test_e2e_cross_platform.zig
zig test src/aot/test_e2e_roundtrip.zig
```

---

## 🟡 P1 - 尽快修复（功能性问题）

### ❌ 5. 实现完整的 scandir

**文件**: `src/runtime/stdlib_ext.zig:304-306`

**当前问题**:
```zig
// 简化实现 - 返回空数组
return Value.initArrayWithManager(&vm.memory_manager);
```

**影响**: 🟡 高 - scandir 函数不可用

**需求**: 5.1 - 完整的文件系统函数

**修复方案**:
```zig
pub fn scandir(vm: *VM, args: []const Value) VMError!Value {
    if (args.len < 1) return error.InvalidArguments;
    
    const dir_path = args[0].getAsString().data.data;
    
    // 打开目录
    var dir = std.fs.cwd().openIterableDir(dir_path, .{}) catch {
        return Value.initArrayWithManager(&vm.memory_manager);
    };
    defer dir.close();
    
    // 创建结果数组
    var result = try Value.initArrayWithManager(&vm.memory_manager);
    var array = result.getAsArray();
    
    // 遍历目录项
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // 创建文件名字符串
        const name = try vm.memory_manager.allocator.dupe(u8, entry.name);
        const name_value = try Value.initStringWithManager(
            &vm.memory_manager,
            name
        );
        
        // 添加到数组
        try array.append(name_value);
    }
    
    // 排序（可选）
    if (args.len >= 2 and args[1].getAsInt() == 0) {
        // SCANDIR_SORT_ASCENDING
        std.sort.sort(Value, array.items, {}, compareStrings);
    }
    
    return result;
}

fn compareStrings(context: void, a: Value, b: Value) bool {
    _ = context;
    const a_str = a.getAsString().data.data;
    const b_str = b.getAsString().data.data;
    return std.mem.order(u8, a_str, b_str) == .lt;
}
```

**测试验证**:
```bash
zig test src/runtime/test_filesystem_complete.zig
```

---

### ❌ 6. 完善 strtotime 实现

**文件**: `src/runtime/time.zig:967-973`

**当前问题**:
```zig
/// PHP strtotime() - 解析日期时间字符串（简化实现）
pub fn phpStrtotime(datetime: []const u8, base_time: ?i64) !i64 {
    // 简化实现：只支持一些常见格式
    if (std.mem.eql(u8, datetime, "now")) {
        return base.getUnix();
```

**影响**: 🟡 高 - 大部分日期格式无法解析

**需求**: 5.3 - 完整的 strtotime

**修复方案**:
```zig
pub fn phpStrtotime(datetime: []const u8, base_time: ?i64) !i64 {
    const base = if (base_time) |ts| Time.unix(ts, 0) else Time.now();
    
    // 1. 处理特殊关键字
    if (std.mem.eql(u8, datetime, "now")) return base.getUnix();
    if (std.mem.eql(u8, datetime, "today")) {
        return Time.startOfDay(base).getUnix();
    }
    if (std.mem.eql(u8, datetime, "tomorrow")) {
        return Time.addDays(Time.startOfDay(base), 1).getUnix();
    }
    if (std.mem.eql(u8, datetime, "yesterday")) {
        return Time.addDays(Time.startOfDay(base), -1).getUnix();
    }
    
    // 2. 处理相对时间（"+1 day", "-2 weeks"）
    if (datetime[0] == '+' or datetime[0] == '-') {
        return try parseRelativeTime(datetime, base);
    }
    
    // 3. 处理时间戳（"@1234567890"）
    if (datetime[0] == '@') {
        return try std.fmt.parseInt(i64, datetime[1..], 10);
    }
    
    // 4. 尝试各种日期格式
    const formats = [_][]const u8{
        "Y-m-d H:i:s",      // 2024-01-01 12:00:00
        "Y-m-d",            // 2024-01-01
        "d/m/Y",            // 01/01/2024
        "m/d/Y",            // 01/01/2024
        "Y/m/d",            // 2024/01/01
        "d-m-Y",            // 01-01-2024
        "M d, Y",           // Jan 1, 2024
        "d M Y",            // 1 Jan 2024
    };
    
    for (formats) |format| {
        if (try parseDateTime(datetime, format)) |time| {
            return time.getUnix();
        }
    }
    
    return error.InvalidDateFormat;
}

fn parseRelativeTime(datetime: []const u8, base: Time) !i64 {
    // 解析 "+1 day", "-2 weeks" 等格式
    // 实现细节...
}

fn parseDateTime(datetime: []const u8, format: []const u8) !?Time {
    // 根据格式解析日期时间字符串
    // 实现细节...
}
```

**测试验证**:
```bash
zig test src/runtime/builtin_time.zig
```

---

### ❌ 7. 实现多文件编译器 IR 生成

**文件**: `src/aot/multi_file_compiler.zig:348-351`

**当前问题**:
```zig
// For now, we'll create a placeholder module since we don't have
// the actual parser integration here. In a real implementation,
// we would parse the source and generate IR.
```

**影响**: 🟡 高 - 无法编译多文件项目

**需求**: 3.5 - 跨文件链接

**修复方案**:
```zig
fn compileFile(
    self: *MultiFileCompiler,
    source_path: []const u8
) !*IRModule {
    // 1. 读取源文件
    const source = try std.fs.cwd().readFileAlloc(
        self.allocator,
        source_path,
        10 * 1024 * 1024 // 10MB max
    );
    defer self.allocator.free(source);
    
    // 2. 解析源代码
    const parser = @import("../compiler/parser.zig");
    var p = parser.Parser.init(self.allocator, source);
    defer p.deinit();
    
    const ast = try p.parse();
    defer ast.deinit();
    
    // 3. 生成 IR
    var ir_gen = IRGenerator.init(self.allocator);
    defer ir_gen.deinit();
    
    const ir_module = try ir_gen.generate(ast);
    
    // 4. 注册模块
    try self.modules.put(source_path, ir_module);
    
    return ir_module;
}
```

**测试验证**:
```bash
zig test src/aot/test_linker_property.zig
```

---

## 🟢 P2 - 可以延后（优化性问题）

### ❌ 8. 完善日期时间精度

**文件**: `src/runtime/datetime_complete.zig:132-138`

**当前问题**:
- 微秒固定为 0
- 毫秒固定为 0
- 时区固定为 UTC
- 无夏令时处理

**影响**: 🟢 中 - 时间精度和时区处理不准确

**需求**: 5.2 - 完整的 date 格式化

**修复方案**:
```zig
// 获取真实的微秒/毫秒
'u' => {
    const micros = @mod(timestamp * 1_000_000, 1_000_000);
    try result.writer().print("{d:0>6}", .{micros});
},
'v' => {
    const millis = @mod(timestamp * 1000, 1000);
    try result.writer().print("{d:0>3}", .{millis});
},

// 获取真实的时区
'e' => {
    const tz = try getSystemTimezone();
    try result.appendSlice(tz);
},
'I' => {
    const is_dst = try isDaylightSavingTime(timestamp);
    try result.append(if (is_dst) '1' else '0');
},
```

---

### ❌ 9. 优化 JIT 内联决策

**文件**: `src/jit/codegen_x64.zig:228-231`

**当前问题**:
```zig
// 简化版本：总是内联小函数
return true;
```

**影响**: 🟢 中 - 可能导致代码膨胀

**需求**: 2.4 - 方法内联

**修复方案**:
```zig
fn shouldInline(self: *CodeGenX64, func: *const CompiledFunction) bool {
    // 1. 检查函数大小
    if (func.instructions.len > self.max_inline_size) {
        return false;
    }
    
    // 2. 检查调用频率
    if (self.hotspot_detector.getCallCount(func.name) < self.min_inline_calls) {
        return false;
    }
    
    // 3. 检查递归
    if (self.isRecursive(func)) {
        return false;
    }
    
    // 4. 计算内联成本
    const cost = self.calculateInlineCost(func);
    const benefit = self.calculateInlineBenefit(func);
    
    return benefit > cost * 1.5; // 收益必须超过成本 50%
}
```

---

## 📊 进度跟踪

### 总体进度
- [ ] P0 问题: 0/4 完成 (0%)
- [ ] P1 问题: 0/3 完成 (0%)
- [ ] P2 问题: 0/2 完成 (0%)

### P0 详细进度
- [x] 1. 更新任务 6 状态 ✅
- [ ] 2. 修复 GC 标记阶段
  - [ ] 2.1 OldGeneration.markPhase
  - [ ] 2.2 Compactor.markPhase
- [ ] 3. 修复压缩 GC 引用更新
  - [ ] 3.1 Compactor.updateReferences
  - [ ] 3.2 CompactingGC 对象扫描
- [ ] 4. 修复 AOT 可执行文件生成

### P1 详细进度
- [ ] 5. 实现完整的 scandir
- [ ] 6. 完善 strtotime 实现
- [ ] 7. 实现多文件编译器 IR 生成

### P2 详细进度
- [ ] 8. 完善日期时间精度
- [ ] 9. 优化 JIT 内联决策

---

## 📝 注意事项

1. **测试优先**: 每个修复都必须有对应的测试验证
2. **增量修复**: 一次修复一个问题，避免引入新的 bug
3. **代码审查**: 所有修复都应该经过代码审查
4. **文档更新**: 修复后更新相关文档
5. **性能测试**: 修复后运行性能基准测试

---

**最后更新**: 2026-01-19  
**下次更新**: 修复完成后
