# 高级 AOT 优化技术

## 概述

本模块实现了来自 Zig、Rust、Java HotSpot、Go 等现代编译器的先进优化技术，进一步提升 AOT 编译性能。

## 优化技术详解

### 1. 标量替换（Scalar Replacement of Aggregates）

**来源**: Java HotSpot C2 编译器

**原理**: 
- 将对象分解为独立的标量变量
- 避免堆分配，改为栈分配
- 消除对象访问开销

**示例**:
```php
// 优化前
class Point {
    public $x;
    public $y;
}
$p = new Point();
$p->x = 10;
$p->y = 20;
$sum = $p->x + $p->y;

// 优化后（标量替换）
$x = 10;
$y = 20;
$sum = $x + $y;  // 无对象分配
```

**性能提升**: 
- 消除堆分配开销（~100ns）
- 提高缓存局部性
- 减少 GC 压力

**参考资料**:
- [HotSpot Escape Analysis and Scalar Replacement](https://cr.openjdk.java.net/~cslucas/escape-analysis/EscapeAnalysis.html)
- [Improving OpenJDK Scalar Replacement](https://devblogs.microsoft.com/java/improving-openjdk-scalar-replacement-part-1-3/)

---

### 2. 全局值编号（Global Value Numbering, GVN）

**来源**: Go 编译器 SSA 优化

**原理**:
- 识别等价的表达式
- 消除冗余计算
- 使用哈希表跟踪已计算的值

**示例**:
```php
// 优化前
$a = $x + $y;
$b = $x + $y;  // 冗余计算
$c = $a + $b;

// 优化后（GVN）
$a = $x + $y;
$b = $a;       // 复用已计算的值
$c = $a + $a;
```

**性能提升**:
- 减少计算次数
- 降低寄存器压力
- 提高指令级并行

**参考资料**:
- [Optimizing SSA Code: GVN-PRE](https://medium.com/@mikn/optimizing-ssa-code-gvn-pre-69de83e3be29)
- [Go SSA Optimization Rules](https://quasilyte.dev/blog/post/go_ssa_rules/)

---

### 3. 稀疏条件常量传播（Sparse Conditional Constant Propagation, SCCP）

**来源**: Go 编译器

**原理**:
- 结合常量传播和死代码消除
- 只沿可达控制流路径传播常量
- 使用格值（Lattice）表示常量状态

**格值定义**:
```
Top ∩ any = any
Bottom ∩ any = Bottom
ConstantA ∩ ConstantA = ConstantA
ConstantA ∩ ConstantB = Bottom
```

**示例**:
```php
// 优化前
$x = 10;
if ($x > 5) {
    $y = $x + 20;  // $x 已知为 10
} else {
    $y = $x - 5;   // 不可达
}

// 优化后（SCCP）
$x = 10;
$y = 30;  // 常量折叠 + 死代码消除
```

**性能提升**:
- 比单独应用常量传播和死代码消除更强大
- 发现更多优化机会
- 快速收敛（每个格值最多降低两次）

**参考资料**:
- [Go SCCP Implementation](http://golang.google.cn/src/cmd/compile/internal/ssa/sccp.go)
- [Sparse Conditional Constant Propagation](https://en.wikipedia.org/wiki/Sparse_conditional_constant_propagation)

---

### 4. 超字级并行（Superword Level Parallelism, SLP）向量化

**来源**: LLVM、现代编译器

**原理**:
- 识别直线代码中的同构指令
- 将标量指令打包为向量指令
- 使用 ILP 求解器全局优化打包策略

**示例**:
```php
// 优化前
$a[0] = $x[0] + $y[0];
$a[1] = $x[1] + $y[1];
$a[2] = $x[2] + $y[2];
$a[3] = $x[3] + $y[3];

// 优化后（SLP 向量化）
// 使用 SIMD 指令一次处理 4 个元素
$a[0:3] = $x[0:3] + $y[0:3];  // 单条向量指令
```

**性能提升**:
- 2-4 倍吞吐量提升
- 减少指令数量
- 提高 SIMD 利用率

**参考资料**:
- [Globally Optimized SLP Framework](https://dl.acm.org/doi/10.1145/3276480)
- [Superword Level Parallelism](https://dl.acm.org/doi/10.1145/3519939.3523701)

---

### 5. 多面体循环优化（Polyhedral Loop Optimization）

**来源**: LLVM Polly、学术研究

**原理**:
- 使用多面体模型表示循环
- 应用数学变换优化循环
- 同时优化并行性和数据局部性

**支持的变换**:
- 循环交换（Loop Interchange）
- 循环分块（Loop Tiling）
- 循环融合（Loop Fusion）
- 循环分裂（Loop Fission）

**示例**:
```php
// 优化前（缓存不友好）
for ($i = 0; $i < 1000; $i++) {
    for ($j = 0; $j < 1000; $j++) {
        $C[$i][$j] = $A[$i][$j] + $B[$i][$j];
    }
}

// 优化后（循环分块）
for ($ii = 0; $ii < 1000; $ii += 32) {
    for ($jj = 0; $jj < 1000; $jj += 32) {
        for ($i = $ii; $i < min($ii+32, 1000); $i++) {
            for ($j = $jj; $j < min($jj+32, 1000); $j++) {
                $C[$i][$j] = $A[$i][$j] + $B[$i][$j];
            }
        }
    }
}
```

**性能提升**:
- 10-100 倍缓存命中率提升
- 更好的并行性
- 减少内存带宽需求

**参考资料**:
- [Polyhedral Compilation](https://link.springer.com/chapter/10.1007/978-3-319-43659-3_17)
- [Performance Vocabulary for Affine Loop Transformations](https://ar5iv.labs.arxiv.org/html/1811.06043)

---

### 6. 循环向量化（Loop Vectorization）

**来源**: 所有现代编译器

**原理**:
- 自动将循环转换为向量操作
- 依赖分析确保正确性
- 生成 SIMD 指令

**示例**:
```php
// 优化前
for ($i = 0; $i < 1000; $i++) {
    $a[$i] = $b[$i] * 2.0;
}

// 优化后（向量化）
for ($i = 0; $i < 1000; $i += 4) {
    // 使用 SIMD 一次处理 4 个元素
    $a[$i:$i+3] = $b[$i:$i+3] * [2.0, 2.0, 2.0, 2.0];
}
```

**性能提升**:
- 2-8 倍吞吐量提升（取决于向量宽度）
- 减少循环开销
- 更好的内存带宽利用

**参考资料**:
- [Loop-Oriented Pointer Analysis for SIMD Vectorization](https://www.researchgate.net/publication/322850339)
- [Hardware-Aware Code Transformation](https://dl.acm.org/doi/10.1145/2723772.2723776)

---

## 优化流水线

推荐的优化顺序：

1. **SCCP（稀疏条件常量传播）** - 发现常量和死代码
2. **GVN（全局值编号）** - 消除冗余计算
3. **标量替换** - 消除对象分配
4. **循环向量化** - 向量化简单循环
5. **SLP 向量化** - 向量化直线代码
6. **多面体优化** - 复杂循环变换

## 性能预期

| 优化技术 | 典型提升 | 适用场景 |
|---------|---------|---------|
| 标量替换 | 2-5x | 大量小对象分配 |
| GVN | 1.2-1.5x | 冗余计算多的代码 |
| SCCP | 1.3-2x | 常量密集型代码 |
| SLP 向量化 | 2-4x | 直线代码中的同构操作 |
| 多面体优化 | 10-100x | 嵌套循环 + 数组操作 |
| 循环向量化 | 2-8x | 简单循环 |

## 实现状态

- ✅ 框架已实现
- ✅ 接口已定义
- ⏸️ 具体优化算法待完善
- ⏸️ 测试待添加

## 参考文献

1. **Java HotSpot**:
   - [Escape Analysis and Scalar Replacement](https://cr.openjdk.java.net/~cslucas/escape-analysis/)
   - [Improving Scalar Replacement](https://devblogs.microsoft.com/java/improving-openjdk-scalar-replacement-part-1-3/)

2. **Go Compiler**:
   - [SCCP Implementation](http://golang.google.cn/src/cmd/compile/internal/ssa/sccp.go)
   - [SSA Optimization Rules](https://quasilyte.dev/blog/post/go_ssa_rules/)

3. **LLVM**:
   - [Globally Optimized SLP](https://dl.acm.org/doi/10.1145/3276480)
   - [Polyhedral Compilation](https://link.springer.com/chapter/10.1007/978-3-319-43659-3_17)

4. **Rust**:
   - [MIR Optimizations](https://internals.rust-lang.org/t/mir-optimize-for-loop-on-integer-ranges/17731)
   - [Iterator Optimizations](https://cceckman.com/writing/rust-iterator-optimizations/)

5. **Academic Research**:
   - [Performance Vocabulary for Affine Loop Transformations](https://ar5iv.labs.arxiv.org/html/1811.06043)
   - [Loop-Oriented Pointer Analysis](https://www.researchgate.net/publication/322850339)
