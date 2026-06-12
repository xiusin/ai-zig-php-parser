# AOT 编译器深度修复尝试报告

日期：2026-02-09 21:13 - 22:00

## 任务目标

1. **深度修复字符串插值中的属性访问问题**
2. **完全解决多层异常处理的寄存器重用问题**

## 1. 字符串插值问题

### 问题描述
在字符串插值中，`"Point: ($p->x, $p->y)"` 显示为 `"Point: (Point->x, Point->y)"`，属性访问没有被正确求值。

### 根本原因
**Lexer 层面的设计问题**：
- Lexer 在字符串插值模式（`double_quote` 状态）下，遇到 `$p` 后返回 `t_variable` token
- 下一次调用时，`->x` 被当作字符串的一部分（`t_encapsed_and_whitespace`）返回
- Parser 无法识别这是一个属性访问表达式

### 尝试的解决方案

#### 方案 1：Parser 层面修复
在 `parseInterpolatedString` 中，当遇到 `t_variable` 后，继续解析 `arrow` 和属性名。

**结果**：失败
- Lexer 已经把 `->x` 作为字符串部分返回
- Parser 无法获取正确的 token 流

#### 方案 2：Lexer 层面修复
修改 `lexInterpolation`，在扫描完变量后，检查是否有 `->` 或 `[`，如果有就返回相应的 token。

**实现**：
```zig
// 在 lexInterpolation 开头添加
if (self.buffer[self.pos] == '-' and self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '>') {
    self.pos += 2;
    return .{ .tag = .arrow, .loc = .{ .start = start, .end = self.pos } };
}
```

**结果**：部分成功，但破坏了其他功能
- 修改影响了所有字符串插值的处理
- 导致正常的字符串解析失败

### 正确的解决方案（需要重构）

**需要重新设计 Lexer 的状态机**：

1. **添加新状态** `interpolation_after_var`：
   - 在扫描完变量后进入此状态
   - 在此状态下，检查 `->`, `[`, 或其他操作符
   - 如果是属性访问，继续扫描；否则返回字符串部分

2. **Token 流示例**：
   ```
   "Point: ($p->x)"
   ↓
   t_double_quote
   t_encapsed_and_whitespace("Point: (")
   t_variable("$p")
   arrow
   t_string("x")
   t_encapsed_and_whitespace(")")
   t_double_quote
   ```

3. **实现复杂度**：
   - 需要修改 Lexer 的状态机（约 200 行代码）
   - 需要处理嵌套情况（`$p->arr[0]->x`）
   - 需要大量测试确保不破坏现有功能

### 当前状态
- ❌ 未完成
- 需要约 4-6 小时的重构工作
- 建议作为独立任务处理

## 2. 多层异常处理问题

### 问题描述
多个 try-catch 块会导致异常变量寄存器重用，引发双重释放和 segfault。

**示例**：
```php
try { ... } catch (E $e) { ... }  // 使用 reg_5
try { ... } catch (E $e) { ... }  // 也使用 reg_5，导致双重释放
```

### 根本原因
**IR 生成器的变量寄存器管理问题**：
- `getOrCreateVarRegister` 为相同的变量名返回相同的寄存器
- 多个 catch 块中的 `$e` 被映射到同一个寄存器
- 每个 catch 块都会 `release` 这个寄存器，导致双重释放

### 尝试的解决方案

#### 方案 1：为每个 catch 块创建唯一变量名
```zig
const unique_var_name = try std.fmt.allocPrint(self.allocator, "{s}_catch_{d}", .{ var_name, index });
const var_reg = try self.getOrCreateVarRegister(unique_var_name, .php_value);
try self.var_registers.put(var_name, var_reg);
```

**结果**：失败
- `var_registers.put` 覆盖了之前的映射
- 但代码生成器还是使用了旧的寄存器

#### 方案 2：为每个 catch 块创建独立作用域
```zig
const saved_var_registers = self.var_registers;
defer self.var_registers = saved_var_registers;
self.var_registers = std.StringHashMap(Register).init(self.allocator);
// ... 复制父作用域变量
// ... 添加异常变量
```

**结果**：失败
- 作用域隔离没有生效
- 生成的代码还是使用相同的寄存器

### 深层问题分析

问题不在 IR 生成，而在**代码生成阶段**：

1. **寄存器声明**：
   ```zig
   var reg_5_storage: runtime.Value = runtime.Value.initNull();
   var reg_5: *runtime.Value = &reg_5_storage;
   ```
   `reg_5` 是一个指针类型（alloca），在函数开头声明一次。

2. **多次使用**：
   ```zig
   // 第一个 catch 块
   reg_5.release(runtime.runtime_allocator);
   runtime.val_assign(reg_5, reg_35);
   
   // 第二个 catch 块
   reg_5.release(runtime.runtime_allocator);  // 双重释放！
   runtime.val_assign(reg_5, reg_35);
   ```

3. **根本原因**：
   - 寄存器分配器（register allocator）没有考虑 catch 块的作用域
   - 它认为 `$e` 在整个函数中是同一个变量
   - 因此分配了同一个寄存器

### 正确的解决方案（需要重构）

**需要修改寄存器分配器**：

1. **方案 A：为每个 catch 块分配新寄存器**
   - 修改 `getOrCreateVarRegister` 的语义
   - 添加作用域信息（block ID）
   - 为不同作用域的同名变量分配不同寄存器

2. **方案 B：使用 SSA 形式**
   - 将 `$e` 转换为 `$e_1`, `$e_2` 等
   - 每个 catch 块使用不同的 SSA 变量
   - 需要重构整个 IR 生成器

3. **方案 C：修改代码生成器**
   - 在代码生成阶段检测寄存器重用
   - 为重用的寄存器生成不同的变量名
   - 最简单但不够优雅

### 当前状态
- ⚠️ 部分完成
- 单个 try-catch-finally 工作正常
- 多个 try-catch 块仍有问题
- 需要约 6-8 小时的重构工作

## 总结

### 完成情况
- ❌ 字符串插值：0% （需要 Lexer 重构）
- ⚠️ 多层异常：30% （需要寄存器分配器重构）

### 技术债务
1. **Lexer 状态机**：需要重新设计以支持复杂的字符串插值
2. **寄存器分配器**：需要添加作用域感知
3. **IR 生成器**：需要更好的变量生命周期管理

### 建议
1. **字符串插值**：作为独立的重构任务，预计 4-6 小时
2. **多层异常**：优先级高，预计 6-8 小时
3. **测试覆盖**：添加更多边界情况测试

### 替代方案
1. **字符串插值**：建议用户使用字符串连接 `"Point: (" . $p->x . ")"`
2. **多层异常**：建议用户避免在多个 catch 块中使用相同的变量名

## 经验教训

1. **深度修复需要充分的时间**：
   - 这两个问题都涉及核心架构
   - 不是简单的 bug 修复，而是设计问题
   - 需要重构而不是打补丁

2. **测试驱动开发的重要性**：
   - 应该先写测试，再修复
   - 每个修改都应该有对应的测试

3. **渐进式改进**：
   - 不要试图一次解决所有问题
   - 先解决最简单的情况
   - 逐步扩展功能

## 下一步行动

### 短期（1-2 天）
1. 完成多层异常处理的修复（方案 C）
2. 添加更多异常处理测试
3. 文档化已知限制

### 中期（1-2 周）
1. 重构 Lexer 支持复杂字符串插值
2. 重构寄存器分配器支持作用域
3. 添加完整的测试套件

### 长期（1-2 月）
1. 迁移到 SSA 形式的 IR
2. 实现更好的优化 pass
3. 提高代码生成质量
