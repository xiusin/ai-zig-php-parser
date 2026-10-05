# AOT-TYPE-001 完整修复方案

**问题**: Phi 节点类型不匹配
**优先级**: P0（高）
**状态**: **CLOSED（2026-10-01 复测 + 代码取证；下列行号属 RC-4 `0ff09cf`(+145) / RC-5 工作区(+54) 代次，R9-B 代次实测见本段末）** —— 本文推荐的**方案 1 已落地**：统一函数 `generatePhiValueAssignment`（`src/aot/native_linker.zig:18098`，8 个调用点：:17707 / :17799 / :17848 / :17856 / :17862 / :25923 / :31750 / :31755），内部按 `result_reg.type_` **原始类型**而非推断类型分支，并额外处理 alloca / ref_ptr / 引用计数 retain-release（比本文草图完备）；标签驱动发射侧的同类收口由 `writePtrAwareAssign`（:1090，**117 个调用点**，另有 1 处定义）承担。**复测**：新永久探针 `fuzzy_scripts_720/tmp/t001_phi_type_mix_tmp.php`（int/string/double/bool/null 跨臂 PHI × for/foreach/while/do-while，用 `gettype()` 暴露误特化）编译 `COMPILE_RC=0`、compile stderr 中 `error:` **0 行**、运行 `RUN_RC=0` 且输出与 `/opt/homebrew/bin/php` **逐字节等值**。
>
> **代次刷新（2026-10-05 实测，R9-B 干净树 `0e38b018b24b9ba0aa358f8d26a7f012`／32796 行，直接 grep 非偏移换算）**：`generatePhiValueAssignment` 定义 **`:18402`**，8 个调用点 **`:18011` / `:18103` / `:18152` / `:18160` / `:18166` / `:26227` / `:32054` / `:32059`**（`grep -n` 命中 11 行 = 8 调用 + 2 注释提及 `:18006`/`:18149` + 1 定义 ⇒ 调用点计数仍为 8，结论不变）；`writePtrAwareAssign` 定义 **`:1333`**，`grep -c 'writePtrAwareAssign('` = **118** = 117 调用点 + 1 定义（口径与数量均未变）。本文其余各处行号仍属 RC-5 代次，行动前须按符号 re-grep。  

---

## 问题分析

### 根本原因

1. **类型推断与寄存器声明不一致**
   - 所有寄存器都声明为 `runtime.Value`
   - 但类型推断（`current_register_types`）认为某些寄存器是 i64/f64/bool
   - Phi 预赋值生成时使用推断类型，导致生成 `.toInt()` 等转换
   - 但寄存器实际是 Value 类型，导致类型不匹配

2. **Phi 预赋值生成点太多**
   - 至少 10 处代码生成 phi 预赋值
   - 每处都需要正确处理类型转换
   - 当前只修复了 2 处

### 影响范围

- 复杂算法脚本编译失败
- 涉及循环和条件分支的代码

---

## 已完成的修复

1. ✅ Phi 节点类型特化逻辑
   - 只有当所有 incoming 值都是同一原生类型时才特化
   - 如果有 php_value，保持 php_value

2. ✅ 部分 phi 预赋值生成
   - `generatePhiAssignments` (行 9958)
   - 终止指令生成中的 phi 预赋值 (行 2929)

---

## 需要修复的地方

### Phi 预赋值生成点

> **2026-10-01 收口现状（2026-10-03 按 RC-4/RC-5 行号漂移重新 grep 刷新；下表行号仍为 2026 早期几何，已失效，仅保留作历史线索）**：实测 grep —— 发射 `reg_N = reg_M.toInt()/toFloat()/toBool()` 的点**当前为 0 处**，即本工单的致损形态（向 `runtime.Value` 寄存器发原生类型转换）已不存在；phi 赋值收敛到 `generatePhiValueAssignment`（:18098）与 `writePtrAwareAssign`（:1090）两个统一函数。另有 **7 处**裸 `reg_{d} = reg_{d};` 拷贝位于两个函数之外（:19467 / :19544 / :20766 / :20929 / :20939 / :21850 / :22468）—— 类型正确（Value←Value），**不属于本工单缺陷**，但它们绕过了 `writePtrAwareAssign` 的 `retain()`（:1133），是否需要同步引用计数需逐处核对 ⇒ 登记为下方 P2，不作缺陷断言。

