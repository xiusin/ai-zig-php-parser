# AOT-CODEGEN-009 · `::class` 四个解析面：`parent::class` 折叠成字面量 `"parent"`（含无父类时该致命却静默）、`$对象::class` 返回空串、`$字符串::class` 该致命却照常解析

**问题 ID**: AOT-CODEGEN-009
**优先级**: P1（B/D 两面为**该致命而不致命**的静默错值；A/C 为值错）
**性质**: 混合 —— A/B 在**发射/IR 侧**（`src/aot/ir_generator.zig` 的 `::class` 快速路径），C/D 在**运行时侧**（`php_get_class_constant_dynamic`）
**状态**: **OPEN（四面已独立探针实测并进门；修复待裁决，未动一字节源码）**
**发现日期**: 2026-10-07（任务 #114，替身探针 `f004_ro_unser_tmp.php` 的 `class_const` 形；该形同时受 AOT-CODEGEN-008 §3B 影响，故本单改用**无链直线探针**取证）
**触发档**: 默认档（`--compile --no-debug-info`）

**代次锚点（本轮实测）**

| 资产 | md5 | 行数 |
|---|---|---|
| `zig-out/bin/php-interpreter` | `1f15e4ce9b5c9cdaaef7cabf5efb9c76` | — |
| `src/aot/ir_generator.zig` | `cb53c2da7d4fe2e1f62b728511f7c3ea` | 9732 |
| `src/aot/native_linker.zig` | `fbe6382a2e0904b6740d771b88c409c7` | 32797 |
| `src/aot/runtime_lib_template.zig` | `008b7b639f1069cb73e443064e115ed1` | 30810 |
| 门读数 `fuzzy_scripts_720/tmp/c009_class_const_gate_tmp.tsv` | `C009_DONE probes=4 same=0 diff=4 compile_fail=0` | `ELAPSED=16s` |

---

## 1. 四面实测（门：`fuzzy_scripts_720/tmp/c009_class_const_gate_tmp.sh`，每形一文件独立编译，零 `if/elseif` 链）

| 形 | 探针 | PHP 真值 | AOT | rc(P/A) | 判读 |
|---|---|---|---|---|---|
| **A** `parent::class`（有父类，三层链两处调用） | `c009_a_parent_class_tmp.php` | `midup=parent=GRoot`、`leafup=parent=GMid`（按**定义类的父类**词法解析） | `midup=parent=parent`、`leafup=parent=parent` | 0/0 | **DIFF：值 = 字面量 token** |
| **B** `parent::class`（作用域无父类） | `c009_b_no_parent_tmp.php` | `PHP Fatal error: Cannot use "parent" when current class scope has no parent` | `p=parent=parent` + `DONE` | **255/0** | **DIFF：该致命 → 静默错值，进程正常退出** |
| **C** `$对象变量::class` | `c009_c_var_class_tmp.php` | `obj=VBravo` | `obj=`（**空串**） | 0/0 | **DIFF：空串** |
| **D** `$字符串变量::class` | `c009_d_str_class_tmp.php` | `PHP Fatal error: Uncaught TypeError: Cannot use "::class" on string` | `str=DAlpha`（照常解析） | **255/0** | **DIFF：非法语法被静默放行** |

**控制面（同门内逐字节等值，落地时必须保持 SAME ⇒ 禁止顺手改）**：
`self::class`（继承方法内 = 定义类 `GRoot`，三层链全等）、`static::class` 晚期静态绑定（`mid=GMid`、`leaf=GLeaf` **两侧全等** ⇒ LSB 路径本身正确）、`GRoot::class` 字面量折叠、`get_class($o)`。

---

## 2. 机制归因（生成码直读 + 实文核对，零插桩零源码改动）

### 2.1 A/B —— `::class` 快速路径跑在 `parent`/`self` 解析之前

`src/aot/ir_generator.zig:8485 generateClassConstantAccess`：

