# 结构化控制流生成器的 continue 插入问题

**问题 ID**: AOT-CODEGEN-002  
**优先级**: P0（高）  
**状态**: 已识别  
**发现日期**: 2026-02-27

---

## 问题描述

结构化控制流生成器在循环中生成嵌套 if 语句时，错误地在第二个 if 的 then 分支中插入了 `continue`，导致后续代码被跳过。

## 复现代码

```php
<?php
$x = "a";
for ($i = 0; $i < 2; $i++) {
    if ($i == 0) {
        $x = "b";
    }
    if ($i == 1) {
        $x = "c";
    }
}
echo $x . "\n";
// 期望: c
// 实际: b
?>
```

## 生成的代码（错误）

```zig
while (true) {
    if ($i == 0) {
        reg_21 = "b";
        if ($i == 1) {  // 第二个 if 嵌套在第一个 if 中！
            reg_22 = "c";
            continue;  // 错误：跳过了后续代码
        } else {
            reg_22 = reg_21;
        }
    } else {
        reg_21 = reg_23;  // 永远不会执行
    }
    reg_23 = reg_22;
}
```

## 期望的代码

```zig
while (true) {
    if ($i == 0) {
        reg_21 = "b";
    } else {
        reg_21 = reg_23;
    }
    
    if ($i == 1) {  // 顺序的，不是嵌套的
        reg_22 = "c";
    } else {
        reg_22 = reg_21;
    }
    
    reg_23 = reg_22;
}
```

## 根本原因

结构化控制流生成器（`tryGenerateStructuredControlFlowNew`）在重建控制流时：
1. 错误地将两个顺序的 if 语句识别为嵌套结构
2. 在第二个 if 的 then 分支中插入 `continue`，认为这是循环的最后一条语句
3. 导致第一个 if 的 else 分支永远不会执行

## 影响范围

- 循环中有多个顺序的 if 语句
- 结构化控制流生成模式（非状态机模式）

## 临时解决方案

禁用结构化控制流生成，强制使用状态机模式：

```zig
// src/aot/native_linker.zig:2375
if (false) {  // 禁用结构化控制流
    const structured_result = try self.tryGenerateStructuredControlFlowNew(&writer, func, cleanup_regs, alloca_regs);
    if (structured_result) {
        return;
    }
}
```

## 修复方案

### 方案 1: 修复结构化控制流生成器

在 `tryGenerateStructuredControlFlowNew` 中：
1. 正确识别顺序的 if 语句（不是嵌套的）
2. 不要在非最后一条语句的 if 分支中插入 `continue`
3. 改进控制流重建算法

### 方案 2: 改进状态机代码生成

状态机模式虽然正确，但生成的代码冗长。可以优化：
1. 识别简单的控制流模式
2. 生成更简洁的代码
3. 减少不必要的状态转换

### 推荐方案

短期：使用方案 1 的临时解决方案（禁用结构化控制流）  
长期：重构结构化控制流生成器，参考 LLVM 的 StructurizeCFG pass

## 相关代码

- `src/aot/native_linker.zig:5700`: `tryGenerateStructuredControlFlowNew`
- `src/aot/native_linker.zig:2330`: `generateControlFlowStateMachine`

## 测试用例

```bash
cat > /tmp/test_sequential_if.php << 'EOF'
<?php
$x = "a";
for ($i = 0; $i < 2; $i++) {
    if ($i == 0) {
        $x = "b";
    }
    if ($i == 1) {
        $x = "c";
    }
}
echo $x . "\n";
?>
EOF

# 期望输出: c
# 实际输出: b
```

---

**更新日志**:
- 2026-02-27: 初始创建，问题识别和分析
