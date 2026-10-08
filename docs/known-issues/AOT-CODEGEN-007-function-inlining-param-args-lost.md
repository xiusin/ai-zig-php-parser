# AOT-CODEGEN-007 · 函数内联丢失 `.param` 绑定：非默认档位下实参错绑 / 生成码类型错误 / 多块 callee 体静默截断

**状态**: OPEN（2026-10-06 立项，任务 #88；同轮 #94 完成抬档三臂实测与单变量归因；#105/#108 钉死最小内联引爆阈值 = 35（§3.7）；**#110／轮次 #111 完成两枚 SIGSEGV 的运行时侧归因 ⇒ §7.5「留口」闭合，新增 §3.8 读数与 §6.3 复测路径、§5 路线表新增 E**；**缺陷本体仍未修，A–E 全部待点头**）
**性质**: AOT 编译期缺陷（**优化器侧**，非发射侧；修复需改 `src/aot/optimizer.zig` ⇒ 属编译器语义改动 ⇒ **待点头**）
**触发档**: `--optimize=release-fast` / `--optimize=release-safe`（`function_inlining=true`）；**无需整档抬升即可复现** —— 默认档 + `--aot-enable-pass=inline --aot-inline-threshold=50` 三形全部复现（任务 #94 C 臂标定，见 §3.5/§6.1）
**默认档不触发**: `optimize_level` 默认 `.release_small` ⇒ `PassConfig.releaseSmall()` ⇒ `function_inlining=false` ⇒ 冻结基线 68 语料**面 = 0**（本轮实测证明，见 §3.4）。**语料暴露面实测更正（任务 #94）**：即使开内联，§1 三形在 68 语料上的命中面仍为 **0**（编译失败 0 次），语料唯一内联命中形是 `f152` 的 **SIGSEGV（1/67，属新「形 D」，见 §7.5）**；threshold 保持 releaseSmall 的 5 时全语料零内联
**代次锚点**: `src/aot/native_linker.zig` md5 `fbe6382a2e0904b6740d771b88c409c7`／32797 行（未改）；`src/aot/optimizer.zig` md5 `252234ef48cb47a42e6f39d1bc3e845b`／6877 行（未改）

---

## 1. 症状（三形，全部实测）

永久探针（**勿删**）：`fuzzy_scripts_720/tmp/t007_inline_refparam_tmp.php`、`t007_inline_byval_tmp.php`、`t007_inline_multiblock_tmp.php`

| 形 | 语法 | 档 | 编译 | 输出 | PHP 真值 | 判定 |
|---|---|---|---|---|---|---|
| **A 引用形参** | `function t007_ap(array &$a): void { $a[] = 9; }` + `$x=[1,2]; t007_ap($x);` | release-fast | **rc=1** | — | `A count=3 last=9` | `main.zig:210:45: error: expected type '*runtime_lib.Value', found 'runtime_lib.Value'` ⇒ **整脚本不可编译** |
| **A 引用形参** | 同上 | 默认 | rc=0 | `A count=3 last=9` | 同 | 逐字节等值 ⇒ **仅非默认档触发** |
| **B 按值形参** | `function t007_plus(int $a, int $b): int { return $a + $b; }` | release-fast | rc=0 | `B1=0` `B2=0` | `B1=5` `B2=30` | **静默错值**（形参绑到了 caller 自己的 `args[]`） |
| **B 按值形参** | 同上 | 默认 | rc=0 | `B1=5` `B2=30` | 同 | 等值 |
| **C 多块 callee** | `function t007_cmp(int $a): int { if ($a > 5) { return 1; } return 0; }` | release-fast | rc=0 | `D=` （空，连分隔符都没产出） | `D=1 0` | **静默截断**（callee 第 2 块起整体丢弃 + 返回值未回传） |
| **C 多块 callee** | 同上 | 默认 | rc=0 | `D=1 0` | 同 | 等值 |

> B 与 C 比 A 更危险：A 是硬失败，B/C **exit code 0、无任何告警**、结果错。

---

## 2. 根因（只读源码取证，实测行号，非偏移推算）

内联器位于 `src/aot/optimizer.zig`：`runFunctionInlining`（`:4615`，由 `:506-507` 在 `config.function_inlining` 为真时调用）→ `inlineFunctionsInFunction`（`:4628`）→ `shouldInline`（`:4661`）→ `inlineFunction`（`:4672`）→ `cloneAndRemapInstruction`（`:4763`）→ `remapInstructionOp`（`:4794`）。

### 2.1 核心缺陷：`.param` 不做实参替换

`remapInstructionOp` 的逐 op 重映射表里，`.param` 被**原样返回**：

```zig
// src/aot/optimizer.zig:4861（实测现文）
            .param => op,
```

而 callee 的形参读取在 IR 里就是一条 `.param`（`ir.zig:973` `param: ParamOp`，`ir.zig:1708` 打印 `param {d} ({s})` 用 `op.index`/`op.name`），发射侧据此生成「从**当前函数的 `args[]`** 取第 index 个实参」的 Zig 代码。`inlineFunction` 把 callee **入口块的全部指令**（`:4711`）搬进 caller，`.param` 因未被替换而留在原地 ⇒ 该指令现在读的是 **caller 的 `args[]`**：

- caller = `__main__` ⇒ `args` = `$argv` ⇒ 恒缺参 ⇒ 形参取到 `null`/`initInt(0)` ⇒ 形 B（`B1=0`）
- caller = 另一个也有形参的函数 ⇒ 形参**串位错绑**到 caller 自己的实参

`inlineFunction` 里唯一像「参数映射」的代码把**形参下标**当成了**寄存器 id**：

```zig
// src/aot/optimizer.zig:4695-4701（实测现文）
        for (callee.params.items, 0..) |_, i| {
            if (i < args.len) {
                try reg_map.put(@intCast(i), args[i].id);   // key = 下标，不是 callee 的 result id
            }
        }
```

`.param` 指令的 result 寄存器 id 与下标无关，且随后 `cloneAndRemapInstruction` 无条件给它分配新 id（`:4775-4777`）并覆盖映射 ⇒ 这段映射对 `.param` **完全不生效**。

### 2.2 次缺陷一：只搬入口块 ⇒ 多块 callee 体静默丢弃

```zig
// src/aot/optimizer.zig:4711-4717（实测现文，节选）
        for (callee_entry.instructions.items) |callee_inst| {   // 只有 entry block
```

`:4682` 的门是 `callee.blocks.items.len > 3 ⇒ return false`，即**允许 2–3 块**的 callee 被内联，但克隆面只有 `callee.getEntryBlock()`。形 C 的 `if` 之后块（`return 0;` 所在块）根本没被搬进来 ⇒ 体被截断。

### 2.3 次缺陷二：返回值只在「入口块终止符恰为 `.ret`」时回传

```zig
// src/aot/optimizer.zig:4720-4743（实测现文，节选）
        if (callee_entry.terminator) |term| {
            switch (term) {
                .ret => |ret_val| { ... 追加一条 .load 到 result_reg ... },
                else => {},
```

形 C 的入口块终止符是 `.cond_br` ⇒ 落入 `else => {}` ⇒ **调用结果寄存器从未被写** ⇒ 输出空串。两处门还互相矛盾：`can_inline` 用 `block_count <= 6`（`:4592`），`inlineFunction` 用 `> 3`（`:4682`），实际生效的是后者，前者只是噪声。

### 2.4 形 A 的成因链（编译期报错 = 上游缺陷 + 发射侧缺分支的合取）

1. 内联把 callee 的 `.param`（引用形参，其 result 在 IR 里即 `*Value` 语义）搬进 `__main__`。
2. 发射侧的 ref_ptr 寄存器集合按**「本函数的 `ref_params`」**构建（`native_linker.zig:5492-5516`，两支：`res.type_ == .ptr` ⇒ 入集 `:5496-5499`；`.param.index ∈ func.ref_params` ⇒ 入集 `:5505-5513`）。搬进 caller 后 `func` = `__main__`，其 `ref_params` 为空 ⇒ **第二支不命中**，但 **第一支按 IR 的 `.ptr` 类型仍然命中** ⇒ 该寄存器被声明为 `var reg_N: *runtime.Value`。
3. 同一个 `.param` 的**发射分支选择**走的是 `is_ref_param`（`native_linker.zig:21042-21049`，按 caller 的 `func.ref_params` 比对 `op.index`）⇒ 此处为 **false** ⇒ 落入「普通参数 COW」支（`:21134` 起）。
4. 该支的目标类型判别**只有 alloca 一枚维度**（`:21143` `const is_alloca = ...`），没有 `isPointerReg`/ref_ptr 第三支（对照同函数引用参数支 `:21068-21074` 的三分判别）⇒ 向 `*Value` 寄存器发射 `runtime.Value`：

```zig
// src/aot/native_linker.zig:21178-21184（实测现文，节选）
        "        if (__pv.isArray() and !__pv.isRef() and __pv.asArray().ref_count > 1) {"
        ...
        if (is_alloca) { "            reg_{d}.* = runtime.Value.initArray(__cloned);\n" }
        else            { "            reg_{d} = runtime.Value.initArray(__cloned);\n" }
```

⇒ **上游（内联器）造出了非法 IR 几何，下游（COW 支）缺该几何的分支** ⇒ 报错点落在发射产物上，容易被误判为发射侧缺陷。

**本工单的定性**：根因 = 内联器（§2.1–§2.3）。§2.4 第 4 步是**独立的发射侧健壮性缺口**，登记为 §5 C 项；其在默认档语料上的命中面**未实测**，禁止据此断言有无风险（默认档不产生该几何，因为不内联）。

### 2.5 排除项（本轮已实测排除的误判）

- **不是 AOT-TYPE-001 的类型收口回归**：TYPE-001 §P2 已证「向 `runtime.Value` 寄存器发射原生转换」的发射点为 0 处；本例发射的是 `runtime.Value.initArray(...)`，包装正确，错在**目标寄存器指针性判别缺失**。
- **不是 `=&` 引用装槽族（REF-001/002/003）**：形 A 无需 `=&`，仅普通 `array &$a` 形参即触发。
- **不是「默认档也在坏」**：三形在默认档全部等值（§1 表内 6 个默认档/真值对照）。
- **与 `native_linker.zig:32446` 的 200KB 升档无关**：该处只改 `zig build-exe` 的 `-O`／strip（`config.optimize_level` 的全部用法实测为 `:32446/:32447/:32448/:32463/:32466/:32470/:32656/:32660/:32701`），**不影响 IR pass 选择**（pass 配置在 `compiler.zig:608-610` 于 codegen 之前定死）。⇒ 大脚本今日**不会**被静默推进内联。

---

## 3. 档位链（决定性，实测）

```
--optimize=<s> → compiler.zig:238 OptimizeLevel.fromString
  → :247 toIROptimizeLevel   debug→none / release-safe→basic / release-fast→aggressive / release-small→size
  → optimizer.zig:60 getPassConfig   none→debug() / basic→releaseSafe() / aggressive→releaseFast() / size→releaseSmall()
  → PassConfig.function_inlining     :132 debug=false / :153 releaseSafe=true(threshold 15) / :181 releaseFast=true(threshold 50) / :209 releaseSmall=false(threshold 5)
```

