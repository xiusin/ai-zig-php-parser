# AI 防幻觉 & 防代码漂移规范（Zig 编译器项目专用）

> **目标**：让任何 AI 助手在本项目中产出的代码 100% 可编译、语义正确、不引入回归。
> **适用范围**：所有通过 AI 生成/修改 Zig 代码的场景。
> **Zig 版本**：0.15.2（minimum_zig_version = 0.15.1）

---

## 一、Zig 版本锁定（最高优先级）

Zig 语言 API **跨版本剧变**，这是 AI 幻觉的第一大来源。

### 1.1 版本声明——每次对话开头必须确认

```
本项目使用 Zig 0.15.2，build.zig.zon 中 minimum_zig_version = "0.15.1"。
禁止使用任何 0.11.x / 0.12.x / 0.13.x / 0.14.x 的 API。
```

### 1.2 高频踩坑 API 对照表

| 功能 | ❌ 旧版（AI 常幻觉） | ✅ 0.15.2 正确写法 |
|------|----------------------|-------------------|
| ArrayList | `std.ArrayList(T).init(allocator)` | `std.ArrayList(T).initCapacity(allocator, 0)` |
| ArrayList.deinit | `list.deinit()` | `list.deinit(allocator)` |
| ArrayList.append | `list.append(item)` | `list.append(allocator, item)` |
| ArrayList.appendSlice | `list.appendSlice(items)` | `list.appendSlice(allocator, items)` |
| HashMap.put | `map.put(k, v)` | `map.put(allocator, k, v)` |
| HashMap.getOrPut | `map.getOrPut(k)` | `map.getOrPut(allocator, k)` |
| addExecutable | `.root_source_file = b.path(...)` 直接传 | 需用 `.root_module = b.createModule(.{...})` |
| @truncate | `@truncate(u8, value)` | `@truncate(value)` 或 `@as(u8, @truncate(value))` |
| @intCast | `@intCast(i64, value)` | `@intCast(value)` 或 `@as(i64, @intCast(value))` |
| @enumFromInt | `@intToEnum(E, v)` | `@enumFromInt(v)` |
| @intFromEnum | `@enumToInt(v)` | `@intFromEnum(v)` |
| @ptrCast | `@ptrCast(*T, ptr)` | `@ptrCast(ptr)` 或 `@as(*T, @ptrCast(ptr))` |
| @alignCast | `@alignCast(alignment, ptr)` | `@alignCast(ptr)` |
| std.mem.zeroes | `std.mem.zeroes(T)` | `std.mem.zeroes(T)` （未变，但注意返回值类型） |
| for + index | `for (items) \|item, i\|` | `for (items, 0..) \|item, i\|` |
| 切片哨兵 | `[:0]const u8` | `[:0]const u8`（未变） |

### 1.3 强制验证指令

> **规则**：AI 生成任何 std 库调用时，必须先在脑中确认「这个 API 在 0.15.2 中存在吗？参数签名是什么？」
> 如果不确定，必须要求查看项目中已有的同类调用模式，而不是凭训练数据猜测。

---

## 二、上下文感知规范（防止大文件漂移）

本项目有多个 **超大源文件**，AI 的上下文窗口无法一次性读取完整文件：

| 文件 | 大小 | 风险 |
|------|------|------|
| `native_linker.zig` | 664 KB | AI 极易生成与已有函数签名/模式不一致的代码 |
| `runtime_lib_template.zig` | 389 KB | 模板代码，改动必须与 native_linker 联动 |
| `optimizer.zig` | 255 KB | 优化 pass 之间有严格的依赖顺序 |
| `ir_generator.zig` | 234 KB | IR 指令集必须与 ir.zig 定义一一对应 |

### 2.1 修改前必做——上下文采集清单

修改任何文件前，AI 必须：

1. **读取目标函数及其前后 50 行上下文**（理解局部模式）
2. **grep 搜索同名函数/同类函数的已有实现**（对齐模式）
3. **确认被修改函数的调用者**（防止签名漂移）
4. **确认相关类型定义**（在 `ir.zig` / `ir_generator.zig` 中查找 enum/struct）

```
// 反面案例：AI 直接写一个新函数，参数类型与项目约定不一致
fn generateSomething(self: *Self, writer: Writer, inst: Instruction) !void  // ❌ 猜的签名

// 正面案例：先 grep 已有的 generate* 函数签名，对齐风格
fn generateSomething(self: *CodeGen, writer: anytype, inst: *const IR.Instruction) !void  // ✅ 对齐已有模式
```

### 2.2 禁止凭记忆引用代码

> **铁律**：不允许 AI 说「根据我之前看到的代码...」然后写出未经验证的代码。
> 每次编辑必须基于**当次对话中实际读取**的文件内容。

### 2.3 增量修改原则

- **单次修改不超过 100 行**（超过则拆分为多个原子修改）
- **每次修改必须明确标注：修改了哪个函数、改了什么、为什么改**
- **禁止「顺便重构」**——只改需求要求的部分，不碰无关代码

