# AOT-REF-004 · 引用形参的实参边界缺装填：动态调用与内建回调回落 `&null_val` ⇒ 默认档段错误 + 静默错值/丢写回

**状态**: OPEN（2026-10-06 新立项，任务 #89；同轮追加 §7 内建回调族普查；2026-10-07 任务 #111 追加 §7.2「内建回调族引用面实测补测（21 形）」+ §7.3「三枚新崩形崩点归因」⇒ **崩溃面由 1 枚派发器实测扩为 4 枚**（`usort`/`uasort`/`array_map`/`array_filter`），路线 H 的覆盖面已从推断升为实测；2026-10-07 任务 #112 追加 §7.4「H 路线触发面实测」⇒ **H 的定价已实测**：**发射面 27 句／7 枚语料脚本**（⇒ 基线需重冻结 7 行）vs **运行时触发面 0**（`else` 支在绿语料不可达 ⇒ 无负向优化风险，§六-7 前置解除）；2026-10-07 任务 #113 追加 §7.5「动态入口 → 含引用形参的类方法触发面实测」⇒ **§7.4 留下的 TRAMPOLINE 未量边界已闭合，且为负结果**：桩路径不仅**可达**而且**必然走 `else`**（五形探针 4 崩 `rc=139`／1 等值），**「H 不可顶替 E」由推断升为实测**，E 的落点被实测约束到**调用侧实参物化**）
**性质**: AOT 编译期缺陷（**IR 实参装填侧** + **发射侧回落语义**+ 运行模板块缺装填），**默认档即触发** ⇒ 非优化档位问题
**档位**: 默认 `--compile --no-debug-info`（`function_inlining=false`）⇒ **与 [AOT-CODEGEN-007](AOT-CODEGEN-007-function-inlining-param-args-lost.md) 无关且更严重**（那个只在非默认档，这个直接把可执行文件打成 SIGSEGV）
**代次锚点**: `src/aot/native_linker.zig` md5 `fbe6382a2e0904b6740d771b88c409c7`／32797 行（未改）；`src/aot/ir_generator.zig`、`src/aot/runtime_lib_template.zig` 均**只读**
**语料面**: 冻结 68 语料 = **0**（两条口径均实测：① 非 `tmp/` 目录下含「闭包/箭头函数带 `&$` 形参」的脚本只有 `fuzzy_scripts_720/fail_runtime/f008_array_functional_pipeline.php`，而它用的是 `array_walk` ⇒ §1 表内 `ctrl_walk` 属**等值绿**路径；② §7 的逐语句窗口扫描（内建高阶函数 + 回调引用形参声明）在全语料**零命中**）⇒ **基线不覆盖本族 = 未被保护的真功能缺口，不是回归**。**#112 补两个面（§7.4，禁与上条混用）**：**引用形参声明面 = 7/68**（三形态并集实测：具名 7、匿名闭包 0、箭头 0）⇒ 该 7 枚发射 **27 句 `&null_val` 回落**（= H 的**文本漂移面**）；但**回落触发面 = 0**（43 个静态引用位全为 `make_ref` 19 + `initRef` 18 已装填，桩 6 枚无动态入口，`VALUE_PASSED`/`ARG_OMITTED` 均 0）⇒ **语料既崩不到也慢不到，H 的运行时代价只在缺陷路径上**。**#113 补第三个口径（§7.5，禁与前两者混用）**：**机制面 ≠ 0** —— 「动态入口 + 目标帧含回落句」的专用探针五形实测 **4 形 `rc=139`／1 形逐字节等值** ⇒ "语料触发面 0"仅是**基线不保护该路径**，**不可外推为"路径不存在"**（判据 4）。

---

## 1. 症状（六形，全部实测；默认档）

永久探针（**勿删**）：
- `fuzzy_scripts_720/tmp/t007_dynref_shapes_tmp.php`（六形 × `$argv[1]` 选路 ⇒ 一次编译六次运行）
- `fuzzy_scripts_720/tmp/t007_closure_byref_min_tmp.php`（最小复现：CTRL 等值 + 闭包形崩溃）
- `fuzzy_scripts_720/tmp/t007_refparam_noninline_geom_tmp.php`（六形分离：①–⑤ 全等值，⑥ 崩溃 ⇒ 本工单的发现入口，同时结案 CODEGEN-007 §7.2）

| 形 | 调用形态 | PHP 真值 | AOT（默认档） | 判定 |
|---|---|---|---|---|
| CTRL 具名 | `t007dyn_ctrl($v);` | `count=2 last=9` | `count=2 last=9` | 等值 ⇒ **直接调用路径无缺陷** |
| CTRL 内建 | `array_walk($w, function(mixed &$val,$k))` | `val=10` | `val=10` | 等值 ⇒ runtime 侧 `make_ref`（`runtime_lib_template.zig:25569`，`php_array_walk` 起 `:25549`）生效 |
| ① 变量函数名 | `$f='t007dyn_ctrl'; $f($v);` | `count=2 last=9` | **`rc=139`（SIGSEGV），零输出** | **崩溃** |
| ② call_user_func | `call_user_func($t007dyn_cl, $v);` | Warning「Argument #1 ($a) must be passed by reference」+ 按值 | **`rc=139`** | **崩溃**（PHP 是告警+降级，AOT 是段错误） |
| ③ 数组下标 callable | `$pair=[$cl]; $pair[0]($v);` | `count=2 last=42` | **`rc=139`** | **崩溃** |
| ④ `[$obj,'m']` callable | `$f=[$this,'cbRef']; $f($a);` | `count=2 last=7` | **`rc=139`** | **崩溃** |
| ⑤ 闭包变量直调 | `$cl($cb);`（最小探针形 ⑥） | `CLOSURE count=2 last=42` | **`rc=139`** | **崩溃**（本工单主形） |

**关键对照**：同一 callee 换成**具名直接调用**（CTRL 行）即等值 ⇒ 缺陷面**精确落在「callee 无法静态定名」的调用形态**，与引用形参声明本身无关。

---

## 2. 根因（只读取证 + 生成码实证，实测行号）

### 2.1 引用形参的实参装填是**按函数名**查表的

`src/aot/ir_generator.zig` 的 `generateFunctionCall`（`:6218` 起）在无命名实参冲突时进入 `:6810` 起的 else 支，三重查表全部以 `func_name.len > 0` 为前提：

```zig
// src/aot/ir_generator.zig:6811-6825（实测现文）
            const target_func = if (func_name.len > 0 and self.module != null)
                self.module.?.findFunction(func_name)
            else
                null;
            const prescan_ref_params: []const u32 = if (func_name.len > 0)
                (self.function_ref_params.get(func_name) orelse &[_]u32{})
            else
                &[_]u32{};
            const builtin_ref_params = if (func_name.len > 0) NativeLinker.getBuiltinRefParams(func_name) else &[_]u8{};
```

命中即发射「临时 alloca + `ref_aware_store` + `make_ref` + 调用 + 回写」（生成码实证：`.zigphp_aot_build_22277/main.zig:330-336`，对应 CTRL 具名形，输出等值）。

### 2.2 动态调用无名可查 ⇒ 实参**原样透传**

调用目标是变量/表达式时，`:6229-6249` 把 `indirect_callee` 置为「load / global_get / generateExpression」的**值寄存器**，`func_name` 为空 ⇒ §2.1 三支全落空 ⇒ 该位置不会被 `make_ref`；随后：

```zig
// src/aot/ir_generator.zig:7361-7366（实测现文）
        if (indirect_callee) |callee_reg| {
            return self.emitWithResult(.{ .call_indirect = .{
                .func_ptr = callee_reg,
                .args = args,          // ← 引用形参装填从未发生
                .return_type = .php_value,
            } }, .php_value);
        }
```

发射侧（`native_linker.zig:23389-23420`，`.call_indirect` 支）把 `op.args` 原样写成值数组：

```zig
// 生成码 .zigphp_aot_build_22277/main.zig:567（最小探针形 ⑤，源行 :29）
    reg_27 = getGlobalVar("$cb");                       // ← 取的是**副本**，非引用 cell
    reg_28 = try runtime.php_invoke_callable(reg_26, &[_]runtime.Value{reg_27}, runtime.runtime_allocator);
```

### 2.3 callee 侧回落 `&null_val` ⇒ 下游把 null 当数组写 ⇒ SIGSEGV

被引用形参的发射支（`native_linker.zig:21051-21055`）在 `args[i].isRef()` 为假时**静默**回落：

```zig
// src/aot/native_linker.zig:21055（实测现文）
                            try writer.print("    reg_{d} = if (args.len > {d} and !args[{d}].isMissing() and args[{d}].isRef()) args[{d}].asRef() else &null_val;\n", ...);
```

生成码里该回落后紧跟数组写入（`.zigphp_aot_build_22277/main.zig:886-912`，闭包体）：

```zig
    reg_1 = if (args.len > 0 and !args[0].isMissing() and args[0].isRef()) args[0].asRef() else &null_val;
    reg_0 = reg_1.*;                 // null
    reg_3 = reg_1.*;                 // null
    if (reg_3.isArray() and reg_3.asArray().ref_count > 1) { ... }   // false ⇒ 跳过
    try reg_3.asArray().push(runtime.runtime_allocator, reg_2);      // ← 对 null 取 asArray() ⇒ 段错误
```

⇒ **两个独立缺口合成一次崩溃**：
- **G1（语义）**：`call_indirect` 无引用形参装填通道（§2.1–§2.2）⇒ 即使不崩，写回也会丢（PHP 的引用语义不成立）。
- **G2（健壮性）**：`:21055` 的 `&null_val` 回落无任何后续保护，被下游当作「已装填的引用」继续按类型写入（模板 `php_array` 写入路径无 null 型别防御）⇒ 崩溃而非可诊断错误。

### 2.4 排除项

- **不是内联**：默认档 `function_inlining=false`（`compiler.zig:140` → `optimizer.zig:209`），且崩溃发生在闭包/具名函数的**实参边界**，与 CODEGEN-007 的 `.param` 错绑是两回事。
- **不是 COW 支缺 `isPointerReg`**（CODEGEN-007 §2.4 第 4 步 / 其修复项 D）：`t007_refparam_noninline_geom_tmp.php` 的 ①–⑤ 形（实例方法、静态方法、含默认值、引用+普通混排、双引用互换）在默认档**全部逐字节等值** ⇒ 该缺口在非内联几何下**未被触达**（同轮结案 CODEGEN-007 §7.2，见其更新日志）。
- **不是 `=&` 显式引用族（REF-001/002/003）**：本探针无 `=&`，仅需 `array &$a` 形参 + 动态调用。
- **不是数组写入路径本身坏**：同一数组、同一 callee 的具名调用等值（CTRL 行）。

---

## 3. PHP 侧口径（为什么这是缺陷而非「未支持特性」）

PHP 对 `vfn`／`arrcb`／`this_cb`／闭包直调四种形态**都按引用传递并写回**（§1 表内真值列）；只有 `call_user_func*` 因为是 runtime 转发才降级为 Warning + 按值（AOT 在此形态连 Warning 都没有，直接段错误）。⇒ 前四形属「PHP 语法已支持 ⇒ 禁止简化」范围，失败即 AOT 缺陷（宪法 §七.8 前半条）。

---

## 4. 修复口径（全部属 IR/发射/模板改动 ⇒ **待点头**）

