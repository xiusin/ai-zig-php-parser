# 类型推断系统设计 - 向前兼容的深度优化方案

## 🎯 设计目标

1. **双向类型推断** - 前向 + 反向传播
2. **全局一致性** - 统一求解所有约束
3. **向前兼容** - 渐进式添加新约束类型
4. **可扩展** - 支持更复杂的类型关系

## 🏗️ 架构设计

### 核心组件

```
┌─────────────────────────────────────────┐
│     Type Constraint Solver              │
│  (约束收集 + 统一求解)                    │
└─────────────────────────────────────────┘
           ↑                    ↓
    收集约束              求解结果
           │                    │
┌──────────┴────────────────────┴─────────┐
│     Type Inference Pass                 │
│  (遍历 IR，生成约束，应用结果)            │
└─────────────────────────────────────────┘
           ↑                    ↓
      IR 输入              类型标注的 IR
```

### 约束类型

1. **具体类型约束** - `T = i64`
   - 来源：常量、已特化的 phi 节点
   
2. **等式约束** - `T1 = T2`
   - 来源：move 指令、赋值

3. **二元操作约束** - `T_result = T_lhs op T_rhs`
   - 规则：`i64 + i64 = i64`
   - 反向：如果 `T_result = i64` 且 `T_lhs = i64`，则 `T_rhs = i64`

4. **Phi 约束** - `T_result = phi(T1, T2, ...)`
   - 规则：所有 incoming 类型相同 → result 也是该类型
   - 反向：result 类型已知 → 传播到所有 incoming

### 求解算法

```zig
while (changed) {
    for (constraint in constraints) {
        // 前向传播
        if (can_infer_from_operands(constraint)) {
            infer_result_type(constraint);
            changed = true;
        }
        
        // 反向传播
        if (can_infer_from_result(constraint)) {
            infer_operand_types(constraint);
            changed = true;
        }
    }
}
```

## 🔄 双向传播示例

### 场景：循环变量优化

**IR 代码：**
```
block_entry:
  reg_0 = const.i64 0
  br loop_header

loop_header:
  reg_15 = phi [reg_0, entry], [reg_9, loop_body]  // 已特化为 i64
  reg_4 = cast reg_15 (i64 → php_value)
  reg_6 = lt reg_4, reg_5
  br reg_6, loop_body, exit

loop_body:
  reg_7 = cast reg_15 (i64 → php_value)
  reg_9 = add reg_7, reg_8  // reg_8 = const.i64 1
  br loop_header
```

**约束收集：**
```
C1: reg_0 = i64                    (具体类型)
C2: reg_15 = phi(reg_0, reg_9)     (phi 约束)
C3: reg_15 = i64                   (phi 已特化)
C4: reg_9 = add(reg_7, reg_8)      (二元操作)
C5: reg_8 = i64                    (具体类型)
```

**求解过程：**
```
迭代 1 (前向):
  C1 → reg_0 = i64
  C5 → reg_8 = i64
  C3 → reg_15 = i64

迭代 2 (反向):
  C2 + C3 → reg_9 = i64  (phi 反向传播)
  
迭代 3 (反向):
  C4 + C5 + (reg_9 = i64) → reg_7 = i64  (二元操作反向传播)
```

**结果：**
- `reg_7 = i64` → cast 可以被穿透
- `add(i64, i64) → i64` → 可以特化为原生加法

## 📊 优化效果预测

| 优化 | 当前 | 双向推断后 | 提升 |
|------|------|-----------|------|
| Cast 消除 | 1/迭代 | 10+/迭代 | 10x |
| 操作特化 | 1/迭代 | 20+/迭代 | 20x |
| 类型覆盖率 | 12/N | 80%+ | 6x+ |

**预期性能：** 7.8x → **<3x** 慢于 PHP

## 🛠️ 实施计划

### Phase 1: 基础约束求解器 (P0)
- [ ] TypeConstraintSolver 基础结构
- [ ] 具体类型约束
- [ ] 等式约束
- [ ] 前向传播算法

### Phase 2: 二元操作约束 (P0)
- [ ] 算术操作约束
- [ ] 比较操作约束
- [ ] 反向传播规则

### Phase 3: Phi 约束 (P1)
- [ ] Phi 节点约束收集
- [ ] Phi 反向传播
- [ ] 跨基本块一致性验证

### Phase 4: 高级约束 (P2)
- [ ] 子类型关系
- [ ] 条件类型（类型窄化）
- [ ] 跨函数类型推断

## 🔮 未来扩展

### 1. 类型窄化
```php
if (is_int($x)) {
    // 这里 $x 的类型窄化为 int
    $y = $x + 1;  // 可以特化
}
```

### 2. 跨函数推断
```php
function add_one(int $x): int {
    return $x + 1;
}

$result = add_one($i);  // $result 推断为 int
```

### 3. 数组元素类型
```php
$arr = [1, 2, 3];  // array<int>
$sum = array_sum($arr);  // 可以 SIMD 优化
```

## 📝 设计原则

1. **渐进式** - 每个 Phase 独立可测试
2. **向后兼容** - 新约束不影响旧代码
3. **可调试** - 每个约束记录来源
4. **性能优先** - 求解算法 O(n) 复杂度

## 🎯 成功指标

- 类型推断覆盖率 > 80%
- Cast 消除率 > 90%
- 性能 < 3x 慢于 PHP
- 编译时间增加 < 20%
