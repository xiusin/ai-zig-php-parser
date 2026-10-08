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
| P2 | ~~核对 §需要修复的地方 列出的 **7 处裸 `reg_a = reg_b;`**~~ ⇒ **结案（2026-10-06，任务 #87）**：逐处实读证明 **7 枚全部不需改走 `writePtrAwareAssign`**（3 枚自带 retain、4 枚属 helper 认可的非拥有指针拷贝口径），详见 **§P2 逐项核对结果**；原「绕过 retain」表述已在该节按现文更正 | 引用计数一致性（**非类型问题**） | 实测成本 = 一次逐处实读，**零编译** |
| P2 | ~~**唯一存活线索**：ref 参数 alloca 槽写入的 retain 分歧需 `=&` 压测探针定性~~ ⇒ **结案（2026-10-06，任务 #88）**：永久探针 `t001_refparam_retain_probe_tmp.php`（S1–S5 五形 × 200000 轮压测）在**默认档**编译成功、`run_rc=0`，除 `MEM=` 行外与 PHP **逐字节等值** ⇒ 该分歧在探针覆盖的几何下**无可观测后果**（无变空/垃圾/段错误等提前释放症状），维持「不改发射侧」；详见 **§P2 存活线索运行时定性** | 引用计数一致性 + 引用 cell 回收上界 | 实测成本 = 1 枚探针 + 1 次编译运行 |
| **P1（新立单）** | 同一探针在 `--optimize=release-fast` 档**编译失败**，顺此线索立项 [AOT-CODEGEN-007](AOT-CODEGEN-007-function-inlining-param-args-lost.md)：**函数内联 pass 不替换 callee 的 `.param`**（`optimizer.zig:4861`）⇒ 按引用形参编译失败／按值形参静默错值／多块 callee 返回值丢失；默认档 `function_inlining=false` ⇒ 冻结语料面 0 | release-safe / release-fast 档的全部内联调用点（含 PERF-001 默认档 P0 的耦合） | 中（优化器侧 4 处，**属编译器语义改动 ⇒ 待点头**） |
| P2 | 把 `t001_phi_type_mix_tmp.php` 纳入常跑探针门（与 16 探针门同批执行） | 测试资产 | 低 |

**风险**: 低（历史变更范围明确，当前树已复测）

---

**更新日志**:
- 2026-10-06（任务 #87 → #88 同轮）: **#87 的 P2 核对项与 #88 的存活线索均结案**，本工单不再有未定性的静态分歧。#87 = 7 枚裸拷贝逐处实读（3 自带 retain / 4 非拥有口径）⇒ 全部不需改走 helper，见 §P2 逐项核对结果；#88 = 新建永久探针 `t001_refparam_retain_probe_tmp.php` 在默认档单次编译运行，除 `MEM=` 行外 9/10 行与 PHP 逐字节等值 ⇒ `:21069` 的不 retain 无可观测后果，见 §P2 存活线索运行时定性（同批给出 REF-002 R-6 的 4151 B/轮回收缺口读数）。**副产物**：该探针在 `--optimize=release-fast` 档编译失败，顺线索立项 [AOT-CODEGEN-007](AOT-CODEGEN-007-function-inlining-param-args-lost.md)（函数内联不替换 callee `.param`）⇒ 本工单的复测命令今后**必须固定默认档**，否则会被 CODEGEN-007 的编译失败掩盖。零源码改动（`fbe6382a`/32797、`git diff --numstat` = `5 4`）。
- 2026-10-01: **状态 部分修复 → CLOSED**。代码取证：方案 1 的 `generatePhiValueAssignment` 已落地（:17953，8 调用点）且比草图完备；`writePtrAwareAssign`（:1076，118 调用点）承担标签驱动侧同类收口；发射 `reg_N = reg_M.toInt()/toFloat()/toBool()` 的点 grep 结果为 **0 处**。复测：新建永久探针 `fuzzy_scripts_720/tmp/t001_phi_type_mix_tmp.php`（四形 × 五种 PHP 类型跨臂 PHI）编译零 `error:`、运行 `RUN_RC=0`、与 PHP 逐字节等值。同轮更正 PHI 特化误锚（→ `optimizer.zig:2036-2059`）、换掉 2026 早期行号、替换他人机器路径的复测命令，并登记 7 处裸拷贝的 P2 核对项