| 优先级 | 方案 | 落点 | 覆盖面 | 落地成本 / 风险 |
|---|---|---|---|---|
| **P0（推荐首落，止血且零语义牺牲）** | **E：`call_indirect` 装填按「callee 掩码」中介化** —— 发射侧对**实参表达式为纯变量**的位置，无条件发射 `make_ref(该变量存储槽)`（具名路径已有同款四段式，直接复用），并在 `PHPClosure`/`function_meta_registry` 带上「引用形参位图」；`php_invoke_callable` 调用前：该位为 1 ⇒ 透传 Ref；为 0 ⇒ 解包回值（等价现有 `actual_cb` 的 Ref 透明处理） | `ir_generator.zig:7361-7366`（+ 复用 `:6856` 起的 alloca/make_ref 生成）、`native_linker.zig:23389-23420`、`runtime_lib_template.zig:2904`（`PHPClosure` 字段）+ `:3210/:3247-3253`（`php_create_closure` 已在读 meta 表填 `param_count`/`required_params` ⇒ 同一通道加一枚掩码）+ `:5042`（`php_invoke_callable` 咨询掩码） | 形 ①③④⑤（PHP 按引用语义全复原）；形 ② `call_user_func` 需同批给 `php_call_user_func`（`:30409`）加同一咨询 | 中：跨 IR + 模板 + 运行时分发三处；**动态调用点的实参多一次 `make_ref`**（仅纯变量位置）⇒ 需性能复测，禁止负向优化。**#112 复核口径（§7.4 (c)）**：绿语料 43 个引用位里已有 **18 个用零分配形态** `runtime.Value.initRef(reg_N.*)`（`Value.initRef(ptr: *Value)`，模板 `:2423`）⇒ E 的装填**不必默认按 `make_ref` 计价**，可按该形态重算成本（前置 = 确认所指向槽在 callee 生命周期内有效）。**#113 落点约束（§7.5 结论 3，实测收紧）**：生成的桩 `aot_dispatch_static_method` 每分支 **callee 名静态已知**（理论上无需运行时掩码即可判引用位），但实测到达桩时 `args` 已是 caller 侧的**值拷贝**（`:1506 reg_38 = getGlobalVar("$a")` → `:1509 php_invoke_callable(… &[_]Value{reg_38} …)`）⇒ **在桩侧装填等于做错**（只救崩溃、救不了写回，且它覆盖的两形 PHP 本就按值）⇒ E 的落点**必须**是 caller 的实参物化点（即本行指向的 `ir_generator.zig:7361-7366` 一带） |
| **P1（最小可用子集，先救闭包直调）** | **F：闭包身份可静态解析时复用具名路径** —— `$cl = function(&…){}` 且调用点能定值到 `__closure_N` 时，按 `function_ref_params.get("__closure_N")` 装填 | `ir_generator.zig:6811`（在 `indirect_callee` 分支前追加「callee 变量 ⇒ 闭包名」解析）| 形 ⑤（本探针主形）；形 ①③④ 不覆盖 | 低-中；判定条件必须保守（单一赋值），否则退化为错绑 ⇒ 比崩溃更难查 |
| **P2（健壮性，不解决语义）** | **G：callee 回落可诊断化** —— `:21055` 的 `&null_val` 回落改为分配私有临时 cell（写入不落空、也不崩），或在模板数组写入前对 `isNull()` 显式报 `Argument #N ($x) must be passed by reference` 型 Warning | `native_linker.zig:21055`；或 `runtime_lib_template.zig` 的 `php_array_set`/`push` 前置判型 | 全形态（崩溃 → 告警/值语义）| 低；**单独落 G 会把「静默崩溃」换成「静默丢写回」**，只能作为 E/F 排期前的兜底，不可当修复结案 |
| **不建议** | 在 `php_invoke_callable` 里无条件把 args 全部 `asRef()` 解包/包装 —— callee 的引用形参信息在运行时只有 `PHPClosure` 的 `param_count`，无位图 ⇒ 无条件处理等于对所有动态调用加拷贝/解引用开销，且无法区分「值参」与「引用参」，属不考虑全局的优化 | — | — | — |

**验收门（建议）**：`t007_dynref_shapes_tmp.php` 六形 × {PHP, AOT} 逐字节等值（形 ② 允许 Warning 行文本差异但 rc 必须为 0）+ `t007_closure_byref_min_tmp.php`/`t007_refparam_noninline_geom_tmp.php` 全等值 + 官方 68 语料默认档 `SWEEP_DONE mismatch=0` 不漂移 + 动态调用热点（`array_map`/`usort`/`array_walk` 组）基准不劣化 + **`t004_stub_dynentry_tmp.php` 五形（#113 §7.5 永久门，实测成本 10s）**：当前期望 `1 绿（ctrl_static）+ 4 崩（rc=139）`，落 H 后期望「五形 rc 全 0 且 `cuf_*` 两形等值」，落 E 后期望「五形逐字节等值 PHP 且 `varfunc_str`/`inst_dyn` 真写回」。

---

## 5. 复测路径（老铁复验，全部带超时）

```bash
cd /Users/wangjianjun/products/parser
P=fuzzy_scripts_720/tmp
# 一次编译，六次运行（默认档）
timeout 600 ./zig-out/bin/php-interpreter --compile --no-debug-info \
  --output=/tmp/aot_compile_t007_dynref_shapes_tmp $P/t007_dynref_shapes_tmp.php
for s in ctrl_named ctrl_walk vfn cuf arrcb this_cb; do
  printf "%-11s " $s
  out=$(timeout 10 /tmp/aot_compile_t007_dynref_shapes_tmp $s 2>&1); rc=$?
  printf "rc=%-4s %s\n" "$rc" "$(echo "$out" | head -1)"
done      # 现状：ctrl_* 两行等值；vfn/cuf/arrcb/this_cb 四行 rc=139
# 最小复现 + 生成码取证
ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 ./zig-out/bin/php-interpreter --compile --no-debug-info \
  --output=/tmp/aot_compile_t007_closure_byref_min_tmp $P/t007_closure_byref_min_tmp.php
timeout 10 /tmp/aot_compile_t007_closure_byref_min_tmp            # 现状：CTRL 行后 rc=139
# 产物清理（禁止删 .php 源）
rm -f /tmp/aot_compile_t007_dynref_shapes_tmp /tmp/aot_compile_t007_closure_byref_min_tmp

# —— 任务 #111 追加的永久通道（实测成本见注释，禁按估算报）——
# §7.2 内建回调族引用面 21 形 × {PHP 真值, AOT}：1 次编译 + 42 次运行 ⇒ 实测 ELAPSED=20s
timeout 600 bash $P/c004_uasort_face_tmp.sh   # 期望末行 C004_FACE_DONE shapes=21；读数落 $P/c004_uasort_face_tmp.tsv

# —— 任务 #112 追加的永久通道（§7.4 H 路线触发面定价；实测 ELAPSED=87s，逐枚编译 10–14 秒）——
# 选路面须先重算（三形态并集，禁只跑具名一种 ⇒ 会漏 fn(...&$x) 与 function(...&$x)）
cd fuzzy_scripts_720/pass && grep -l -E 'function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\([^)]*&\$' *.php   # 现状 7 枚
cd fuzzy_scripts_720/pass && grep -l -E 'function[[:space:]]*\([^)]*&\$' *.php; grep -l -E 'fn[[:space:]]*\([^)]*&\$' *.php   # 现状 0 / 0
timeout 900 bash fuzzy_scripts_720/tmp/c004_hface_tmp.sh    # §7.4(a) 发射面；末行 HFACE_DONE；读数 c004_hface_tmp.tsv（现状 27 句）
timeout 900 bash fuzzy_scripts_720/tmp/c004_hface2_tmp.sh   # §7.4(b) 触发面；末行 HFACE2_DONE；读数 c004_hface2_tmp.tsv（现状 43 位点 / VALUE_PASSED=0）
# 单枚复算（已有保留目录时，秒级）：python3 fuzzy_scripts_720/tmp/c004_hface_analyze_tmp.py <dir>/main.zig
# 两枚 harness 均自带 KEEP_TEMP + 按显式路径清产物；禁止删 .php 源

# —— 任务 #113 追加的永久通道（§7.5 桩面/动态入口触发实测；实测 ELAPSED=10s，编译 5s + Debug 重建 3s）——
timeout 120 bash fuzzy_scripts_720/tmp/c004_stub_dyn_tmp.sh   # 期望末行 STUB_DONE；读数 $P/c004_stub_dyn_tmp.tsv
#   现状期望（落地 H/E 后须改）：ctrl_static 等值 rc=0；cuf_string/cuf_array/varfunc_str/inst_dyn 四形 rc=139
#   探针含 -ODebug 崩点归因段 ⇒ 该 harness 会临时拷出 main.zig 重建，末尾按显式路径自清理

# §7 七形普查（探针永久、但 #89 那轮的 harness 是一次性脚本已删除 ⇒ 复测须手工展开）
timeout 600 ./zig-out/bin/php-interpreter --compile --no-debug-info \
  --output=/tmp/aot_compile_t004_builtin_cb_ref_tmp $P/t004_builtin_cb_ref_tmp.php
for s in ctrl_walk walkrec_scalar walkrec_nested map_ref filter_ref usort_ref reduce_ref; do
  printf "%-15s " "$s"
  out=$(timeout 10 /tmp/aot_compile_t004_builtin_cb_ref_tmp "$s" 2>&1); rc=$?
  truth=$(/opt/homebrew/bin/php $P/t004_builtin_cb_ref_tmp.php "$s" 2>/dev/null | head -1)
  printf "rc=%-4s AOT[%s] PHP[%s]\n" "$rc" "$(echo "$out" | head -1)" "$truth"
done                                                              # 现状：仅 ctrl_walk 等值；walkrec_* 丢写回、map/filter/reduce 静默错值、usort_ref rc=139
rm -f /tmp/aot_compile_t004_builtin_cb_ref_tmp
```

---

## 6. 遗留 / 未知

