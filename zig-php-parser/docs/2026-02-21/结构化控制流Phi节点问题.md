# 结构化控制流生成器 Phi 节点问题

## 问题描述
在 AOT 编译模式下，当代码包含多个循环（foreach/while/for）时，生成的代码会在运行时触发 "reached unreachable code" panic。

## 复现步骤

### 最小复现用例
```php
<?php
$arr = [1, 2, 3];

// 第一个循环
foreach ($arr as $v) {
    echo $v . " ";
}

// 第二个循环 - 触发问题
foreach ($arr as $v) {
    echo $v . " ";
}
```

### 错误信息
```
thread panic: reached unreachable code
.zigphp_aot_build/main.zig:404:17: in __main__
        else => unreachable,
                ^
```

## 根本原因

在生成的 Zig 代码中，phi 节点的 switch 语句缺少某些 incoming 块：

```zig
switch (prev_block) {
    0 => { reg_100 = reg_10; _ = reg_100.retain(); },
    3 => { reg_100 = reg_35; _ = reg_100.retain(); },
    else => unreachable,  // ❌ 缺少其他可能的 prev_block 值
}
```

当控制流从未列出的块到达时，会触发 `unreachable`。

## 影响范围

- ✅ **单个循环**：工作正常
- ❌ **多个顺序循环**：触发 unreachable
- ❌ **嵌套循环**：触发 unreachable  
- ❌ **循环后的其他控制流**：可能触发 unreachable

## 相关代码

### 问题位置
- `src/aot/native_linker.zig`: `generateStructuredCodeNew()` 函数
- Phi 节点的 incoming 块收集逻辑不完整

### 可能的原因
1. **CFG 重建不完整**：在优化后 CFG 的前驱/后继关系未正确更新
2. **Phi 节点分析错误**：未正确识别所有可能的 incoming 块
3. **块编号不一致**：优化过程中块 ID 发生变化但未同步

## 临时解决方案

### 方案 1：避免多个循环
将多个循环合并为一个：
```php
// 不要这样：
foreach ($arr as $v) { /* ... */ }
foreach ($arr as $v) { /* ... */ }

// 改为：
foreach ($arr as $v) {
    // 合并逻辑
}
```

### 方案 2：使用 while 循环
```php
$i = 0;
while ($i < count($arr)) {
    // 处理 $arr[$i]
    $i++;
}
```

## 修复建议

### 短期修复
在 phi 节点生成时，添加调试输出查看所有可能的 incoming 块：

```zig
// 在 generateStructuredCodeNew 中
std.debug.print("Phi reg_{}: incoming blocks = {any}\n", 
    .{phi_reg, incoming_blocks});
```

### 长期修复
1. **完善 CFG 分析**：
   - 在每次优化后重建完整的 CFG
   - 验证所有块的前驱/后继关系

2. **改进 Phi 节点处理**：
   - 收集所有可能到达 phi 节点的块
   - 为每个 incoming 块生成对应的 case

3. **添加验证**：
   - 在代码生成前验证 phi 节点的完整性
   - 检测缺失的 incoming 块并报错

## 测试用例

已添加测试用例位于 `tests/aot/`:
- `test_ref_basic.php` - 多个 foreach 循环
- `test_simple_nested_ref.php` - 嵌套循环
- `test_ref_single_loop.php` - foreach + while 组合

## 优先级

**P1 - 高优先级**

这个问题严重限制了 AOT 编译器的实用性，因为大多数实际代码都包含多个循环。

## 相关 Issue

- 引用迭代实现：已完成，功能正常
- 本问题与引用实现无关，是代码生成器的独立问题

## 工作量估算

- 调试和定位：2-3 小时
- 修复实现：3-4 小时
- 测试验证：1-2 小时
- **总计**：6-9 小时
