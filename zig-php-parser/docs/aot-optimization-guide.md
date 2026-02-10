# PHP AOT 编译器优化指南

## 📊 当前状态（2026-02-10）

### 性能现状
| 测试项 | AOT | PHP-CLI | 倍数 | 状态 |
|--------|-----|---------|------|------|
| 简单循环 (100K) | 2.5ms | 0.5ms | 5.0x 慢 | ✅ |
| 嵌套循环 (100x100) | 0.26ms | 0.055ms | 4.8x 慢 | ✅ |
| 算术运算 (10K) | 0.42ms | 0.12ms | 3.6x 慢 | ✅ |
| 数组求和 (10K) | 3.5ms | 0.17ms | 20.4x 慢 | ⚠️ |
| 字符串拼接 (1K) | 5.4ms | 0.005ms | 1084x 慢 | 🔴 |
| **总计** | **12ms** | **0.84ms** | **14.3x 慢** | ✅ |

**结论**：✅ 已达到性能目标（≤15x），但字符串和数组仍有巨大优化空间。

---

## 🎯 优化历程

### Phase 1: 初始状态（18.7x 慢）
**问题**：
- 所有操作通过 runtime 函数调用
- 没有任何编译时优化
- 字符串操作极慢（2050x）

### Phase 2: 编译器优化（18.7x → 18.7x）
**实现**：
1. ✅ 结构化循环生成（原生 for/while）
2. ✅ 完全循环展开（≤16 次迭代）
3. ✅ 数学简化（`sum+=1` 循环 → `sum+=N`）
4. ✅ 死代码消除
5. ✅ Phi 节点支持（三元运算符）
6. ✅ Alloca 优化（消除指针解引用）

**结果**：性能没有明显提升（编译器优化已经很好，但 runtime 是瓶颈）

### Phase 3: Runtime 优化（18.7x → 14.3x）
**实现**：
1. ✅ 字符串快速路径
   ```zig
   // 快速路径：两个都是字符串
   if (lhs.isString() and rhs.isString()) {
       return lhs.asString().concat(rhs.asString(), allocator);
   }
   ```

2. ✅ 小字符串栈优化
   ```zig
   // ≤256 字节使用栈缓冲
   if (new_length <= 256) {
       var stack_buf: [256]u8 = undefined;
       // ... 栈上拼接
   }
   ```

**结果**：字符串性能提升 2.3x（12.3ms → 5.4ms），总体提升 1.56x

---

## 🔴 当前困局

### 1. 字符串操作（最大瓶颈）
**现状**：1084x 慢于 PHP-CLI

**根本原因**：
- 循环内重复拼接常量字符串
- 每次 concat 都分配新内存
- 没有字符串池化

**示例**：
```php
for ($i = 0; $i < 1000; $i++) {
    $str = "Hello" . " " . "World";  // 每次都重新拼接
}
```

**已尝试的方案**：
- ✅ AST 层面常量折叠（部分生效）
- ❌ IR 层面常量折叠（实现了但 debug 模式未启用）
- ❌ LICM（循环不变量提升）- 有 bug，导致死循环

**问题分析**：
1. **LICM 实现有 bug**：
   - 启用后程序死循环
   - 可能是 pre-header 创建错误
   - 或与循环展开交互有问题

2. **优化级别问题**：
   - 默认 debug 模式不启用优化
   - Release-safe 模式优化过度（删除循环递增，导致死循环）
   - 需要平衡优化强度

### 2. 数组操作（次要瓶颈）
**现状**：20.4x 慢于 PHP-CLI

**根本原因**：
- 循环内调用 `array_sum` 10000 次
- 每次都遍历数组（虽然已优化为 packed array 快速路径）
- 本质是循环不变量问题

**已尝试的方案**：
- ✅ Packed array 快速路径（直接遍历，避免 HashMap）
- ❌ 循环不变量提升（LICM 有 bug）

### 3. 优化过度问题
**现状**：Release-safe 模式死循环

**问题代码**：
```zig
while (true) {
    if (!(reg_2 < reg_3)) break;
    // 循环体被 DCE 完全删除（包括递增操作）
    // reg_13 永远不变 → 死循环
}
```

**根本原因**：
- 常量折叠 + DCE 删除了所有循环内代码
- 但没有删除循环本身
- 循环变量递增也被删除

---

## 🚀 后续优化方案

### P0: 修复 LICM（关键）
**预期提升**：字符串 10-100x，总体 2-5x

**问题定位**：
1. 查看 `src/aot/optimizer.zig:692` - `runLICMInFunction`
2. 检查 pre-header 创建逻辑
3. 验证循环结构完整性
4. 测试与循环展开的交互