1. ~~`array_map`/`usort`/`filter` 等**内建回调**族的引用形参是否全部经 `make_ref`。~~ ⇒ **已结案（同轮 §7 grep + 任务 #111 §7.2 实测）**：全模板 `make_ref` 仅 `php_array_walk:25569` 一处落在回调派发器内；`array_map`/`array_filter`/`array_reduce`/`usort`/`uasort`/`uksort`/`array_walk_recursive`/`call_user_func*` **均不装填**。其中按 PHP 规范**本就不该装填**的按值族暴露出「回落成 null」的静默错值（形 ⑩⑪⑬），`array_walk_recursive` 则属真缺装填（形 ⑧⑨）。**#111 更正**：§7 当时对 `php_uasort`／`php_uksort` **只有 grep 结论**，现已逐形实测（§7.2 表 `*_read*`／`*_write`／`*_reflog` 三组）⇒ 与 grep 同侧，结论不变、证据级别升为实测。
2. ~~崩溃是否**只**发生在「引用形参 + 数组写入」组合。~~ ⇒ **结案（同轮 §7 + 任务 #111 §7.2/§7.3）**：标量引用形参 + 只读**不崩**，但读到的是 `null` ⇒ 输出静默错值（`array_map` ⇒ `r=[5,5]`、`array_filter` ⇒ `r=[]`、`array_reduce` ⇒ `s=0`，均 rc=0 无告警）；崩溃需「数组引用形参 + 写入」，且**与派发器无关** —— #111 实测崩面 4 枚（`usort` 形 ⑫ + `uasort_write` + `map_write` + `filter_write`），后两枚**不涉及任何排序**，三枚崩点全部归因到 `runtime_lib.zig:2585 asArray`（无 tag 断言）← 同一句 `&null_val` 回落（§7.3）。
3. 形 ② 的对齐口径需裁决：PHP 是 Warning + 按值，AOT 落地 E 后是否也发 Warning（本工单按「对齐 PHP」写）。**注**：落地 H 后形 ⑩⑪⑬⑫ 与 PHP 的**数据**一致、仅缺 Warning 文本 ⇒ 同一裁决覆盖 §7 全部按值族。**#111 扩面（实测，§7.2 结论 3）**：裁决面不再是「形 ② 一个」而是**全部引用形参形**，且偏差为**双重** —— AOT 不发 by-ref 告警（`*_reflog` 全形 `warn=0`，PHP 每形 2~6 条），在下标访问实参的只读形上改发一条 PHP 没有的 `Trying to access array offset on null`（`usort_read` 2／`uasort_read` 4／`usort_read3` 6／`uasort_read3` 8 条）⇒ **H 落地后两条告警都会消失**（数据等值、诊断仍与 PHP 不一致），若要求文本对齐需在 H 之外另批发射点。
4. 闭包注册存在**重复登记**：生成码 `main.zig:964/965` 对 `__closure_2` 打了两次 `registerFunctionMeta`（发射源 `native_linker.zig:2370-2377` 与 `:2381-2391` 两段循环对闭包函数重叠）⇒ 幂等写入、无功能损害，但属可清理的冗余发射，未列为缺陷。
5. 变量函数名（形 ①）在 PHP 中若目标函数有引用形参是**合法按引用**的（实测真值列；**#113 再实证**：§7.5 `varfunc_str` 目标为**具名静态方法** `RefStub::take(array &$a)` 时 PHP 真值仍为 `after=[1,2,99]` 真写回）⇒ 落地 F 方案不覆盖它，必须靠 E 的运行时掩码；这点决定 E 不是「可选加固」而是完整修复的必要条件。
6. **（#112 新立）H 的新 cell 释放属权未定义**：现状 `else &null_val` 指向**帧局部栈槽**（`native_linker.zig:5703` 每帧无条件发射 `var null_val = …`）⇒ 无需归还；H 改为「值装私有 cell」后该 cell 由 `runtime.runtime_allocator` 分配 ⇒ **必须指定归还点**（callee 帧尾 or 随 `reg_K` 的 value 生命周期释放），否则每条「传值给引用形参」路径漏一个 `Value` cell。⇒ H 落地批把 **leak 门**（任务 #25/#30 通道）列为**硬验收项**，并在 (c) 的两种形态间确认语义：caller 侧 `make_ref` 的 cell 由**父槽重写 + 引用计数**接管（模板 `:3055-3068`），H 的私有 cell **没有父槽** ⇒ 不可直接照搬该属权模型。
7. ~~**（#112 新立）TRAMPOLINE 面的可达性只在语料内被证明为 0**：6 枚方法表桩（`return @"Class::m"(ctx, args, allocator)`）整组透传 `args` ⇒ `else` 是否可达取决于**动态调用方**；本 7 枚脚本 `call_user_func*`／数组 callable／变量函数 **0 命中** ⇒ 语料内不可达，但**不能外推为"透传路径永不触发"**（§1 形 ①③④⑤ 正是「整组 `args` 交给 callee」的动态调用族，其 callee 入口实测含同一句回落 —— §7.3 取证点 `main.zig:30421` ⇒ 落地 H 后这些形态会走进新支）。⇒ ~~H 落地后需按 §7.4 建议表的 P1 项构造「`call_user_func_array` + 具名方法引用形参」探针复量~~ ⇒ **已结案（#113 §7.5 实测，负结果）**：专用探针五形已构造并量到 —— 桩路径**不仅可达而且必然走 `else`**（动态调用点在生成码里就把实参物化成值拷贝），4 形 `rc=139`／1 形等值；崩溃面在 §7.2 的「内建派发器 4 枚」之外**再扩 4 形动态入口 = 2 条派发链 × {静态方法、实例方法}**，并首次拿到逐形行号：**生成的桩 `aot_dispatch_static_method`（`main.zig:1977`）只接住 `cuf_string`/`varfunc_str`，实例侧 `cuf_array`/`inst_dyn` 走模板 `callMethod`（`runtime_lib.zig:18544`）而不经过桩**（此事实直接收紧 E 的落点，见 §7.5 结论 3）。**发射面普查扩至 `pass/` 之外仍未做**（列 P2）。

---

## 7. 内建回调族引用装填普查（同轮追加，任务 #89）

新永久探针（**勿删**）：`fuzzy_scripts_720/tmp/t004_builtin_cb_ref_tmp.php`（七形 × `$argv[1]` ⇒ 1 次编译 + 7 次运行；真值 7 次；`KEEP_TEMP` 取证 1 次编译）。所有回调都**声明引用形参并尝试写回**。

| 形 | 内建 | PHP 真值（stdout 的 `SHAPE=` 行；stderr 另有 Warning） | AOT（默认档） | 判定 |
|---|---|---|---|---|
| CTRL | `array_walk` | `a={"x":10,"y":20}` | 同 | **等值** |
| ⑧ | `array_walk_recursive`（标量叶） | `a={"x":10,"y":20}` | `a={"x":1,"y":2}` | **静默丢写回**（rc=0 无告警） |
| ⑨ | `array_walk_recursive`（嵌套叶） | `a={"p":[101,102],"q":[103]}` | `a={"p":[1,2],"q":[3]}` | **静默丢写回** |
| ⑩ | `array_map` | Warning + `r=[6,7]` | `r=[5,5]` | **静默错值**（`$v+5` 里的 `$v` 读到 null ⇒ 恒 5） |
| ⑪ | `array_filter` | Warning + `r={"1":2,"2":3}` | `r=[]` | **静默错值**（`$v>1` 恒 false ⇒ 全滤掉） |
| ⑫ | `usort`（`array &$x` + `$x[] = 9`） | Warning + `a=[[1],[2]]` | **`rc=139`** | **段错误**（与本工单形 ①–⑤ 同一回落链） |
| ⑬ | `array_reduce` | Warning + `s=3` | `s=0` | **静默错值** |

**普查口径（实测，非推断）**：`grep -n make_ref src/aot/runtime_lib_template.zig` ⇒ 全模板 **10 处调用**，其中位于回调派发器内的只有 `php_array_walk`（`:25566` 注释 / **`:25569` 实调用**，REF-002 R-1b 所留）。`php_usort:22506-22534`、`php_uasort:22535-22555`、`php_uksort:22556-22576`、`php_array_map:25246-25334`、`php_array_filter:25335-25397`、`php_array_reduce:25398-25415`、`php_array_walk_recursive_inner:25583-25610`、`php_call_user_func:30409-30417`、`php_call_user_func_array:30418-30422` **均无 make_ref**（逐函数体扫描）。

⇒ 本工单 §1 表内「CTRL 内建等值 ⇒ 内建族已装填」的原锚点 `:25596` **是误读**（`:25596-25598` 属 `php_array_walk_recursive_inner`，那里恰是**不装填**的那一处）；已更正为 `:25569`。

**关键口径分裂（决定修复覆盖面）**：PHP 对 `array_map`/`array_filter`/`usort`/`array_reduce` 的回调**本就按值传递**（引用形参 ⇒ Warning「must be passed by reference, value given」，但形参仍**拿到实参的值**）；只有 `array_walk`/`array_walk_recursive` 规范上是 by-ref 写回。⇒
- 形 ⑩⑪⑬ 的错**不在装填**（不该装填），而在 **callee 的 `&null_val` 回落把「按值传递」变成了「传递 null」** ⇒ 属 §2.3 的 **G2**，与 E 方案无关。
- 形 ⑧⑨ 才是**内建侧缺装填**，落点在 `php_array_walk_recursive_inner:25598`（`args_buf[0] = value;`，且 `:25586` 已把值 `entry.value_ptr.*` 拷出 ⇒ 需改为对 `entry.value_ptr` 装槽，口径同 `:25569`）。
- 形 ⑫（`usort` + `array &$x` + 写入）与 §1 形 ①–⑤ **同一条崩溃链**：`main.zig:6075` 回落 ⇒ `:6087` `reg_5 = reg_2.*`（null）⇒ `:6101` `reg_5.asArray().push(...)` ⇒ SIGSEGV（取证自 `.zigphp_aot_build_24005/main.zig`，闭包 `__closure_6` 起 `:6034`）。

**语料面（实测）**：全语料（排除 `tmp/`）内「内建高阶函数 + 回调声明引用形参」= **0 命中**（逐语句窗口扫描 400 字符内 `function(...)&$...` 声明，7 个内建名 + `array_reduce`/`uksort` 全覆盖）⇒ 冻结基线不覆盖本族；同时说明这是**未被基线保护的真功能缺口**，不是回归。

### 7.1 由本普查新增的修复路线（均属发射/模板改动 ⇒ **待点头**）

| 优先级 | 方案 | 落点 | 覆盖面 | 落地成本 / 风险 |
|---|---|---|---|---|
| **P0** | **H：callee 回落语义改为「值装私有 cell」** —— `:21055` 的 `else &null_val` 改为「实参存在且非 missing 但不是 Ref ⇒ 分配私有 cell 并拷入该值」；实参缺失才回 `&null_val` | `native_linker.zig:21051-21055`（三分判别，对照同支 `:21068-21074`） | **一次消掉崩溃面（形 ⑫ + §1 形 ①–⑤ 的 rc=139）与静默错值面（形 ⑩⑪⑬）**；语义正好等于 PHP 的「value given」行为（写回不落 caller，与 PHP 一致）。**覆盖面已实测（#111 §7.2 结论 1）：崩面 4 枚派发器 × 静默错值 6 形，全由该单点解释**。**#113 再扩面（§7.5 实测）**：崩溃面另有 **4 类动态入口 × {静态方法、实例方法}**（`cuf_string`/`cuf_array`/`varfunc_str`/`inst_dyn` 全 `rc=139`）⇒ H 单点同样消掉这四形的崩溃，但**其中两形（`varfunc_str`/`inst_dyn`）PHP 为真按引用 ⇒ H 消崩不消丢写回**（见下方分工行） | **已实测（#112 §7.4），原"热点基准"前置解除**：① **语料运行开销 = 0**（触发面实测 0 ⇒ 无负向优化，§六-7 条件不成立）；② **代价 = 7 枚脚本 27 行生成码文本变更 ⇒ 基线须重冻结 7 行**；③ 运行时上界 = 每个「传值给引用形参」调用点一次 cell 分配 + `retain` 浅拷贝，且**只在今天必崩/必错的路径上付费**；④ 新增必做项 = **cell 释放属权**（`null_val` 原为帧局部栈槽、无需释放，改为堆 cell 后必须定义归还点 ⇒ leak 门列为验收项）+ §7.2 六枚 `*_zero` 控制臂逐枚复跑 |
| **P1** | **I：`array_walk_recursive` 补装填** —— `:25598` 改 `args_buf[0] = try make_ref(@constCast(entry.value_ptr), allocator);`，口径逐字对齐 `:25569`（含 R-1b 的「装槽而非锚容器槽」理由） | `runtime_lib_template.zig:25583-25610` | 形 ⑧⑨（PHP 规范要求的写回语义） | 低（单点，有同族先例）；但 `php_array_walk_recursive_inner` 递归传入的是 `value.asArray()`（`:25589`）⇒ 需确认子容器在装槽后的生命周期，属模板改动 ⇒ **本批内禁止编辑**，待排期 |
| — | **H 与 E 的分工（勿混）**：H 让「不该写回」的形态变正确（内建按值族 + 崩溃兜底）；E 让「PHP 本应写回」的用户级动态调用（形 ①③④⑤）真正写回。**只落 H 时形 ①③④⑤ 会从崩溃变成 `count=1` 的静默丢写回 ⇒ 仍不等于 PHP ⇒ 不可用 H 顶替 E**。**#113 升为实测（§7.5 结论 2）**：证据形态不再只有闭包/全局函数，已扩到**具名类方法 callee** —— 专用探针里 PHP 真值本身就分两族：`call_user_func`（字符串名／数组 callable）=「Warning + 按值」⇒ H 恰好等于其数据面；`$f='RefStub::take'; $f($a)`／`$o->$m($a)` = **真按引用**（PHP 真值 `after=[1,2,99]`／`after=[1,2,7]`）⇒ H 只把它们变成 `after=[1,2]` 的**静默丢写回**（`varfunc_str`／`inst_dyn` 两形）。⇒ **H 顶替 E 在实测意义上被否证** | — | — | — |

### 7.2 内建回调族引用面**实测**补测（任务 #111，2026-10-07；21 形 × {PHP 真值, AOT}）

