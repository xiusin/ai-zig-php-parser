# AOT快速修复指南

## 🎯 修复优先级

### P0 - 关键问题 (影响30个测试，69.8%)

#### 问题：数组函数返回值无法被 print_r() 输出

**影响函数**:
- `array_map()`
- `array_filter()`
- `sort()` / `rsort()`
- `explode()`

**修复位置**: `src/runtime/stdlib.zig` 或 `src/aot/runtime_lib.zig`

**修复步骤**:

1. **检查数组类型标记**
```zig
// 确保所有返回数组的函数都正确设置类型标记
pub fn array_map(...) !Value {
    const result = try allocator.create(PHPArray);
    result.* = PHPArray.init(allocator);
    
    // 关键：确保类型标记正确
    return Value{
        .tag = .array,  // ← 检查这里
        .data = .{ .array = result },
    };
}
```

2. **检查 print_r() 实现**
```zig
pub fn print_r(value: Value) void {
    switch (value.tag) {
        .array => {
            const arr = value.data.array;
            // 检查这里是否能正确遍历所有类型的数组
            for (arr.items) |item, i| {
                // ...
            }
        },
        // ...
    }
}
```

3. **验证修复**
```bash
cd fuzzy_scripts
php test_0040_array_ops.php > expected.txt
./test_0040_array_ops > actual.txt
diff expected.txt actual.txt
```

---

### P1 - 重要问题 (影响12个测试，27.9%)

#### 问题：闭包 static 变量编译错误

**错误信息**:
```
warning: unable to open library directory '/usr/local/lib': FileNotFound
```

**修复位置**: `build.zig` 或 `src/aot/linker.zig`

**修复步骤**:

1. **检查链接器配置**
```zig
// build.zig
const exe = b.addExecutable(.{
    .name = "output",
    .root_source_file = .{ .path = "generated.zig" },
    .target = target,
    .optimize = optimize,
});

// 添加正确的库路径
exe.addLibraryPath(.{ .path = "/usr/lib" });  // macOS 使用这个
// exe.addLibraryPath(.{ .path = "/usr/local/lib" });  // 如果存在
```

2. **或者使用条件编译**
```zig
if (builtin.os.tag == .macos) {
    exe.addLibraryPath(.{ .path = "/usr/lib" });
} else if (builtin.os.tag == .linux) {
    exe.addLibraryPath(.{ .path = "/usr/lib" });
    exe.addLibraryPath(.{ .path = "/usr/local/lib" });
}
```

3. **验证修复**
```bash
./zig-out/bin/php-interpreter --compile fuzzy_scripts/test_0119_closures_param.php
# 应该编译成功，无错误
./test_0119_closures_param
# 应该输出: 18\n19\n20
```

---

### P2 - 次要问题 (影响1个测试，2.3%)

#### 问题：数组转 int/float 返回0而非1

**PHP规则**: 非空数组转数值类型应返回 `1`

**修复位置**: `src/runtime/types.zig` 或 `src/aot/type_inference.zig`

**修复步骤**:

1. **检查类型转换实现**
```zig
pub fn toInt(value: Value) i64 {
    return switch (value.tag) {
        .int => value.data.int,
        .float => @intFromFloat(value.data.float),
        .bool => if (value.data.bool) 1 else 0,
        .string => parseInt(value.data.string) catch 0,
        .array => if (value.data.array.items.len > 0) 1 else 0,  // ← 修复这里
        .null => 0,
        else => 0,
    };
}
```

2. **验证修复**
```bash
php -r '$x=[1,2,3]; echo (int)$x;'  # 输出: 1
./test_0005_type_conversions | grep "^1,1,"  # 应该匹配
```

---

## 🔧 快速验证脚本

创建 `verify_fix.sh`:

```bash
#!/bin/bash

echo "验证修复..."

# P0: 数组输出
echo "测试 array_map..."
php fuzzy_scripts/test_0154_array_functions.php > /tmp/php.out
./fuzzy_scripts/test_0154_array_functions > /tmp/aot.out 2>&1
if diff -q /tmp/php.out /tmp/aot.out > /dev/null; then
    echo "✅ array_map 修复成功"
else
    echo "❌ array_map 仍有问题"
fi

echo "测试 sort..."
php fuzzy_scripts/test_0040_array_ops.php > /tmp/php.out
./fuzzy_scripts/test_0040_array_ops > /tmp/aot.out 2>&1
if diff -q /tmp/php.out /tmp/aot.out > /dev/null; then
    echo "✅ sort 修复成功"
else
    echo "❌ sort 仍有问题"
fi

# P1: 闭包编译
echo "测试闭包编译..."
if ./zig-out/bin/php-interpreter --compile fuzzy_scripts/test_0119_closures_param.php 2>&1 | grep -q "COMPILE_ERROR"; then
    echo "❌ 闭包编译仍有问题"
else
    echo "✅ 闭包编译修复成功"
fi

# P2: 类型转换
echo "测试类型转换..."
php fuzzy_scripts/test_0005_type_conversions.php > /tmp/php.out
./fuzzy_scripts/test_0005_type_conversions > /tmp/aot.out 2>&1
if diff -q /tmp/php.out /tmp/aot.out > /dev/null; then
    echo "✅ 类型转换修复成功"
else
    echo "❌ 类型转换仍有问题"
fi

echo ""
echo "完整回归测试:"
python3 fuzzy_test_runner.py
```

---

## 📊 修复进度追踪

创建 `FIXES.md` 记录修复进度：

```markdown
# 修复进度

## P0 - 数组输出 (30个测试)

- [ ] 修复 array_map() 返回值类型标记
- [ ] 修复 array_filter() 返回值类型标记
- [ ] 修复 sort() 后的数组结构
- [ ] 修复 rsort() 后的数组结构
- [ ] 修复 explode() 返回值类型标记
- [ ] 统一 print_r() 对所有数组类型的支持
- [ ] 验证所有30个测试通过

## P1 - 闭包与字符串 (12个测试)

- [ ] 修复链接器库路径配置
- [ ] 验证闭包 static 变量编译
- [ ] 验证所有12个测试通过

## P2 - 类型转换 (1个测试)

- [ ] 修复数组到 int 的转换
- [ ] 修复数组到 float 的转换
- [ ] 验证测试通过

## 最终验证

- [ ] 运行完整回归测试
- [ ] 通过率 ≥ 98%
- [ ] 无新增失败测试
```

---

## 🚀 一键修复验证

修复后运行：

```bash
# 1. 重新编译
zig build

# 2. 重新编译所有失败的测试
cd fuzzy_scripts
for f in test_*.php; do
    ../zig-out/bin/php-interpreter --compile "$f" 2>&1 | grep -q "COMPILE_ERROR" || echo "✓ $f"
done

# 3. 运行完整测试
cd ..
python3 fuzzy_test_runner.py

# 4. 查看结果
cat fuzzy_test_report.json | python3 -m json.tool | grep -A 2 '"passed"'
```

---

## 📝 提交检查清单

修复完成后，确保：

- [ ] 所有修复的测试通过
- [ ] 无新增失败测试
- [ ] 通过率 ≥ 98%
- [ ] 代码符合宪法规范（性能、内存安全、线程安全）
- [ ] 添加了相应的单元测试
- [ ] 更新了文档
- [ ] 运行了 `zig build test`
- [ ] 运行了内存检查 (valgrind/ASan)