- 默认值：`compiler.zig:140 optimize_level: OptimizeLevel = .release_small` ⇒ **内联关闭**。
- 用户侧覆盖：`src/main.zig:138 overrides.function_inlining = enabled;`（`--pass-override` 类开关），`compiler.zig:666` 应用 ⇒ 即使默认档，显式打开该 pass 也能触发（本轮未单独复测该路径，属同源）。
- `compiler.zig:1016` 在优化失败回退时强制 `fallback.function_inlining = false` ⇒ 回退路径无本缺陷。
- 测试锁定的现行口径：`optimizer.zig:6222`（releaseSafe 启用内联）／`:6225`／`:6231`（releaseSmall 禁用）。

**§3.4 语料面实测（默认档）**：三形在默认档编译运行全部与 PHP 逐字节等值 ⇒ 冻结基线（默认档 68 语料，`SWEEP_DONE mismatch=0`）对本缺陷**零覆盖、零回归风险**；反之，任何把默认档抬到 release-fast 的改动都会**一次性把三形全部点亮**。

### 3.5 抬档语料面实测（任务 #94，三臂 + 标定，全部只读）

harness（**永久，勿删**）：`fuzzy_scripts_720/tmp/c007_releasefast_face_tmp.sh`（A 臂）／`c007_rf_control_tmp.sh`（B 臂）／`c007_inline_only_face_tmp.sh`（C 臂）；读数 TSV 同名 `.tsv` + `_hdr.txt`（含代次印章）。判据一律用官方 harness 的 `normalize_output`（`scripts/regression_test_720.sh:85-97` 逐字复用），真值 `/opt/homebrew/bin/php`，产物名 `aot_compile_{base}`。

| 臂 | 旗标 | 编译失败 | 生成码漂移（vs 冻结默认档基线） | 输出等值 | 静默错值 DIFF | 运行失败 | SKIP |
|---|---|---|---|---|---|---|---|
| **A 抬档** | `--compile --no-debug-info --optimize=release-fast` | **0** | **67/67**（`gen_same=0`） | 48 | **17** | **2**（`f152` exit=139 SIGSEGV、`f160` exit=255 抛错） | 1（`f004`，PHP 真值侧非 0 退出） |
| **B 对照** | 默认档，仅 A 臂的 19 枚红形 | 0 | — | **19/19** | 0 | 0 | — |
| **C 内联单变量** | 默认档 + `--aot-enable-pass=inline --aot-inline-threshold=50` | 0 | **1/67**（仅 `f152`） | 66 | 0 | 1（`f152`） | 1 |
| **D 门限敏感性** | 默认档 + `--aot-enable-pass=inline`（threshold 仍为 releaseSmall 的 5） | 0 | **0**（`f152` main.zig md5 `f4c41d87a3bfbb78c7ff42fff27c3d66`／46376 行 **== 冻结基线**） | `f152` 等值 | 0 | 0 | — |

A 臂 17 枚 DIFF 名单：`f016 f024 f025 f044 f051 f061 f072 f104 f113 f117 f124 f134 f135 f161 f171 f176 f177`；2 枚运行失败 = `f152_closure_arrow_higher_order`、`f160_virtual_fs_path_traversal`。

**C 臂灵敏度标定（关键，否则 66 绿无意义）**：同一旗标下 §1 三形**全部复现** —— 形 A `rc=1` + `main.zig:215:45: error: expected type '*runtime_lib.Value', found 'runtime_lib.Value'`（本单原记 `:210:45`，行号随档/旗标变的发射行位移，同一错型）；形 B `B1=0 B2=0` vs 真值 `B1=5 B2=30`；形 C `D=`（空）vs 真值 `D=1 0`。⇒ C 臂的 66 绿是「语料里没有这个几何」的**真零面**，不是开关失灵。

**归因读数**：C 臂 `rf_same=0`（67 枚脚本无一的 release-fast `main.zig` 与内联单变量臂的 `main.zig` 逐字节相同）⇒ **抬档的生成码漂移没有一处可由内联单独复现**；19 枚红形里只有 `f152` 一枚能由「只开内联（threshold 50）」单独点亮，其余 **18 枚属另 12 枚 pass 变量**。

**`-O` 混杂已排除（两臂 zig 档位恒等）**：`native_linker.zig:32445-32446` 的尺寸规则（`zig_code.len > 200_000 and optimize_level == .release_small` ⇒ 抬 ReleaseFast）对**全部 68 语料都命中** —— 实测语料最小生成码 `f040_flyweight_forest_pool` = **278,560 bytes／5,606 行**（默认档，`build-exe` 打印 `-OReleaseFast`；**复验**：默认档单独重编译得 `main.zig` md5 `3c9aad342472611a6903a512a61931f3` == 冻结基线，字节数逐字节吻合），A/B/C 三臂 67 枚脚本抓到的 `-O` 一律 `-OReleaseFast` ⇒ 漂移与红面 **100% 归 IR pass 集**，与 zig `-O` 无关。两档唯一非 pass 差异为 `compiler.zig:645 strip_symbols = (optimize_level == .release_small)`，只影响链接期符号表，不影响 `main.zig` 与运行时输出。

**抬档一次翻动 13 枚 PassConfig 字段（非内联单变量）**：`optimizer.zig:175-199`（releaseFast）对 `:203-222`（releaseSmall）的差异 = `function_inlining`(`:181` ← `:209` false→true)、`inline_threshold`(5→50)、`type_specialization`(`:183`)、`copy_propagation`(`:220` false → releaseFast 继承默认 true)、`licm`(`:186`)、`max_iterations`(1→5 `:191`)、`max_instructions_per_function`(30000→50000 `:221`)、`scalar_replacement`(`:193`)、`gvn`(`:194`)、`advanced_sccp`(`:195`)、`slp_vectorization`(`:196`)、`polyhedral_optimization`(`:197`)、`loop_vectorization`(`:198`)；其余字段两档等值（dce／constprop／sccp／box_unbox／cse／strength／mem2reg／loop_unroll／cfg_cleanup／rc_elision）。

**收益读数（给 PERF-001 定价用）**：68 语料生成码总行数 **2,292,895 → 2,263,854**（−29,041，**−1.27%**），逐脚本 65 收缩／1 增长（`f152` +409，正是崩溃那枚）／1 等行（`f026`）。**行数差不可作红/绿预测器**（本轮否证，逐脚本 `baseline − release-fast` 差值实测：48 枚绿形中 **38 枚**的收缩幅度超过最小红形 `f025` 的 17 行，绿形最大收缩达 1,470 行 `f097`；19 枚红形差值横跨 −409（`f152` 增长）到 +2,854（`f117` 收缩）⇒ 幅度与红绿无对应）⇒ 抬档验收只能逐脚本跑比对，无静态捷径。

### 3.6 抬档路线的实测结论（替换 §3.4 的定性说法）

1. **「抬默认档一次性把三形全部点亮」需按实测收窄**：三形的**编译期硬失败**在 68 语料上命中面 **= 0**（A 臂 `compile_fail=0`），三形的静默错值几何在语料上也仅由 C 臂单独点亮 **1 枚**（`f152`，且其症状为 SIGSEGV，不属 §1 三形任一 ⇒ 见 §7.5 形 D 待立案）。
2. **但抬档的代价是 19/67 红 + 67/67 基线整体重登记**，收益仅 −1.27% 生成码行数（且**无运行基准数据**）⇒ 按现口径 **PERF-001 的「改默认档」路线不具备落地条件**；「下调 200KB 阈值」路线不受本单阻塞（只碰 zig `-O`，见 §2.5），且本轮实测显示该规则**对语料已 100% 命中** ⇒ 其剩余收益只在 `<200KB` 的脚本上（68 语料内为 0 枚）。
3. **修复路线 A（收窄内联门）的定位需更正**：它能把语料内联面从 1/67 收到 0，但**单独落地转不了 19 枚红中的 18 枚** ⇒ A 的价值是「非默认档正确性」与「C 臂零面」，**不是解锁抬档**（详见 §5 表格 A 行更正）。

### 3.7 f152 的**最小内联引爆阈值**阶梯 + 逐阈值「新放进来了谁」（任务 #105/#108：纯 CLI、零插桩、**零源码改动**、非门控）

**起因**（承 OPT-001 §5.9.7 遗留 ①）：#94 的 C 臂已用「默认档 + 只有内联旗标」单变量点亮 `f152`，#102 的 `release-safe`（同族但 `inline_threshold=15`）里 `f152` 全绿 ⇒ 引爆条件被夹在 `(15, 50]`，**区间内的最小引爆阈值**当时未钉。该轴 CLI 可达（`main.zig:317 --aot-inline-threshold`）⇒ 无需改 `optimizer.zig` ⇒ **非门控**，归本单。

**资产（永久，勿删）**：
- `fuzzy_scripts_720/tmp/c007_f152_thresh_bisect_tmp.sh` + `.tsv` + `_hdr.txt` —— 臂 = 默认档 + `--aot-enable-pass=inline --aot-inline-threshold=<T>`；两批合成 **13 个阈值／14 次编译臂**，`ELAPSED_R1=114s`（9 臂）+ `ELAPSED_R2=63s`（5 臂）⇒ **12.6 秒／臂**（实测，非估算）。
- `fuzzy_scripts_720/tmp/c007_f152_thresh_diff_probe_tmp.txt` —— **相邻阈值双臂 `main.zig` diff** 的逐字证据（被内联体片段、`reg_367` 全文出现清单、caller `reg_1` 的声明与唯一写入、三条别名签名）。

**阶梯读数**（判定 = 与 `/opt/homebrew/bin/php` 真值经官方 `normalize_output` 比对；`gen` 列对 `T=0` 无旗标臂）：

| `T` | gen | 判定 | `main.zig` 行数 | md5 | 症状（实测明细） |
|---|---|---|---|---|---|
| 0, 15, 20, 25, 30, 31, 32, 33, **34** | `BASE_SAME` | **PASS** | 46376 | `f4c41d87a3bfbb78c7ff42fff27c3d66` | 跑到 `=== f152 Done ===`；md5/行数 == **冻结基线**（同 §7.3 D 臂） |
| **35**, 40 | `BASE_DRIFT` | **RUNTIME_FAIL** | 46798 | `8117a372cad3f09dfc955acb72195584` | `exit=255` `Uncaught TypeError: FuncCollection::__construct(): Argument #1 ($items) must be of type array, **string given**`（抛在 callee 体 `:128`） |
| 45 | `BASE_DRIFT` | **RUNTIME_FAIL** | 47101 | `1c59a2935865215911c8925ff933d1ae` | `exit=139` SIGSEGV，输出停在 `--- Function Composition ---` 之后 |
| 50 | `BASE_DRIFT` | **RUNTIME_FAIL** | 47849 | `ed742689d9e44b7088c1bcdcbe340a01` | `exit=139` SIGSEGV，停在 `--- Partial Application ---` 之后（**逐字节复现 #94 C 臂**） |

⇒ **最小引爆阈值 = 35**（34 绿／35 红，整数粒度已钉死）。35≡40 逐字节相同 ⇒ 该区间无新 callee 过门。行数 `46376 → 46798 → 46798 → 47101 → 47849` **单调不减** ⇒ §7.3 的「内联集合对 threshold 单调不减」由实测正面印证。

**门算式（本轮新核对到行；`inline_threshold` 有**两处**用途，主门不是 §7.3 引的那处）**：