**起因（本小节的存在理由）**：§7 表只实测了 9 枚派发器中的 6 枚，`php_uasort`／`php_uksort` 当时**只有 grep 结论**；崩溃组合（形 ⑫）只在 `usort` 一枚上量过；`array_map`／`array_filter` 只测了**标量只读**形（⑩⑪）⇒ 路线 H 的覆盖面在落地前是**推断**。本小节把三态判据扩到未量派发器，并把「内建是否真的传参」与「回落是否把值变成 null」分离取证。

**通道（永久）**：探针 `fuzzy_scripts_720/tmp/t004_uasort_uksort_ref_tmp.php`（21 形 × `$argv[1]`，md5 `d02d0a73d687b3ef63c375c5b51aebc2`）+ harness `fuzzy_scripts_720/tmp/c004_uasort_face_tmp.sh`（md5 `c7cb8be5dc82e81f9c940fcee290d518`）+ 落盘 `c004_uasort_face_tmp.tsv`（表头四枚戳：冻结二进制 `1f15e4ce9b5c9cdaaef7cabf5efb9c76`、`native_linker.zig` `fbe6382a2e0904b6740d771b88c409c7`、`runtime_lib_template.zig` `008b7b639f1069cb73e443064e115ed1`、探针 `d02d0a73d687b3ef63c375c5b51aebc2` ⇒ 与本工单代次锚点一致，**运行模板块未改**）。**实测成本 `ELAPSED=20s`**（1 次编译 + 21×2 次运行 ⇒ ≈0.45 秒／臂）；编译产物 `size=1177192`。

| 形 | 内建 / 声明 | PHP 真值（stdout） | AOT（默认档，stdout） | 判定 |
|---|---|---|---|---|
| `ctrl_usort` | `usort` + 按值比较器 | `[[1],[2]]` | `[[1],[2]]` | **等值**（对照锚：三枚排序内建本身可用） |
| `usort_read` | `usort` + `array &$x,&$y` 只读 | `[[1],[2]]` | `[[2],[1]]` | **静默错值**（= 输入序 ⇒ 比较器退化） |
| `usort_read3` | 同上，3 元素 | `[[1],[2],[3]]` | `[[3],[1],[2]]` | **静默错值**，且**逐字节等于 `usort_zero3` 的 AOT 读数** |
| `uasort_read` | `uasort` + 只读，2 元素 | `{"q":[1],"p":[2]}` | `{"q":[1],"p":[2]}` | ⚠ **禁判等值**：与 `uasort_zero` 的 AOT 读数逐字节相同 ⇒ 顺序是分区假象 |
| `uasort_read3` | 同上，3 元素 | `{"q":[1],"r":[2],"p":[3]}` | `{"r":[2],"q":[1],"p":[3]}` | **静默错值** = `uasort_zero3` AOT 读数 |
| `uksort_read` | `uksort` + `mixed &$k1,&$k2`，2 元素 | `{"a":2,"b":1}` | `{"a":2,"b":1}` | ⚠ 同 `uasort_read`：= `uksort_zero` AOT 读数 ⇒ 假象 |
| `uksort_read3` | 同上，3 元素（输入 `r,p,q`） | `{"p":1,"q":2,"r":0}` | `{"q":2,"p":1,"r":0}` | **静默错值** = `uksort_zero3` AOT 读数 |
| `uasort_write` | `uasort` + `array &$x` + `$x[] = 9` | `{"q":[1],"p":[2]}`（写回丢弃） | **`rc=139`，零输出** | **段错误**（崩面新增第 2 枚派发器） |
| `map_write` | `array_map` + `array &$v` + `$v[] = 9` | `r=[[1,9],[2,9]] a=[[1],[2]]` | **`rc=139`** | **段错误**（**不涉及排序**） |
| `filter_write` | `array_filter` + 同上 | `r={"1":[2]}` | **`rc=139`** | **段错误**（**不涉及排序**） |
| `usort_zero3`／`uasort_zero3`／`uksort_zero3`／`uasort_zero`／`uksort_zero` | 同输入、按值、比较器**恒返回 0**（控制形） | 与输入序一致（PHP 排序稳定） | 与各自 `*_read*` 形**逐字节相同** | **判据臂**（见下方判据 1） |
| `usort_reflog`／`uasort_reflog`／`uksort_reflog` | 引用形参 + `echo json_encode([$a,$b])` + 恒返回 0 | `CB=[[3],[1]]`、`CB=[[1],[2]]`、`CB=["r","p"]`（真值）＋ Warning×4（2 元素形 ×2 参） | **`CB=[null,null]` ×N，`warn=0`**（回显整组实参、不做下标访问 ⇒ 连"offset on null"告警都不出） | **`&null_val` 回落实证到参数级** |
| `usort_byvalog`／`uasort_byvalog`／`uksort_byvalog` | 同上但**按值**声明（对照） | `CB=[[3],[1]]`／`CB=["r","p"]` 等真值，比较 2 次 | 实参**全为真值且取自输入集合**，但**条数与序列不同**：`usort` AOT 3 条 vs PHP 2、`uasort`／`uksort` AOT 各 4 条 vs PHP 2，且含 `CB=[[1],[1]]`／`CB=["p","p"]` 自我比较 | ⚠ **不判等值**（判据 1）⇒ 本组只证「派发器确实把实参交到了 callee」；比较**次数/顺序**差异属 `quickSort*` 算法面，另计（不在本单缺陷面） |

**判据 1（新立，禁再犯）：排序派发器的输出等于真值 ≠ 等值。** `php_usort:22521`／`php_uasort:22545`／`php_uksort:22566` 全部走 `quickSort*` ⇒ **不稳定排序**，恒返回 0 的比较器同样会打乱顺序。本轮两枚 2 元形（`uasort_read`／`uksort_read`）的 AOT 输出与 PHP 真值逐字节相同，但与同输入的 zero 控制臂**同样相同** ⇒ 属假象，必须判**静默错值**。⇒ 今后凡比较器类形态，**必须成对带 zero 控制臂**，否则读数不可判。

**判据 2（新立，参数级解耦）：比较器恒返回 0 且 `echo json_encode([实参])`。** 两侧排序都退化 ⇒ 顺序不再参与判据，唯一变量 = callee 实际收到什么。三枚 `*_reflog` 全 `[null,null]` × 三枚 `*_byvalog` 全真值 ⇒ 「内建确实传参、缺陷**只在引用形参入口回落**」从推断升为**实测**，本单 §2.3 的链在 `uasort`/`uksort`/`array_map`/`array_filter` 上同样成立。

**四条结论**：
1. **崩面从 1 枚派发器扩到 4 枚**（`usort` 已有 + `uasort` + `array_map` + `array_filter`），其中后两枚**不涉及排序** ⇒ 回落链与派发器无关 ⇒ 路线 **H 的覆盖面 = 全派发器**（原为推断），且 H 单点（`native_linker.zig:21055`）足以覆盖本轮全部崩溃形。
2. **`uasort`／`uksort` 由 grep 结论升为实测结论**：与 §7 其余派发器同侧（不装填、只读 ⇒ 静默错值；写入 ⇒ 崩）。
3. **诊断维度实测（TSV `warn_lines` 列）**：AOT **不发** PHP 的 by-ref 告警（`Argument #N ($x) must be passed by reference, value given`），但在**下标访问实参**的只读形上改发一条 PHP 没有的告警 —— `Trying to access array offset on null`（`usort_read` 2 条／`uasort_read` 4 条／`usort_read3` 6 条／`uasort_read3` 8 条）；`uksort_read*`（键为字符串、不做下标访问）与三枚 `*_reflog`（回显整组实参）AOT **`warn=0`**。⇒ 本缺陷在诊断侧是**双重偏差**：by-ref 告警缺失 **+** `null` 以用户可见告警的形式泄漏到脚本输出流。§6 第 3 条的对齐裁决面因此从「形 ② 一个」扩到**全部引用形参形**，且落地 H 后 AOT 将**两条告警都不发**（数据等值、诊断仍缺）⇒ 若要求对齐 PHP 文本，须在 H 之外另批发射点。
4. 静默错值形在本轮共 **6 枚**（`usort_read`/`usort_read3`/`uasort_read`/`uasort_read3`/`uksort_read`/`uksort_read3` = 三枚派发器 × {2 元素, 3 元素}；其中 `uasort_read`/`uksort_read` 两枚在「AOT 输出 == PHP 真值」的假象口径下看似等值，按判据 1 一律判**静默错值**）⇒ H 落地后必须**逐枚重跑 zero 控制臂**：控制臂是**按值**声明，H 改变的是引用形参入口 ⇒ 控制臂读数**不应变**，变了即 H 溢出到按值路径（新立验收判据）。

### 7.3 三枚新崩形的崩点归因（沿用 CODEGEN-007 §3.8 的 `-ODebug` 通道；零插桩、零源码改动）

通道 = `ZIGPHP_AOT_KEEP_TEMP=1` 编译 ⇒ 整份 preserved 目录拷 `/tmp` ⇒ 同份生成码 `-ODebug` 重建 ⇒ 读 Zig 自带段错误处理器的带行号栈。**实测成本**：`zig build-exe … -ODebug` = **4.5 秒**，逐形运行秒级；生成码 md5 `bbd057cbff458fbf943b039d99da1cb2`／33270 行（跨两次编译**逐字节等值** ⇒ 确定性自证）。

| 形 | ReleaseFast | `-ODebug` 崩溃帧 | 故障句（生成码） |
|---|---|---|---|
| `map_write` | `rc=139` | `runtime_lib.zig:2585 in asArray` ← `main.zig:30441 __closure_6` ← `php_invoke_callable:5074` ← `php_array_map:25324` | `try reg_3.asArray().push(runtime.runtime_allocator, reg_2);` |
| `filter_write` | `rc=139` | 同上 ← `main.zig:30508 __closure_7` ← `:5074` ← `php_array_filter:25353` | 同形 |
| `uasort_write` | `rc=139` | 同上 ← `main.zig:30251 __closure_4` ← `:5074` ← `invokeUserCompare:22392` ← `quickSortEntriesByValueWithCallback:22426` ← `php_uasort:22545` | 同形 |

Debug 下报的是 `panic: incorrect alignment`（`@ptrFromInt` 在 Debug 做对齐检查），ReleaseFast 下同一句是裸 `rc=139` ⇒ **同一处、两种表现**（承 CODEGEN-007 §3.8 陷阱 ①）。三枚崩点上游都是 §2.3 的回落句本身，实测在 `main.zig:30421`：

```zig
// /tmp/.../main.zig:30421（__closure_6 入口，实测现文）
reg_1 = if (args.len > 0 and !args[0].isMissing() and args[0].isRef()) args[0].asRef() else &null_val;
// :30430  reg_3 = reg_1.*;        ← 引用形参拿到的是 null
// :30441  try reg_3.asArray().push(...);  ← 无 tag 断言 ⇒ 崩
```

⚠ **与 CODEGEN-007 的关系（禁互推）**：崩溃**入口**相同（同一处无 tag 断言的 `asArray`，`runtime_lib.zig:2585`），**成因为两条独立路径** —— 本单 = 默认档引用装填缺失 ⇒ 值为 `null`；CODEGEN-007 = 非默认档内联 id 冲突 ⇒ 值为宿主帧活值。但两单的守卫型路线（本单 G/H、CODEGEN-007 §5 路线 E）落在**同一点位**（`asArray` 前置判型），⇒ **裁决须并读两单，禁止重复计价**。

### 7.4 H 路线触发面实测（任务 #112，2026-10-07；零源码改动、非门控、只读生成码）

**起因（本小节的存在理由）**：§7.1 H 行的成本列一直是**估算**（"引用形参入口多一次 cell 分配 + 拷贝 ⇒ 必须做动态调用/回调热点基准，禁止负向优化"），而 §六-7「涉及编译器损失性能必须先问」要求 H 落地前有实测成本。⇒ 本小节把 H 的定价拆成**两个互不相干的面**并逐一量：