- `:8511` `if (std.mem.eql(u8, const_name, "class")) {` 这一支**先于** `:8525` 起的「解析特殊类名：parent, self, static」块；
- 支内只特判 `static`（`:8513-8519` → 发射 `php_get_called_class_name`，运行时 LSB ⇒ 这正是控制面 `static::class` 等值的原因）；
- 其余（含 `parent`）走 `:8520 const resolved = try self.resolveClassName(class_name);` → `:8521-8522` **折叠成编译期 `const_string`**；
- 而 `resolveClassName`（`:5504`）对 `parent` 是**故意原样返回**：`:5516-5518`

```zig
// ir_generator.zig:5511-5518（实文）
// parent → 保留，运行时解析
if (std.mem.eql(u8, class_name, "parent") or std.mem.eql(u8, class_name, "static")) {
    return class_name;
}
```

⇒ 契约是「留给运行时解析」，但 `::class` 支把它编译期折成了常量 ⇒ 字面量 `"parent"` 直接进入输出。对照同文件 `:8527-8541`：`parent::CONSTANT`（非 `::class`）**确实**按 `self.current_class` 遍历 `module.types.items` 取 `type_def.parent` 解析 ⇒ 同一函数里两套口径，`::class` 支漏了这段。

生成码直读证据（**永久探针 `fuzzy_scripts_720/tmp/c009_b_no_parent_tmp.php`**，零插桩、可复跑）：

```bash
cd /Users/wangjianjun/products/parser
ZIGPHP_AOT_KEEP_TEMP=1 timeout 120 zig-out/bin/php-interpreter --compile \
  --output=/tmp/aot_compile_c009_b_tmp fuzzy_scripts_720/tmp/c009_b_no_parent_tmp.php
# 字符串表（element 0 在文件行 9 ⇒ index = 文件行 − 9）
awk 'NR>=9 && NR<=22 {printf "[%d] %s\n", NR-9, $0}' .zigphp_aot_build_<pid>/main.zig
# 方法体
awk '/pub fn @"PBase::p"/,/^}/' .zigphp_aot_build_<pid>/main.zig | grep -n 'static_strings\|setSourceLocation'
```

实测读数（代次 `1f15e4ce…`）：

```
[0] "PBase"   [1] "p"   [2] "string"   [3] "parent="   [4] "parent"   [5] "class"
[6] "$o"      [7] "p="  [8] "\n"       [9] "DONE\n"    [10] "parent=parent"
// PBase::p 体（仅一条常量装载，挂在源行 :5/:6）
    runtime.setSourceLocation("…/c009_b_no_parent_tmp.php", 5);
    runtime.setSourceLocation("…/c009_b_no_parent_tmp.php", 6);
    reg_4 = runtime.Value.initString(static_strings[10]);   // = "parent=parent"
    return … runtime.php_coerce_value(reg_4, "string", …);
```

⇒ 整条 `'parent=' . parent::class` 在编译期被折成 `"parent=parent"`（index 10），运行期**没有任何解析动作**；表里仍残留 `[3] "parent="`、`[4] "parent"`、`[5] "class"` 三个折叠前碎片 ⇒ 折叠发生在 IR/常量层，`resolveClassName` 交回的未解析 token 被原样拼进了常量。对照 `self::class` 在同批探针里折叠正确（`"self=PBase"`），差异只在 `parent` 一支。

### 2.2 C/D —— 动态入口把变量原样交给 `php_get_class_constant_dynamic`

- 发射侧：`ir_generator.zig:8494-8507`，类名以 `$` 开头时发射 `php_get_class_constant_dynamic(变量值, 常量名字符串)`。永久探针 `fuzzy_scripts_720/tmp/c009_c_var_class_tmp.php:12`（`$o::class`）的生成码（`ZIGPHP_AOT_KEEP_TEMP=1` 直读，无插桩）实测为：