```text
optimizer.zig:4583-4587  estimated_cost = instruction_count + 3*branch_count + 10*alloc_count + (may_throw ? 20 : 0)
optimizer.zig:4590-4592  can_inline = !is_recursive ∧ estimated_cost <= inline_threshold ∧ block_count <= 6   ← **主门：逐值比较**
optimizer.zig:4664-4666  very_small = estimated_cost * 4 <= inline_threshold ⇒ max_calls 3→10                   ← 次门：本语实测**惰性**
optimizer.zig:4681-4682  blocks == 0 拒；blocks > 3 拒
```

⇒ 由「34 与冻结基线逐字节相同 ∧ 35 首次漂移」+ cost 为 `u32` ⇒ **引爆 callee 的 `estimated_cost` 恰 = 35**（这是**推导**，不是读到；直接读 `call_graph` 需插桩 ⇒ 门控，见下诚实边界）。次门在 `T=36` 处的放宽（cost ≤ 8 且 `call_count ∈ (3,10]`）在 35≡40 的等值面前**没有放进任何 callee**。

**逐阈值「新放进来了谁」**（双臂 diff：新增 `php_object_new_with_constructor("FuncCollection")` 计数 `t34=3 → t35=4`（恰好 +1 份内联副本）、新增体块的 `setSourceLocation` PHP 源行直方图）：

| 阈值 | 新内联的 callee（实测身份） | 其在 callee 帧里的形参寄存器 | 症状对应 |
|---|---|---|---|
| `T ≤ 34` | **无**（生成码 == 冻结基线） | — | 全绿 |
| `T = 35, 40` | **`collect()`**（源码 `:127-129`，体 = `return new FuncCollection($items);`） | **`reg_1`**（`@"collect"` 体内 `reg_2 = reg_1` ⇒ `$items` 就是 id 1） | TypeError「string given」，抛点 = 内联副本里的 `:128` |
| `T = 45` | `compose`/`pipe` 一族（直方图 60:5 49:5 55:2 54:2 44:2 43:2 56:1 45:1 108:1 100:1） | 见别名签名 `reg_370 = reg_1.*` | SEGV 停在 Function Composition 段 |
| `T = 50` | **`partial()`**（`:36-40`，直方图 38:12 37:8 36:8） | `reg_371 = reg_2.*`、`reg_372 = reg_3.*` | SEGV 停在 Partial Application 段（= §7.5 原记症状） |

⇒ **崩点随「哪枚 callee 被内联」移动**：这不是某一处专用调用点几何，而是**内联机制本身**的通用缺陷在不同 callee 上的不同表现（三条互证见下）。

**发射层机制读数（`T=35` 臂，四条，全部实测）**：

1. **def/use 分裂**：内联副本里 `.param` 的**定义**换到了新号 `reg_367`（t35 `main.zig:3539` 声明、`:32565/:32568` 写入），但 callee 体对 `$items` 的**读取**仍是老号 ⇒ `reg_368 = reg_1.*`（`:32576`）。
2. **老号在 caller 帧里另有其人**：宿主是 `@"__main__"`（`:3507`–`:43407`），它的 `reg_1` 是**引用格** —— `var reg_1: *runtime.Value = &reg_1_storage`（`:3858`），全文**只写一次** = `runtime.Value.initString(static_strings[29])`（`:4562`），而 `static_strings[29]`（`string_table` 起于生成码 `:8`）= 字面量 **`"--- Currying ---\n"`** ⇒ 错绑进来的值就是那个字符串，与 TypeError 的「string given」**逐字相符**。
3. **绑定结果被丢弃**：`reg_367` 全文仅 4 处（声明 + 取址 + 两处写入）、**零次读取** ⇒ 内联体里的实参装填读的是 callee 自己的 `args[0]`（在 caller 帧即 **caller 的 `args`**），产出即死码。
4. **顺带实测到一条子缺陷**：callee 自己帧里的形参类型强校验 `php_check_param_type("collect", 0, args[0], "array", false, "$items")`（`:2995`）在内联副本中**整段不存在**（窗口 `:32500–32600` 命中 0；全文 `php_check_param_type("collect"` 计数 t34 与 t35 同为 **1**）⇒ 内联**丢弃了 callee 的形参类型检查**，错误只能在其后 `__construct` 自带的检查处才炸出来（症状故为「晚一步的 TypeError」而非内联点报错）。

**对 §5 修复口径的实测印证**（不改判据，只把「推测」换成「实测」）：

- **B 行的诊断升级为实测**：`reg_map` 的键是**形参下标**（`:4695-4701` 的 `reg_map.put(@intCast(i), args[i].id)` —— 循环里 `|_, i|` 把参数寄存器本身丢弃了），而 callee 体内用的是**寄存器 id**（本例 id = 1、下标 = 0）⇒ 查表**必 miss** ⇒ `cloneAndRemapInstruction` 沿用旧 id ⇒ 与 caller 同号寄存器串扰。§5-B 的「改按 result id 建表 + 丢弃 `.param`」正是这一 miss 的直接对症点，且本例还额外要求 **B 落地时同时补回形参类型检查**（第 4 条子缺陷），否则「内联后静默跳过 `array` 校验」会独立成害。
- **A 行的定位再补一条依据**：A 属**掩盖式**止血 —— 阶梯显示缺陷与 cost 阈值**无因果**，cost 门只是**恰好**在 35 放进第一枚受害 callee（默认档 `function_inlining=false` + cost 门 5 ⇒ 语料结构性不可见）。换一份语料（存在 cost ≤ 34 的同形 callee）A 就罩不住 ⇒ **A 不能当修复**，与 §3.6 第 3 点同向。

**诚实边界（禁写成已证）**：
1. ~~45/50 两臂只钉到「新内联了谁 + 同样的 def/use 分裂别名签名 + 崩点随之移动」；**SIGSEGV 的具体坏值未取证**（`php_create_closure(reg_374, reg_372, reg_371, reg_4, …)` 里 `reg_4` 在 caller 帧是谁、SEGV 落在哪一次解引用 ⇒ 需运行时侧另一轮）。~~ ⇒ **结案（2026-10-06，任务 #110／轮次 #111，读数见 §3.8）**：崩点语句、`runtime_lib` 落点行、SEGV 地址与**全部操作数盒**均已运行时实测；`T=45` 的错型操作数是 `reg_3.*`（**不是** `reg_4`）= 字符串 `"__arrow_17"`，`T=50` 的是 `reg_6` = `$add` 的闭包盒（`TYPE_FUNCTION`）。⇒ 问法本身被更正：崩在**数组临时量 id 未重绑**（串扰），不在 `php_create_closure` 的实参装填；`reg_4` 在 caller 帧是 `initBool(false)` 的合法值，与崩点无因果。
2. 逐 callee 的 `estimated_cost` 数值**是推导**（整数门 + 实测边界），不是读到；要读 `call_graph` 需插桩 ⇒ **门控**。
3. `T=35` 臂的崩溃是否等价于 §1 形 B（按值形参静默错值）的语料实例：**不判等** —— 本例症状是「晚一步的 TypeError」，形 B 是静默 `0`，二者共享根因（`.param` 未重绑）但**发射结局不同**；§1 三形与形 D 的归并仍以 §7.5 为准。

**方法登记（可复用，且比原计划更省）**：「**相邻阈值／相邻旗标的双臂 `ZIGPHP_AOT_KEEP_TEMP=1` 生成码 diff**」= 零插桩、零源码改动即可拿到「哪枚 callee 被内联、体被搬到哪个宿主帧、哪一格串扰」的身份，成本 = 2 编译臂 ≈ **26 秒** + 若干 grep。⇒ 本单 §7.5 原设想的「C 臂旗标 + 只读取证轮」已被此法**替代**（无需插桩）。

**成本**：阶梯 14 臂 = `114 + 63 = 177` 秒；身份轮 = 5 次编译臂（34/35/40/45/50）+ 2 次运行 + 5 份 `main.zig` diff，按同型臂 12.6 秒／臂 ≈ **63 秒量级**（该轮 harness 未自记墙钟，读数不受影响；正式报价以阶梯两批的 177 秒为准）。

---

### 3.8 两枚 SIGSEGV 的**运行时侧**归因（任务 #110／轮次 #111：同一生成码的 Debug 重建 + 崩点探针，零源码改动、非门控）

**起因** = §3.7 诚实边界第 1 条与 §7.5 的「仍未取证（留口）」。§3.7 全部读数来自**生成码静态面**，只能钉到「哪枚 callee、哪个旧 id」，钉不到「坏值是什么、SEGV 落在哪一次解引用」⇒ 本轮换**运行时侧**通道。

**新通道（方法登记，可复用于任何「ReleaseFast 只给 exit=139」的崩面）**：

1. `ZIGPHP_AOT_KEEP_TEMP=1` 编译臂（几何同 §6.2）→ 取 `main.zig` 并**先比 §3.7 指纹**（md5 + 行数），本 harness 记作 `FP_MATCH`，不等则整轮读数作废；
2. **同一份未改动副本**用 `-ODebug` 重建：`zig build-exe main.zig -femit-bin=<产物> -ODebug -target aarch64-macos -L/opt/homebrew/lib -L/usr/local/lib -lpcre2-8 -lc` ⇒ Zig 自带段错误处理器打印 `file:line` 全栈（ReleaseFast 只给 `exit=139`，无栈）；
3. 按崩点语句**注入零解引用探针**（`c007_segv_probe_tmp.py` 自动生成 `main_probe.zig`）后同样 `-ODebug` 重建 → 拿到操作数原始盒。

**三条实测坑（本轮踩过，禁复踩）**：
- `@ptrFromInt` 在 **Debug 下做对齐检查** ⇒ 探针若「先读 `.ref_count` 再判类型」会先把探针自己跑崩（实测 `panic: incorrect alignment … runtime_lib.zig:2585 in asArray`）⇒ 探针第一行**只打盒与谓词**，仅当 `isArray()` 才读 `PHPArray` 字段。
- 崩点操作数可能是**引用槽**（宿主帧里 `var reg_3: *runtime.Value = &reg_3_storage;`）⇒ 探针须发 `reg_N.*` 并额外打印**槽地址**；判别法 = 向上回溯该寄存器的声明行（遇 `pub fn @` 即停，防跨帧误判）。
- **Debug 的退出码是 134（abort），不是 139** ⇒ **禁止拿 exit 码当同一性判据**；同一性只认「md5 == 登记表」+「输出截断点文本相同」。

**三条自证（本轮全绿，读数在 TSV）**：① 三臂 `FP_MATCH`（`T=34`/`45`/`50` 的 md5 与行数逐一对上 §3.7 阶梯表）；② **对照臂 `T=34` 的 Debug 重建跑到自然结束**（`exit=0`、末行 `=== f152 Done ===`）⇒ Debug 本身不造崩；③ 两枚崩形的 Debug **输出截断点**与 §3.7 登记的 ReleaseFast 症状逐字相同（`--- Function Composition ---`／`--- Partial Application ---`）。

**崩点落点（全部实测；行号 = 未改动 `main.zig`，探针栈里的 `main_probe.zig` 行号需回读 `PROBE-CTX` 的 `fault_line=` 映射）**：