| 面 | 问题 | 决定什么 |
|---|---|---|
| **发射面** | 冻结绿语料生成的 `main.zig` 里有多少句 `else &null_val` | H 改动的**文本行数** ⇒ 基线 md5 **漂移面** |
| **触发面** | 这些句子的 `else` 分支在语料运行时是否**可达** | H 是否新增 cell 分配/拷贝 ⇒ 是否**负向优化**（§六-7） |

**通道（永久资产，勿删）**：
- 发射面：harness `fuzzy_scripts_720/tmp/c004_hface_tmp.sh`（md5 `fb8d97aa6acb60b6f7e2045255b26de5`）→ 落盘 `c004_hface_tmp.tsv`（md5 `f4a079c9d3cc85b19f4fefd2c0eca4dc`，56 行；表头三枚戳 = 冻结二进制 `1f15e4ce9b5c9cdaaef7cabf5efb9c76`／`native_linker.zig` `fbe6382a2e0904b6740d771b88c409c7`／`runtime_lib_template.zig` `008b7b639f1069cb73e443064e115ed1` ⇒ 与本单代次锚点**全等**）
- 触发面：调用点分类器 `c004_hface_analyze_tmp.py`（md5 `7f8fe65da52b512f8ceef3c2380a5b23`）+ harness `c004_hface2_tmp.sh`（md5 `0d805872e8266e5dbe2a7be48f2774d4`）→ 落盘 `c004_hface2_tmp.tsv`（md5 `6ffc38646058ff92cc2854ad4229f4dc`，77 行）
- **选路面实测（三形态并集，全 68 枚 `pass` 脚本）**：具名 `function 名(…&$…)` = **7 枚**（f042/f044/f057/f085/f102/f105/f177）；匿名闭包 `function(…&$…)` = **0**；箭头 `fn(…&$…)` = **0** ⇒ 这 7 枚即语料引用形参声明的**完整集合**。其余 61 枚**结构上不可能触发**该发射点：`native_linker.zig:21042-21049` 的 `is_ref_param` 只从 `func.ref_params` 取值，声明侧无引用形参 ⇒ `:21055` 不可达 ⇒ **发射普查在结构合格集上穷尽，非抽样**。
- **实测成本**：`ELAPSED=87s`（7 枚编译 + 7 次分类；逐枚编译 **10–14 秒**，默认档 `--compile --no-debug-info` + `ZIGPHP_AOT_KEEP_TEMP=1`，产物逐枚按显式路径删除）。

**(a) 发射面 = 27 句 / 7 枚脚本**（`c004_hface_tmp.tsv`；`fallback=` 列 = `grep -c 'else &null_val'`，自证 `grep -c 'FB @'` = **27**）

| 脚本 | 生成码行数 | 回落句 | 脚本内 `make_ref(` 行* | 回落句归属函数（实测去重计数） |
|---|---|---|---|---|
| f042_array_functions_full | 29420 | **9** | 2 | `ArrayTools::{splice×2, sort×2, sortAssoc×2, sortByKey×2, usort×1}` |
| f044_json_deepops_merge_diff | 28120 | **2** | 3 | `JsonTools::deepSet×2` |
| f057_workflow_engine_rollback | 19408 | **4** | 1 | `WorkflowExecution::{executeNode, executeTask, executeDecision, executeParallel}` |
| f085_geo_rtree_knn_geocoder | 48095 | **2** | 2 | `RTree::{rangeSearchNode, collectPoints}` |
| f102_memory_gc_marksweep_refcount_gen | 42195 | **3** | 4 | `RefCountGC::findCycle×2, GenerationalGC::markGen` |
| f105_db_index_btree_hash_queryplan | 40343 | **2** | 7 | `BTree::{rangeSearch, inorderTraverse}` |
| f177_graph_traversal_dfs_bfs | 50310 | **5** | 7 | `Graph::{dfsHelper×2, hasCycleDFS×2, hasCycleUndirected}` |
| **合计** | — | **27** | 26 | **19 个具名类方法**；闭包/箭头函数 **0 句** |

\* 该列为**全脚本 `grep -c 'make_ref('` 文本行计数**，不限引用位 ⇒ 与下方 19 个引用位 `make_ref` 是**口径差异不是矛盾**（差值 7 = 非引用形参位的装填，如数组元素 `=&` 槽，本轮未逐枚归因）。

归属形态示例（实测现文，`fuzzy` 里 `has_this` 使 `args_index` 移位，见 linker `:21039`）：

```zig
// c004_hface_tmp.tsv（f042 @2081，ArrayTools::sort 入口）
reg_3 = if (args.len > 0 and !args[0].isMissing() and args[0].isRef()) args[0].asRef() else &null_val;
```

⇒ **发射面 ≠ 0**：H 一旦落地，这 **27 行**的文本必然变化 ⇒ 这 **7 枚脚本**的生成码/二进制 md5 必然漂移 ⇒ **基线需重冻结 7 行**（不是回归，是预期变更，须在复测口径中预先声明）。

**(b) 触发面 = 0**：分类器逐枚枚举「引用形参位置被静态定位的调用点」，按填充形态分六类（`c004_hface2_tmp.tsv`，`CALLSITE_STATS` 行）

| 脚本 | REF_FILLED | REF_FORWARDED | REF_GLOBAL | ARG_OMITTED | TRAMPOLINE | VALUE_PASSED | TOTAL |
|---|---|---|---|---|---|---|---|
| f042 | 1 | 0 | 0 | 0 | 5 | **0** | 6 |
| f044 | 2 | 0 | 0 | 0 | 1 | **0** | 3 |
| f057 | 5 | 0 | 0 | 0 | 0 | **0** | 5 |
| f085 | 4 | 0 | 0 | 0 | 0 | **0** | 4 |
| f102 | 7 | 0 | 0 | 0 | 0 | **0** | 7 |
| f105 | 6 | 0 | 0 | 0 | 0 | **0** | 6 |
| f177 | 12 | 0 | 0 | 0 | 0 | **0** | 12 |
| **合计** | **37** | 0 | 0 | 0 | **6** | **0** | **43** |

- `VALUE_PASSED`（真值直传引用位 ⇒ `else` **可达**）= **0 命中**；`ARG_OMITTED`（实参数 < 形参数 ⇒ `args.len > I` 静态为假）= **0 命中** ⇒ 静态可定位的引用位 **43/43 已装填或整组透传**。
- 6 枚 `TRAMPOLINE` = 方法表桩 `return @"Class::m"(ctx, args, allocator);`（**整组 `args` 透传**，全部在 f042×5 + f044×1）⇒ 可达性取决于**动态调用方**，故本轮把动态入口**逐项列举**（更正记录见下方「自我更正 ③」）：`call_user_func*` = **0**；数组 callable 字面量 `[$obj,'m']` = **0**；**变量函数调用 ≠ 0** —— f042 有 **2 处**（`:115 $key = $fn($item);`、`:124 if ($fn($item))`，由该脚本 **6 个 `callable` 形参**喂入；其余 6 枚脚本 `callable` 形参 = 0、变量函数调用 = 0；f085 的 1 处 `$p (dist=` 命中系**字符串插值**非调用）。⇒ 桩的 `else` 面判定：这 2 处动态调用的目标是**闭包/箭头函数**，而语料三形态扫描实测「匿名闭包/箭头声明引用形参 = **0**」⇒ 被调帧内**根本没有回落句** ⇒ `else` 仍不可达（**依据从"无动态入口"改为"动态入口的目标无引用形参"，更强且已实测**）。
- f042 的 5 枚桩目标方法：**4 枚零调用**（`splice`/`sortAssoc`/`sortByKey`/`usort` 在脚本内只有声明，体内调的是 PHP 内建 `array_splice`/`usort`）；第 5 枚 `sort` 有 **1 处静态调用**（`:157 ArrayTools::sort($sorted);`）⇒ 正是 f042 那唯一一枚 `REF_FILLED`（`make_ref`，生成码 `main.zig:10214`）⇒ 静态路径已装填，**不入 `else`**。

**(c) 装填的两种形态，成本天差地别**（这是 H 定价的关键，也是 E 的选型输入）

| 形态 | 生成码样例（实测） | 分配 | 锚点 | 本轮位点数 |
|---|---|---|---|---|
| `make_ref` 堆 cell（具名/命名实参五段式） | `reg_64 = try runtime.make_ref(reg_62, runtime.runtime_allocator);` | `allocator.create(Value)` + `retain()` + **父槽重写** | 模板 `:3055-3068` | **19** |
| `Value.initRef(reg_N.*)`（实例调用 `php_object_call` 的 `&[_]runtime.Value{…}` 列表内） | `runtime.Value.initRef(reg_3.*)` | **零分配**（`initRef(ptr: *Value) Value`，只是包一个指针） | 模板 `:2423`；linker `:18980-19029` | **18** |

⇒ 19 + 18 = 37 = REF_FILLED 合计（`grep` 双计数自证）。

**(d) `null_val` 是帧局部量 ⇒ H 不新增逃逸类，但新增释放属权**：linker `:5703` 在**每个函数序言无条件**发射 `var null_val = runtime.Value.initNull();`（另有 `:5543-5544` 的 `null_val_placeholder` 服务 `ref_param_alloca_map`，`:5572` 用它初始化 `reg_X_storage: *runtime.Value`）。⇒ 现状 `else &null_val` 指向的**已是帧内栈槽**；H 把该支改成「值装私有 cell」后，新对象是**同帧同生命周期**的堆 cell ⇒ 逃逸面不变，但**释放属权变了**（栈槽无需释放，cell 必须 `release`）⇒ H 落地批必须同时定义 cell 属权（§6 新增第 6 条）并把 leak 门列为验收项。

**(e) 成本上界与语义一致性**：H 的额外分配**只发生在「非 Ref 实参到达引用形参入口」**，即今天必然 `rc=139` 或必然读到 `null` 的路径（§7.2 表：4 崩 + 6 静默错值）；语料既有绿路径**一次都不执行该支**（(b) 实测）⇒ **H 在冻结基线上的运行时开销实测 = 0**，"必须做热点基准"的前置条件在语料面不成立，改为「在崩/错形上量」。写回隔离由 COW 守卫保证（模板 `:2147`/`:2195`/`:2967`/`:3008-3013`：`ref_count > 1` 的共享容器在 store 时 `cloneShallow`）⇒ callee 对拷入容器的写**不会**泄回 caller ⇒ 与 PHP「must be passed by reference, value given」完全一致（§7 关键口径分裂）。

**四条结论（H 的定价，全部实测）**：
1. **H 不改任何绿语料的运行行为/运行速度**（`else` 支不可达）⇒ 无数据回归风险、无负向优化风险。
2. **H 会改 7 枚脚本的生成码文本（27 行）** ⇒ 这 7 枚 md5 必漂移 ⇒ **基线重冻结 7 行**是 H 的**唯一实测代价**；复测判据应为「仅 `&null_val` 回落行变更，其余行逐字节不变」。
3. **H 的运行时成本上界 = 每个「传值给引用形参」调用点一次 cell 分配 + 浅拷贝（retain）**，语料命中 0 ⇒ **只在缺陷路径付费**；代价量级远低于抬档类路线（参 CODEGEN-007 §7.5 的实测崩形）。
4. **E 的成本口径应随之复核**：既然 `Value.initRef(&slot)` 形态**零分配**且已占 18/37，动态调用装填（§4 路线 E）可优先按该形态计价，而非默认 `make_ref` ⇒ §4 对 E 的"每次调用多一次分配"推断需按此重算（前置：确认所指向槽在 callee 生命周期内保持有效）。