| 行号 | 位置 | 状态 |
|------|------|------|
| 2929 | 终止指令生成 | ✅ 已修复 |
| 6173 | 循环初始化 | ❌ 未修复 |
| 6266 | 循环更新 | ❌ 未修复 |
| 6394 | 循环条件 | ❌ 未修复 |
| 6782 | 嵌套循环 | ❌ 未修复 |
| 6881 | 嵌套循环 | ❌ 未修复 |
| 7030 | 循环展开 | ❌ 未修复 |
| 7366 | 循环优化 | ❌ 未修复 |
| 8263 | 状态机生成 | ❌ 未修复 |
| 8338 | 状态机生成 | ❌ 未修复 |
| 9958 | generatePhiAssignments | ✅ 已修复 |

---

## 推荐解决方案

### 方案 1: 统一修复所有 phi 预赋值生成（推荐）

**步骤**:
1. 创建一个统一的函数 `generatePhiValueAssignment`
2. 所有 phi 预赋值生成都调用这个函数
3. 函数内部使用原始类型，不是推断类型

**优点**:
- 一次修复，所有地方生效
- 代码复用，减少重复
- 易于维护

**缺点**:
- 需要重构现有代码

**实现**:

```zig
fn generatePhiValueAssignment(
    self: *Self,
    writer: anytype,
    result_reg: IR.Register,
    value_reg: IR.Register,
    indent: []const u8,
) !void {
    // 使用原始类型，不是推断类型
    const result_tag = @as(std.meta.Tag(IR.Type), result_reg.type_);
    const value_tag = @as(std.meta.Tag(IR.Type), value_reg.type_);
    
    if (result_tag == .php_value or result_tag == value_tag) {
        // 直接赋值
        try writer.print("{s}reg_{d} = reg_{d};\n", .{ indent, result_reg.id, value_reg.id });
    } else if (value_tag == .php_value and result_tag != .php_value) {
        // 从 php_value 转换到原生类型（不应该发生，因为所有寄存器都是 Value）
        try writer.print("{s}reg_{d} = reg_{d};\n", .{ indent, result_reg.id, value_reg.id });
    } else {
        // 其他情况，直接赋值
        try writer.print("{s}reg_{d} = reg_{d};\n", .{ indent, result_reg.id, value_reg.id });
    }
}
```

### 方案 2: 禁用类型推断（激进）

**步骤**:
1. 移除 `current_register_types`
2. 所有寄存器都使用原始类型
3. 简化代码生成逻辑

**优点**:
- 彻底解决类型不一致问题
- 简化代码

**缺点**:
- 可能影响性能优化
- 需要大量测试

### 方案 3: 修复寄存器声明生成（长期）

**步骤**:
1. 根据类型推断结果生成寄存器声明
2. 如果推断为 i64，声明为 i64
3. 如果推断为 php_value，声明为 Value

**优点**:
- 类型一致
- 可能提升性能

**缺点**:
- 需要重构寄存器声明生成
- 需要处理类型转换

---

## 实施计划

### 阶段 1: 快速修复（1-2 小时）

1. 实现 `generatePhiValueAssignment` 函数
2. 修复所有 10 处 phi 预赋值生成
3. 测试 test_complex_algorithms.php

### 阶段 2: 完善测试（1 小时）

1. 测试 test_complex_webapp.php
2. 添加更多边界测试
3. 确保所有测试通过

### 阶段 3: 长期优化（可选）

1. 评估方案 2 和方案 3
2. 选择最优方案
3. 重构代码

---

## 测试用例

### 历史失败形态（2026-02 读数，勿再照跑）

```text
.zigphp_aot_build/main.zig:333:34: error: expected type 'runtime_lib.Value', found 'i64'
            reg_28 = reg_17.toInt();
```

（原命令写在他人机器的 `/Users/tuoke/...` 路径下、且依赖 `/tmp/test_complex_algorithms.php` 散脚本，两者均已不存在。）

### 2026-10-01 复测（永久探针 `fuzzy_scripts_720/tmp/t001_phi_type_mix_tmp.php`，勿删）

```bash
cd /Users/wangjianjun/products/parser
timeout 10 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/t001_phi_type_mix_tmp.php
timeout 300 ./zig-out/bin/php-interpreter --compile --no-debug-info \
  --output=/tmp/aot_compile_t001_phi_type_mix_tmp fuzzy_scripts_720/tmp/t001_phi_type_mix_tmp.php
timeout 10 /tmp/aot_compile_t001_phi_type_mix_tmp
rm -f /tmp/aot_compile_t001_phi_type_mix_tmp
```