| 臂 | 崩点语句（宿主帧 = `@"__main__"`，起 `:3507`） | 运行时落点（`runtime_lib_template.zig`） | SEGV 地址 | 落点在做什么 |
|---|---|---|---|---|
| `T=45` | `:21332` `try reg_3.*.asArray().pushRaw(runtime.runtime_allocator, reg_2.*);`（PHP 源行 `:49`） | `pushRaw :2220` → `put :1899` | `0x7f` | `if (parent.has_active_refs …)` —— **读**野 `parent` |
| `T=50` | `:17542` `try reg_6.asArray().pushRaw(runtime.runtime_allocator, reg_4);`（PHP 源行 `:38`） | `pushRaw :2220` → `put :1917` | `0x10` | `self.packed_values.items[idx] = value;` —— **写**野基址 |
| `T=34` | 无崩（对照臂） | — | — | — |

**操作数实测（探针在崩点前一行打印；类型用 ABI 自有常量 `nanbox_abi`：`TYPE_STRING=0x0000800000000000`／`TYPE_ARRAY=0x0001000000000000`／`TYPE_FUNCTION=0x0002000000000000`，取证件 = `tag_probe_tmp.zig`，其谓词读数 == 运行时 `isNull/isString/isArray/isBool/isInt/isFloat` 实判）**：

| 臂 | 寄存器 | 原始盒 | `tag` | 实判 | 读出内容 |
|---|---|---|---|---|---|
| `T=45` | **`reg_3.*`（数组目标 ← 错绑）** | `0x7ffc800104f60f80` | `TYPE_STRING` | `str=1 arr=0 ref=0 obj=0` | 字符串盒被当 `*PHPArray` |
| `T=45` | `reg_2.*`（被 push 的值） | `0x7ffd000104d302e8` | `TYPE_ARRAY` | `arr=1` | `ref_count=1 next_index=0 packed_len=0`（合法空数组，槽址 `0x16b796b88`） |
| `T=45` | `reg_371`（**本应**目标） | `0x7ffd000104d31440` | `TYPE_ARRAY` | `arr=1` | `ref_count=1 next_index=0 packed_len=0`（新号已正确重编号，零次读取） |
| `T=45` | `reg_4` / `reg_372` / `reg_374` | `0x7ffc000000000002` / `…01` | `0` / `0` | bool false / nil×2 | 与崩点**无因果** |
| `T=50` | **`reg_6`（数组目标 ← 错绑）** | `0x7ffe000103440658` | **`TYPE_FUNCTION`** | 五谓词全 0（既非 nil/arr/ref/str/obj） | **闭包盒**被当 `*PHPArray` |
| `T=50` | `reg_5` | `0x7ffe000103440658` | `TYPE_FUNCTION` | 同上 | **与 `reg_6` 逐位相同** = 同一枚 `PHPClosure` |
| `T=50` | `reg_373`（**本应**目标） | `0x7ffd0001034a0d38` | `TYPE_ARRAY` | `arr=1` | `ref_count=1 next_index=0 packed_len=0`（新号已重编号，零次读取） |
| `T=50` | `reg_4` | `0x7ffc000000000002` | `0` | bool false | 被 push 的值，合法 |

**逐寄存器溯源（「旧 id 在宿主帧是谁」，两臂各只有一条写入，全部实测）**：
- **`T=45` 的 `reg_3`** = `@"__main__"` 帧的引用槽：`:3950` `var reg_3_storage: runtime.Value = initNull();`／`:3951` `var reg_3: *runtime.Value = &reg_3_storage;`；`:21332` 之前**全帧唯一**非空写入 = `:4966 reg_3.* = runtime.Value.initString(static_strings[116]);`，而 `string_table[116]`（生成码 `:125`，index 0 在 `:9`）逐字 = **`"__arrow_17"`**（同帧 `:4974` 把它作为 `php_create_closure` 第一参 = 闭包名）。⇒ 塞进 `asArray()` 的是**一枚闭包名字面量字符串**。
- **`T=45` 的 `reg_2`** = 同帧引用槽（`:3682`/`:3683`），唯一写入 `:4962 reg_2.* = initArray(PHPArray.init(…))` ⇒ 与探针读到的合法空数组一致。
- **`T=50` 的 `reg_6`** = 普通值（`:3582` 声明、`:3583 _ = &reg_6;`），帧内（`:3507`–`:44458`，`@"__arrow_17"` 起 `:44459`）非空写入**只有一枚**：`:5384 reg_6 = getGlobalVar("$add");`（PHP `:67 $curriedAdd = curry($add);`）；另有 **97 处** `reg_6 = initNull()` **全部落在 `// Cleanup on exception` 支**（最近一枚起点 `:17091`，含 §3.7 曾疑的 `:17175`）⇒ 未执行，与「崩点读到闭包盒」自洽。
- **`T=50` 的 `reg_5`** = 唯一写入 `:4990 reg_5 = try php_create_closure(reg_3.*, reg_2.*, reg_4, …)`（PHP `:66 $add = fn($a,$b,$c) => …`）⇒ `:5380 setGlobalVar("$add", reg_5)` → `:5384 getGlobalVar("$add")` ⇒ `reg_5`/`reg_6` **同一枚闭包对象**（`dp=0x103440658` 逐位相同），这正是两盒相等的解释，**不需要**假设额外的写入点。
- **两臂的「本应目标」都在崩点正上方被重新编号后定义却零次读取**：`T=45` = `:21321 reg_371 = initArray(…)`；`T=50` = `:17531 reg_373 = initArray(…)` ⇒ 与 §3.7 第 ①③ 条同型，本轮把它从「`.param` 的 def/use 分裂」**推广到数组临时量**。

**机制结论（把本单的机制集从「静默错值」升级为「实测类型混淆 → SEGV」）**：
内联副本把 callee 的**数组临时量定义**搬到新号（`reg_371`/`reg_373`），体内**读写仍留在 callee 旧 id**（`reg_3`/`reg_6`）；旧 id 在宿主帧是**另一枚活值且类型不同**（`T=45` = 字符串、`T=50` = 闭包），而 `asArray()`（`runtime_lib_template.zig:2578-2586`）**只 `decodePtr` + `@ptrFromInt`，不校验 tag**（仅 `isRef()` 透传，无 `isArray()` 前置）⇒ `PHPString`／`PHPClosure` 头被当 `PHPArray` 用，`elements.parent`／`packed_values.items` 读成野值 ⇒ 一枚崩在 `put:1899` 的**读**、一枚崩在 `put:1917` 的**写**。

⇒ **两条新判据（必须进 §5 的落地评审）**：
1. **§5-B 的覆盖面需扩**：「按 result id 建表 + 丢弃 `.param`」只治形参映射；本轮两枚崩串扰的是 callee 的**临时量 id**，与 `.param` **无关** ⇒ **只改 `.param` 重绑消不掉这两枚崩**（`T=45`/`50` 可作为 B 方案的必过反例）。重绑必须覆盖体内**全部**寄存器 id。
2. **发射侧硬化为独立缺口**：`asArray()` 无 tag 断言 ⇒ 任何 id 串扰都以 SEGV 暴露而非可控错误，取证成本极高（本轮 24 秒／臂 vs `T=35` 臂的「晚一步 TypeError」几乎零成本）。

| 优先级 | 建议 | 影响面 | 落地成本 |
|---|---|---|---|
| P0 | §5-B 重绑范围改为「callee 体内全部 id」，并把 `T=45`/`T=50` 两臂列为**必过反例**（复测路径 §6.3） | 抬档红面 2/19 崩形 + 未来任何同类 callee | 中（`optimizer.zig` 内联体重编号一处，门控） |
| P1 | 内联副本内的数组/对象强转点前插 `isArray()` 守卫或发射期断言（路线 **E**，§5 之外新增） | 把「不可取证的黑盒崩」转为「可控错值/编译期报错」，语料面 0（默认档不内联） | 低-中（发射侧每处一次 tag 判定 ⇒ **有性能代价，需老铁裁决**） |
| P2 | `-ODebug` 重建通道登记为「ReleaseFast 只给 exit=139」类崩形的默认取证法 | 后续归因轮 | 零（harness 已永久化） |

**诚实边界（禁写成已证）**：
1. 探针只在**崩点前一行**读一次操作数 ⇒ 「旧 id 更早是否也被同一机制写过/读过」未测。
2. 「为何 `reg_371`/`reg_373` 的定义没被同步重绑到体内」的**内联器侧具体分支**仍未读到；逐 callee 的 `estimated_cost` 仍是推导 ⇒ 需 `optimizer.zig` 插桩 ⇒ **门控**。
3. 本通道为 **Debug 重建**，与 ReleaseFast 在分配器／UAF 行为上可能有差（历史分歧见 `feedback-native-linker-clone-debugging`）⇒ 结论**只用于归因崩点与操作数类型**，不断言「ReleaseFast 也停在 `:1899`/`:1917`」；自证 ③ 只覆盖输出截断面。
4. **语料面未测**：只跑了 `f152` 的三臂 ⇒ 「类型混淆是另 18 枚抬档崩形的通用机制」属未证。
5. 无 `lldb`（本仓 Bash 禁用）⇒ 落点行完全依赖 Debug 打印 + 探针，栈深只到 `main`。

**成本（实测，非估算）**：整轮跑两次，`ELAPSED=66s` 与 `ELAPSED=71s`；每轮含 3 臂 KEEP_TEMP 编译 + 3 次 Debug 重建（含对照臂）+ 2 份探针生成码 + 2 次探针 Debug 构建 + 2 次运行 ⇒ ≈ **24 秒／臂**（单枚 Debug 重建 ≈5 秒）；tag 解码取证件 ≈10 秒。

**资产（永久，勿删）**：`fuzzy_scripts_720/tmp/c007_segv_runtime_probe_tmp.sh`／`.tsv`／`_hdr.txt`（三步法 harness，含 `FP_MATCH`/`CUT_MATCH` 自证列）、`fuzzy_scripts_720/tmp/c007_segv_probe_tmp.py`（探针生成器，文件头已写死三条实测坑）。**零源码改动**（`optimizer.zig` `252234ef`/6877 未改；`native_linker.zig` `fbe6382a`/32797 仍为 #74 纯注释批 numstat `5 4`；探针只写 `/tmp` 副本）。

---

## 4. 与 AOT-PERF-001 的耦合（必须先读）

PERF-001 的 P0 决策项之一（该工单 §8 表）是「把默认 `optimize_level` 由 `release_small` 改为 `release_fast`（或下调 `native_linker.zig:32446` 的 200KB 阈值）」，其理由包含「**只改 `zig build-exe` 的 `-O` 与 `strip_symbols` ⇒ 不改生成码 ⇒ 理论上零漂移**」。**该理由已被本轮实测否证**：

| 同一脚本 | 档 | `main.zig` md5 | 行数 |
|---|---|---|---|
| `t007_inline_byval_tmp.php` | 默认（release-small） | `f7e7f303a9d01b821b540eec39686b88` | 1370 |
| 同上 | `--optimize=release-fast` | `722c97eb6abba8e7e4f484136300d97c` | 1332 |

⇒ `--optimize` 同时驱动 **IR pass 集**与 **zig `-O`**，改默认档**必然改生成码**（冻结基线哈希按产物规约需重登记），且**必然启用 `function_inlining`** ⇒ 本工单三形即刻生效。