**判据 3（新立，禁再犯）：分类器 0 命中 ≠ 语料 0 命中 ⇒ 任何"静态面 = 0"的结论必须先枚举派发形态清单，再补一次独立 `grep -c` 自证。** 本轮三次实证：
- ① 分类器初版只扫具名形态 `@"Class::m"(` ⇒ **5/7 脚本报全零**；实测 f177 保留目录内 `runtime.php_object_call(` 有 **75 处**（实例调用的主形态），补形态后 f177 = **12 个位点** ⇒ 初版会误判成"**语料侧引用位装填面 = 0**"（实际是"分类器看不见这种形态"）。
- ② 正则 `@"NAME\(` 少写**闭合引号** ⇒ 每枚脚本 **0 命中**（与既有「字符类缺自身字母即静默空」同类陷阱）；诊断法 = 同一目标用字面量模式与拼接模式各跑一次比字节。
- ③ 选路 grep 初版 `function[^{]*&\$` 只覆盖**具名**声明 ⇒ 漏 `fn(…&$…)`/`function(…&$…)`；本轮改为**三形态并集**分别计数（7/0/0）才敢下"7 枚 = 全语料面"。

**三条自我更正（推翻本轮开轮前的前提；③ 由本轮登记时复验自查捕出，正是判据 3 的自反使用）**：
- ① 原读感是「`&null_val` 回落 = 闭包/动态载体专属」；实测 **该句是通用 `.param` 引用读的发射形态**（`:21051-21055` 对**任何**具名方法的引用形参都发射），闭包只是其中一种 ⇒ 语料 27 句**全部落在具名类方法**，闭包 0 句。
- ② 原读感是「`null_val` 是全局/共享占位」；实测**每帧一份**（`:5703` 无条件发射）⇒ H 的逃逸与属权判断必须按"帧局部"重算（见 (d)），且 H 不会引入新的跨帧引用。
- ③ 初稿曾写「这 7 枚脚本 `call_user_func*`／数组 callable／**变量函数** 0 命中 ⇒ 桩无动态入口」——**该结论错误**：登记前复验实测 f042 有 **2 处变量函数调用**（`:115`/`:124`，由 6 个 `callable` 形参喂入）。⇒ **触发面 = 0 的结论不变**，但依据换为实测的更强形式：这两处的目标是**无引用形参的箭头函数**（`:179 fn($r) => $r['dept']`、`:181 fn($x) => $x > 3`）⇒ 被调帧内**不含回落句**。⇒ 教训入规：**"无动态入口"这类否定式断言必须逐形态列举并给行号**，不得以单一 grep 概括三种不同机制（`call_user_func` 派发器 ≠ 数组 callable ≠ 变量函数调用）。

**后续建议（优先级 × 影响面 × 落地成本）**：

| 优先级 | 事项 | 影响面 | 落地成本 |
|---|---|---|---|
| **P0** | H 落地批（**仍待点头**）：`:21055` 改三分支（Ref ⇒ 现路；非 Ref 且非 missing ⇒ 值装私有 cell；缺失 ⇒ `&null_val`）+ **cell 释放属权**定义 + leak 门 + 7 行基线重冻结 + §7.2 六枚 `*_zero` 控制臂逐枚复跑（判据 1）+ **§7.5 五形桩门**（当前 1 绿 4 崩 ⇒ 落 H 后应"五形 rc 全 0、`cuf_*` 等值、`varfunc_str`/`inst_dyn` 仍丢写回属预期"） | 崩面 4 枚内建派发器 + **动态入口 4 形（§7.5 实测）** + 静默错值 6 形；语料运行开销实测 0 | 中：单点发射改动，但含属权设计与基线重冻结 |
| **P1** | E 的装填形态复核：动态调用能否用零分配 `Value.initRef(&slot)`；前置 = 槽生命周期（callee 是否可能越过 caller 帧）。**#113 收紧（§7.5 结论 3）**：落点**必须**在 caller 实参物化侧，且需同时覆盖 `php_invoke_callable` 与 `php_object_call*`/`callMethod` **两条入口**（实例名运行时才定值 ⇒ 生成的静态方法桩覆盖不到） | 形 ①③④⑤ + `varfunc_str`/`inst_dyn` 的用户级**真写回**（H 顶替不了，见 §7.1 分工行） | 低–中（覆盖面因双入口而高于原估） |
| ~~**P1**~~ **已结案（#113 §7.5，负结果）** | ~~TRAMPOLINE 可达性的**探针侧**补量~~ ⇒ 已用专用探针量到：语料内动态入口确为 `call_user_func*` 0／数组 callable 0／变量函数 2（f042，目标无引用形参），但**机制上**「动态入口 + 目标帧含回落句」组合**必崩** —— 五形探针 `cuf_string`/`cuf_array`/`varfunc_str`/`inst_dyn` **四形 `rc=139`**、`ctrl_static` 逐字节等值 ⇒ 桩路径**必然走 `else`** | H 的"透传不可达"边界：**语料内成立、机制上否证**（判据 4） | 实测 10s（成本比预估更低） |
| **P2** | 发射面普查扩至 `pass` 之外（`fuzzy_scripts_720/fail_runtime/` 等）⇒ 确认无第二回落形态；同时把三形态选路 grep 固化进 harness 表头 | 定价完整性 | 低 |

### 7.5 「动态入口 → 含引用形参的类方法」触发面实测（任务 #113，2026-10-07；零源码改动）

**起因**：§7.4(b) 把绿语料的触发面定为 0，但**明确留了一条未量边界**（建议表 P1 行）——「动态入口 **且** 目标帧含回落句」的组合在语料里不存在 ⇒ "桩路径 `else` 不可达"**只在语料内成立**。本小节直接把该组合做出来实测。

**通道（永久资产，勿删）**：探针 `fuzzy_scripts_720/tmp/t004_stub_dynentry_tmp.php`（md5 `ba58ffdb9c8fe3118bcab8a581702b38`；五形 × `$argv[1]`，callee = `RefStub::take(array &$a)` 静态 / `RefStub::takeP(array &$a)` 实例，体内 `$a[] = 99|7; return count($a);`）+ harness `c004_stub_dyn_tmp.sh`（md5 `6e83deb8b6aa0076aef008ad5f366c39`；表头四枚戳 + 静态面计数 + 五形双臂 + `-ODebug` 崩点 + 自计时 + 按显式路径清产物）+ 落盘 `c004_stub_dyn_tmp.tsv`（md5 `6ab05dc575d01db29e93b1386ddf399a`，25 行）。**实测成本 `ELAPSED=10s`**（编译 **5s** + 5×2 运行 + `-ODebug` 重建 **3s** + 5 次 Debug 运行）；戳与代次锚点全等（`fbe6382a…`／`008b7b63…`／冻结二进制 `1f15e4ce…`）。

**生成码静态面**（本轮同次编译的保留目录，自证"同 callee、同帧、同回落句"）：`else &null_val` = **2 句**（`main.zig:109` 在 `@"RefStub::take"`、`:208` 在 `@"RefStub::takeP"`）、`make_ref(` = **1 句**（`:1091`，只服务**静态直调形**）、`initRef(` = **0 句**；动态派发器为 linker 发射的 `aot_dispatch_callable`（`:1942`）→ `aot_dispatch_static_method`（`:1974`，**每分支 callee 名静态已知**：`return @"RefStub::take"(runtime.Value.initNull(), args, allocator);`）⇒ 与 §7.4 分类器在语料里看到的 TRAMPOLINE 形态**逐字同型**。

**锚点代次说明（登记时逐枚复验）**：Debug 帧里的 `runtime_lib.zig:NNNN` 与源文件 `src/aot/runtime_lib_template.zig` 的**行号同源**（发射体即模板正文）⇒ 本小节引用的 `:2585`（`asArray` 无 tag 断言）、`:18544`（`callMethod` 派发 `lookup.method.func(...)`）、`:5087`/`:5120`（`php_invoke_callable`）、`:30414`（`php_call_user_func`）、`:5302`（`php_object_call_args_array`）、`:19736`（`php_object_call`）**已在 `008b7b63…` 代次逐行复验命中**。而 `main.zig:NNNN`（`:109`/`:208`/`:1091`/`:1099`/`:1201`/`:1204`/`:1506`/`:1509`/`:1942`/`:1974`/`:1977`）属**一次性保留目录**读数（`.zigphp_aot_build_40149` 已按规范删除）⇒ 复得方式 = §5 的 `c004_stub_dyn_tmp.sh`（自带 `KEEP_TEMP`），TSV 内已持久化 `# FB 109`/`# FB 208` 两句原文与三个静态面计数。

| 形 | 派发链（`-ODebug` 实测栈，自下而上） | PHP 真值 | AOT（默认档） | 判定 ⇒ 对 H/E 的意义 |
|---|---|---|---|---|
| `ctrl_static` | `main.zig:1099` 直调（`:1091` 已 `make_ref`） | `before=[1,2] ret=3 after=[1,2,99]`（**真写回**） | `rc=0`，**逐字节等值** | 对照绿 ⇒ 缺陷只在入口侧 |
| `cuf_string` | `php_invoke_callable:5087` → `aot_dispatch_callable`(main `:1947`) → **`aot_dispatch_static_method`(main `:1977`)** → `RefStub::take`(`:129`) → `asArray:2585` | **Warning×2**「Argument #1 ($a) must be passed by reference, value given」+ `ret=3 after=[1,2]`（按值） | **`rc=139`，零输出** | **崩**（桩路径实测可达）⇒ **H 落地后 = PHP 数据面等值**（`ret=3`、不写回），仅缺 Warning（§6 第 3 条） |
| `varfunc_str` | 同上链（`$f='RefStub::take'; $f($a)`） | `ret=3 after=[1,2,99]`（**真写回**，PHP 允许变量函数按引用） | **`rc=139`** | **崩** ⇒ **H 只会把它变成 `after=[1,2]` 的静默丢写回 ⇒ 必须 E** |
| `cuf_array` | `php_call_user_func:30414` → `php_invoke_callable:5120` → **`callMethod`(runtime `:18544`)** → `RefStub::takeP`(`:228`) → `asArray:2585` | Warning×2 + `ret=3 after=[1,2]`（按值） | **`rc=139`** | 同 `cuf_string`（**实例方法侧**，走 `callMethod` 而非生成的桩） |
| `inst_dyn` | `php_object_call_args_array:5302` → `php_object_call:19736` → `callMethod:18544` → `takeP` | `ret=3 after=[1,2,7]`（**真写回**） | **`rc=139`** | 同 `varfunc_str` ⇒ **必须 E** |

**三条结论**：
1. **§7.4 留下的 TRAMPOLINE 边界已闭合，且为负结果**：§7.4 里"整组透传 `args`"的方法表桩路径不仅**实测可达**，而且其 callee 帧**必然走 `else`**（动态调用点在生成码里就把实参物化成值拷贝：`:1506 reg_38 = getGlobalVar("$a")` → `:1509 php_invoke_callable(… &[_]Value{reg_38} …)`；`:1201/1204` 同形）⇒ **崩溃面在"内建派发器 4 枚"（§7.2）之外，再扩 4 形动态入口 = 2 条派发链 × {静态方法、实例方法}**：TSV 帧行实测 **生成的桩 `aot_dispatch_static_method`（`main.zig:1977`）只接住 `cuf_string`/`varfunc_str`**（静态方法 `RefStub::take`），而 **`cuf_array`/`inst_dyn`（实例方法 `takeP`）根本不经过生成的桩，而是走模板 `callMethod`（`runtime_lib.zig:18544`）** ⇒ **两条链各自的 callee 帧都命中同一句回落**（`:129` 与 `:228`，即静态面的 `# FB 109`/`# FB 208`）。
2. **H 的覆盖面在本族被实测精确切分**：PHP 真值本身**分裂成两族** —— `call_user_func`（字符串名／数组 callable）= 「Warning + 按值」⇒ H 恰好等于 PHP 的**数据面**；变量函数／动态方法名（`$f($a)`、`$o->$m($a)`）= **真按引用**⇒ H 会产出 `after=[1,2]` 的**静默丢写回 ≠ PHP**。⇒ §7.1「**H 不可顶替 E**」由推断升为**实测**，且证据形态扩到**具名类方法 callee**（原证据只有闭包与全局函数）。
3. **E 的落点约束被实测收紧（落地评审必须按此分层）**：装填**只能发生在 caller 的实参物化点**（那里 `$a` 的活槽还在）。生成的桩 `aot_dispatch_static_method` 虽**每个分支 callee 名静态已知**（无需运行时掩码即可判引用位），但到达桩时 `args` 已是**值拷贝** ⇒ 实测两条否证：① **桩侧装填救不了写回**——它接住的 `varfunc_str` 正是 PHP 真按引用那族，装填只能把崩溃换成 `after=[1,2]` 的丢写回；② **桩侧装填覆盖面天然缺一半**——`cuf_array`/`inst_dyn` 两形走模板 `callMethod`，**根本不经过生成的桩**（实例方法名在运行时才定值）。⇒ **「E 改在桩侧实施」等于做错**；真正的 E 落点仍是 §4 指向的 `ir_generator` 动态调用装填侧（`:7361-7366` 一带），且必须同时覆盖 `php_invoke_callable` 与 `php_object_call*`/`callMethod` 两条入口。

