# foreach 循环实现计划

## 当前状态

- ✅ **解析器**: 已实现 `parseForeach()` (src/compiler/parser.zig:956)
- ✅ **AST**: 已定义 `foreach_stmt` 节点 (src/compiler/ast.zig:153)
- ✅ **字节码生成**: 已实现 `visitForeach()` (src/bytecode/generator.zig:675)
- ✅ **指令定义**: 已定义 `foreach_init` (0x7E) 和 `foreach_next` (0x7F)
- ❌ **VM 执行**: **未实现** - 这是问题所在
- ❌ **AOT 编译**: **未实现**

## 问题根源

VM 的 `executeInstruction()` 函数中没有处理 `foreach_init` 和 `foreach_next` 指令，导致：
```
InvalidOpcode: func='main' ip=14 opcode=0x7e(foreach_init)
```

## 实现方案

### 1. VM 实现 (src/runtime/vm.zig)

需要在 `executeInstruction()` 中添加两个指令的处理：

#### 1.1 foreach_init (0x7E)

**功能**: 初始化迭代器

**栈操作**:
- 输入: `[iterable]`
- 输出: `[iterator_state]`

**伪代码**:
```zig
.foreach_init => {
    const iterable = self.stack.pop();
    
    // 创建迭代器状态
    const iterator = try self.createIterator(iterable);
    
    // 压入栈
    try self.stack.push(iterator);
}
```

**迭代器状态结构**:
```zig
const IteratorState = struct {
    iterable: Value,      // 原始数组/对象
    current_index: i64,   // 当前索引
    keys: ?[]Value,       // 键数组（关联数组）
    is_done: bool,        // 是否完成
};
```

#### 1.2 foreach_next (0x7F)

**功能**: 获取下一个元素，如果没有则跳转

**栈操作**:
- 输入: `[iterator_state]`
- 输出: `[iterator_state, key, value]` 或跳转

**伪代码**:
```zig
.foreach_next => {
    const jump_target = inst.op1;
    const iterator = self.stack.peek();
    
    if (iterator.is_done) {
        // 迭代完成，跳转到循环结束
        self.ip = jump_target;
        _ = self.stack.pop(); // 清理迭代器
    } else {
        // 获取当前元素
        const key = try iterator.getCurrentKey();
        const value = try iterator.getCurrentValue();
        
        // 压入栈
        try self.stack.push(key);
        try self.stack.push(value);
        
        // 移动到下一个
        iterator.moveNext();
    }
}
```

### 2. AOT 实现 (src/aot/ir_generator.zig)

需要在 `generateForeachStmt()` 中生成正确的 IR：

**当前状态**: 函数已存在但可能不完整

**需要生成的 IR 结构**:
```
block_init:
    %iterable = ...
    %iterator = foreach_init %iterable
    br %loop_cond

block_loop_cond:
    %has_next = foreach_has_next %iterator
    cond_br %has_next, %loop_body, %loop_exit

block_loop_body:
    %key = foreach_get_key %iterator
    %value = foreach_get_value %iterator
    store %key_var, %key
    store %value_var, %value
    ... body ...
    %iterator2 = foreach_next %iterator
    br %loop_cond

block_loop_exit:
    ...
```

### 3. 测试用例

#### 3.1 简单遍历
```php
<?php
$arr = [1, 2, 3];
foreach ($arr as $val) {
    echo $val;
}
?>
```

#### 3.2 键值遍历
```php
<?php
$arr = ["a" => 1, "b" => 2];
foreach ($arr as $key => $val) {
    echo "$key: $val\n";
}
?>
```

#### 3.3 嵌套遍历
```php
<?php
$matrix = [[1, 2], [3, 4]];
foreach ($matrix as $row) {
    foreach ($row as $val) {
        echo $val;
    }
}
?>
```

## 实现步骤

### 阶段 1: VM 基础实现 (4-6 小时)

1. **定义迭代器状态结构** (30 分钟)
   - 在 `src/runtime/types.zig` 中定义 `IteratorState`
   - 支持数组和关联数组

2. **实现 foreach_init** (1-2 小时)
   - 创建迭代器
   - 处理数组和关联数组
   - 错误处理

3. **实现 foreach_next** (1-2 小时)
   - 检查是否完成
   - 获取当前键值
   - 移动到下一个
   - 跳转逻辑

4. **测试验证** (1-2 小时)
   - 测试简单遍历
   - 测试键值遍历
   - 测试嵌套遍历

### 阶段 2: AOT 实现 (4-6 小时)

5. **完善 IR 生成** (2-3 小时)
   - 检查 `generateForeachStmt()` 实现
   - 生成正确的控制流
   - 处理键值变量

6. **实现 IR 指令** (1-2 小时)
   - `foreach_init`
   - `foreach_has_next`
   - `foreach_get_key`
   - `foreach_get_value`
   - `foreach_next`

7. **代码生成** (1-2 小时)
   - 在 `native_linker.zig` 中生成 C 代码
   - 调用运行时函数

8. **测试验证** (1 小时)
   - 测试 AOT 编译
   - 对比解释器输出

### 阶段 3: 优化和边界情况 (2-4 小时)

9. **性能优化**
   - 避免不必要的内存分配
   - 优化迭代器状态

10. **边界情况**
    - 空数组
    - 单元素数组
    - 大数组
    - 引用传递 (`foreach ($arr as &$val)`)

## 预计总时间

- **VM 实现**: 4-6 小时
- **AOT 实现**: 4-6 小时
- **优化和测试**: 2-4 小时
- **总计**: **10-16 小时**

## 依赖和风险

### 依赖
- 需要理解当前的迭代器实现（如果有）
- 需要理解 VM 的栈操作机制
- 需要理解 AOT 的 IR 结构

### 风险
- 迭代器状态管理可能复杂
- 引用传递 (`&$val`) 可能需要额外工作
- 性能可能不如原生循环

### 替代方案
如果实现太复杂，可以考虑：
1. **转换为 for 循环**: 在编译时将 foreach 转换为 for 循环
2. **仅支持数组**: 先不支持关联数组和对象
3. **简化实现**: 不支持引用传递

## 后续工作

实现 foreach 后，可以解决：
- ✅ test_7.php - 关联数组遍历
- ✅ test_30.php - 数组遍历
- ✅ test_39.php - 数组遍历
- ✅ 其他所有使用 foreach 的测试

---

**优先级**: **P0 - 立即实施**  
**预计完成**: 2-3 天（全职工作）  
**负责人**: xiusin