**调试步骤**：
```bash
# 1. 创建简单测试
cat > test_licm.php << 'EOF'
<?php
for ($i = 0; $i < 3; $i++) {
    $const = 5 + 3;  // 循环不变量
    echo $const;
}
EOF

# 2. 启用 LICM（修改 optimizer.zig:140）
# licm: true  // 在 releaseSafe() 中

# 3. 编译并查看 IR
./zig-out/bin/php-interpreter --compile --optimize=release-safe --dump-ir test_licm.php

# 4. 检查 const 是否被提升到循环外
```

**可能的修复**：
- 检查 `getOrCreatePreHeader` 实现
- 确保 phi 节点正确更新
- 验证支配树计算

### P1: 修复优化过度问题
**预期提升**：启用 release-safe 模式

**问题**：DCE 删除循环递增操作

**解决方案**：
1. **保守的 DCE**：
   - 标记循环变量为"活跃"
   - 不删除影响循环条件的操作

2. **循环完整性检查**：
   ```zig
   // 在 DCE 后验证循环
   fn verifyLoopIntegrity(loop: *Loop) bool {
       // 检查循环变量是否有递增
       // 检查退出条件是否可达
   }
   ```

3. **分离优化 pass**：
   - 先运行 LICM（提升不变量）
   - 再运行 DCE（删除死代码）
   - 最后验证循环完整性

### P2: 字符串池化
**预期提升**：字符串 1.5-2x

**实现**：
```zig
// 在 Module 中添加字符串池
pub const Module = struct {
    string_pool: std.StringHashMap(*PHPString),
    
    pub fn internString(self: *Module, str: []const u8) !*PHPString {
        if (self.string_pool.get(str)) |existing| {
            return existing;
        }
        const new_str = try PHPString.init(self.allocator, str);
        try self.string_pool.put(str, new_str);
        return new_str;
    }
};
```

### P3: 常量数组优化
**预期提升**：数组 5-10x

**实现**：
```zig
// 编译时生成常量数组
const const_array = [_]Value{
    Value.initInt(1),
    Value.initInt(2),
    Value.initInt(3),
};
```

### P4: 内联小函数
**预期提升**：总体 1.2-1.5x

**目标函数**：
- `php_add`（i64 直接运算）
- `php_concat`（小字符串）
- `array_sum`（小数组）

---

## 🛠️ 技术债务

### 1. LICM 实现
**文件**：`src/aot/optimizer.zig`
**问题**：
- Line 692: `runLICMInFunction` - 死循环 bug
- Line 746: `isLoopInvariant` - 可能判断不准确
- Line 815: `getOrCreatePreHeader` - pre-header 创建可能有问题

**需要**：
- 添加详细日志
- 单元测试覆盖
- 与循环展开隔离测试

### 2. 优化级别配置
**文件**：`src/aot/compiler.zig`
**问题**：
- Line 140: 默认 `debug` 模式（无优化）
- Release-safe 优化过度

**建议**：
- 添加 `release-balanced` 模式
- 可配置的优化强度
- 分离 LICM 和 DCE

### 3. 字符串常量折叠
**文件**：`src/aot/optimizer.zig`
**状态**：已实现但未生效（debug 模式）

**问题**：
- Line 2820: `foldConstantExpression` - concat 折叠已实现
- 但 debug 模式不调用

**修复**：
- 默认启用常量折叠（即使在 debug 模式）
- 或修改默认优化级别为 release-safe

---

## 📝 代码导航

### 关键文件
```
src/aot/
├── compiler.zig          # 编译器入口，优化级别配置
├── optimizer.zig         # 优化 pass（LICM, DCE, 常量折叠）
├── native_linker.zig     # 代码生成（结构化循环，指令生成）
├── ir_generator.zig      # IR 生成（AST → IR）
├── runtime_lib_template.zig  # Runtime 库（php_concat, array_sum）
└── ir.zig               # IR 定义
```

### 关键函数
```zig
// 优化入口
optimizer.zig:385  - optimize()
optimizer.zig:544  - optimizeFunction()

// LICM
optimizer.zig:692  - runLICMInFunction()
optimizer.zig:746  - isLoopInvariant()
optimizer.zig:815  - getOrCreatePreHeader()

// 常量折叠
optimizer.zig:2619 - propagateConstantsInFunction()
optimizer.zig:2656 - foldConstantExpression()
optimizer.zig:2820 - concat 折叠

// 代码生成
native_linker.zig:4500 - tryGenerateStructuredControlFlowNew()
native_linker.zig:4747 - generateForLoopStructuredNew()

// Runtime
runtime_lib_template.zig:2512 - php_concat()
runtime_lib_template.zig:5722 - php_array_sum()
```