**判据 4（新立，禁再犯）：任何"触发面 = 0"的定价必须区分「语料内」与「机制上」两个口径，且各配一条实测。** 语料内 0 只说明**基线不保护该路径**（本单语料面一以贯之），**不说明路径不存在**；本轮 §7.4 的桩面就是"语料内 0、机制上必崩"的实例 ⇒ 定价文档里凡写"不可达"必须带限定词，并把边界交给探针复量（成本实测仅 10s/探针）。

**后续建议更新**（接 §7.4 建议表）：

| 优先级 | 事项 | 影响面 | 落地成本 |
|---|---|---|---|
| **P1** | E 的分层落地设计：caller 侧装填点清单（变量函数 / 动态方法名 / 数组 callable / `call_user_func` 四形各自的 `getGlobalVar` 物化点）+ 非引用位 callee 的解包口径 | `varfunc_str`／`inst_dyn` + §1 形 ①③④⑤ 的**真写回** | 中（§7.5 结论 3 已把落点收敛到一处，但需掩码来源） |
| **P2** | 把 §7.5 的派发链计数做成常驻门（五形 × {等值, 崩} 写进 `c004_stub_dyn_tmp.sh` 的期望值）⇒ 落地 H/E 时可直接当验收门（当前期望：1 绿 4 崩） | H/E 落地验收 | 低 |

---