---

## 三、类型系统严格约束（编译器项目核心）

### 3.1 IR 指令类型一致性

本项目的 IR 定义在 `src/aot/ir.zig`，代码生成在 `native_linker.zig`。

> **规则**：新增/修改 IR 指令时，必须同步更新以下位置：
> 1. `ir.zig` 中的 enum 定义
> 2. `ir_generator.zig` 中的 IR 生成逻辑
> 3. `native_linker.zig` 中的代码生成 switch case
> 4. 相关测试文件

### 3.2 运行时值类型

本项目的 PHP 值在 AOT 中使用 `runtime.Value` 表示。

```zig
// ❌ 常见幻觉：直接对 f64 和 Value 做算术
const result = a + b;  // 当 a 是 f64, b 是 Value 时编译失败

// ✅ 正确做法：统一通过 runtime 函数
const result = runtime.php_add(a_val, b_val);
```

### 3.3 类型转换必须显式

```zig
// ❌ 隐式假设类型
const n = value;  // 不知道 value 是什么类型

// ✅ 显式声明预期类型
const n: i64 = value.toInteger();
const f: f64 = value.toFloat();
const s: []const u8 = value.toString();
```

---

## 四、函数签名契约

### 4.1 不可臆造函数

> **规则**：调用项目中的任何函数前，必须先确认该函数存在。
> AI 不得凭训练数据或命名推测「应该有这个函数」。

```
// ❌ AI 幻觉常见模式
try self.emitInstruction(.load_var, reg);     // 这个方法存在吗？参数对吗？
try writer.print("{s}", .{name});              // writer 是什么类型？有 print 方法吗？

// ✅ 先 grep 确认
// $ grep "fn emitInstruction" src/aot/ir_generator.zig
// 确认签名后再调用
```

### 4.2 错误集一致性

```zig
// ❌ 随意定义新错误
error{CodeGenFailed, InvalidState}  // 项目中有这些错误吗？

// ✅ 使用项目已有的错误集，或明确说明为新增
// 先搜索: grep "error{" src/aot/*.zig
```

---

## 五、测试验证闭环

### 5.1 每次修改必须验证编译

```bash
# 修改后立即执行，超时 120 秒
timeout 120 zig build 2>&1 | head -50
```

### 5.2 AOT 测试必须对比 PHP 原生输出

```bash
# 步骤 1: PHP 原生执行（真值）
timeout 10 php test.php > /tmp/php_out.txt 2>&1

# 步骤 2: AOT 编译
timeout 30 ./zig-out/bin/php-interpreter --compile --output=/tmp/test_aot test.php 2>&1

# 步骤 3: AOT 执行
timeout 10 /tmp/test_aot > /tmp/aot_out.txt 2>&1

# 步骤 4: 对比
diff /tmp/php_out.txt /tmp/aot_out.txt
```

### 5.3 执行超时保护

> **铁律**：所有脚本执行必须带 `timeout`，单个脚本不超过 10 秒。
> 编译命令不超过 120 秒。

### 5.4 编译产物清理

> 测试/编译产物必须在验证完成后删除，不留垃圾文件。

---

## 六、代码生成特有规范（AOT 编译器）

### 6.1 生成的 Zig 代码必须可编译

本项目的 AOT 编译器会生成 `.zig` 源文件然后编译。AI 修改代码生成逻辑时：

1. **先手写一个预期的目标 Zig 代码**（生成结果应该长什么样）
2. **再去修改生成器让它产出这个代码**
3. **最后验证生成的代码能编译通过**

```
// 工作流：
// Step 1: 写出期望的生成结果
//   var reg_0: i64 = 0;
//   reg_0 = runtime.php_add(reg_0, reg_1);
//
// Step 2: 修改 native_linker.zig 的生成逻辑
// Step 3: 查看 .zigphp_aot_build/main.zig 验证
// Step 4: 编译运行验证
```

### 6.2 字符串拼接安全

代码生成大量使用 `writer.print` / `writer.writeAll`，常见幻觉：

```zig
// ❌ 格式化占位符与参数不匹配
try writer.print("const {s} = {d};\n", .{name});  // 少了一个参数

// ❌ 忘记转义
try writer.print("const str = "{s}";\n", .{val});  // 引号未转义

// ✅ 仔细对齐占位符
try writer.print("const {s} = {d};\n", .{ name, value });
try writer.print("const str = \"{s}\";\n", .{val});
```

---

## 七、模块边界与导入规范

### 7.1 跨目录导入

Zig 0.15.2 不推荐 `../` 跨目录导入，本项目通过 `build.zig` 中的 module 系统解决：

```zig
// ❌ 禁止
const parser = @import("../compiler/parser.zig");

// ✅ 通过 build.zig 注册的模块导入
const compiler = @import("compiler");
const Parser = compiler.Parser;
```

### 7.2 同目录导入

```zig
// ✅ 同目录直接导入
const ir = @import("ir.zig");
const IR = ir.IR;
```

### 7.3 导入顺序

