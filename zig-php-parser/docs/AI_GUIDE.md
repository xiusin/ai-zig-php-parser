# 给 AI 助手的指引

如果你是另一个 AI 助手，接手这个项目来修复模糊测试发现的问题，请阅读本文档。

---

## 🎯 你的任务

修复 AOT 编译器的模糊测试问题，使其达到生产可用状态。

---

## 📚 必读文档（按顺序）

1. **[fuzzy_test_quickref.md](fuzzy_test_quickref.md)** (2 分钟)
   - 了解问题全貌
   - 关键数字和优先级

2. **[fuzzy_test_summary.md](fuzzy_test_summary.md)** (10 分钟)
   - 详细的问题分类
   - 修复时间表
   - 立即行动项

3. **[foreach_implementation_plan.md](foreach_implementation_plan.md)** (15 分钟)
   - foreach 循环的详细实现方案
   - 这是 P0 优先级任务

---

## ⚠️ 重要提示

### 不要被数字吓到

测试报告显示 1566 个"错误"，但：
- **~1400 个是误判**（调试输出被当作错误）
- **90 个是测试生成器的问题**（生成了无效 PHP 代码）
- **真正的问题只有 ~140 个**

### 核心功能是稳定的

AOT 编译器的核心功能（基础语法、控制流、函数、数组）都工作正常。主要问题是：
1. **功能缺失**（foreach、内置函数）
2. **少量 bug**（~30 个）

### 优先级清晰

| 优先级 | 任务 | 为什么 |
|--------|------|--------|
| P0 | 实现 foreach 循环 | 阻塞性问题，影响基本可用性 |
| P1 | 实现 10 个常用内置函数 | 提升实用性 |
| P2 | 修复其他 bug | 改善稳定性 |

---

## 🚀 开始工作

### 第一步：实现 foreach 循环

**为什么先做这个？**
- P0 优先级
- 阻塞 3 个测试
- 是基础语法，必须支持

**怎么做？**
1. 阅读 [foreach_implementation_plan.md](foreach_implementation_plan.md)
2. 按照计划的 3 个阶段实施：
   - 阶段 1: VM 实现（4-6 小时）
   - 阶段 2: AOT 实现（4-6 小时）
   - 阶段 3: 优化和测试（2-4 小时）

**测试用例**:
```php
// test_7.php
<?php
$assoc = ["a" => 1, "b" => 2, "c" => 3];
$sum = 0;
foreach ($assoc as $key => $value) {
    $sum += $value;
}
echo $sum;
?>
```

**验证**:
```bash
cd /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser
./zig-out/bin/php-interpreter iflow_scripts/test_7.php
# 应该输出: 6
```

### 第二步：实现 count() 函数

**为什么？**
- P1 优先级
- 最常用的函数之一
- 实现简单，可以快速见效

**怎么做？**
1. 在 `src/runtime/stdlib.zig` 中添加 `count()` 函数
2. 在 AOT 中添加支持
3. 测试验证

**测试用例**:
```php
<?php
$arr = [1, 2, 3, 4, 5];
echo count($arr);
?>
```

### 第三步：实现 implode() 函数

**为什么？**
- P1 优先级
- 被使用 16 次（最多）
- 解决多个测试失败

**怎么做？**
1. 在 `src/runtime/stdlib.zig` 中添加 `implode()` 函数
2. 在 AOT 中添加支持
3. 测试验证

### 第四步：继续实现其他函数

按照 [fuzzy_test_summary.md](fuzzy_test_summary.md) 中的优先级列表继续实现。

---

## 🔧 开发环境

### 编译项目

```bash
cd /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser
rm -rf .zig-cache zig-out
zig build
```

### 测试单个文件

```bash
# 解释器模式
./zig-out/bin/php-interpreter test.php

# AOT 编译
./zig-out/bin/php-interpreter --compile --output=/tmp/test_aot test.php
/tmp/test_aot
```

### 对比输出

```bash
php test.php > /tmp/php_out.txt
./zig-out/bin/php-interpreter --compile --output=/tmp/test_aot test.php
/tmp/test_aot > /tmp/aot_out.txt
diff /tmp/php_out.txt /tmp/aot_out.txt
```

---

## 📁 关键文件

### VM 相关
- `src/runtime/vm.zig` - VM 执行引擎
- `src/runtime/stdlib.zig` - 内置函数
- `src/bytecode/instruction.zig` - 指令定义

### AOT 相关
- `src/aot/ir_generator.zig` - IR 生成
- `src/aot/native_linker.zig` - 代码生成
- `src/aot/compiler.zig` - AOT 编译器入口

### 解析器相关
- `src/compiler/parser.zig` - 语法解析
- `src/compiler/ast.zig` - AST 定义
- `src/bytecode/generator.zig` - 字节码生成

---

## 🐛 调试技巧

### 查看 IR

```bash
./zig-out/bin/php-interpreter --compile --dump-ir test.php 2>&1 | grep -A 20 "=== IR Dump ==="
```

### 查看生成的代码

```bash
cat .zigphp_aot_build/main.zig
```

### 查看编译错误

```bash
./zig-out/bin/php-interpreter --compile --output=/tmp/test_aot test.php 2>&1 | grep "error:"
```

---

## ✅ 完成标准

### 第一阶段完成标准

- [ ] foreach 循环可用（test_7, test_30, test_39 通过）
- [ ] count() 函数可用
- [ ] implode() 函数可用
- [ ] explode() 函数可用
- [ ] printf() 函数可用
- [ ] 至少 20 个测试从失败变为通过

### 第二阶段完成标准

- [ ] 15+ 个内置函数可用
- [ ] 主要 bug 已修复
- [ ] 至少 50 个测试从失败变为通过
- [ ] 达到生产可用状态

---

## 📊 进度跟踪

### 建议的工作流程

1. **每完成一个功能**:
   - 运行相关测试
   - 更新 `docs/README.md` 中的进度
   - 提交 git commit

2. **每天结束时**:
   - 总结完成的工作
   - 记录遇到的问题
   - 计划明天的任务

3. **每周结束时**:
   - 运行完整的测试套件
   - 更新文档
   - 评估进度

---

## 💡 提示

### 实现内置函数的模板

```zig
// src/runtime/stdlib.zig

pub fn count(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        return error.InvalidArgumentCount;
    }
    
    const arr = args[0];
    if (arr.tag != .array) {
        return Value.initInt(1); // 非数组返回 1
    }
    
    const len = arr.data.array.items.len;
    return Value.initInt(@intCast(i64, len));
}
```

### 添加到函数表

```zig
// src/runtime/stdlib.zig

pub const builtin_functions = std.ComptimeStringMap(*const BuiltinFunction, .{
    // ... 其他函数 ...
    .{ "count", count },
});
```

### AOT 支持

```zig
// src/aot/native_linker.zig

// 在 generateFunctionCall 中添加
if (std.mem.eql(u8, func_name, "count")) {
    try writer.writeAll("runtime.count(");
    // ... 生成参数 ...
    try writer.writeAll(")");
}
```

---

## 🎯 最终目标

**让 AOT 编译器达到生产可用状态**

具体指标：
- ✅ foreach 循环可用
- ✅ 10+ 个常用内置函数可用
- ✅ 主要 bug 已修复
- ✅ 测试通过率 > 90%

---

## 📞 需要帮助？

如果遇到问题：
1. 查看相关文档
2. 查看已有的实现（如 `for` 循环）
3. 查看测试用例
4. 提交 issue

---

**祝你成功！** 🚀

---

**文档维护**: xiusin  
**最后更新**: 2026-02-28