## 锚点代次刷新（2026-10-05，当前工作区代次 `fbe6382a`／32797 行实测；只读巡检，零代码改动）

本文正文、状态行与 §相关文件 的行号登记于 **RC-4 `0ff09cf`／RC-5 工作区** 代次（`9490bf9f`/32663 之前），已被 A／D／R9-B 三批（`497edc6`）与 #74 注释批整体推过 ⇒ **按符号 grep 逐条实测**（非偏移推算）得到下表。**历史值一律保留不改写**，动手时以本表为准。

| 符号 / 语句 | 本文旧登记 | **当前树实测** | 实测依据 |
|---|---|---|---|
| `writePtrAwareAssign`（标签驱动侧统一赋值） | `:1090` | **`:1333`** | `grep -n "fn writePtrAwareAssign"` 唯一命中 |
| 该函数内 `retain()`（裸拷贝绕过面） | `:1133` | **`:1376`**（`_ = reg_{d}.retain();`，同一 `else` 分支） | `sed -n '1370,1382p'` 逐行核对 |
| `writePhiAssignWithRetain` | `:1139` | **`:1382`** | `grep -n "fn writePhiAssignWithRetain"` |
| `generatePhiValueAssignment`（方案 1 的统一函数） | `:18098` | **`:18403`** | `grep -n "fn generatePhiValueAssignment"` |
| 其 **8 个调用点** | `:17707`/`:17799`/`:17848`/`:17856`/`:17862`/`:25923`/`:31750`/`:31755` | **`:18012` / `:18104` / `:18153` / `:18161` / `:18167` / `:26228` / `:32055` / `:32060`** | `grep -n "generatePhiValueAssignment("` = **9** 命中（1 定义 + 8 调用）⇒ 计数与本文「8 个调用点」一致，仅行号漂移 |
| `generatePhiAssignments`（旧 `:9958` 的后继位置） | `:31727` | **`:32032`**（另有同族 `generatePhiAssignmentsParallel` 在 `:18494`，勿混） | `grep -n "fn generatePhiAssignments"` = 两处命中 |
| `writePtrAwareAssign` **117 个调用点**计数 | 117 | **仍为 117** | `grep -c "writePtrAwareAssign("` = **118**（1 定义 + 117 调用） |
| 7 处绕过 `writePtrAwareAssign` 的裸拷贝（P2 核对项） | `:19467`/`:19544`/`:20766`/`:20929`/`:20939`/`:21850`/`:22468` | **`:19772` / `:19849` / `:21071` / `:21234` / `:21244` / `:22155` / `:22773`** | `grep -n "reg_{d} = reg_{d};"` = **15** 命中，剔除两函数内部 8 处（`:1352`/`:1364`/`:1375` 属 `writePtrAwareAssign`，`:18440`/`:18446`/`:18461`/`:18472`/`:18487` 属 `generatePhiValueAssignment`）后恰余 **7** 处 ⇒ 计数与本文一致 |

**状态判定不受行号漂移影响**：本文的致损形态是**把原生类型转换直接赋给 `runtime.Value` 寄存器**，按该精确形状实测 `grep -E 'reg_\{d\} = reg_\{d\}\.(toInt|toFloat|toBool)'` = **0 处** ⇒ 结论维持。需说明口径：文件内 `.toInt()`/`.toBool()`/`.toFloat()` 的原生取值发射**并非 0**（`reg_{d}.toInt()` 9 处、`.toFloat()` 1 处、`.toBool()` 11 处），但它们一律被 `runtime.Value.initInt(...)` 重新包装（如 `:20057`、`:20930`）或落在 `switch`／比较的原生上下文（`:19265`、`:19299`），**不属于**本工单缺陷形态。⇒ 该判定是**形状特定**的，不可复述成「全文件零原生转换」。7 处裸拷贝的类型口径不变 ⇒ **CLOSED 维持**；P2「7 处是否需同步 `retain()`」的核对成本未变，只是定位行号需按本表走。

## P2 逐项核对结果（2026-10-06，任务 #87；零插桩、零编译、零源码改动）