```zig
// 1. 标准库
const std = @import("std");
const builtin = @import("builtin");

// 2. 项目模块（通过 build.zig 注册的）
const compiler = @import("compiler");
const runtime = @import("runtime");

// 3. 同目录文件
const ir = @import("ir.zig");
const codegen = @import("codegen.zig");
```

---

## 八、AI 交互纪律

### 8.1 修改前三问

AI 在动手改代码前，必须回答：

1. **改什么？**——精确到函数名、行号范围
2. **为什么改？**——关联到具体的 bug/需求
3. **影响面？**——列出所有受影响的调用者/被调用者

### 8.2 禁止猜测性编码

| 情况 | 正确做法 |
|------|----------|
| 不确定函数是否存在 | `grep` 搜索确认 |
| 不确定参数类型 | 读取函数定义 |
| 不确定 enum 成员 | 读取 enum 定义文件 |
| 不确定已有逻辑 | 读取完整函数体 |
| 不确定 Zig API | 查看项目中同类用法 |

### 8.3 拒绝过度工程

```
// ❌ AI 常见问题：为了一个小修复引入大量「防御性」代码
if (value) |v| {
    if (v.tag == .integer) {
        if (v.data) |d| {
            if (d.integer) |i| {
                // 4层嵌套只为取一个整数...
            }
        }
    }
}

// ✅ 遵循项目已有模式
const int_val = value.toInteger() catch return error.TypeError;
```

### 8.4 单一职责修改

> 一个 PR/commit 只做一件事。禁止在修 bug 的同时重构代码风格。

---

## 九、高频幻觉模式清单

基于本项目历史踩坑，以下是 AI 最容易犯的错误：

| # | 幻觉模式 | 后果 | 防范 |
|---|----------|------|------|
| 1 | ArrayList 旧版 API | 编译失败 | 查本文 1.2 对照表 |
| 2 | 臆造 std 库函数 | 编译失败 | grep 项目已有用法 |
| 3 | f64 与 Value 直接运算 | 编译失败 | 走 runtime.php_* 路径 |
| 4 | switch 未覆盖所有 enum 分支 | 编译警告/panic | 必须有 else 分支 |
| 5 | 忘记 `defer` 释放资源 | 内存泄漏 | allocate 必配 defer |
| 6 | `@intCast` 用旧版两参数语法 | 编译失败 | 0.15.2 是单参数 |
| 7 | 引用了不存在的 struct 字段 | 编译失败 | 先读取 struct 定义 |
| 8 | 生成代码中的格式化参数不匹配 | 运行时 panic | 逐个对齐 {s}/{d}/{} |
| 9 | 在 `comptime` 上下文中使用运行时值 | 编译失败 | 分清编译期/运行期 |
| 10 | `catch unreachable` 掩盖错误 | 运行时 panic | 必须显式处理错误 |
| 11 | 混淆 `[]const u8` 与 `[*]const u8` | 未定义行为 | 切片 vs 指针分清 |
| 12 | `@as` 强转不兼容类型 | 编译失败 | 只能在安全转换时使用 |

---

## 十、检查清单（每次提交前）

```
[ ] 1. zig build 编译通过（无 error，无 warning）
[ ] 2. 修改的函数签名与已有调用者兼容
[ ] 3. 新增的 API 调用在项目中有同类先例
[ ] 4. 所有 ArrayList/HashMap 操作传了 allocator
[ ] 5. 所有 @intCast/@truncate 用单参数语法
[ ] 6. 代码生成的 writer.print 占位符与参数数量匹配
[ ] 7. switch 覆盖了所有 enum 分支或有 else
[ ] 8. 所有 allocate 都有对应的 defer free/deinit
[ ] 9. 测试脚本执行带 timeout（≤10s）
[ ] 10. 编译产物已清理
[ ] 11. 没有「顺便重构」的无关改动
[ ] 12. IR 变更同步到了 ir.zig + ir_generator.zig + native_linker.zig
```

---

## 十一、提示词模板（给 AI 的开场白）

在新会话开始时，建议贴上以下 prompt：

```
你正在维护一个 Zig 0.15.2 的 PHP AOT 编译器项目。

关键约束：
1. Zig 0.15.2 API — ArrayList/HashMap 全部需要 allocator 参数
2. @intCast/@truncate/@ptrCast 都是单参数语法
3. 跨目录导入通过 build.zig 模块，禁止 ../ 路径
4. 修改代码前必须先读取目标文件的相关上下文
5. 不要凭记忆写代码，每个函数调用都要有依据
6. 编译验证：timeout 120 zig build
7. 测试执行：timeout 10 <command>
8. native_linker.zig 有 664KB，ir_generator.zig 有 234KB
   — 修改前必须 grep 搜索已有模式
   — 禁止凭推测写代码
```

---

## 十二、文档维护

- **维护者**：项目团队
- **最后更新**：2026-03-11
- **版本**：v1.0

> 本文档应随 Zig 版本升级、项目架构变化而同步更新。
> 发现新的幻觉模式时，及时添加到第九章清单中。
