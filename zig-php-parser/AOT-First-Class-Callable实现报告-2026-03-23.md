# AOT First-Class Callable 实现报告

**日期**: 2026-03-23  
**功能**: PHP 8.1 First-Class Callable 语法支持  
**状态**: 解析完成，运行时待修复

---

## 📊 实现概览

实现了 PHP 8.1 的 first-class callable 语法 `$obj->method(...)` 的解析器支持，将其转换为等价的闭包表达式。

### 语法转换

```php
// 原始语法
$add = $obj->add(...);

// 转换为
$add = fn(...$args) => $obj->add(...$args);
```

---

## ✅ 已完成工作

### 1. 解析器修改

**文件**: `src/compiler/parser.zig`

**修改位置**: 两处方法调用解析逻辑
- Line ~2143-2180: `parseUnary()` 中的方法调用处理
- Line ~2509-2546: `parseUnaryPostfix()` 中的方法调用处理

**实现逻辑**:
1. 检测 `(...)` 模式（左括号 + ellipsis + 右括号）
2. 创建可变参数 `...$args`
3. 创建变量引用 `$args`
4. 创建参数解包表达式 `...$args`
5. 创建方法调用 `$obj->method(...$args)`
6. 包装为箭头函数 `fn(...$args) => ...`

**代码示例**:
```zig
// 检查是否是 first-class callable: $obj->method(...)
if (self.curr.tag == .ellipsis) {
    self.nextToken();
    _ = try self.eat(.r_paren);
    
    // 1. 创建可变参数 ...$args
    const args_var_id = try self.context.intern("args");
    const args_param = try self.createNode(.{ 
        .tag = .parameter, 
        .main_token = op, 
        .data = .{ .parameter = .{ 
            .attributes = &.{}, 
            .name = args_var_id, 
            .type = null, 
            .default_value = null, 
            .is_promoted = false, 
            .modifiers = .{}, 
            .is_variadic = true, 
            .is_reference = false 
        } } 
    });
    
    // 2-5. 创建闭包体
    // ...
    
    // 6. 创建箭头函数
    left = try self.createNode(.{ 
        .tag = .arrow_function, 
        .main_token = op, 
        .data = .{ .arrow_function = .{ 
            .attributes = &.{}, 
            .params = &[_]ast.Node.Index{args_param}, 
            .return_type = null, 
            .body = method_call, 
            .is_static = false 
        } } 
    });
}
```

---

## ⚠️ 已知问题

### 运行时参数传递错误

**问题描述**: 
- 闭包成功创建和调用
- 但参数传递不正确
- 测试用例 `$add(5, 3)` 返回 `0` 而不是 `8`

**测试结果**:
```
=== First-class callable ===
add(5, 3): 0    ← 应该是 8
```

**可能原因**:
1. **参数解包问题**: `...$args` 在方法调用时可能没有正确展开
2. **闭包上下文**: 闭包可能没有正确捕获 `$obj` 对象
3. **可变参数传递**: 运行时可能不支持可变参数到可变参数的转发

**需要调试的组件**:
- 箭头函数的代码生成 (`src/aot/native_linker.zig`)
- 可变参数的处理逻辑
- 参数解包表达式的求值
- 方法调用时的参数传递

---

## 🔧 技术细节

### AST 节点使用

| 节点类型 | 用途 | 数据结构 |
|---------|------|----------|
| `parameter` | 可变参数定义 | `{ attributes, name, type, default_value, is_promoted, modifiers, is_variadic, is_reference }` |
| `variable` | 变量引用 | `{ name: StringId }` |
| `unpacking_expr` | 参数解包 `...` | `{ expr: Index }` |
| `method_call` | 方法调用 | `{ target, method_name, args }` |
| `arrow_function` | 箭头函数 | `{ attributes, params, return_type, body, is_static }` |

### 关键发现

1. **Modifier 结构**: 参数使用 `modifiers: Modifier` 而不是单独的 `visibility` 和 `is_readonly` 字段
2. **Variable 数据**: 必须包装为 `{ name: StringId }` 而不是直接传递 `StringId`
3. **Unpacking 节点**: 使用 `unpacking_expr` 而不是 `unpack`

---

## 📈 测试状态

### 编译测试
- ✅ 语法解析成功
- ✅ AST 构建成功
- ✅ 代码生成成功
- ✅ 编译到原生可执行文件成功

### 运行时测试
- ✅ 闭包创建成功
- ✅ 闭包调用成功
- ❌ 参数传递错误（返回值不正确）

---

## 🚀 后续工作

### 优先级 P0 - 立即修复

| 任务 | 描述 | 预计工作量 |
|------|------|-----------|
| 调试参数传递 | 使用调试输出追踪参数值 | 2-4小时 |
| 修复解包逻辑 | 确保 `...$args` 正确展开 | 2-3小时 |
| 验证闭包上下文 | 确认 `$obj` 正确捕获 | 1-2小时 |

### 优先级 P1 - 功能完善

| 任务 | 描述 | 预计工作量 |
|------|------|-----------|
| 支持静态方法 | `ClassName::method(...)` | 3-4小时 |
| 支持函数引用 | `strlen(...)` | 2-3小时 |
| 添加类型检查 | 确保只在方法上使用 | 1-2小时 |

### 优先级 P2 - 性能优化

| 任务 | 描述 | 预计工作量 |
|------|------|-----------|
| 避免闭包开销 | 直接生成函数指针 | 4-6小时 |
| 内联优化 | 简单方法直接内联 | 3-4小时 |

---

## 💡 调试建议

### 1. 添加调试输出

在 `src/aot/runtime_lib_template.zig` 中的箭头函数调用处添加：

```zig
std.debug.print("Arrow function called with {} args\n", .{args.len});
for (args, 0..) |arg, i| {
    std.debug.print("  arg[{}] = {}\n", .{i, arg});
}
```

### 2. 检查参数解包

在方法调用生成代码中验证 `unpacking_expr` 的处理：

```zig
// 查找 unpacking_expr 的代码生成逻辑
// 确保它正确展开为多个参数
```

### 3. 验证闭包捕获

检查箭头函数是否正确捕获了 `$obj`：

```zig
// 箭头函数应该捕获外部变量
// 或者通过某种方式保持对 $obj 的引用
```

---

## 📝 代码变更总结

### 修改文件

1. **src/compiler/parser.zig**
   - 修改两处方法调用解析逻辑
   - 添加 first-class callable 检测和转换
   - 约 60 行新增代码

### 代码统计

- 新增代码: ~60 行
- 修改代码: ~20 行
- 删除代码: 0 行
- 总变更: ~80 行

---

## ✨ 成果亮点

1. **语法支持**: 成功实现 PHP 8.1 新语法的解析
2. **AST 转换**: 巧妙地将新语法转换为现有的闭包机制
3. **零侵入**: 不需要添加新的 AST 节点类型
4. **可扩展**: 为后续支持其他 callable 语法打下基础

---

## 🎯 最终状态

- **解析器**: ✅ 完成
- **AST 构建**: ✅ 完成
- **代码生成**: ✅ 完成
- **运行时**: ⚠️ 部分完成（参数传递待修复）
- **测试通过**: ❌ 待修复

---

**报告生成时间**: 2026-03-23  
**报告作者**: AI Assistant  
**审核状态**: 待审核