```zig
// main.zig（c009_c 生成码摘录，源行标注均为 :12）
    reg_2 = getGlobalVar("$o");                                  // 对象 Value 原样入参，无预处理
    reg_3 = runtime.Value.initString(static_strings[4]);         // [4] = "class"
    reg_4 = try runtime.php_get_class_constant_dynamic(
        &[_]runtime.Value{ reg_2, reg_3 }, runtime.runtime_allocator);   // main.zig:123
```

  ⇒ **变量值原样传入，不做类型/对象名预处理**（对象走 `else ""` 分支即 C 形空串，字符串走 `::class` 原样返回即 D 形该致命不致命）；
- 运行时侧：`src/aot/runtime_lib_template.zig:20208-20217`

```zig
const class_name = if (args[0].isString()) args[0].asString().data else "";   // :20210 → 对象落入 "" ⇒ C 空串
if (std.mem.eql(u8, const_name, "class")) {                                    // :20214 → 字符串直接当类名返回 ⇒ D 该致命却不致命
    const str = try PHPString.init(allocator, class_name);
    return Value.initString(str);
}
```

⇒ C = `:20210` 的 `else ""` 回落；D = `:20214-20217` 缺「`::class` 只允许对象/类名来源」的类型判定（PHP 侧为 `TypeError: Cannot use "::class" on string`，致命）。

---

## 3. 语料面与风险

| 维度 | 实测结论 |
|---|---|
| 68 语料面（= `fuzzy_scripts_720/pass/f*.php`，官方门只扫该目录：`run_regression.sh:9`/`:98`/`:109`）| **本单四形 0**：`grep -E '(parent\|self\|static)::class'` 与 `\$[A-Za-z_]\w*::class` 在 `pass/` 目录**均 0 命中**（ripgrep 实测）。此前记录的「`static::class` 命中 `f130`」经复核为**误归属**：`f130_test_framework_assert_mock_coverage.php:25` 在 `fuzzy_scripts_720/` 根目录、`f046_exception_handling_chain.php:16` 的 `self::class` 在 `fail_runtime/`，两枚都**不在官方 68 语料内** ⇒ 不构成语料面 |
| 语料内的 `::class` 面（**必须保护的对照**）| **字面量 `ClassName::class` 大量在语料内且逐字节等值**：`f010_oop_singleton_registry_di.php` 12 处、`f104_game_engine_ecs_collision_render.php` 35 处（`grep -E '::class[^a-zA-Z_]'` 实测，`f048:95` 的 `::classify` 为子串假命中，已剔除）⇒ 「基线对本单无保护力」**仅指本单四形**；R-1 改 `resolveClassName` 相关支路时字面量折叠受基线 md5 约束，砸不得 |
| 为何语料 0 | 唯一会命中这些形的 `f004_oop_deep_inheritance_magic.php` 被官方回归 **skip-before-compile** 整枚排除（`run_regression.sh:43-49`，PHP 侧 rc≠0 ⇒ 写 `SKIP` 且不编译 AOT） |
| 静默性 | A/C 静默错值 rc=0；**B/D 把 PHP 致命降级为正常退出**（下游若据此字符串做类名 `findClass`/反射，会拿到 `"parent"` 或空串继续跑） |
| 修复破坏面 | A/B 改 `ir_generator.zig` ⇒ 生成码可能整体移动 ⇒ **需重冻 `baseline_main_zig_md5.tsv` 并跑全门链**；C/D 改模板 ⇒ 发射为 `runtime_lib.zig`，不触发 `main.zig` md5 漂移，但仍需 `timeout 120 zig build` |

---

## 4. 修复路线（优先级 / 影响面 / 落地成本）

