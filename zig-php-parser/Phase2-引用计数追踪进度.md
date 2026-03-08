# Phase 2: 引用计数追踪进度报告

**时间**: 2026-03-08 10:47  
**通过率**: 38/48 (79.2%)  
**Commit**: 868e476

---

## 🎯 当前状态

### 通过率
- Phase 1.0 (foreach cleanup): 54.1%
- Phase 1.5 (ArrayList重构): 79.2%
- **Phase 2.0 (引用计数追踪): 79.2%** ← 当前

### 失败的11个脚本
```
test_0003, test_0006, test_0007, test_0009, test_0028,
test_0030, test_0033, test_0034, test_0036, test_0038, test_0048
```

---

## 🔍 问题分析

### 根本原因：迭代器未被释放

**test_0007的迭代器生命周期**:
```
ITER_INIT: iter=0x104bd4000 array=0x104bc4010  ← 最外层
ITER_INIT: iter=0x104c28000 array=0x104bc4098  ← 第2层
ITER_FREE: iter=0x104c28000 array=0x104bc4098  ✅
ITER_INIT: iter=0x1095f8000 array=0x104bc41a8  ← 第3层
ITER_FREE: iter=0x1095f8000 array=0x104bc41a8  ✅
ITER_INIT: iter=0x1096c4000 array=0x104bc41a8  ← 第4层
❌ 最外层迭代器(0x104bd4000)从未被FREE
```

### 为什么没被释放？

**控制流分析**:
```
foreach_cond → valid? → yes: foreach_body
                     → no: foreach_cleanup → foreach_exit

foreach_body → (用户代码) → foreach_increment → foreach_cond
            → (异常) → try_catch → finally → ❌ 绕过cleanup
```

**关键问题**:
- foreach body中的try-catch捕获异常
- 异常处理完成后，直接继续执行
- **没有回到foreach的cleanup块**
- 导致迭代器泄漏

---

## 🧪 尝试的修复

### 尝试1: 在catch变量store前retain ❌
```zig
const retained_catch = try self.emitWithResult(.{ .retain = catch_reg }, .php_value);
_ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = retained_catch } }, null);
```
**结果**: 通过率下降到37/48 (过度retain)

### 尝试2: 添加cleanup_catch块 ❌
```zig
// 在foreach body/cond/increment设置exception_handler
body_block.exception_handler = cleanup_catch_block;

// cleanup_catch块清理迭代器并重新抛出
const exception_reg = try self.emitWithResult(.{ .catch_ = ... }, .php_value);
_ = try self.emit(.{ .throw = exception_reg }, null);
```
**结果**: 通过率下降到37/48 (引入新问题)

### 尝试3: ArrayIterator双重释放防护 ⚠️
```zig
pub const ArrayIterator = struct {
    freed: bool = false,
    // ...
};

pub fn php_array_iter_free(...) {
    if (iter.freed) return;
    iter.freed = true;
    // ...
}
```
**结果**: 通过率38/48 (防护未触发，问题不在双重释放)

---

## 💡 核心洞察

### 问题不是双重释放，而是**未释放**

**证据**:
1. 双重释放防护从未触发
2. 迭代器日志显示INIT但没有FREE
3. 最外层foreach的迭代器总是泄漏

### 为什么cleanup块没执行？

**场景**: 嵌套foreach + try-catch
```php
foreach ($arr0 as $k => $v) {  // ← 最外层
    // ...
    foreach ($arr2 as $k => $v) {  // ← 内层
        // ...
        try {
            throw new Exception();
        } catch (Exception $e) {
            // 异常被捕获
        }
    }
    // ← 这里应该继续外层foreach
}
```

**实际执行**:
1. 外层foreach开始 → ITER_INIT(0x104bd4000)
2. 内层foreach开始 → ITER_INIT(0x104c28000)
3. try-catch捕获异常
4. 内层foreach结束 → ITER_FREE(0x104c28000) ✅
5. **外层foreach异常退出** → ❌ 没有FREE(0x104bd4000)

### 真正的问题

**foreach的cleanup块只在两种情况下执行**:
1. ✅ 正常结束 (valid=false)
2. ✅ break语句
3. ❌ **异常退出** ← 问题在这里

**为什么异常退出不执行cleanup？**
- foreach body设置了exception_handler指向外层catch
- 异常直接跳到catch，绕过cleanup
- cleanup块变成死代码

---

## 🚧 正确的解决方案

### 方案A: 使用defer语义 (推荐)

**思路**: 在IR中添加defer指令，确保cleanup总是执行

```zig
// 伪代码
foreach_start:
    iter = php_array_iter_init(array)
    defer php_array_iter_free(iter)  // ← 无论如何都会执行
    
    while (php_array_iter_valid(iter)) {
        // body
    }
```

**实现**:
1. 在IR中添加`defer`指令
2. codegen时生成cleanup代码
3. 所有退出路径（正常/break/异常）都执行defer

### 方案B: 修改异常处理链

**思路**: 让异常先经过cleanup再传播

```zig
foreach_body.exception_handler = cleanup_catch_block

cleanup_catch_block:
    php_array_iter_free(iter)
    exception = catch_exception()
    throw exception  // 重新抛出
```

**问题**: 已尝试，通过率下降（可能实现有误）

### 方案C: 使用RAII包装器

**思路**: 在runtime中创建RAII迭代器

```zig
const ScopedIterator = struct {
    iter: *ArrayIterator,
    allocator: Allocator,
    
    pub fn deinit(self: *ScopedIterator) void {
        php_array_iter_free(Value.initInt(@intFromPtr(self.iter)), self.allocator);
    }
};
```

**问题**: IR中没有RAII语义

---

## 📋 下一步行动

### 优先级排序

**P0 - 立即执行**:
1. 重新实现方案B (cleanup_catch)，修复实现错误
2. 或实现方案A (defer指令)

**P1 - 后续优化**:
3. 添加完整的引用计数追踪
4. 实现智能指针

### 推荐：方案A (defer指令)

**理由**:
- 语义清晰，符合RAII
- 不依赖异常处理链
- 可以处理所有退出路径

**工作量**: 2-3小时

**步骤**:
1. 在IR中添加`defer`指令类型
2. 在ir_generator中emit defer指令
3. 在codegen中生成cleanup代码
4. 测试验证

---

## 🎯 预期效果

### 方案A (defer)
- 通过率: 79.2% → **95%+**
- 迭代器泄漏: 完全消除
- 引用计数: 正确匹配

### 方案B (cleanup_catch修复)
- 通过率: 79.2% → **90%+**
- 迭代器泄漏: 大部分消除
- 可能还有边缘情况

---

**当前阻塞**: 需要选择方案并实施
**推荐**: 方案A (defer指令)
**预计时间**: 2-3小时
