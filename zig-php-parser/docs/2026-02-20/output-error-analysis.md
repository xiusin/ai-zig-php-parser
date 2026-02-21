# 输出错误问题分析

## 问题用例
1. 05_foreach_break: 输出 0，预期 6
2. 51_unset_iter_consistency: 输出 3,10，预期 2,6  
3. 52_foreach_by_ref: 输出 6，预期 36

## 根本原因

**结构化循环中的 PHI 节点未正确初始化和更新**

### 现象
- PHI 节点被标记为 "handled in terminator"
- 但实际上没有生成初始化和更新代码
- 导致 PHI 寄存器保持初始值（0 或默认值）

### 示例（05_foreach_break）
```zig
var reg_29: i64 = 0;  // PHI 节点，应该累加 sum
// PHI: reg_29 (handled in terminator)  // 注释说处理了，但实际没有
return runtime.Value.initInt(reg_29);  // 返回 0
```

### 问题位置
`src/aot/native_linker.zig` 中的结构化循环生成：
- `generateWhileLoopStructuredNew` (5795行)
- `generateForLoopStructuredNew` (6012行)

这些函数生成结构化 while/for 循环时，PHI 节点的初始化和更新逻辑不完整。

## 修复方案

### 方案 1：完善结构化循环的 PHI 处理
在 `generateWhileLoopStructuredNew` 和 `generateForLoopStructuredNew` 中：
1. 循环前：为每个 PHI 节点生成初始化代码
2. 循环体末尾：生成 PHI 更新代码

### 方案 2：回退到状态机模式
对于包含复杂 PHI 的循环，使用状态机模式而非结构化循环。

## 优先级
**P1 - 高优先级**

虽然不影响编译和运行稳定性，但输出错误会导致功能不正确，必须修复。

## 建议
优先修复方案 1，因为结构化循环性能更好。如果复杂度太高，可以考虑方案 2 作为后备。
