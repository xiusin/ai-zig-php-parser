# AOT编译器已知问题

## 🔴 问题1: foreach内部try-catch触发unreachable (P0)

### 问题描述
当PHP代码中存在**foreach循环内部的try-catch块**时，AOT编译器会触发unreachable panic。

### 触发条件
```php
foreach ($array as $item) {
    try {
        // 任何代码
    } catch (Exception $e) {
        // 这里会触发unreachable panic
    }
}
```

### 错误信息
```
thread XXXXX panic: reached unreachable code
/opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/mem/Allocator.zig:147:25: in grow
/opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/hash_map.zig:1296:30: in put
src/aot/ir_generator.zig:2027:43: in generateStatement
```

### 影响范围
- **影响脚本**: 42% (约385/918个gemini_scripts)
- **严重程度**: 🔴 高
- **常见程度**: 非常常见的错误处理模式

### 状态
- **发现时间**: 2026-03-08
- **状态**: 🔴 未解决
- **优先级**: P0 (阻塞性问题)

---

## 🟡 问题2: 数组迭代器integer overflow (P1)

### 问题描述
在某些情况下，数组迭代器会触发integer overflow panic。

### 触发条件
- 嵌套的foreach循环（3层或更多）
- 每层foreach都包含try-catch
- 数组操作频繁

### 错误信息
```
thread XXXXX panic: integer overflow
/opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/multi_array_list.zig:228:35: in slice
    ptr += field_size * self.capacity;
                      ^
runtime_lib.zig:1205:71: in iterator
runtime_lib.zig:3155:40: in php_array_iter_init
```

### 影响范围
- **影响脚本**: ~1% (test_0007.php等)
- **严重程度**: 🟡 中
- **触发条件**: 特定的数组操作模式（嵌套foreach+try-catch）

### 根本原因
ArrayHashMap的capacity字段在某些情况下被设置为非常大的值，导致`field_size * self.capacity`溢出。

可能的原因：
1. Double free导致内存破坏
2. ArrayHashMap内部状态被破坏
3. Zig标准库的bug

### 状态
- **发现时间**: 2026-03-08
- **状态**: 🟡 待修复
- **优先级**: P1
- **需要**: 深入调试ArrayHashMap的内存管理

---

## 🟢 问题3: StringTooLarge限制 (P2)

### 问题描述
字符串大小限制为100MB，超过会报错。

### 错误信息
```
error: StringTooLarge
runtime_lib.zig:860:13: in init
```

### 影响范围
- **影响脚本**: ~2% (test_0033.php, test_0036.php等)
- **严重程度**: 🟢 低
- **说明**: 这是正常的资源限制，不是bug

### 状态
- **发现时间**: 2026-03-08
- **状态**: 🟢 按设计工作
- **优先级**: P2 (可选优化)

---

## 不受影响的情况

### 问题1的Workaround
```php
// ✅ 这些模式都正常工作
try {
    foreach ($array as $item) {
        // ...
    }
} catch (Exception $e) {
    // ...
}

// ✅ 或使用函数封装
function processWithErrorHandling($item) {
    try {
        processItem($item);
    } catch (Exception $e) {
        logError($e);
    }
}

foreach ($items as $item) {
    processWithErrorHandling($item);
}
```

---

## 统计总结

### 前100个脚本分析
- **总计**: 88个有效脚本
- **成功**: 48个 (54%)
- **问题1 (unreachable)**: 37个 (42%)
- **问题2 (overflow)**: 1个 (1%)
- **问题3 (StringTooLarge)**: 2个 (2%)

### 预估总影响 (918个脚本)
- **问题1**: ~385个 (42%)
- **问题2**: ~9个 (1%)
- **问题3**: ~18个 (2%)
- **理论通过率**: 55% (如果修复问题1可达97%)

---

**最后更新**: 2026-03-08 09:20
**当前通过率**: 52.8% (93/176)
**目标通过率**: 97%+ (修复问题1后)

