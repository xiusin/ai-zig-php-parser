# AOT 编译器已知问题 - 更新

## P1 问题

### 1. ✅ 三元运算符条件类型（已修复）
**状态**: 已修复（commit 7b9d085）

**问题**: 三元运算符条件判断生成 `if (reg_122)` 而不是 `if (reg_122.toBool())`

**修复**: writeConditionExpr 中，bool 类型也统一调用 .toBool()

### 2. ⚠️ Do-While 循环死循环（严重）
**状态**: 待修复

**问题**: do-while 循环中的变量更新不生效，导致死循环

**复现**:
```php
$n = 1;
do {
    echo "$n\n";
    $n = $n + 1;
} while ($n <= 3);
```

**预期输出**: 1, 2, 3
**实际输出**: 1, 1, 1, ... (死循环)

**根本原因**:
- do-while 循环的 body 块有两个前驱（entry 和 cond）
- mem2reg 优化后，body 块开始时缺少 phi 节点
- 循环变量没有从 cond 块传递回 body 块

**生成的错误代码**:
```zig
// do_while_body_0
reg_2 = reg_0;  // 使用初始值
reg_7 = try runtime.php_add(reg_0, reg_6);  // 计算新值
// 跳转到 do_while_cond_1

// do_while_cond_1
reg_8 = reg_7;  // 使用新值
if (reg_10.toBool()) {
    current_block = 1;  // 回到 body，但 reg_0 没有更新！
}
```

**应该生成**:
```zig
// do_while_body_0
switch (prev_block) {
    0 => { reg_0 = 初始值; },  // 从 entry 来
    2 => { reg_0 = reg_7; },   // 从 cond 来（回边）
    else => unreachable,
}
reg_2 = reg_0;  // 使用正确的值
reg_7 = try runtime.php_add(reg_0, reg_6);
```

**修复方案**:
1. **方案 A**: 修复 mem2reg 的 phi 节点插入逻辑
   - 确保循环 header 块正确插入 phi 节点
   - 需要深入理解 dominance frontier 计算
   - 风险：可能影响其他优化

2. **方案 B**: 在状态机生成时手动插入 phi 赋值
   - 检测循环块（有回边的块）
   - 为循环变量生成 switch 赋值
   - 风险：需要准确识别循环变量

3. **方案 C**: 临时禁用 mem2reg 优化
   - 最简单，但性能损失大
   - 仅作为临时方案

**推荐**: 方案 A（修复 mem2reg）

**影响范围**: 所有 do-while 循环，可能影响 while 和 for 循环

### 3. ⚠️ 多维数组对齐问题
**状态**: 待修复

**问题**: 多维数组访问时出现 `incorrect alignment` 错误

**复现**:
```php
$matrix = [];
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        $matrix[$i][$j] = $i * 3 + $j;
    }
}
```

**错误信息**:
```
thread panic: incorrect alignment
runtime_lib.zig:1591:16: in asArray
    return @ptrFromInt(nanbox_abi.decodePtr(self.val));
```

**根本原因**: nanbox 指针编码/解码时对齐不正确

**修复方案**: 
1. 检查 nanbox_abi.encodePtr 是否保证对齐
2. 在 asArray() 中添加对齐检查和修正
3. 确保数组分配时使用正确的对齐

## P2 问题

### 4. implode 函数未实现
**状态**: 待实现

**问题**: `implode()` 函数未实现

**修复**: 在 runtime_lib.zig 中实现 php_implode 函数

### 5. 字符串索引访问未实现
**状态**: 待实现

**问题**: `$str[0]` 字符串索引访问未实现

**修复**: 在 IR 生成器中处理字符串索引访问

## 测试状态

### 回归测试
- ✅ test_fibonacci.php: 通过
- ✅ test_phi_swap.php: 通过
- ✅ test_complex_ecommerce.php: 通过
- ✅ test_complex_algorithms.php: 通过
- ✅ test_simple_types.php: 通过（三元运算符修复后）
- ❌ test_control_flow.php: 失败（do-while 死循环）
- ❌ test_array_string.php: 失败（implode 未实现）

### 优先级
1. **P1**: 修复 do-while 循环死循环（阻塞所有循环测试）
2. **P1**: 修复多维数组对齐问题
3. **P2**: 实现 implode 函数
4. **P2**: 实现字符串索引访问

## 下一步行动

1. 修复 do-while 循环的 phi 节点问题（方案 A）
2. 修复多维数组对齐问题
3. 运行完整回归测试
4. 提交最终报告

---

**更新时间**: 2026-02-27 17:08
**更新人**: xiusin