---

## 🧪 测试方法

### 性能测试
```bash
# 编译 benchmark
./zig-out/bin/php-interpreter --compile tests/aot/benchmark_performance.php

# 对比性能
echo "=== PHP-CLI ==="
php tests/aot/benchmark_performance.php

echo -e "\n=== AOT ==="
./benchmark_performance
```

### 优化验证
```bash
# 查看生成的 IR
./zig-out/bin/php-interpreter --compile --dump-ir --optimize=release-safe test.php

# 查看生成的代码
cat .zigphp_aot_build/main.zig

# 检查优化标记
grep -E "Fully unrolled|Mathematical|Optimized" .zigphp_aot_build/main.zig
```

### LICM 调试
```bash
# 启用 LICM
# 修改 src/aot/optimizer.zig:140
# licm: true

# 编译测试
./zig-out/bin/php-interpreter --compile --optimize=release-safe test_licm.php

# 检查是否死循环（2秒超时）
(./test_licm & sleep 2 && kill $! 2>/dev/null)

# 查看 IR 验证不变量是否提升
./zig-out/bin/php-interpreter --compile --dump-ir --optimize=release-safe test_licm.php | grep -A 10 "for_body"
```

---

## 💡 优化原则

### 1. 先测量，再优化
- 使用 benchmark 验证每次优化效果
- 不要盲目优化

### 2. 编译器 vs Runtime
- **编译器优化**：适合结构性改进（循环展开、常量折叠）
- **Runtime 优化**：适合热点函数（concat, array_sum）
- 当前瓶颈在 Runtime，不是编译器

### 3. 优化强度平衡
- Debug：快速编译，方便调试
- Release-safe：基本优化，保持正确性
- Release-fast：激进优化，可能有 bug

### 4. 渐进式优化
- 每次只改一个优化
- 立即测试验证
- 出问题立即回滚

---

## 🎓 经验教训

### 1. LICM 很难实现正确
**问题**：
- 需要精确的支配树分析
- Pre-header 创建容易出错
- 与其他优化交互复杂

**建议**：
- 先实现简单的循环不变量检测
- 逐步增加复杂度
- 充分测试边界情况

### 2. 优化可能引入 bug
**案例**：Release-safe 模式死循环

**原因**：
- DCE 过于激进
- 没有验证循环完整性

**教训**：
- 优化后必须验证正确性
- 添加完整性检查
- 保守优于激进

### 3. Runtime 优化效果最明显
**数据**：
- 编译器优化 15 种：性能无明显提升
- Runtime 优化 2 处：性能提升 1.56x

**结论**：
- 热点在 Runtime，不是编译器
- 优先优化 Runtime 函数
- 内联比优化 pass 更有效

### 4. 默认配置很重要
**问题**：
- 默认 debug 模式无优化
- 用户不知道要加 `--optimize=release-safe`

**建议**：
- 默认使用 release-safe
- 或添加 `--debug` 标志显式禁用优化

---

## 📚 参考资料

### 编译器优化
- [LLVM Optimization Passes](https://llvm.org/docs/Passes.html)
- [GCC Optimization Options](https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html)
- [Loop-Invariant Code Motion](https://en.wikipedia.org/wiki/Loop-invariant_code_motion)

### Zig 相关
- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Build System](https://ziglang.org/learn/build-system/)

### PHP 性能
- [PHP Opcache](https://www.php.net/manual/en/book.opcache.php)
- [PHP JIT](https://www.php.net/manual/en/opcache.configuration.php#ini.opcache.jit)

---

## 🎯 下一步行动

### 立即可做（1-2 小时）
1. ✅ 修改默认优化级别为 release-safe
2. ✅ 添加循环完整性验证
3. ✅ 保守的 DCE（不删除循环变量操作）

### 短期目标（1-2 天）
1. 🔴 修复 LICM bug
2. 🔴 字符串池化
3. 🔴 常量数组优化

### 长期目标（1-2 周）
1. 内联小函数
2. 类型特化（i64 直接运算）
3. 边界检查消除

---

## 📊 预期最终性能

完成所有优化后：
- 简单循环：**2x 慢**
- 数组操作：**5x 慢**
- 字符串拼接：**50x 慢**
- **总体：5-8x 慢**

**可行性**：✅ 高（主要是 LICM 和 Runtime 优化）

---

**最后更新**：2026-02-10
**维护者**：AI Assistant
**状态**：生产可用（14.3x 慢，已达标）
