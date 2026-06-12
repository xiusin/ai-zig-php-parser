# 循环中嵌套 if 语句的 Phi 节点赋值问题

**问题 ID**: AOT-PHI-001  
**优先级**: P0（高）  
**状态**: 已识别，待修复  
**发现日期**: 2026-02-27

---

## 问题描述

在循环中有多个 if 语句修改同一变量时，phi 节点的 incoming 值不正确，导致变量值没有正确累积。

## 复现代码

```php
<?php
$result = "";
for ($i = 0; $i < 5; $i++) {
    if ($i % 2 == 0) {
        $result = $result . "even";
    } else {
        $result = $result . "odd";
    }
    if ($i < 4) {
        $result = $result . ",";
    }
}
echo $result . "\n";
// 期望: even,odd,even,odd,even
// 实际: even,even,even
?>
```

## 问题分析

### IR 结构

```
PHI reg_39: incoming = [reg_20 from block_6, reg_24 from block_7]  // 第一个 if-else 的结果
PHI reg_40: incoming = [reg_30 from block_9, reg_39 from block_8]  // 第二个 if 的结果
PHI reg_41: incoming = [reg_0 from block_1, reg_40 from block_4]   // 循环变量
```

### 控制流

```
block_1 (init)
  ↓
block_2 (loop header) ← reg_41 = phi(reg_0, reg_40)
  ↓
block_3 (loop body)
  ↓
if ($i % 2 == 0)
  ├─ block_6 (then): reg_20 = $result . "even"
  └─ block_7 (else): reg_24 = $result . "odd"
  ↓
block_8 (merge) ← reg_39 = phi(reg_20, reg_24)
  ↓
if ($i < 4)
  ├─ block_9 (then): reg_30 = reg_39 . ","
  └─ block_8 (else): ???
  ↓
block_4 (latch) ← reg_40 = phi(reg_30, reg_39)
  ↓
back to block_2
```

### 错误原因

在第二个 if 的 else 分支（block_8），phi 节点使用了 `reg_39`（第一个 if-else 的结果），而不是 `reg_41`（循环开始时的 `$result` 值）。

**正确的应该是**:
```
PHI reg_40: incoming = [reg_30 from block_9, reg_41 from block_8]
```

因为在 else 分支中，`$result` 应该保持不变（使用循环开始时的值），而不是使用第一个 if-else 的结果。

### 根本原因

这是 SSA 构造算法的问题。在处理嵌套的 if 语句时，IR 生成器没有正确追踪变量的定义-使用链。

具体来说：
1. 第一个 if-else 定义了 `$result` 的新值（`reg_39`）
2. 第二个 if 的 then 分支使用 `reg_39` 作为基础（正确）
3. 第二个 if 的 else 分支应该使用循环开始时的 `$result`（`reg_41`），但错误地使用了 `reg_39`

## 影响范围

- 循环中有多个 if 语句修改同一变量
- 嵌套的 if 语句
- 任何需要保持变量值不变的分支

## 临时解决方案

避免在循环中使用多个 if 语句修改同一变量。可以改写为：

```php
$result = "";
for ($i = 0; $i < 5; $i++) {
    $part = ($i % 2 == 0) ? "even" : "odd";
    $sep = ($i < 4) ? "," : "";
    $result = $result . $part . $sep;
}
```

## 修复方案

需要修改 IR 生成器中的 SSA 构造逻辑：

### 方案 1: 修复变量定义追踪

在 `src/aot/ir_generator.zig` 中，改进变量定义追踪：

1. 维护每个变量在当前作用域的最新定义
2. 在 if 语句的 else 分支中，使用进入 if 之前的定义
3. 在 phi 节点中，正确选择 incoming 值

### 方案 2: 使用标准 SSA 构造算法

参考 LLVM 的 mem2reg 算法：
1. 插入 phi 节点到支配边界
2. 重命名变量（使用栈追踪定义）
3. 填充 phi 节点的 incoming 值

### 推荐方案

方案 2 更可靠，但需要重构 IR 生成器。建议：
1. 短期：实现方案 1 的简化版本
2. 长期：重构为标准 SSA 构造算法

## 相关代码

- `src/aot/ir_generator.zig`: IR 生成器
- `src/aot/optimizer.zig`: mem2reg 优化（已有 SSA 构造逻辑）
- `src/aot/native_linker.zig`: 代码生成器

## 测试用例

```bash
# 测试脚本
cat > /tmp/test_phi_bug.php << 'EOF'
<?php
$result = "";
for ($i = 0; $i < 5; $i++) {
    if ($i % 2 == 0) {
        $result = $result . "even";
    } else {
        $result = $result . "odd";
    }
    if ($i < 4) {
        $result = $result . ",";
    }
}
echo $result . "\n";
?>
EOF

# 编译并运行
./zig-out/bin/php-interpreter --compile --output=/tmp/test_phi /tmp/test_phi_bug.php
/tmp/test_phi

# 期望输出: even,odd,even,odd,even
# 实际输出: even,even,even
```

## 参考资料

- [SSA Construction Algorithm](https://en.wikipedia.org/wiki/Static_single-assignment_form)
- [LLVM mem2reg Pass](https://llvm.org/docs/Passes.html#mem2reg-promote-memory-to-register)
- [Efficiently Computing Static Single Assignment Form](https://www.cs.utexas.edu/~pingali/CS380C/2010/papers/ssaCytron.pdf)

---

**更新日志**:
- 2026-02-27: 初始创建，问题识别和分析