**结论**：PERF-001 的「抬默认档」与「下调 200KB 阈值」两条路线在本缺陷上**不等价** —— 阈值路线只碰 zig `-O`（见 §2.5），不碰 IR pass，因而不受本工单阻塞；默认档路线受本工单阻塞。**建议把该耦合登记进 PERF-001 §8 的前置条件**（本轮已在新立单侧记录，PERF-001 侧文本待相应轮次更正，避免凭推断改他人工单）。

### 4.1 给 PERF-001 两条路线定价（任务 #94 实测，读数见 §3.5）

| PERF-001 路线 | 是否受本单阻塞 | 实测阻塞程度 | 实测总代价 | 实测收益 |
|---|---|---|---|---|
| **抬默认档 `release_small → release_fast`** | **是，但只是次要阻塞项** | 19 枚红形中**仅 1 枚**（`f152`）可由内联单变量点亮 ⇒ 落地路线 A 也只能转绿 1/19 | 67/67 生成码漂移（冻结基线须整体重登记）+ 17 枚静默错值 + 2 枚运行失败 + 跳过 1 枚 | 生成码行数 −1.27%（−29,041/2,292,895）；**运行时无基准** |
| **下调 `native_linker.zig:32446` 的 200KB 阈值** | **否**（只碰 zig `-O`／`strip_symbols`，不碰 pass 集） | 0 | **对 68 语料 = 空操作** —— 实测语料最小 `main.zig` 278,560 bytes 已越过 200KB，尺寸规则对语料 **100% 命中**，两臂 `-O` 恒为 ReleaseFast | 语料侧 0；只对「生成码 <200KB」的小脚本有效（如 `t007_closure_byref_min_tmp` 类最小探针） |

⇒ 抬档路线的真实阻塞项**不是本单**，而是「另 12 枚 pass 变量造成的 18 枚红形」；本单在语料上的暴露面为 1/67。**阈值路线在语料上无剩余收益**，若仍要走它，必须先给出语料外（小脚本/嵌入式产物）的收益证据 —— 该更正需在 PERF-001 §8 侧落地（见 §7.4）。

---

## 5. 修复口径（A–E 五条，可叠加；均为发射侧或优化器侧改动 ⇒ **待点头**）

| 优先级 | 方案 | 落点 | 影响面 | 落地成本 |
|---|---|---|---|---|
| **P0（止血，推荐首落）** | **A：收窄内联门** —— `can_inline`/`shouldInline` 追加「callee 无引用形参 ∧ `block_count == 1` ∧ 入口块终止符为 `.ret`（或 callee 返回 void）」三条合取 | `optimizer.zig:4590-4592` + `:4661-4669` + `:4681-4682` | 三形全部退出内联 ⇒ 与默认档逐字节等价；**代价 = 放弃这部分内联收益**（PERF-001 的 `-O` 收益不受影响，因为那是 zig 侧）。**实测更正（#94）**：语料内联面本就仅 1/67（`f152`），A 可把它收到 0；但**单独落地 A 转不了 19 枚抬档红形中的 18 枚** ⇒ A 不是解锁 PERF-001 抬档的钥匙（见 §3.6/§4.1） | 低（10 行内），但属生成码改动 ⇒ 必须走 68 语料漂移门 + 基线重登记评估；**默认档下预期零漂移**（D 臂实测：threshold=5 时语料无函数被内联，`f152` 的 `main.zig` 与冻结基线逐字节相同 ⇒ A 的收窄不可能反被触发），抬档侧才需重登记 |
| P1 | **B：把 `.param` 换成实参寄存器** —— 内联时不再搬 `.param` 指令，而是把 callee 的 `.param` result id 直接映射到 `args[i].id`（`:4695-4701` 改按 result id 建表、`:4861` 改为丢弃该指令），并保留类型强转/默认值/COW 语义 | `optimizer.zig:4695-4701`、`:4711-4717`、`:4861` | 修形 B，但**修不了形 A**（引用形参要搬的是 cell 指针而非值）、也修不了 C（体截断）⇒ B 必须与 A/C 同批或更晚。**⚠ 实测收窄（#110／轮次 #111）**：`T=45`/`50` 两枚崩串扰的是 callee 的**数组临时量 id**（`reg_3`/`reg_6`），与 `.param` 映射**无关** ⇒ **只按上述落点改 `.param` 消不掉这两枚崩**；重绑范围必须覆盖**体内全部寄存器 id**，且验收须把 §6.3 两臂列为**必过反例**（`fault_line=21332`／`17542` 不再出现 + 对照臂 `T=34` 保持逐字节等值）。另需一并补回形参类型检查（§3.7 第 ④ 条）。 | 中-高（跨 IR 语义，需逐 op 核） |
| P1 | **C：多块 callee 要么整块搬要么不搬** —— 克隆 `callee.blocks` 全量 + CFG 缝合，或直接由 A 的 `block_count == 1` 门排除 | `optimizer.zig:4711`、`:4720-4743` | 形 C；缝合方案会引入块重命名/寄存器跨界，成本显著 | 高 |
| P2 | **D：发射侧健壮性补支** —— 「普通参数 COW」支补 `isPointerReg` 判别，使 `*Value` 目标不再被写入 `Value`（把「静默非法」变成「合法发射」或至少显式报错） | `native_linker.zig:21143`、`:21170-21193`（对照 `:21068-21074` 的三分判别） | 默认档命中面**已实测为不可达**（六形探针 ①–⑤ 方法/静态/默认值/混排/互换全部逐字节等值，见 §7.2 结案条）⇒ 本项为**纯防御**，非缺陷修复 | 低-中，发射侧 ⇒ 需漂移门 |
| P1 | **E（#111 新增）：内联副本内的强转点前补 tag 守卫／发射期断言** —— `asArray()`（`runtime_lib_template.zig:2578-2586`）实测**不校验 tag**（只 `decodePtr` + `@ptrFromInt`）⇒ 任何 id 串扰都直接以 SEGV 暴露。可选项：① 发射器在内联副本的数组写点前插 `isArray()` 守卫；② 只加**编译期**断言（`@panic`/`error.UnexpectedType`）把「不可取证的黑盒崩」转为「可控报错」 | `native_linker.zig` 内联副本发射路径 +（可选）`runtime_lib_template.zig:2578` | 不改语义、不改正确路径行为；默认档语料面 **0**（不内联 ⇒ 无命中）；收益 = 抬档崩形从「24 秒／臂的运行时归因」降为「报错点自证」。**⚠ ①在每次数组写前多一次 tag 判定 ⇒ 属性能代价改动，按宪法 §六-7 需老铁裁决；②为发射期一次性判定，零运行时成本** | ①低-中（有性能代价）／②低（发射期断言，仍属生成码改动 ⇒ 走漂移门） |

**不建议**：直接关 `releaseFast/releaseSafe` 的 `function_inlining`（`:153`/`:181`）—— 那是档位语义变更，触及 `optimizer.zig:6222/6225` 的测试锁定，且会把 PERF-001 的优化面一并砍掉；A 方案的窄门是可回退的同效替代。

---

## 6. 复测路径（老铁复验，全部带超时）

```bash
# 环境：仓库根目录，二进制为当前工作区代次构建物
P=fuzzy_scripts_720/tmp
# 形 A：按引用形参 ⇒ release-fast 编译失败、默认档等值
timeout 600 ./zig-out/bin/php-interpreter --compile --no-debug-info --optimize=release-fast \
  --output=/tmp/aot_compile_t007_inline_refparam_tmp $P/t007_inline_refparam_tmp.php   # 期望 rc=1 + 上述 error
timeout 10 /opt/homebrew/bin/php $P/t007_inline_refparam_tmp.php                        # A count=3 last=9
# 形 B：按值形参 ⇒ release-fast 输出 B1=0 B2=0（错），默认档正确
timeout 600 ./zig-out/bin/php-interpreter --compile --no-debug-info --optimize=release-fast \
  --output=/tmp/aot_compile_t007_inline_byval_tmp $P/t007_inline_byval_tmp.php
timeout 10 /tmp/aot_compile_t007_inline_byval_tmp                                       # 现状 B1=0 / B2=0
timeout 10 /opt/homebrew/bin/php $P/t007_inline_byval_tmp.php                           # 真值 B1=5 / B2=30
# 形 C：多块 callee ⇒ release-fast 输出空
timeout 600 ./zig-out/bin/php-interpreter --compile --no-debug-info --optimize=release-fast \
  --output=/tmp/aot_compile_t007_inline_multiblock_tmp $P/t007_inline_multiblock_tmp.php
timeout 10 /tmp/aot_compile_t007_inline_multiblock_tmp                                  # 现状 D=（空）
# 产物清理（禁止删 .php 源）
rm -f /tmp/aot_compile_t007_inline_*
```

**落地批的验收门（建议）**：三形 × {默认档, release-fast} 六个输出全部与 `/opt/homebrew/bin/php` 逐字节等值 + 官方 68 语料默认档 `SWEEP_DONE mismatch=0` 不漂移。

### 6.1 抬档面三臂复测路径（任务 #94，永久 harness，全部带超时）

```bash
cd /Users/wangjianjun/products/parser
# A 臂：68 语料 × release-fast 面（约 30 min，禁与任何其他 AOT 批次并发）
nohup bash fuzzy_scripts_720/tmp/c007_releasefast_face_tmp.sh > /tmp/c007_rf_run.log 2>&1 &
tail -1 fuzzy_scripts_720/tmp/c007_rf_face_tmp.tsv
# 期望 RFACE_DONE total=68 gen_same=0 gen_drift=67 pass=48 diff=17 runtime_fail=2 compile_fail=0 skip=1

# B 臂：A 臂 19 枚红形的默认档对照（名单从 A 臂 TSV 自动取）
bash fuzzy_scripts_720/tmp/c007_rf_control_tmp.sh   # 期望 CTRL_DONE total=19 pass=19 diff=0 runtime_fail=0 compile_fail=0

# C 臂：内联单变量归因（纯 CLI 通道 main.zig:311 --aot-enable-pass → compiler.zig:662 applyPassOverrides）
bash fuzzy_scripts_720/tmp/c007_inline_only_face_tmp.sh
# 期望 INLINE_ONLY_DONE total=68 base_same=66 base_drift=1 rf_same=0 pass=66 diff=0 runtime_fail=1 compile_fail=0 skip=1

# C 臂灵敏度标定（三形必须复现，否则该臂零面读数无意义）
for s in refparam byval multiblock; do
  timeout 600 ./zig-out/bin/php-interpreter --compile --no-debug-info \
    --aot-enable-pass=inline --aot-inline-threshold=50 \
    --output=/tmp/aot_compile_t007_inline_${s}_tmp fuzzy_scripts_720/tmp/t007_inline_${s}_tmp.php
done   # 期望：refparam rc=1（expected type '*runtime_lib.Value'）、byval 输出 B1=0/B2=0、multiblock 输出 D= 空

# D 臂：门限敏感性（threshold 保持 releaseSmall 的 5 ⇒ f152 生成码须回到冻结基线）
ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 ./zig-out/bin/php-interpreter --compile --no-debug-info \
  --aot-enable-pass=inline --output=/tmp/aot_compile_f152_t5 fuzzy_scripts_720/pass/f152_closure_arrow_higher_order.php
# 期望 main.zig = 46376 行 / md5 f4c41d87a3bfbb78c7ff42fff27c3d66（= baseline_main_zig_md5.tsv 行）
# 产物清理（禁止删 .php 源与 harness）
rm -rf /tmp/c007_rf_work /tmp/c007_rf_ctrl /tmp/c007_inline_only_work /tmp/c007_*_run.log
rm -f /tmp/aot_compile_t007_inline_* /tmp/aot_compile_f152_*; rm -rf .zigphp_aot_build_*
```