**判据口径先行**（实读 `writePtrAwareAssign` `:1333`–`:1378`）：该函数 8 个分支里**只有两支刻意不 retain** —— `:1352`（普通 alloca ← ref_ptr：指针重定向，不拷贝值）与 `:1364`（ref_ptr ← ref_ptr，注释原文「ref_ptr 不拥有值，无需 retain」）；其余分支各自紧跟 `_ = reg_{d}.*.retain();` 或 `_ = reg_{d}.retain();`（`:1343`/`:1349`/`:1357`/`:1361`/`:1372`/`:1376`）。⇒ 「裸拷贝即缺 retain」这一表述不成立，**唯一有效判据是目标寄存器是否拥有该值**。

| 站点 | 语境（实测） | retain / release 就地证据 | 判定 |
|---|---|---|---|
| `:19772` | `.box` 的 else 支（`:19758–:19764` 按 alloca 四分流后落入「两侧均非 alloca」） | 前置条件化 release `:19769–:19771`（`shouldReleaseReg ∧ regMayHeap`）+ 后置 retain `:19773`；注释原文「所有者语义（与 cast 一致）：目标寄存器是独立所有者。裸别名会使 cleanup 对同一值双重释放……（f044）」 | **已闭合**，不需改走 helper |
| `:19849` | `.store`：`op.value ∈ current_ref_ptr_regs` ∧ 目标是 alloca ∧ `!isRefParamAlloca`（`:19837–:19851`） | 无 retain —— 与 helper `:1352` **同几何同口径**（指针重定向） | **已闭合**（非拥有） |
| `:21071` | 引用参数实参初始化：源 `reg` 由 `args[..].asRef()` 得 `*Value`（`:21055`），目标满足 `isPointerReg`（`:21070`） | 同块三支 `:21069`/`:21071`/`:21073` 之后仅 `break;`，**整块无 retain** | 本轮判**非拥有**（源与目标皆 `*Value`）⇒ 不改；但见下方分歧 1 |
| `:21234` / `:21244` | `.select`：结果寄存器 ∈ `current_ref_ptr_regs`（`:21221`）且该臂源为指针（`:21225`/`:21226`） | 无 retain —— 目标为非拥有 ref_ptr，与 helper `:1364` 同口径 | **已闭合**（非拥有） |
| `:22155` | 排序类内建（`php_sort`/`rsort`/`asort`/…/`natsort`/`natcasesort`）COW store-back 的非 alloca 支（`:22150–:22156`） | 后置 retain `:22158`，注释原文「store-back 后两个寄存器共享同一数组，需增加引用计数」 | **已闭合** |
| `:22773` | 同族第二处（`php_usort`/`uasort`/`uksort`/`shuffle`/`sort`… 组，`:22769–:22774`） | 后置 retain `:22776`（同注释） | **已闭合** |

**净结论**：**7 枚全部不需要改走 `writePtrAwareAssign`** ⇒ P2「是否应同步引用计数」核对项**结案**（成本 = 一次逐处实读，零编译）。原句「它们绕过 `writePtrAwareAssign` 的 `retain()`」按现文更正为：**3 枚自带 retain（`:19772`/`:22155`/`:22773`），4 枚属 helper 自身认可的「非拥有指针拷贝／重定向」口径（`:19849`/`:21071`/`:21234`/`:21244`）**。

**两条新登记的口径分歧（静态可证，定性需运行时探针；本轮不作缺陷断言）**：

1. **ref 参数 alloca 槽写入的 retain 不一致**：helper 在「alloca ← ref_ptr ∧ 目标是引用参数 alloca」支**retain**（写 `.*` 于 `:1348` + retain 于 `:1349`），而引用参数**实参初始化**路径的同一几何（`:21069`，`isRefParamAlloca(store_op.ptr.id)` 支）**不 retain**。是否为缺陷取决于「该槽位此刻是否已被调用方持有」⇒ **已于同轮定性**（永久探针 + 默认档单次编译运行，见 **§P2 存活线索运行时定性**）：五形 × 200000 轮压测下输出与 PHP 逐字节等值 ⇒ **无可观测后果**，维持不改动；该探针同时给出 REF-002 **R-6** 的每轮 4151 B 回收缺口读数（方向相反，独立登记）。
2. **`.box` 的四支分流不查 `current_ref_ptr_regs`**（`:19749–:19764` 只测 `current_alloca_regs`），而 helper 以 alloca × ref_ptr **双轴**分类 ⇒ 二者仅在「两侧均非 ref_ptr」几何下等价；`box` 的结果寄存器为 ref_ptr 的**语料面未实测**，禁止据此推断有或无风险。