| 路线 | 内容 | 优先级 | 影响面 | 落地成本 |
|---|---|---|---|---|
| **R-1** | A/B：`::class` 支（`:8511-8523`）在 `parent` 上复用同函数 `:8527-8541` 已有的「按 `self.current_class` 查 `type_def.parent`」解析；无父类时发射运行期 `Error: Cannot use "parent" when current class scope has no parent`（模板已有同族 scope 守卫先例 `:20236-20245`） | P1 | `parent::class` 全部用法；`self`/`static`/字面量三支必须逐字节不变（控制臂锁定） | 改 `ir_generator.zig`（9732 行，非超大文件但发射相关）⇒ `timeout 120 zig build` + 全门链 + 基线重冻；本门复跑实测 `16s` |
| **R-2** | C：`php_get_class_constant_dynamic`（`:20210`）对 `args[0].isObject()` 取其 `class_meta.name`（等价 `get_class`）后再走 `::class`；保留字符串与非对象两分支的区分 | P1 | 动态 `::class` 与 `Class::CONSTANT` 动态入口（同函数下半段 `:20220-20229`） | 纯模板 ⇒ 不漂基线；`timeout 120 zig build` + 本门 `16s` |
| **R-3** | D：`:20214` 前补「来源必须是对象 ⇒ 否则 `TypeError: Cannot use "::class" on string`（致命）」；与 R-2 同批落地以免两面互相掩盖 | P1 | 同上 | 同上（同批不额外增加实测成本，待实测） |
| **R-4** | 覆盖面探针（**落地前置**）：`parent::CONSTANT`、`$var::CONSTANT`、`self::CONSTANT` 继承链三个面目前**未测**，本门只覆盖 `::class` | P2 | 判定 R-1 是否顺带动到常量查找支路 | 新增 3 形探针，实测成本待补 |

**门控声明**：R-1 属发射侧改动且要重冻基线，R-2/R-3 属运行时语义改动 ⇒ 按宪法 §六 全部**待老铁裁决**；本轮只取证登记。修复顺序建议 R-2/R-3 先行（模板、不漂基线、可单独验收），R-1 走全门链批次。

---

## 5. 复测路径（体验流程）

```bash
cd /Users/wangjianjun/products/parser
timeout 300 bash fuzzy_scripts_720/tmp/c009_class_const_gate_tmp.sh
# 当前代次预期：C009_DONE probes=4 same=0 diff=4，ELAPSED=16s（4 次编译 + 8 次运行）
# 修复后预期   ：probes=4 same=4 diff=0
#   —— 控制面（self/static LSB/字面量/get_class）必须仍等值，否则属砸基线
#   —— B/D 两形的 php_rc=255 一侧必须产出致命文本；AOT 若仍 rc=0 即未消解
```

判读口径：归一化合并 stdout+stderr 逐字节；exit 码只记录不判等（B/D 两侧本应同为 255，当前 AOT 为 0 即「丢致命」的证据本身，但仍按门规范单列）。

---

## 6. 与其他工单的边界（只陈述，不并案）

- **AOT-RUNTIME-002 §2 `class_const` 形**：那张门里的同名形是本单 A+C 两面的旧载体，但它跑在 `if/elseif` 链派发里，其「缺 `DONE`」部分属 **AOT-CODEGEN-008 §3B**；本单的四面门已把它整体替代，RUNTIME-002 里对应行标注为「另立 → 本单」。
- **AOT-CODEGEN-008**：本单探针刻意**不含任何 `if/elseif` 链**，正是为了让四面 DIFF 只能归因 `::class` 解析本身。
- **AOT-CODEGEN-006 形 7（末臂整体未发射）**：与 CODEGEN-008 §3B 的第二面同症状族，本单不涉及。

## 7. 遗留 / 未判定

1. `parent::class` 在**trait**、**接口默认实现**、**顶层函数**（无类作用域）三处作用域未测。
2. B 形的致命在 PHP 是**编译期还是运行期**触发：本探针里 PHP 在 `echo` 前即 Fatal（rc=255 且无任何 stdout），提示偏编译期/早期；AOT 侧要复刻「早于任何输出」还是「调用点抛 Error」需在 R-1 落地时定档（**未判定**）。
3. R-1 若只做编译期解析，`parent::class` 写在被继承方法里时的作用域归属（定义类 vs 调用类）需一枚三层链探针锁定 —— 本门 A 形的 `leaf=` 行走的正是继承方法，可直接复用为验收。