### 6.2 f152 最小引爆阈值阶梯复测路径（任务 #105/#108，永久 harness，全部带超时）

```bash
cd /Users/wangjianjun/products/parser
SRC=fuzzy_scripts_720/pass/f152_closure_arrow_higher_order.php

# 第 1 轮：粗阶梯（含 threshold=0 的默认档 base 行，9 臂 ≈ 114s）
bash fuzzy_scripts_720/tmp/c007_f152_thresh_bisect_tmp.sh "0 15 20 25 30 35 40 45 50"
# 第 2 轮：在 34/35 之间钉整数边界（5 臂 ≈ 63s；base 行须与第 1 轮 md5 相同）
bash fuzzy_scripts_720/tmp/c007_f152_thresh_bisect_tmp.sh "0 31 32 33 34"
# 期望（合并后 TSV 汇总行，见 c007_f152_thresh_bisect_tmp.tsv）：
#   THRESH_BISECT_MERGED thresholds=13 arms=14 rounds=2 green_T_max=34 red_T_min=35
#     base_md5=f4c41d87a3bfbb78c7ff42fff27c3d66 base_lines=46376
#   T ≤ 34 ⇒ BASE_SAME|PASS；T=35/40 ⇒ BASE_DRIFT|RUNTIME_FAIL（exit=255 TypeError，line 128）
#   T=45 ⇒ 47101 行 / 1c59a293…（exit=139，停在 --- Function Composition ---）
#   T=50 ⇒ 47849 行 / ed742689…（exit=139，停在 --- Partial Application ---，= #94 C 臂逐字节）

# 「新放进来了谁」——零插桩双臂生成码 diff（读 main.zig，不碰源码）
mkdir -p /tmp/c007_probe_work
for t in 34 35; do
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 ./zig-out/bin/php-interpreter --compile --no-debug-info \
    --aot-enable-pass=inline --aot-inline-threshold=$t \
    --output=/tmp/c007_probe_work/aot_compile_f152_t$t $SRC 2> /tmp/c007_probe_work/t$t.cerr
done
# 取 KEEP_TEMP 保留目录（错误输出里 'preserved' 行的最后一列），diff 出新增内联体
d34=$(awk '/preserved/ {print $NF; exit}' /tmp/c007_probe_work/t34.cerr)
d35=$(awk '/preserved/ {print $NF; exit}' /tmp/c007_probe_work/t35.cerr)
diff -u "$d34/main.zig" "$d35/main.zig" > /tmp/c007_probe_work/t34_t35.diff
# 期望：diff 唯一新增体 = collect()（源码 :127-129），且能看到
#   ① reg_367 只在 :32565/:32568 被写、零次读取 ② reg_368 = reg_1.*（caller 帧的引用格）
#   ③ 内联副本窗口内 php_check_param_type("collect", ...) 命中 0
grep -c 'php_object_new_with_constructor("FuncCollection"' "$d34/main.zig" "$d35/main.zig"   # 期望 3 → 4
# 产物清理（禁止删 .php 源与 harness；全部显式路径）
rm -rf /tmp/c007_probe_work /tmp/c007_f152_thresh_work /tmp/c007_thresh_run.log /tmp/c007_thresh_run2.log
rm -f /tmp/c007_f152_probe.log; rm -rf .zigphp_aot_build_*
```

**判据要点**：双臂 diff 只认「新增的 callee 体」，因此无需插桩即可把崩点钉到单枚 callee；`--output` 的父目录必须先存在（首轮曾因 `/tmp/c007_f152_probe/` 缺失静默 `rc=1`），且 md5 必须与阶梯 TSV 行对上才算复现。

### 6.3 两枚 SIGSEGV 的运行时侧复测路径（任务 #110／轮次 #111，永久 harness，全部带超时）

```bash
# 三步法一键复跑（默认 45 50 两臂 + 自动追加对照臂 34；实测 66~71 秒/轮）
bash fuzzy_scripts_720/tmp/c007_segv_runtime_probe_tmp.sh
# 单臂复跑（例如只验对照臂不造崩）
bash fuzzy_scripts_720/tmp/c007_segv_runtime_probe_tmp.sh 34

# 期望（三行自证必须全绿，缺一即本轮读数作废）
#   ① kind=gen   field=FP_MATCH  T=34/45/50 三臂均命中 ⇒ md5/行数 == §3.7 登记表
#      34=f4c41d87…/46376    45=1c59a293…/47101    50=ed742689…/47849
#   ② kind=dbg   T=34 ⇒ exit=0 且 last_line="=== f152 Done ==="（Debug 不造崩）
#   ③ kind=dbg   T=45 ⇒ CUT_MATCH；T=50 ⇒ CUT_MATCH（截断点与 ReleaseFast 同处）
# 期望崩点读数（读 TSV 的 dbg/probe 行）
#   T=45：fault_line=21332 stmt=try reg_3.*.asArray().pushRaw(runtime.runtime_allocator, reg_2.*);
#         落点 pushRaw:2220 → put:1899 ；SEGV 0x7f ；PROBE reg_3 SLOT str=1 arr=0（= static_strings[116]="__arrow_17"）
#   T=50：fault_line=17542 stmt=try reg_6.asArray().pushRaw(runtime.runtime_allocator, reg_4);
#         落点 pushRaw:2220 → put:1917 ；SEGV 0x10 ；PROBE reg_6 tag=TYPE_FUNCTION、与 reg_5 逐位相同
#   两臂各自的「本应目标」reg_371 / reg_373 须读到 arr=1 ref_count=1 next_index=0 packed_len=0
# 类型解码取证件（可选，10 秒级；把「手算 TYPE_MASK」换成运行时谓词实判）
cd /tmp/c007_p111_work/t50 && zig build-exe tag_probe_tmp.zig -femit-bin=/tmp/c007_p111_work/tag_probe_tmp \
  -ODebug -target aarch64-macos -L/opt/homebrew/lib -L/usr/local/lib -lpcre2-8 -lc && /tmp/c007_p111_work/tag_probe_tmp

# 产物清理（禁止删 .php 源与 harness；全部显式路径，禁用通配删 PHP 侧目录）
rm -rf /tmp/c007_p111_work /tmp/c007_p111_probe
rm -f fuzzy_scripts_720/tmp/aot_compile_f152_*   # 期望：本仓不应留下任何 aot_compile_*
```

**本通道的两条使用注意（踩过）**：
1. **`exit` 码不可当同一性判据** ⇒ ReleaseFast 崩形是 `139`，同一崩在 Debug 下是 `134`（Zig 的段错误处理器捕获后 `abort`）。同一性只认「`FP_MATCH` + `CUT_MATCH`」。
2. **探针栈里的行号属于 `main_probe.zig`**（插了 print 后整体下移）⇒ 必须回读 TSV 的 `PROBE-CTX … fault_line=<N>` 映射回未改动 `main.zig` 的行号（例：`T=50` 栈显 `17552`，未改动行号 `17542`）。

---

## 7. 遗留 / 未知

1. ~~形 B 的**语料面**在 release-fast 档下多大，未实测（68 语料今日只在默认档冻结）。~~ ⇒ **结案（2026-10-06，任务 #94 三臂实测，见 §3.5）**：抬档面 = **19/67 红**（17 静默错值 + 2 运行失败）+ **67/67 生成码漂移** + **0 编译失败**；默认档对照臂 19/19 绿 ⇒ 红面确由档造成。但**内联单变量只解释其中 1 枚**（`f152`），其余 18 枚属另 12 枚 pass 变量 ⇒ 「形 A/B/C 在语料上的面」实测为 **0**（编译失败 0 次、C 臂静默错值 0 枚），本单的语料暴露面被改记为 **1/67 且症状不同**（见 §7.5）。
2. ~~§2.4 第 4 步的发射侧缺口（COW 支缺 `isPointerReg`）在**非内联**几何下能否被触达，未实测 ⇒ 不判风险。~~ ⇒ **结案（2026-10-06，任务 #89，默认档六形实测 + 静态同基论证）**：
   - **实测**：`fuzzy_scripts_720/tmp/t007_refparam_noninline_geom_tmp.php` 六形在默认档编译 `rc=0`，①实例方法引用形参 / ②实例方法引用形参+默认值 / ③静态方法引用形参 / ④引用+普通混排 / ⑤双引用互换 **全部与 PHP 逐字节等值** ⇒ 该缺口在默认档（不内联）几何下**未被触达**。
   - **静态同基论证**（解释为何恒不触达）：`.ptr` 型 `.param` 与 `func.ref_params` 出自**同一** AST 谓词 `param_data.is_reference`（`ir_generator.zig:1092-1094` 写 ref_params 用 `param_index = func.params.items.len`；`:1150-1157`/`:1204-1258` 写 `.param` 用 `i + param_offset`），而 `this` 在 `generateParameters` **之前**已 `addParam` 到 index 0（`:2509-2517`）⇒ `param_offset` 与 `func.params` 基址恒等；闭包/箭头函数自建 `Function` 且 `params` 为空、`current_has_this_param=false`（`:8706-8729`/`:8834-8844`）⇒ 两径同为 0 基。故非内联时「`.ptr` 型 `.param`」必然命中 `is_ref_param` ⇒ 只走 `:21051-21055` 引用支，不会落入 COW 支。
   - **形 ⑥（闭包直调）崩不构成反证**：其成因是动态调用未装填引用实参（回落 `&null_val`），与 COW 支的指针判别无关 ⇒ 已独立立案 [AOT-REF-004](AOT-REF-004-dynamic-call-byref-arg-not-made.md)。**禁止把两单互为证据。**