**复算自证（2026-10-06 实测）**：`md5` = `fbe6382a2e0904b6740d771b88c409c7`、`wc -l` = 32797、`git diff --numstat` = `5 4`（#74 原样）⇒ 零源码改动、零编译，不产生新门读数，R15 收尾轮的十二腿（12/12）登记值继续有效。计数逐条复现：`grep -c 'reg_{d} = reg_{d};'` = **15**（helper 内 8 + 外部 7，行号与本表逐字一致）；`self.writePtrAwareAssign(` = **117**、`self.generatePhiValueAssignment(` = **8**，与 §刷新表的 117／8 一致。

**工具口径更正（防复发）**：本轮一度把「同一式子只返回 9 行」记为 BSD grep BRE 对 `{d}` 的解析陷阱，**复跑同一命令实测返回 15 行 ⇒ 该说法作废**，真实原因是命令输出被显示截断。固化为口径：**计数类结论必须以 `grep -c` 或 `wc -l` 复核，禁止以一次带外截断的行数差作断言**。

## P2 存活线索运行时定性（2026-10-06，任务 #88；永久探针 + 单次编译运行，零源码改动）

**探针**：`fuzzy_scripts_720/tmp/t001_refparam_retain_probe_tmp.php`（永久保留，勿删）。五形 = S1 引用参数整体改写为 4101 字节堆字符串 / S2 两个引用参数互换 / S3 引用参数指向数组并追加（COW 换代）/ S4 同一变量的引用参数跨两帧 / S5 引用参数与局部别名共存后 `unset` 局部名；末尾 200000 轮 `s1_overwrite($pressure)` 压测。

| 档 | 编译 | 运行 | 等值判定（`MEM=` 行按设计不参与） |
|---|---|---|---|
| 默认档（`--compile --no-debug-info`，`function_inlining=false`） | `rc=0` | `rc=0` | **10 行输出中 9 行逐字节等值**（`S0/S1/S2/S3/S4-inner/S4/S5/PRESSURE-ALIVE/DONE`）⇒ 无变空、无垃圾、无段错误 ⇒ 「`:21069` 支不 retain」在探针覆盖的几何下**无可观测后果** ⇒ 判定**维持不改发射侧**，本 P2 线索结案 |
| `--optimize=release-fast` | **`rc=1`** | — | `main.zig:3627:46: error: expected type '*runtime_lib.Value', found 'runtime_lib.Value'`（另 1 处同形）⇒ **非本工单类型缺陷**，归因链见新立单 [AOT-CODEGEN-007](AOT-CODEGEN-007-function-inlining-param-args-lost.md)（函数内联把 callee 的 `.param` 原样搬进 caller 帧） |

**REF-002 R-6 同批读数（引用 cell 回收上界）**：同一探针的 `MEM_AFTER=/DELTA=` 行（200000 轮压测前后 `memory_get_usage()` 差）——

| 侧 | `DELTA`（字节） | 折算每轮 |
|---|---|---|
| PHP 真值 | `8224` | ≈ 0.04 B |
| AOT（默认档） | `830181854` | ≈ **4151 B/轮** |

⇒ AOT 每轮保留约一枚 4 KB 块（与 4101 字节的改写值同量级）⇒ **R-6「引用 cell/被引用值无回收」在按引用参数改写路径上量化成立**，斜率约等于「每轮一个新堆载荷且旧载荷不归还」。该读数与本轮的 retain 判定**方向相反**（少 retain ⇒ 提前释放；实测是少释放 ⇒ 累积），故二者不可互相佐证，各自独立登记：**retain 分歧 = 无可观测后果；回收缺口 = 有稳定斜率**。回收侧修复归 REF-002 R-6 裁决项，不在本工单范围。

**工具口径追加**：`MEM=` 绝对值（830298919 vs 512584）不可比较（分配器与池化策略不同，见 AOT-MEM-001），只有 `DELTA` 可用；探针头部注释已写明该行不参与等值。
