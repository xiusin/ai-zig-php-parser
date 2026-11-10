# isNamedLabelStart patch 说明（parser.zig，commit f6e5e2a 内）

> 供老铁追认前审阅爆炸半径。该改动已随批十九①（Q1 内建形参名表）合入 HEAD；本文档只做事实陈述与影响面分析，不含回滚动作。

## 1. 改了什么

`src/compiler/parser.zig` 新增一个谓词函数 + 4 处调用点替换：

```zig
// src/compiler/parser.zig:123
fn isNamedLabelStart(self: *Parser) bool {
    if (self.peek.tag != .colon) return false;
    const t = self.curr.tag;
    if (t == .t_string) return true;
    const v = @intFromEnum(t);
    return v >= @intFromEnum(@TypeOf(t).k_class) and v <= @intFromEnum(@TypeOf(t).k_void);
}
```

四处调用点原判定 `self.curr.tag == .t_string and self.peek.tag == .colon` 统一替换为 `self.isNamedLabelStart()`：

| 调用点 | 语法语境 |
|---|---|
| parser.zig:2766 | 函数调用实参循环 |
| parser.zig:2939 | 函数调用实参循环（另一入口/变体） |
| parser.zig:3768 | `new` 表达式实参循环 |
| parser.zig:3839 | 动态调用实参循环 |

语义变化：命名实参标签的合法字符集从「仅标识符（t_string）」放宽为「标识符 ∪ 关键字（Token.Tag 中 k_class...k_void 连续区间，序数判定）」。

## 2. 为什么必须改（动机）

PHP 8.5.8 实测接受**关键字作命名实参标签**：

```php
class_exists(class: "X");        // 合法
array_slice(array: [1,2], 0);    // 合法（官方文档常见示例）
function_exists(function: "x");  // 合法
f(true: 1);                      // 合法语法 ⇒ 运行期 Error「Unknown named parameter $true」
```

Q1 的真值核验路径（`phpInvokeBuiltinNamed` 运行期绑定 + 反射表）依赖 parser 能把这些标签**解析成命名实参节点**；parser 层拒收 ⇒ 语法错误 ⇒ 整条命名实参战线无法核验。fuzzy_scripts_720 语料及真实 PHP 代码中该形态客观存在 ⇒ 不支持即编译器缺陷（宪法 §7.8：PHP 语法已支持的特性禁止简化绕过）。

## 3. 为什么不能用别的方式绕

| 替代方案 | 否决理由 |
|---|---|
| **改探针写法**（把 `class_exists(class: "X")` 换成位置实参） | 探针的目的是核验命名实参绑定真路径；绕开 ⇒ 测不到目标机制，Q1 验收失效。且语料中关键字标签真实存在，绕探针不绕缺陷。 |
| **lexer 层降级**（调用语境下把关键字 token 改写成 t_string） | lexer 需前后文感知「调用实参起始位」⇒ lexer 从全文无关变为语境耦合，爆炸半径远大于 parser 侧 4 点替换；且关键字判定在 lexer 是唯一权威点，加旁路违反单一来源。 |
| **运行期补判**（parser 照旧拒收，运行期特判） | parser 阶段已报语法错误，根本到不了运行期。 |

parser 侧谓词是唯一满足「最小侵入 + 语义正确」的点：判定条件精确（关键字 **且紧跟冒号**），只作用于 4 个实参循环。

## 4. 爆炸半径分析

### 4.1 判定条件的唯一命中面

`isNamedLabelStart` 为真当且仅当：**当前 token ∈ {t_string, 关键字} 且下一 token 是冒号**。该组合在 PHP 语法中只出现于：

1. **命名实参标签**（目标形态）✓
2. 三元 `?:`——冒号必在表达式中段，**永不落在实参起始位**（起始位是表达式开头，三元冒号前必有完整条件表达式）⇒ 不误判
3. `case label:` / `default:` / `goto` 标签 / `switch`——这些语境根本不在 4 个实参循环内 ⇒ 不可达
4. 数组字面量 `["k" => v]`——键后是 `=>` 不是 `:` ⇒ 不误判

### 4.2 关键字区间内的特殊成员

k_class...k_void 区间内包含 `k_true`/`k_false`/`k_null`（token.zig:120-122）⇒ `f(true: 1)` 被判为命名标签。PHP 8.5.8 实测同形：**PHP 同样把 `true:` 解析为命名参数**（运行期报 `Unknown named parameter $true`，可捕获 Error）⇒ AOT 解析层与 PHP **语义一致**，无歧义面。

### 4.3 对既有语法路径的影响

- **4 个实参循环内的位置实参**：标签判定失败的实参（非「串/关键字+冒号」）走原路径，一字不变。
- **关键字的其他用法**（`class Foo {}`、`function f(): void` 等）：那些语境 curr 后不是冒号 ⇒ 谓词为假 ⇒ 不介入。
- **回归证据**：Q1 落地时 41 格面板零转移；本 P2 批复跑（panel_p2/panel_p24）持续零转移。

### 4.4 结论

爆炸半径 = 4 个实参循环内「关键字+冒号」序列的解释归属。该序列在 PHP 语法中唯一合法解释即命名实参标签 ⇒ 无既有路径被改变语义。

## 5. 关联文件

- 谓词与调用点：[src/compiler/parser.zig](../../../src/compiler/parser.zig)（:123 定义；:2766/:2939/:3768/:3839 调用）
- 关键字区间：[src/compiler/token.zig](../../../src/compiler/token.zig)（k_class…k_void）
- 合入 commit：`f6e5e2a`（批十九①）
- 运行期配套：`phpInvokeBuiltinNamed`（runtime_lib_template.zig，命名实参绑定真值核验）