| 形 | 覆盖 | 实测 |
|---|---|---|
| T1 | `for` 携带变量依次取 string / int / bool / double / null，`gettype()` 逐轮打印 | `COMPILE_RC=0`、compile stderr `error:` 0 行、`RUN_RC=0`，与 PHP 逐字节等值（`T1 i=3 type=double v=3` … `final_type=string`） |
| T2 | `foreach` + `??` 产生的混合类型 PHI 累加 | 同上（`T2 sum=13 kinds=integer,string,double,string,string,integer`） |
| T3 | 嵌套 `for`，外层携带 string、内层携带 int，两侧退出边各带 PHI | 同上（`T3 r0:12\|r1:12\|r2:12`） |
| T4 / T4b | `while(true)`+`break` 与 `do-while` 中函数返回混合类型 | 同上（`T4 string:k1,integer:0,…` / `T4b acc=x12x34 d=4`） |

⇒ 类型误特化若在，`gettype()` 必错报；四形全等值 ⇒ 症状不复现。

---

## 相关文件

> 工单原文的 `:2929 / :6173-8338 / :9958` 为 2026 早期几何。**2026-10-01 实测锚点**：

- `src/aot/optimizer.zig:2036-2059` — Phi 节点类型特化规则（原文注释「只有当所有 incoming 值都是同一原生类型时才特化」，:2037 / :2059 两处）。**注**：工单原文写的 `optimizer.zig:1750` 是误锚（该处实为参数 COW-skip 标记）；`type_specialization_pass.zig` 内**不含** phi 分支，故 PHI 特化只此一处
- `src/aot/native_linker.zig:1090` — `writePtrAwareAssign`（标签驱动侧统一赋值，含 alloca/ref_ptr 解引用与 `retain()`，**117 个调用点**；2026-10-03 重新 grep）
- `src/aot/native_linker.zig:1139` — `writePhiAssignWithRetain`（PHI 赋值 + retain 的薄封装；2026-10-03 重新 grep）
- `src/aot/native_linker.zig:18098` — `generatePhiValueAssignment`（本工单方案 1 的统一函数，**8 个调用点**，见 §状态；行号为 2026-10-03 重新 grep）
- `src/aot/native_linker.zig:31727` — `generatePhiAssignments`（旧登记 :9958 的后继位置；2026-10-03 重新 grep）

---

## 总结

**收口结论（2026-10-01）**：方案 1（统一赋值函数）已落地，且比本文草图完备 —— 除类型分支外还处理 alloca / ref_ptr / 引用计数 retain-release。本工单的致损形态（向 `runtime.Value` 寄存器发射 `.toInt()` 等原生转换）在代码中**已无发射点**（grep 0 处），复测探针四形编译零错误且与 PHP 逐字节等值 ⇒ 判 **CLOSED**。

| 优先级 | 后续 | 影响面 | 落地成本 |
|---|---|---|---|
| P2 | 核对 §需要修复的地方 列出的 **7 处裸 `reg_a = reg_b;`**（2026-10-03 重新 grep：:19467 / :19544 / :20766 / :20929 / :20939 / :21850 / :22468；原登记 :19322 组因 RC-4 `0ff09cf` 的 +145 而漂移）是否应改走 `writePtrAwareAssign` 的 retain 路径；若其语境的值已被持有则维持现状，只在文档登记「不拥有值」的边界 | 引用计数一致性（**非类型问题**） | 低（逐点判定），但属发射侧改动 ⇒ 需走回归 + 基线漂移门 |
| P2 | 把 `t001_phi_type_mix_tmp.php` 纳入常跑探针门（与 16 探针门同批执行） | 测试资产 | 低 |

**风险**: 低（历史变更范围明确，当前树已复测）

---

**更新日志**:
- 2026-10-01: **状态 部分修复 → CLOSED**。代码取证：方案 1 的 `generatePhiValueAssignment` 已落地（:17953，8 调用点）且比草图完备；`writePtrAwareAssign`（:1076，118 调用点）承担标签驱动侧同类收口；发射 `reg_N = reg_M.toInt()/toFloat()/toBool()` 的点 grep 结果为 **0 处**。复测：新建永久探针 `fuzzy_scripts_720/tmp/t001_phi_type_mix_tmp.php`（四形 × 五种 PHP 类型跨臂 PHI）编译零 `error:`、运行 `RUN_RC=0`、与 PHP 逐字节等值。同轮更正 PHI 特化误锚（→ `optimizer.zig:2036-2059`）、换掉 2026 早期行号、替换他人机器路径的复测命令，并登记 7 处裸拷贝的 P2 核对项