3. ~~`--pass-override` 显式开 `function_inlining` 的路径（`main.zig:138` → `compiler.zig:666`）与本轮同源，未单独复测。~~ ⇒ **结案（任务 #94 C/D 臂实测）**：该通道为**纯 CLI、零源码改动**，实际旗标是 `--aot-enable-pass=<p>`／`--aot-disable-pass=<p>`（`src/main.zig:305/:311` → `applyPassToggle` `:124-172`，pass 名 `inline`/`function-inlining`）＋ `--aot-inline-threshold=<n>`，由 `compiler.zig:662-679 applyPassOverrides` 覆盖进 `PassConfig`（可覆盖 `function_inlining`/`inline_threshold`/`max_iterations` 等 14 枚字段）。
   - **标定读数**：C 臂（`inline` + threshold 50）下 §1 三形**全部复现** ⇒ 「显式开内联」与本单同源成立，不必再借 `--optimize` 整档抬升即可复现缺陷（取证成本大幅下降）。
   - **零面读数**：D 臂（`inline`，threshold 仍为 releaseSmall 的 5）下 `f152` 的 `main.zig` 与冻结基线**逐字节相同**（46376 行 / `f4c41d87…`），其余 66 枚在 threshold 50 已等值 ⇒ **threshold=5 时全语料无任何 callee 过内联门**。该结论有源码单调性支撑：`shouldInline`（`optimizer.zig:4661-4671`）里 `very_small = estimated_cost * 4 <= inline_threshold` 只把 `max_calls` 从 3 抬到 10 ⇒ 内联集合对 threshold **单调不减**，故 threshold=5 的内联集 ⊆ threshold=50 的内联集，无脚本可能「只在 5 下内联」。
     - **⚠ 本轮更正该段的依据（结论不变、主门换人，读数见 §3.7）**：`inline_threshold` 的**主门**不是 `:4664` 的 `very_small`，而是 `buildCallGraph` 里 `can_inline` 的逐值比较 `estimated_cost <= inline_threshold`（`optimizer.zig:4590-4592`）⇒ 阈值敏感性是**逐整数**放宽，不是「4 的台阶」。单调不减的结论仍成立，并被 §3.7 阶梯（`46376 → 46798 → 46798 → 47101 → 47849`、`T ≤ 34` 全部逐字节等于基线）**实测正面印证**；今后任何 threshold 推理必须先引 `:4590-4592`，`:4664` 只是次门（本语实测惰性）。
   - **该通道对后续归因轮的硬约束（实读）**：`applyPassToggle`（`src/main.zig:124-172`）只认 11 个 pass 名（`dce`／`constprop`／`box-unbox`／`inline`／`typespec`／`cse`／`licm`／`strength`／`mem2reg`／`unroll`／`cfg-cleanup`），`applyPassOverrides`（`compiler.zig:662-679`）另加 `inline_threshold`/`unroll_factor`/`max_iterations` ⇒ §3.5 列出的 **13 枚两档差异字段中仅 5 枚可由 CLI 关闭**（`function_inlining`、`type_specialization`、`licm`、`max_iterations`、`inline_threshold`），**另 8 枚无开关**（`copy_propagation`、`max_instructions_per_function`、`scalar_replacement`、`gvn`、`advanced_sccp`、`slp_vectorization`、`polyhedral_optimization`、`loop_vectorization`，未知名一律 `error.UnknownPass`）。⇒ 「把 18 枚抬档红形钉到单枚 pass」的二分**只能靠 CLI 覆盖 5/13 维**；5 枚全关仍红者，其下一步必然落到改 `optimizer.zig`（门控项 ⇒ 需点头）。
4. ~~本工单否证了 PERF-001「抬默认档不改生成码」的论证文本，PERF-001 侧更正需在下一轮巡检落地（见 §4）。~~ ⇒ **结案（同轮任务 #94）**：更正已在 PERF-001 工单内实际落地 5 处（§4 合一 P0 行拆为「阈值下调」与「改默认值」两行且后者标注「实测否决，建议降级 P2」、§5 的「预期 `diff=0`」收窄为只对阈值路线成立、§7 裁决项 1 收窄为「建议只改阈值」并把锚点由 `:32195` 刷为 `:32446`、TL;DR 补实测边界子条、§8.2.1 记录该锚点位移 +134 的复验），并附 #94 更新日志。
5. **形 D（`f152`）：机制已取证到**发射层（任务 #105/#108，读数见 §3.7）**与运行时侧（任务 #110／轮次 #111，读数见 §3.8）**，两枚 SIGSEGV 的崩点、落点与坏值均已钉死**：`f152_closure_arrow_higher_order` = 语料唯一「内联单变量可点亮」的红形。**它不属 §1 三形中的任一形**（三形为编译期类型错／静默错值／空返回，均不崩；本形崩，见 §3.8）。
   - **门槛已量化（§3.7 阶梯实测，替代原「C 臂旗标 + 只读取证轮」设想）**：**最小引爆阈值 = 35**（`T ≤ 34` 的 8 枚绿色旗标阈值 15/20/25/30/31/32/33/34，连同 `T=0` base 臂共 9 行全部 `BASE_SAME` 且 md5 == 冻结基线 `f4c41d87…`／46376 行；`T=35` 首次漂移并崩）。逐阈值新内联 callee 的身份由**双臂生成码 diff**（零插桩）钉死：`T=35/40` = **`collect()`**（源码 `:127-129`）⇒ `exit=255` `TypeError: FuncCollection::__construct(): Argument #1 ($items) must be of type array, **string given**`；`T=45` = `compose`/`pipe` 一族 ⇒ `exit=139` 停在 Function Composition 段；`T=50` = **`partial()`**（`:36-40`）⇒ `exit=139` 停在 Partial Application 段（逐字节复现 #94 C 臂 `ed742689…`／47849 行）。⇒ **原记「归因到 `.param` 错绑还是变参/spread 帧实参计数错配」这一问法被实测否证为二选一**：崩点随「哪枚 callee 被内联」移动，`partial` 的变参几何**不是**必要条件（`collect` 无变参、无 `use`、体只有一条 `return new`，同样崩）。
   - **已取证到的机制（§3.7 四条，全部发射层实测）**：① **def/use 分裂** —— 内联副本把 `.param` 的定义挪到新号 `reg_367`（`main.zig:3539`/`:32565`/`:32568`），但体内对 `$items` 的读取仍是老号 ⇒ `reg_368 = reg_1.*`（`:32576`）；② **老号在 caller 帧另有其人** —— 宿主 `@"__main__"`（`:3507`–`:43407`）的 `reg_1` 是引用格（`:3858`）且全文只写一次 = `static_strings[29]` = 字面量 `"--- Currying ---\n"` ⇒ 错绑值与 TypeError 的「string given」逐字相符；③ **绑定结果即死码** —— `reg_367` 零次读取，内联体的实参装填读的是 callee 自己的 `args[0]`（在 caller 帧 = caller 的 `args`）；④ **内联丢弃了 callee 的形参类型检查** —— `php_check_param_type("collect", 0, args[0], "array", …, "$items")` 只存在于 callee 自己帧（`:2995`），内联副本窗口 `:32500–32600` 命中 0（全文计数 t34 与 t35 同为 1）。根因位置 = `reg_map` 以**形参下标**为键（`optimizer.zig:4695-4701` 的 `reg_map.put(@intCast(i), args[i].id)`，循环 `|_, i|` 丢了参数寄存器本身）而 callee 体以**寄存器 id** 引用 ⇒ id 1 vs 下标 0 必 miss ⇒ 沿用旧号串扰。⇒ §5-B 由推测转为实测对症，且**落地时必须一并补回形参类型检查**。
   - ~~**仍未取证（留口，禁写成已证）**：`T=45`/`50` 两臂的 **SIGSEGV 具体坏值**未钉（别名签名 `reg_370 = reg_1.*`／`reg_371 = reg_2.*`+`reg_372 = reg_3.*`、`php_create_closure(reg_374, reg_372, reg_371, reg_4, …)` 已实测可见，但 `reg_4` 在 caller 帧是谁、SEGV 落在哪一次解引用 ⇒ 需运行时侧另一轮）~~ ⇒ **结案（2026-10-06，任务 #110／轮次 #111，读数与通道见 §3.8、复测见 §6.3）**：崩点 = `T=45` `main.zig:21332`（落 `put:1899` 读野 `parent`，SEGV `0x7f`）、`T=50` `main.zig:17542`（落 `put:1917` 写野基址，SEGV `0x10`）；错绑寄存器 = `reg_3.*`（盒 = `TYPE_STRING`，实文 = 闭包名 `"__arrow_17"`）与 `reg_6`（盒 = **`TYPE_FUNCTION`**，= `$add` 闭包，与同帧 `reg_5` 逐位相同）；两臂**本应**目标 `reg_371`/`reg_373` 均已正确重编号却零次读取。⇒ **原问法被更正两处**：① 崩因是 **callee 数组临时量 id 未重绑**（与 `.param` 无关 ⇒ §5-B 覆盖面必须扩到体内全部 id），② `reg_4` 是合法的 `bool false`，**不在**因果链上。**仍未测**：「内联器为何漏重绑临时量」的具体分支（需 `optimizer.zig` 插桩 ⇒ 门控）、该机制对另 18 枚抬档崩形的语料面（只跑了 `f152`）。逐 callee 的 `estimated_cost` 数值仍属**推导**（整数门 + 实测边界），直接读 `call_graph` 需插桩 ⇒ **门控**。
   - **禁止与 AOT-REF-004 互为证据**：REF-004 需「引用形参 + 动态调用装填缺口」，本形 callee 无引用形参；共同点仅在「实参边界」，成因与档位触发条件都不同。

---

**更新日志**:
- 2026-10-06（任务 #110／轮次 **#111**）: **§3.8 新增、§6.3 新增、§5 表 B 行实测收窄 + 新增 E 行、§7.5 留口闭合、§3.7 诚实边界第 1 条结案** —— 把 `f152` 两枚 SIGSEGV 从「生成码级推测」推进到**运行时侧实测**，全程**零源码改动、非门控**（探针只写 `/tmp` 副本）：
  - **新通道（三步法）**：KEEP_TEMP 取 `main.zig` → **先比 §3.7 指纹**（`FP_MATCH`）→ **同一份未改动副本 `-ODebug` 重建**（Zig 段错误处理器打印 `file:line` 栈）→ 按崩点语句自动生成**零解引用探针**副本再重建取操作数。三条自证全绿：① 三臂 `FP_MATCH`（34/45/50），② **对照臂 `T=34` 的 Debug 跑到 `exit=0`／`=== f152 Done ===`** ⇒ Debug 不造崩，③ 两枚崩形 Debug 的**输出截断点**与 §3.7 的 ReleaseFast 症状逐字相同（`CUT_MATCH`）。
  - **崩点与落点（实测）**：`T=45` = `main.zig:21332` `reg_3.*.asArray().pushRaw(…)` → `pushRaw:2220` → **`put:1899` 读野 `parent`**，SEGV `0x7f`；`T=50` = `:17542` `reg_6.asArray().pushRaw(…)` → `pushRaw:2220` → **`put:1917` 写野基址**，SEGV `0x10`。
  - **坏值（操作数盒 + 谓词实判）**：`T=45` 的数组目标 `reg_3.*` = **`TYPE_STRING`**，溯源到该帧 `:21332` 之前唯一非空写入 `:4966 initString(static_strings[116])`，`string_table[116]` 逐字 = **`"__arrow_17"`**（同帧拿它当 `php_create_closure` 的闭包名）；`T=50` 的 `reg_6` = **`TYPE_FUNCTION`**（闭包盒，`dp=0x103440658`）= `$add`，与同帧 `reg_5`（唯一写入 `:4990`）**逐位相同** ⇒ 两盒相等由 `setGlobalVar/getGlobalVar` 自证，**无需假设额外写入点**；曾疑的 97 处 `reg_6 = initNull()` **全部落在 `// Cleanup on exception` 支**（起点 `:17091`）⇒ 未执行。两臂的**本应**目标（`reg_371`/`reg_373`）均读到 `arr=1 ref_count=1 next_index=0 packed_len=0` 且**零次读取**；`reg_4` 是合法 `bool false` ⇒ **原 §7.5 问法（「`reg_4` 在 caller 帧是谁」）被实测判为不在因果链上**。
  - **机制升级**：本单机制集由「静默错值」扩为「**类型混淆 → SEGV**」—— 内联副本重编号了 callee 的**数组临时量定义**，却把体内读写留在旧 id；旧 id 在宿主帧是**另一枚活值且类型不同**，而 `asArray()`（`runtime_lib_template.zig:2578-2586`）**只 `decodePtr` + `@ptrFromInt`、不校验 tag** ⇒ 字符串头／闭包头被当 `*PHPArray` 用。
  - **两条新判据**：① **§5-B 覆盖面收窄**（串扰与 `.param` 无关 ⇒ 只改 `.param` 重绑消不掉这两枚崩，重绑须覆盖体内**全部**寄存器 id，`T=45`/`50` 列为必过反例）；② 新增**路线 E**（内联副本强转点前补 `isArray()` 守卫或发射期断言）⇒ ①型有性能代价、按宪法 §六-7 **需老铁裁决**，②型为发射期一次性判定零运行时成本。
  - **三条实测坑（已写进 harness 头注释，禁复踩）**：`@ptrFromInt` 在 Debug 下做**对齐检查**（未判 `isArray()` 即读字段会先崩探针，实测 `panic: incorrect alignment … :2585 in asArray`）；崩点操作数可能是**引用槽** ⇒ 须 `reg_N.*` 并打印槽地址（判别 = 向上回溯声明、遇 `pub fn @` 即停）；**Debug 的 exit 码是 134 不是 139 ⇒ 禁止拿 exit 码当同一性判据**。
  - **成本（实测，非估算）**：整轮两次 `ELAPSED=66s`／`71s`（每轮 3 臂编译 + 3 次 Debug 重建 + 2 份探针 + 2 次探针构建与运行）⇒ ≈ **24 秒／臂**（单枚 Debug 重建 ≈5 秒）；tag 解码取证件 ≈10 秒。
  - **新增永久资产**：`c007_segv_runtime_probe_tmp.sh`／`.tsv`／`_hdr.txt`、`c007_segv_probe_tmp.py`（探针生成器）。**零源码改动**（`optimizer.zig` `252234ef`/6877 未改；`native_linker.zig` `fbe6382a`/32797 仍为 #74 纯注释批 numstat `5 4`；冻结二进制 `1f15e4ce9b5c9cdaaef7cabf5efb9c76` 未重建）。
  - **仍未测**：内联器「为何漏重绑临时量」的具体分支（需 `optimizer.zig` 插桩 ⇒ 门控）、该机制对另 18 枚抬档崩形的**语料面**（只跑了 `f152` 三臂）、以及「ReleaseFast 下是否同停 `:1899`/`:1917`」（本通道为 Debug 重建，只用于归因崩点与类型）。