**更新日志**:
- 2026-10-07: **§7.5 「动态入口 → 含引用形参的类方法」触发面实测（任务 #113，零源码改动、非门控、只读生成码 + `-ODebug` 归因）**。起因 = §7.4 把绿语料的 `else` 触发面定为 0 时**明确留了一条未量边界**（其建议表 P1 行 / §6 第 7 条）：「动态入口 **且** 目标帧含回落句」的组合在 68 语料里不存在 ⇒ "桩路径不可达"只在语料内成立、**不可外推**。本条把该组合直接做成探针实测，**结果为负**。新增永久资产（**勿删**）：探针 `fuzzy_scripts_720/tmp/t004_stub_dynentry_tmp.php`（md5 `ba58ffdb9c8fe3118bcab8a581702b38`；五形 × `$argv[1]`，callee = 静态 `RefStub::take(array &$a)` / 实例 `RefStub::takeP(array &$a)`，体内 `$a[] = 99|7; return count($a);` ⇒ 同时覆盖"崩"与"丢写回"两种结局）+ harness `fuzzy_scripts_720/tmp/c004_stub_dyn_tmp.sh`（md5 `6e83deb8b6aa0076aef008ad5f366c39`；表头四枚戳 + 静态面计数 + 五形双臂 + `-ODebug` 崩点 + 自计时 + 按显式路径清产物）+ 落盘 `c004_stub_dyn_tmp.tsv`（md5 `6ab05dc575d01db29e93b1386ddf399a`，25 行）。**实测成本 `ELAPSED=10s`**（编译 **5s** + 5×2 运行 + Debug 重建 **3s** + 5 次 Debug 运行 ⇒ 比 §7.4 预估"低成本"更低，边界复量的代价量级 = 单探针 10 秒）。**生成码静态面**（同次编译保留目录）：`else &null_val` = **2 句**（`main.zig:109` 静态方法帧、`:208` 实例方法帧）、`make_ref(` = **1 句**（`:1091`，只服务静态直调形 `:1099`）、`initRef(` = **0 句**；linker 发射 `aot_dispatch_callable`(`:1942`) → `aot_dispatch_static_method`(`:1974`，**每分支 callee 名静态已知**）⇒ 与 §7.4 分类器在语料里看到的 TRAMPOLINE 形态**逐字同型**。**五形读数**：`ctrl_static` **`rc=0` 逐字节等值**（`before=[1,2] ret=3 after=[1,2,99]`）；`cuf_string`／`cuf_array`／`varfunc_str`／`inst_dyn` **四形 `rc=139` 零输出**。PHP 真值按引用语义**分两族**：`call_user_func`（字符串名／数组 callable）= Warning×2「must be passed by reference, value given」+ 按值 `after=[1,2]`；变量函数／动态方法名 = **真写回**（`varfunc_str after=[1,2,99]`、`inst_dyn after=[1,2,7]`）。**三条结论**：① **§7.4 的 TRAMPOLINE 边界闭合且为负结果** —— 桩路径不仅**可达**而且其 callee 帧**必然走 `else`**（caller 侧在生成码里就把实参物化成值拷贝：`:1506 getGlobalVar("$a")` → `:1509 php_invoke_callable(… &[_]Value{reg_38} …)`，`:1201/1204` 同形），崩面在 §7.2「内建派发器 4 枚」之外**再扩 4 形 = 2 条派发链 × {静态方法、实例方法}**；② **H 的覆盖面在本族被精确切分** —— PHP 本就按值的两形（`cuf_*`）落 H 后**数据面等值**（仅缺 Warning，§6 第 3 条），PHP 真按引用的两形（`varfunc_str`/`inst_dyn`）落 H 后变成 `after=[1,2]` 的**静默丢写回 ≠ PHP** ⇒ **§7.1「H 不可顶替 E」由推断升为实测**，且证据形态首次扩到**具名类方法 callee**（原证据只有闭包与全局函数）；③ **E 的落点被实测收紧** —— 生成的桩虽每个分支 callee 名静态已知（无需运行时掩码即可判引用位），但到达桩时 `args` 已是值拷贝，**且实例侧两形根本不经过生成的桩**（走模板 `callMethod` `runtime_lib.zig:18544`）⇒ 桩侧实施**既救不了写回、覆盖面又天然缺一半**，E 必须落在 caller 实参物化侧（`ir_generator.zig:7361-7366` 一带）并同时覆盖 `php_invoke_callable` 与 `php_object_call*`/`callMethod` 两条入口。**新立判据 4**：**任何"触发面 = 0"的定价必须区分「语料内」与「机制上」两个口径，且各配一条实测** —— 语料内 0 只说明基线不保护该路径，不说明路径不存在；凡写"不可达"必须带限定词并把边界交给探针复量。**一条自我更正（登记时按 TSV 帧行复验捕出）**：初稿 §7.5 结论 3 曾把"桩侧实施的覆盖面"写成 **{`cuf_string`, `cuf_array`}** ⇒ 与帧行不符，实测为 **{`cuf_string`, `varfunc_str`}**（`cuf_array`/`inst_dyn` 走 `callMethod` 不经过生成的桩）；该误置会把"实例方法也走生成的方法表桩"读进去、进而低估 E 的双入口成本，已按 TSV 逐字更正（同批更正 §6 第 7 条与结论 1 的入口计数措辞）。同步刷新：状态行、语料面行（新增第三个口径「**机制面 ≠ 0**」，禁与语料面/声明面混用）、§4 路线 E 行（落点约束）+ 验收门（五形桩门入常驻）、§5 永久通道（`timeout 120 bash …/c004_stub_dyn_tmp.sh`，期望末行 `STUB_DONE`）、§6 第 5 条（变量函数按引用再实证）与第 7 条（结案）、§7.1 H 行覆盖面 + 分工行 + §7.4 建议表 P0/P1 行（TRAMPOLINE 项转「已结案·负结果」）。代次自证：`native_linker.zig` `fbe6382a2e0904b6740d771b88c409c7`／32797 行、`runtime_lib_template.zig` `008b7b639f1069cb73e443064e115ed1`、`ir_generator.zig` `cb53c2da…`、冻结二进制 `1f15e4ce9b5c9cdaaef7cabf5efb9c76` **全未变**；三枚源文件全程只读，`src/` 仅存 #74 的既有纯注释批（numstat `5 4`）⇒ **本轮零源码改动**；产物已清（`.zigphp_aot_build_40149`、`/tmp/c004_stub_dbg`、`/tmp/aot_compile_t004_stub_dynentry_tmp`、`/tmp/c004_stub_dyn.err`），`.php` 源零删除。**编号消歧**：本条「任务 #113」属本工单所在任务清单，与 CODEGEN-007 自称的「轮次 #NNN」非同一编号空间。**路线 E/F/G/H/I 仍全部待点头**，本条只补定价与落点约束，未落地任何修复。
- 2026-10-07: **§7.4 H 路线触发面实测（任务 #112，零源码改动、非门控、只读生成码）**。起因 = §7.1 H 行的成本列长期是**估算**（"多一次 cell 分配 + 拷贝 ⇒ 必须做热点基准"），而 §六-7「涉及编译器损失性能必须先问」要求落地前有实测 ⇒ 把 H 的定价拆成**发射面**（改多少文本 ⇒ 基线漂移）与**触发面**（`else` 是否可达 ⇒ 是否负向优化）两个独立面逐一量。新增永久资产（**勿删**）：`fuzzy_scripts_720/tmp/c004_hface_tmp.sh`（md5 `fb8d97aa6acb60b6f7e2045255b26de5`）+ `c004_hface_tmp.tsv`（`f4a079c9d3cc85b19f4fefd2c0eca4dc`，56 行）+ 调用点分类器 `c004_hface_analyze_tmp.py`（`7f8fe65da52b512f8ceef3c2380a5b23`）+ `c004_hface2_tmp.sh`（`0d805872e8266e5dbe2a7be48f2774d4`）+ `c004_hface2_tmp.tsv`（`6ffc38646058ff92cc2854ad4229f4dc`，77 行）。**选路面为穷尽非抽样**：三形态并集实测（具名 `function 名(…&$…)` = 7 枚 f042/f044/f057/f085/f102/f105/f177；匿名 `function(…&$…)` = 0；箭头 `fn(…&$…)` = 0），其余 61 枚由 `native_linker.zig:21042-21049` 的 `is_ref_param`（只读 `func.ref_params`）保证 `:21055` 结构上不可发射。**读数**：发射面 **27 句**／7 枚（9/2/4/2/3/2/5，自证 `grep -c 'FB @'`=27），归属 **19 个具名类方法**、闭包 **0 句**；触发面 **43 个静态引用位 = `make_ref` 19 + 零分配 `Value.initRef(reg_N.*)` 18 + 方法表桩 6**，`VALUE_PASSED`/`ARG_OMITTED`/`REF_FORWARDED`/`REF_GLOBAL` **全 0** ⇒ **`else` 支在绿语料不可达**（**依据按登记时的自我更正③ 重立**：f042 实测**确有 2 处变量函数调用**（`:115`/`:124`），但其目标是**无引用形参的箭头函数**（`:179 fn($r) => $r['dept']`、`:181 fn($x) => $x > 3`）⇒ **被调帧内不含回落句**；此外 f042 的 5 枚桩目标方法中 4 枚零调用点，`ArrayTools::sort($sorted)` 则在 `:157` 被调且正是该枚唯一的 `make_ref` 位点）。**结论**：H 的语料运行时开销实测 **0**（§六-7 负向优化前置解除，热点基准改为「在崩/错形上量」）；H 的**唯一实测代价 = 7 枚脚本 27 行生成码文本变更 ⇒ 基线须重冻结 7 行**；新增加分项 = **cell 释放属权必须定义**（`null_val` 经 `:5703` 实测为**每帧无条件发射的栈槽** ⇒ 现状无需归还，H 改堆 cell 后必须指定归还点，leak 门列硬验收，且不可照搬 `make_ref` 的"父槽重写"模型 —— §6 新增第 6 条）；COW 守卫（模板 `:2147`/`:2195`/`:2967`/`:3008-3013`）保证拷入容器的写不泄回 caller ⇒ 与 PHP「value given」一致。**E 的口径随之下调**：`Value.initRef(ptr: *Value)`（模板 `:2423`）**零分配**且已占 18/37 ⇒ §4 路线 E 不必默认按 `make_ref` 计价（前置 = 槽生命周期），已回写 §4 E 行。**实测成本 `ELAPSED=87s`**（7 枚编译 + 7 次分类，逐枚编译 **10–14 秒**；默认档 `--compile --no-debug-info` + `KEEP_TEMP`，逐枚按显式路径清产物）。**新立判据 3**：**分类器 0 命中 ≠ 语料 0 命中 ⇒ 任何"静态面 = 0"必须先枚举派发形态清单并补一次独立 `grep -c` 自证**；本轮三次实证 = ① 初版只扫具名形态 `@"Class::m"(` ⇒ 5/7 脚本报全零，而 f177 保留目录内 `runtime.php_object_call(` 实测 **75 处**（补形态后 f177 = 12 位点）；② 正则 `@"NAME\(` **少写闭合引号** ⇒ 每枚 0 命中（同类"字符类缺自身字母即静默空"陷阱，诊断法 = 字面量模式与拼接模式各跑一次比字节）；③ 选路 grep 初版 `function[^{]*&\$` 只覆盖具名 ⇒ 漏 `fn(`/`function(`。**三条自我更正**：① 回落句**不是闭包专属**，而是通用 `.param` 引用读形态（`:21051-21055` 对任何具名方法的引用形参都发射）⇒ 语料 27 句全在具名类方法；② `null_val` **不是全局占位**而是帧局部 ⇒ H 的逃逸/属权判断必须按帧局部重算（结论：H 不新增逃逸类，但新增释放属权）；③ 初稿曾写「这 7 枚脚本 `call_user_func*`／数组 callable／**变量函数** 0 命中」——**该否定式断言错误**（f042 实测 2 处变量函数调用），已由上文重立依据更正 ⇒ **教训入规：否定式断言必须逐形态列举并给行号**，不得用单一 grep 概括三种不同机制（`call_user_func` 派发器 ≠ 数组 callable ≠ 变量函数调用）。同步刷新状态行、语料面行（补「声明面 7/68 + 发射面 27 + 触发面 0」三口径，禁与"回调族 0 命中"混用）、§7.1 H 行成本列、§4 E 行、§5 永久通道、§6 第 6/7 条。**边界保留**：桩面 0 只在语料内成立，不可外推（§1 形 ①③④⑤ 的 callee 入口实测含同一回落句，§7.3 `main.zig:30421`）⇒ 列 P1 探针复量（**该边界已于同日 #113 §7.5 闭合，读数为负结果：桩路径可达且必走 `else`**）；发射面普查未扩至 `pass/` 之外 ⇒ 列 P2（仍开放）。代次自证：`native_linker.zig` `fbe6382a…`／32797 行、`runtime_lib_template.zig` `008b7b63…`、`ir_generator.zig` `cb53c2da…`、冻结二进制 `1f15e4ce…` **均未变**；三枚源文件全程只读，`src/` 仅存 #74 的既有纯注释批（numstat `5 4`）⇒ **本轮零源码改动**。**编号消歧**：本条「任务 #112」属本工单所在任务清单；与 #111 条同款消歧有效（CODEGEN-007 自称的「轮次 #NNN」是另一编号空间 ⇒ 禁止互相指认）。H 及其余路线（E/F/G/I）**仍待点头，本轮只定价未落地**。
- 2026-10-07: **§7.2/§7.3 内建回调族引用面实测补测 + 三枚新崩形归因（任务 #111，零源码改动）**。起因 = §7 的普查对 `php_uasort`／`php_uksort` **只有 grep 结论**、崩溃组合只在 `usort` 一枚上量过、`array_map`／`array_filter` 只测标量只读形 ⇒ 路线 H 的覆盖面在落地前是**推断**。新增永久资产（**勿删**）：探针 `fuzzy_scripts_720/tmp/t004_uasort_uksort_ref_tmp.php`（21 形 × `$argv[1]`）+ harness `c004_uasort_face_tmp.sh`（表头四枚戳 + 自计时 + 按显式路径清产物）+ 落盘 `c004_uasort_face_tmp.tsv`。**实测成本**：面测 `ELAPSED=20s`（1 次编译 + 42 次运行 ⇒ ≈0.45 秒／臂）；`-ODebug` 运行时归因重建 **4.5 秒**，生成码 md5 `bbd057cbff458fbf943b039d99da1cb2`／33270 行跨两次编译逐字节等值（确定性自证）。**两条新判据**：① 三枚排序派发器（`php_usort:22521`／`php_uasort:22545`／`php_uksort:22566`）全走 `quickSort*` ⇒ **不稳定排序**，"AOT 输出 == PHP 真值" **不等于**等值，比较器形必须成对带恒返回 0 的 `*_zero` 控制臂（据此把 `uasort_read`／`uksort_read` 两枚"看似绿"改判**静默错值**）；② 参数级解耦 = 比较器恒返回 0 且回显 `json_encode([实参])` ⇒ 顺序退出判据，唯一变量是 callee 收到什么。**四条结论**：崩面从 1 枚派发器扩到 **4 枚**（`usort`/`uasort`/`array_map`/`array_filter`，后两枚**不涉及排序** ⇒ 回落链与派发器无关，H 单点足以覆盖全部崩溃形）；`uasort`／`uksort` 由 grep 升为实测；**诊断侧为双重偏差** —— AOT 不发 PHP 的 by-ref 告警（三枚 `*_reflog` `warn=0`）却在下标访问实参的只读形改发一条 PHP 没有的 `Trying to access array offset on null`（`usort_read` 2／`uasort_read` 4／`usort_read3` 6／`uasort_read3` 8 条），⇒ 落地 H 后**两条告警都消失**、文本仍不对齐（§6 第 3 条裁决面由「形 ② 一个」扩到全部引用形参形）；静默错值形 **6 枚** ⇒ H 落地后须逐枚重跑 zero 控制臂（控制臂按值声明，读数变了即 H 溢出到按值路径）。§7.3 三枚崩形全部归因 `runtime_lib.zig:2585 in asArray`（无 tag 断言）← 生成码 `main.zig:30421` 的 `else &null_val` 回落，故障句 `try reg_3.asArray().push(...)`（`:30441`/`:30508`/`:30251`）；**Debug `panic: incorrect alignment` vs ReleaseFast 裸 `rc=139`** ⇒ 禁拿 exit 码当同一性判据（承 CODEGEN-007 §3.8 陷阱）。与 CODEGEN-007 的关系写明 **禁互推**（崩溃入口同为 `asArray`，成因两条独立路径；但守卫型路线 H/G 与 C007 §5-E 落同一点位 ⇒ 裁决须并读两单、禁止重复计价）。同步更正 §7.2 结论 4 计数、状态行、§5 复测路径、§6 第 1/2/3 条、§7.1 H 行覆盖面指针，以及本轮对初稿的两处**自我更正**：① `*_byvalog` 组**不可判等值**（AOT 比较条数 3/4/4 vs PHP 各 2，且含 `CB=[[1],[1]]`／`CB=["p","p"]` 自我比较 ⇒ 该组只作「派发器是否传参」的判据，次数/顺序差属 `quickSort*` 算法面、另计）；② §7.2 通道行探针戳初稿写作 `a2a8cfc7…` 系误记，按 TSV 表头更正为实测 `d02d0a73d687b3ef63c375c5b51aebc2`。代次自证：`native_linker.zig` `fbe6382a…`／32797 行、`runtime_lib_template.zig` `008b7b63…`、冻结二进制 `1f15e4ce…` 均未变；`ir_generator.zig`／`runtime_lib_template.zig` 全程只读。**编号消歧**：本条所称「任务 #111」= 任务清单里 #111 这张补测任务；而 [CODEGEN-007](AOT-CODEGEN-007-function-inlining-param-args-lost.md) §3.8／§6.3 自称的「轮次 #111」属**任务 #110** 的轮次标号，两者非同一编号空间 ⇒ **禁止互相指认**（本轮只复用了它的 `-ODebug` 取证方法，未共享任何读数）。
- 2026-10-06（同轮追加）: **§7 内建回调族普查**（新永久探针 `t004_builtin_cb_ref_tmp.php`，7 形 × `$argv[1]` ⇒ 1 次编译 + 7 次运行 + 7 次真值 + 1 次 `KEEP_TEMP` 取证）。读数：`array_walk` 等值；`array_walk_recursive` 两形**静默丢写回**；`array_map`/`array_filter`/`array_reduce` 三形**静默错值**（引用形参读到 `null` ⇒ `r=[5,5]`／`r=[]`／`s=0`，rc=0 无告警）；`usort`（`array &$x` + 写入）**`rc=139`**。普查口径：全模板 `make_ref` 10 处调用，落在回调派发器内的只有 `php_array_walk:25569` ⇒ **更正 §1 原误读锚点 `:25596`**（该处属 `php_array_walk_recursive_inner`，且那里正是**不装填**的点 `:25598`）。据此得出**按值族 vs walk 族的口径分裂**：`array_map`/`usort` 等 PHP 本就按值（错在 callee 回落成 null，非缺装填），只有 `array_walk*` 需要装填 ⇒ 新增修复路线 **H（P0：`:21055` 回落改为值装私有 cell，一次性消掉崩溃面 + 按值族静默错值）** 与 **I（P1：`:25598` 补 `make_ref`）**，并写明 **H 不可顶替 E**（只落 H 时形 ①③④⑤ 变为静默丢写回，仍不等于 PHP）。语料面：逐语句窗口扫描全语料「内建高阶函数 + 回调引用形参」= **0 命中**（含 `pass/f042`、`f122` 等 13 个提到这些内建的文件均无引用形参声明）⇒ 基线不覆盖本族。结案 §6 第 1、2 条。零源码改动（`fbe6382a`/32797、numstat `5 4`；`ir_generator.zig`/`runtime_lib_template.zig` 只读）。
- 2026-10-06: **立项（任务 #89）**。发现路径 = 为 CODEGEN-007 §7.2（「COW 支缺 `isPointerReg` 在非内联几何下能否触达」）设计只读定面探针 `t007_refparam_noninline_geom_tmp.php`，六形实测中 ①–⑤ 全等值、⑥ 闭包直调 `rc=139` ⇒ 缺陷与本工单原设问无关，转而独立立案。最小化 `t007_closure_byref_min_tmp.php`（CTRL 等值 / 闭包崩）+ `KEEP_TEMP` 生成码取证（调用点 `main.zig:567`、闭包体 `:886-912` 的 `&null_val` 回落与 `asArray().push`）。六形定面探针 `t007_dynref_shapes_tmp.php` 以 `$argv[1]` 选路 ⇒ **一次编译、六次运行**即量化四形崩溃两形等值。根因锁定到行：`ir_generator.zig:6811-6825`（按名三支查表）与 `:7361-7366`（`call_indirect` 透传）+ `native_linker.zig:21055`（静默回落）。同时结案 CODEGEN-007 §7.2。零源码改动（`fbe6382a`/32797、`git diff --numstat` = `5 4` 为 #74 纯注释批）。