- 2026-10-06（任务 #105/#108）: **§3.7 新增、§6.2 新增，§7.3 依据更正，§7.5 形 D 部分结案** —— 把「`f152` 的最小内联引爆阈值」从 OPT-001 §5.9.7 的遗留里取回并**实测钉死**，全程**纯 CLI、零插桩、零源码改动**（非门控实验）：
  - **阶梯读数**：13 枚阈值 × 14 臂（默认档 base + 15/20/25/30/31/32/33/34 全 `BASE_SAME`，md5 逐字节 == 冻结基线 `f4c41d87…`／46376 行）⇒ **最小引爆阈值 = 35**（`THRESH_BISECT_MERGED … green_T_max=34 red_T_min=35`）。
  - **逐阈值「新放进来了谁」**（双臂 `main.zig` diff，零插桩）：`T=35/40` = **`collect()`**（`:127-129`）⇒ `exit=255` `TypeError: … Argument #1 ($items) must be of type array, string given`；`T=45` = `compose`/`pipe` 一族 ⇒ `exit=139`；`T=50` = **`partial()`**（`:36-40`）⇒ `exit=139`（与 #94 C 臂 `ed742689…`／47849 行逐字节复现）。⇒ **崩点随 callee 移动**，原记「`.param` 错绑 vs 变参/spread 帧计数错配」的二选一问法被实测否证。
  - **机制取证到发射层四条**：① def/use 分裂（`.param` 定义搬去新号 `reg_367`，体内读取仍是老号）② 老号在 caller 帧另有其人（`@"__main__"` 的 `reg_1` = 引用格，全文只写一次 = `static_strings[29]` = `"--- Currying ---\n"` ⇒ 与「string given」逐字相符）③ 绑定结果即死码（`reg_367` 零次读取）④ **内联丢弃 callee 的形参类型检查**（`php_check_param_type("collect", …)` 只在 callee 自有帧，t34 与 t35 全文计数同为 1）⇒ **§5-B 落地时必须一并补回形参类型检查**；§5-A「收窄门限」的口径由「同效替代」更正为**遮掩而非修复**。
  - **§7.3 依据更正（结论不变、主门换人）**：`inline_threshold` 的**主门** = `buildCallGraph` 的 `can_inline` 逐值比较 `estimated_cost <= inline_threshold`（`optimizer.zig:4590-4592`），不是 `:4664` 的 `very_small`（后者只把 `max_calls` 3→10，本语实测惰性）⇒ 阈值敏感性是**逐整数**放宽（34→35 翻面即反证「4 的台阶」说）；单调不减结论被阶梯实测**正面印证**。
  - **成本（实测，非估算）**：第 1 轮 9 臂 114s + 第 2 轮 5 臂 63s = **14 臂 177s ⇒ 12.6 s/臂**；身份轮（双臂 diff）未自计时，登记为口径缺口。
  - **新增永久资产**：`c007_f152_thresh_bisect_tmp.sh`／`.tsv`／`_hdr.txt`（合并阶梯 + 两轮时间戳）、`c007_f152_thresh_diff_probe_tmp.txt`（生成码级证据，5 节）。**零源码改动**（`optimizer.zig` `252234ef`/6877 未改、`native_linker.zig` `fbe6382a`/32797 仍为 #74 纯注释批 numstat `5 4`；二进制 `1f15e4ce9b5c9cdaaef7cabf5efb9c76` 冻结）。同轮在 [AOT-OPT-001](AOT-OPT-001-licm-multi-iteration-silent-wrong-values.md) §5.9.7 销掉遗留①、[AOT-PERF-001](AOT-PERF-001-默认优化档位与函数级状态机回退.md) §7 关闭「换一档」路线。
- 2026-10-06（任务 #94）: **§3.5/§3.6/§4.1 新增，§7.1/§7.3 结案，§7.5 新遗留（形 D），§5 A 行定位更正** —— 用三臂只读实测给「抬默认档」定价并做单变量归因：
  - **A 臂**（68 语料 × `--optimize=release-fast`）：`compile_fail=0`、**生成码漂移 67/67**（`gen_same=0`）、输出等值 48、**静默错值 17**、**运行失败 2**（`f152` SIGSEGV／`f160` exit=255）、skip 1（`f004`，PHP 真值侧非 0 退出）。
  - **B 臂**（A 臂 19 枚红形的默认档对照）：**19/19 全绿** ⇒ 红面确由档造成，非语料本底。
  - **C 臂**（默认档 + `--aot-enable-pass=inline --aot-inline-threshold=50`）：**66/67 生成码与冻结基线逐字节相同**、红形仅 `f152` 一枚、`rf_same=0` ⇒ **抬档的漂移与红面 18/19 与内联无关**；同旗标下 §1 三形全部复现（形 A `main.zig:215:45` 错型、形 B `B1=0 B2=0`、形 C `D=` 空）⇒ 该臂灵敏度已标定，零面是真零面。
  - **D 臂**（同上但 threshold 保持 5）：`f152` 的 `main.zig` == 冻结基线（46376 行／`f4c41d87…`）⇒ **threshold=5 时全语料零内联**（`shouldInline` `:4661-4671` 的 threshold 单调性已论证）。
  - **`-O` 混杂排除**：语料最小 `main.zig` = `f040` 278,560 bytes > 200KB ⇒ `native_linker.zig:32445-32446` 尺寸规则对 68 语料 **100% 命中**，三臂 `-O` 恒为 `-OReleaseFast`。
  - **收益**：生成码总行数 2,292,895 → 2,263,854（−29,041，−1.27%）；**静态行数差预测红/绿被否证**（逐脚本差值实测：48 枚绿形中 38 枚的收缩幅度超过最小红形 `f025` 的 17 行，绿形最大收缩 1,470 行；19 枚红形差值横跨 −409 到 +2,854）。
  - **同轮落地**：§7.3 追加「CLI 覆盖面对归因轮的硬约束（13 枚差异字段仅 5 枚可关）」、§7.4 **结案**（PERF-001 侧 5 处更正已实际写入该工单：§4 两行拆分／§5 期望收窄／§7 裁决项 1 只改阈值／TL;DR 实测边界／§8.2.1 锚点复验）。
  - **定位更正**：路线 A 单独落地只转 1/19 ⇒ A 不是解锁 PERF-001 抬档的钥匙；**阈值路线在语料上剩余收益为 0**。新增永久 harness `c007_releasefast_face_tmp.sh`／`c007_rf_control_tmp.sh`／`c007_inline_only_face_tmp.sh`（+ 同名 TSV/HDR）。**零源码改动**（`native_linker.zig` `fbe6382a`/32797 仍为 #74 纯注释批 numstat `5 4`；`optimizer.zig` `252234ef`/6877、`ir_generator.zig` `cb53c2da`、`runtime_lib_template.zig` 均未改；二进制 `1f15e4ce9b5c9cdaaef7cabf5efb9c76` 冻结）。
- 2026-10-06（任务 #89 同轮）: **§7.2 结案** —— 六形默认档探针实测 ①–⑤ 全等值 + 静态同基论证 ⇒ COW 支缺 `isPointerReg` 在非内联几何下**不可达**，修复项 **D 由「P2 健壮性缺口」降级为「P2 纯防御」**。同轮形 ⑥（闭包直调）暴露出**另一条默认档缺陷**并独立立案 [AOT-REF-004](AOT-REF-004-dynamic-call-byref-arg-not-made.md)：两单共享「引用形参实参装填**按函数名**查表」这一口径缺口（本单是内联把 `.param` 搬进无 `ref_params` 的帧，REF-004 是动态调用无名可查），但**成因、档位、症状均不同**（本单仅非默认档且为类型错误/静默错值，REF-004 默认档即 SIGSEGV），裁决与排期**不得互相顶替**。零源码改动（`fbe6382a`/32797、numstat `5 4`；`optimizer.zig` `252234ef`/6877 未改）。
- 2026-10-06: **立项（任务 #88）**。发现路径 = AOT-TYPE-001 §P2 存活线索的 `=&` 压测探针（`t001_refparam_retain_probe_tmp.php`）在 release-fast 档编译失败；收窄出三形永久探针 `t007_inline_refparam_tmp.php`／`t007_inline_byval_tmp.php`／`t007_inline_multiblock_tmp.php`，两档 × 三形共 6 组编译运行 + 6 组 PHP 真值实测。根因锁定 `optimizer.zig:4861`（`.param` 原样返回）、`:4695-4701`（映射键类型错）、`:4711`（只搬入口块）、`:4720-4743`（仅入口块 `.ret` 才回传结果），并给出形 A 的完整成因链（含 `native_linker.zig:5492-5516` 与 `:21143/:21170-21193` 两处口径）。实测否证 PERF-001 的「改默认档不改生成码」论证（同脚本两档 md5/行数不同）。零源码改动（`fbe6382a`/32797 与 `252234ef`/6877 均为读-only 复验）。
