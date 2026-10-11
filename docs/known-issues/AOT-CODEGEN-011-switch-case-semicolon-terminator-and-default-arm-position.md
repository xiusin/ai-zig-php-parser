# AOT-CODEGEN-011 · `switch` 臂族的两张独立面孔：① PHP 合法的 `case expr;` / `default;` **分号终结符被 AOT 编译期假拒绝**（5 形）；② `default` 臂的**源码位次在 AST 层就不存在** ⇒ 三模式各自给出**三种不同的错答**（6 形 × 4 侧实测，含「执行了 PHP 不执行的语句」的假执行面）

**问题 ID**: AOT-CODEGEN-011
**优先级**: **P1**（面孔 B = **PHP 合法而 AOT 拒**，按宪法 §七-8 前半句禁止以简化脚本绕过 ⇒ 比宽容面更致命；面孔 C = **rc=0 无消息的错语义 + 假执行** ⇒ 假绿）
**性质**: **两张面孔不同根**。面孔 B = 编译前端**文法位**（`src/compiler/parser.zig` 两处 `eat(.colon)`）；面孔 C = **AST 形态缺字段**（`src/compiler/ast.zig:186`）× 三模式各自的臂序消费（`ir_generator.zig` / `vm.zig` / `bytecode/generator.zig`）⇒ 与 AOT-CODEGEN-010 的 lexer 根**无关**，与 §3.6 的替代语法根也无关（实测与花括号／替代语法**无关**）。
**状态**: **立项 + 取证完成，落地待老铁裁决**（本轮**零 `src/` 改动**；面孔 B 的跨模式副作用与面孔 C 的 AST 形态选择均需 §六 点头）。**姊妹面 A（= CODEGEN-010 路线 R-5）已于 2026-10-09 任务 #127 落地收口** ⇒ 本单两面孔**仍未落地**（实测证据见 §7-7 与页顶「任务 #127 代次更正」块：门 K `aot_only_red` 前后恒 5、`diff_php_ok` 恒 1）；D-1…D-4 裁决仍未获答复。
**发现日期**: 2026-10-09（任务 #126 建**永久侧门 K** 轮实测发现，自 `AOT-CODEGEN-010` §3.7 拆出 ⇒ 该单只保留与关键字大小写同源的面孔 A）
**触发档**: 默认档（`--compile --no-debug-info`），无需抬档

**代次锚点（本轮实测，非记忆；判代次顺序承 CODEGEN-010 §9）**

| 资产 | md5 | 行数 / 说明 |
|---|---|---|
| `zig-out/bin/php-interpreter` | `81f8a55a989f9a793fec2f75c32fd37d` | 与 CODEGEN-010 的 **R-3 批同代次**（修复前基线二进制备份在 `/tmp/c010_prefix_backup/`，`1f15e4ce…`） |
| `src/compiler/parser.zig` | `5ad452fe4bc250b4732cbb3a2827b28a` | 4288 行（`wc -l` 实测）；面孔 B 的 `:3571`/`:3583`、面孔 C 的 `:3616` 同文件 |
| `src/compiler/ast.zig` | `3b2828f9028df923515e094a4aaa0493` | 面孔 C 的形态位 = `:186` |
| `src/aot/ir_generator.zig` | `96377ae7d33d52c6551a5daadefd886e` | 9743 行；宪法 §一 **超大文件**，改前必须 grep 既有模式 |
| `src/runtime/vm.zig` | `8d032b2f2d499099ace93fa4aca5a957` | `evaluateSwitchStatement:10146-10205`（解释器侧消费） |
| `src/bytecode/generator.zig` | `2175dd4af464d577c279be328e6bb243` | `visitSwitch:655-720+`（字节码侧消费） |
| `fuzzy_scripts_720/tmp/c010_brace_switch_gate_tmp.sh`（**永久侧门 K**，任务 #126 新立） | `6408a6b6f32d73367fa8e458a8ee249b` | 24 形（正例 14 + 负例 10）；本单引用其 `k_case_semi*`/`k_default_semi`/`k_default_first` 五 + 一枚形 |
| `fuzzy_scripts_720/tmp/c010_brace_switch_tmp.tsv`（门 K 注册读数） | `b3eb6e913edbc774a8b95a3fe61f0613` | `C010K_DONE shapes=24 same=8 over_accept=4 diff_php_ok=1 both_reject=6 aot_only_red=5 run_red=0 repo_build_residue=0 SMOKE_ONLY=0`，`ELAPSED=42s`（= 1.8 s/形） |
| `fuzzy_scripts_720/tmp/c010k_presnap/c010_brace_switch_gen1_tmp.tsv`（首轮快照） | `6f4e9f8b2d119b8cb5c08f694cfbca7a` | 与注册表仅 `ELAPSED` 行不同 ⇒ 跨 run `diff_rows=0` |
| `fuzzy_scripts_720/tmp/c010k_brace_switch_corpus_scan_tmp.php` / `.txt`（语料扫描器 ①） | `d7a2ccdc0a3002cacfe0d7c0cd858a04` / `a999224aba026cd5bf6096cf31d3e639` | 头型 / 首 `case` 前语句位（面孔 A 用，本单引其 switch 总面计数） |
| `fuzzy_scripts_720/tmp/c010k_case_order_terminator_scan_tmp.php` / `.txt`（语料扫描器 ②，**v2**） | `83247654ada70c9b587181869753af66` / `653fc553cf255214fc0f50254ad2d628` | 面孔 B 的 `semi_arm` 与面孔 C 的 `nonlast_default` 两个维度；v1 读数全废（见 §4） |
| `fuzzy_scripts_720/tmp/c010km_crossmode_probe_tmp.sh` / `.txt`（**跨模式探针门，本轮新立**） | `973996ef88c6db340871dc9402682c42` / `52f32f9d0d71bf350e522f1b89ac8b5b` | 6 形 × **php / tree / bytecode / AOT** 四侧实测，`ELAPSED=13s`／14s（= 约 2.3 s/形，每形一次 AOT 编译 + 两次 VM 执行）；路径归一后跨 run `diff_rows=0` |

> 📦 **本单全部资产未提交**（未获「提交」二字）；与 CODEGEN-010 的 R-3 批资产、门 K 资产同批待指令。

> ⚠ **【2026-10-09 任务 #127 代次更正：三条引用面已变，引用本单前必读】**
> **① parser 锚点漂移**：面 A（= CODEGEN-010 路线 R-5）已落地，`parseSwitch` 中部插入 17 行 ⇒ 本单全文的 `parser.zig:3571`/`:3583`（R-B1 两处硬 `eat(.colon)`）与 `:3616`（面 C 的 `.switch_stmt` 构造点）**当代次实测为 `:3580` / `:3592` / `:3633`**；完整漂移表见 [CODEGEN-010 §3.8.6](AOT-CODEGEN-010-keyword-case-insensitive-lexer.md)。⇒ `ast.zig:186`、`ir_generator.zig:3211-3221`/`:3236-3237`、`vm.zig:10146-10205`、`generator.zig:655-720+` **四枚锚点未受影响**（R-5 零触碰发射侧与 VM 侧，实测：`lexer.zig`/`keyword_lookup.zig` md5 与 `0652130` 逐枚全等）。
> **② 门 K 读数表已被就地覆盖**：门 K **脚本未变**（`6408a6b6…`），但本单上表引用的注册读数（`over_accept=4 … aot_only_red=5` @`42s`，表 md5 `b3eb6e91…`）已由 R-5 验收链的复跑**写回同一路径** ⇒ 该注册表现保存在 `fuzzy_scripts_720/tmp/c010_r5_presnap/c010_brace_switch_tmp.tsv`（**与注册 md5 逐字节全等**，实测）；工作树活动表 `c010_brace_switch_tmp.tsv` 代次为 `compiler_md5=6939cd2e…`／`parser_md5=1eab26c0…`、表 md5 `60cbac5a…`、`over_accept=0 both_reject=10 aot_only_red=5` @`31s`。⇒ **复测本单时读到 `over_accept=0` 属正常**（面 A 已收口）；**`aot_only_red` 必须仍为 5**，它是本单面 B 未修的现役证据 ⇒ 若该列变 0，说明面 B 已被某批顺带动到，必须回读本单并更正 §3/§5。
> **③ 门号冲突已消解**：本单 §5 原拟「把面 C 六形固化为**永久门 L**」，但**门 L 已被 CODEGEN-010 任务 #127 占用**（`switch` 臂表位邻形 23 形，`c010l_switch_armslot_*`）⇒ **本单拟建门改名「永久门 M」**（形集不变）。门 L 与门 M 的覆盖面**互不重叠**：L 盯「臂表位的接受/拒绝边界」（面 A），M 盯「`default` 臂序语义」（面 C）⇒ 建 M 时不得复用 L 的脚本或表路径。

---

## 1. 测法与判读口径

1. **真值源** = `/opt/homebrew/bin/php`（PHP 8.5.8），**判据源** = `zig-out/bin/php-interpreter`（AOT 产物 / `--mode=tree` / `--mode=bytecode`）。
2. **五桶契约**（承 CODEGEN-010 §3.5.1 任务 #125 定稿）：`SAME_BOTH_ERROR_LIKE` / `OVER_ACCEPT` / `DIFF_PHP_OK_AOT_DIFF` / `BOTH_REJECT`（= 收敛，PHP 也拒）/ `AOT_ONLY_RED_COMPILE` + `AOT_ONLY_RED_RUN`（= 硬守卫，须 0）。**「AOT 拒 ≠ 红」** —— 只有「PHP 通过而 AOT 拒」才是红。
3. **编译失败判据取「产物不可执行」，不取 rc**（记忆规则 21：`--compile` 解析失败仍 rc=0 且无产物）。
4. **`--compile` 必须仓库根**（越界 cwd 报 `executable generation failed: FileNotFound`）—— 本轮面孔 C 的补充六形**首跑即在 `/tmp` 下执行，六形全部假报 `compile_fail`，读数作废**，仓库根复跑后才得真值。
5. 多行输出以字面量 `\n`（门 K）或 `~`（跨模式探针）连接，**禁止** `tr '\n' '|'`（与列分隔符冲突 ⇒ 撑破列契约）。
6. 全部命令带 `timeout`；产物名 `aot_compile_*`；探针 `.php` 写在 `mktemp -d` 目录并随 `trap` 删除；**语料 `.php` 源零删除**（宪法 §七-9）；`repo_build_residue=0` 实测。

---

## 2. 实测

### 2.1 面孔 B：PHP 合法的 `case`/`default` **分号终结符**被 AOT 假拒绝（门 K，5 形 `AOT_ONLY_RED_COMPILE`）

| 形（门 K id） | 源码 | PHP 真值 | AOT 实测 |
|---|---|---|---|
| `k_case_semi` | `switch (1) { case 1; echo "S"; }` | rc=0，`Deprecated: Case statements followed by a semicolon (;) are deprecated, use a colon (:) instead` ×2 行 + **`S`** | **无产物**：`Parse error: syntax error, unexpected ";", expecting ":"` |
| `k_case_semi_fall` | `switch (1) { case 1; case 2; echo "T"; }` | rc=0，Deprecated ×4 行 + **`T`** | 同上 |
| `k_default_semi` | `switch (1) { default; echo "D"; }` | rc=0，Deprecated ×2 行 + **`D`** | 同上 |
| `k_case_semi_alt` | `switch (1): case 1; echo "Q"; endswitch;` | rc=0，Deprecated ×2 行 + **`Q`** | 同上 ⇒ **与花括号/替代语法无关**（两支共用同一 `eat(.colon)`） |
| `k_case_semi_two_arms` | `switch (1) { case 1; case 2; echo "b"; }` 双臂版 | rc=0，Deprecated ×4 行 + **`b`** | 同上 |

⇒ 门 K 的硬守卫列 `aot_only_red=5` **非 0** ⇒ **门 K 自建成起即为「验收门」而非「守卫门」**，引用时禁止把该列读成新增回归（同 §3 口径已登记于 CODEGEN-010 §7-9）。
⇒ **PHP 8.5 仍接受该写法**（仅 Deprecated）⇒ 按宪法 §七-8「PHP 语法已支持的特性 → 禁止简化」，**禁止以改脚本绕过**。

### 2.2 面孔 C：`default` 臂源码位次丢失（AOT 侧，门 K 1 形 + 补充 6 形）

分界实测 = **「`default` 是否位于末臂」**（与花括号／替代语法无关）：

| 形 | 源码 | PHP | AOT | 判读 |
|---|---|---|---|---|
| `k_default_first` | `switch (1) { default: echo "D"; case 2: echo "C"; }` | `DC` | `D` | **丢臂尾**：default 体尾不落进后续 case |
| `c_lastcase_fall_into_default` | `switch (2) { default: echo "D"; case 2: echo "C"; }` | `C` | **`CD`** | ★ **假执行**：末位 case 的体尾错落进 default ⇒ 执行了 PHP 不执行的语句（比丢输出更重） |
| `c_middle_default` | `switch (1) { case 1: echo "a"; default: echo "d"; case 2: echo "b"; }` | `adb` | `abd` | default 被搬到**末臂位** ⇒ 臂序丢失的直接证据 |
| `switch (9) { case 1: "a"; default: "d"; case 2: "b"; }` | — | `db` | `d` | 未匹配走 default 后同样丢后续臂 |
| `c_ctl_default_last`（**控制臂**） | `switch (1) { case 1: "a"; case 2: "b"; default: "d"; }` | `abd` | `abd` | **AOT SAME** ⇒ 68 语料恰只有这一种形态（§4） |
| `switch (0) { case 1: "a"; default: "d"; case 2: "b"; case 3: "c"; }` | — | `dbc` | `d` | 多臂同形复现，非单臂特例 |

### 2.3 跨模式实测（**本轮新立探针门 `C010KM`**，6 形 × php/tree/bytecode/AOT，`ELAPSED=13s`）

| 形 | PHP 真值 | `--mode=tree` | `--mode=bytecode` | AOT | 三模式关系 |
|---|---|---|---|---|---|
| `b_case_semi` | rc=0，Deprecated + `S` | **rc=0 空输出**（无 Deprecated、无 `S`） | **rc=0 空输出** | **compile_fail**（有 `Parse error` 日志） | ★ 三侧**三种不同结局**；且 VM 两侧是**连错误都不打的静默假绿**（原始输出仅性能统计段，`Function calls: 0`／`Execution time: 0ns` ⇒ 语句从未执行） |
| `b_default_semi` | rc=0，Deprecated + `D` | rc=0 空输出 | rc=0 空输出 | compile_fail | 同上 |
| `c_default_first` | `DC` | `D` | `D` | `D` | **三模式同一错答** ⇒ 根在 AST 层（§3.2），不是发射侧 |
| `c_lastcase_fall_into_default` | `C` | **`C`（唯一正确）** | `CD` | `CD` | tree 因「default 只在未匹配时执行」恰好躲过假执行；bc/AOT 同错 |
| `c_middle_default` | `adb` | **`ab`**（丢 `d`） | `abd` | `abd` | ★ **三模式三种不同错答**（`ab`／`abd`／`adb` 真值） |
| `c_ctl_default_last`（控制臂） | `abd` | **`ab`（丢 `d`）** | `abd` | `abd` | ★★ **控制臂在 tree 模式为红** ⇒ 解释器模式**连「default 在末臂的正常 fall-through into default」都不实现**；bc/AOT 与 PHP 等值 ⇒ 冻结基线绿恰好只覆盖 AOT/bc 侧 |

⇒ 三条判读：
1. **面孔 B 的修复落在共享前端**（`parser.zig`）⇒ 任何直接修法都会同时改变 tree/bytecode 的行为（从「静默空输出」变成「真的执行」）⇒ **宪法 §五/§六 必须先问**（裁决项 D-1）。
2. **面孔 C 的「三模式三样错」证明根不在发射侧**，而在 `ast.zig:186` 的形态缺字段；AOT 侧只需 `ir_generator` 消费新字段 ⇒ **可做到 AOT-only**（裁决项 D-2：AST 加字段是三模式共享的**结构改动**，但其余两模式**不读该字段即行为不变**）。
3. **副产品（新流程面，非本单面孔）**：`--mode=tree`/`--mode=bytecode` **对解析失败静默吞掉**（rc=0、零输出、无错误行），比 AOT 更危险（AOT 至少写 `Error: Parse error…` 到编译日志）。已实测两形（分号臂 + 缺 `}` 的 `if`）均如此 ⇒ 属**其他模式**的问题，按 §五 **本轮只登记不修**（§7-1）。

---

## 3. 机制锚点（实文核对，只读；行号为 `parser.zig 5ad452fe…` / `ir_generator.zig 96377ae7…` 代次）

### 3.1 面孔 B —— 两处硬只认冒号

```zig
// src/compiler/parser.zig:3568-3571（case 臂）〔当代次实测 :3577-3580，R-5 后 +9〕
if (self.curr.tag == .k_case) {
    self.nextToken();
    const case_expr = try self.parseExpression(0);
    _ = try self.eat(.colon); // or .fat_arrow
// src/compiler/parser.zig:3581-3583（default 臂）〔当代次实测 :3590-3592〕
} else if (self.curr.tag == .k_default) {
    self.nextToken();
    _ = try self.eat(.colon); // or .fat_arrow
```

- `eat` = 硬匹配（失配即 `Parse error`）⇒ 分号终结符在**两处**同病，替代语法支共用 ⇒ 实测「与头型无关」。
- ★ **注释声称的合法面实测方向相反**：`// or .fat_arrow` 描述的 `case 1 => echo …` 在 PHP 自己就 **rc=255**（门 K `k_case_arrow` 判 `BOTH_REJECT`，AOT 消息 `unexpected "=>", expecting ":"`）⇒ 注释既**不成立**又**误导**（真实合法的 `;` 反被拒）。⇒ 属源码注释失效锚点，改动需 §六 点头（宪法 §四-2 语义）。
- 体扫描（`:3573`/`:3585`，当代次 `:3582`/`:3594`）以 `.k_case`/`.k_default`/`end_token`/`eof` 为界 ⇒ **接受 `;` 后无需改体扫描**（`;` 由臂体自己的 `parseStatement` 正常消耗）⇒ 实测改动面可锁在**两行**。**★但该「两行」结论只覆盖臂终止符位**：R-5 已实测证明**臂表位**（`case` 前）另有「单枚空语句分号合法」的文法（CODEGEN-010 §3.8.1）⇒ 两处的 `;` 语义**不同位不同规**，R-B1 落地时必须以**门 N**（臂终止符位守卫门）先注册真值，禁止把门 L 的读数当成本位的判据。

### 3.2 面孔 C —— 位次在 AST 层就不存在，三模式各自重排

```zig
// src/compiler/ast.zig:186
switch_stmt: struct { expression: Index, cases: []const Index, default: ?Index },
// src/compiler/parser.zig:3616（全树唯一构造点）〔当代次实测 :3633，R-5 后 +17〕
return self.createNode(.{ .tag = .switch_stmt, … .data = .{ .switch_stmt =
    .{ .expression = expr, .cases = cases_slice, .default = default_case } } });
```

⇒ `default_case` 是**单个可空槽**，不记在 `cases` 序列里的位置 ⇒ 任何下游要还原源码序都必须**新增信息**，不是重排能解决。

三个消费侧的实测行为（读取点全树仅三处：`ir_generator.zig:3094`、`vm.zig:7650`、`bytecode/generator.zig:658`）：

| 模式 | 站点 | 机制（实文） | 对应 §2.3 读数 |
|---|---|---|---|
| **AOT/IR** | `ir_generator.zig:3100-3106` 建 `switch.merge`／`switch.default`；`:3112-3117` 按 `cases` 建块；`:3211-3221` 臂尾链 `case_blocks.items[i + 1]`，**末臂才** `:3215-3217` 接 `default_block`；`:3236-3237` default 体尾**恒 `br merge_block`**；派发侧 `:3156-3183` 比较链的末个 `else_block` 亦 = `default_block`（`:3177`） | default 被**强制搬到链尾** | `D`／`CD`／`abd` |
| **tree（解释器）** | `vm.zig:10154-10183` 顺序扫 `cases`，`matched` 后**持续执行后续臂体**；`:10186` 的 default 支条件是 **`if (!matched and default != null)`** | default **只在完全未匹配时**执行 ⇒ **永不 fall-through 进 default**（连控制臂都丢） | `D`／`C`（侥幸）／`ab`／`ab` ★ |
| **bytecode** | `generator.zig:672-697` 先为全部 `cases` 发标签、比较链末端 `jmp default_label`；`:700-720+` 按 `cases` 序发体、无 break 则 fall through 到下一个 case | 与 AOT 同型（default 恒在链尾） | `D`／`CD`／`abd` |

⇒ **面孔 C 的修复面 = 三处**（AST 形态 + 各模式消费侧），但 **AOT-only 路线可只动 `ir_generator`**（新字段其余模式不读）。

---

## 4. 语料面与风险（两枚独立分词器扫描器互证，`token_get_all` 口径，判据 3/4）

| 语料 | 文件 | `switch` 总数 | 花括号头 | 替代语法头 | `default` 非末臂（面 C） | `case`/`default` 分号臂（面 B） | 冒号臂（对照） |
|---|---|---|---|---|---|---|---|
| `fuzzy_scripts_720/pass/`（冻结基线） | 68 | 4 | 4 | 0 | **0** | **0** | 20 |
| `fuzzy_scripts_720/fail_runtime/` | 77 | 1 | 1 | 0 | 0 | 0 | 4 |
| `fuzzy_scripts_720/fail_compile/` | 12 | 0 | 0 | 0 | 0 | 0 | 0 |
| `fuzzy_scripts/`（旧语料，非基线） | 42 | 0 | 0 | 0 | 0 | 0 | 0 |
| `fuzzy_scripts_715/` | 50 | 2 | 2 | 0 | 0 | 0 | 13 |
| **GRAND** | 249 | **7** | **7** | **0** | **0** | **0** | **37** |

- 基线 4 枚花括号 `switch` 站点逐处回文核对：`pass/f048:118`（default **末臂**）、`pass/f134:94`、`pass/f134:160`、`pass/f163:133`（三枚**无 default**）；另 `fail_runtime/f082:98`（无 default）。⇒ **AOT 侧全部与 PHP 等值**（= §2.2 控制臂形态）⇒ **两张面孔的「语料内」暴露面均为 0，冻结基线对本单零保护力**。
- **「机制可达」= 完全可达**：写一个 `default` 不在末尾的 `switch` 即命中面 C；用 `case 1;` 即命中面 B。
- **§2.3 的新风险面（本单唯一「语料非 0」的观察）**：**解释器模式对控制臂也是错的**（`tree=ab` vs PHP `abd`）⇒ 语料里凡「case 无 break、直落 default」的写法在 VM 侧会丢输出。基线该形态实测为 **0**（4 枚 switch 的臂尾均有 break 或 default 末臂且语料只跑 AOT）⇒ 判据 4 仍成立，但**修复面 C 时若只改 AOT，VM 侧的这张更红的面孔会被留下** ⇒ 需 §五 明示（D-1/D-3）。
- **扫描器修记录（先修 scanner、后引用；v1 读数全废，禁止引用）**：扫描器 ② v1 把**全树** `T_CASE`/`T_DEFAULT` 一律当 switch 臂、边界只认 `:`/`;` ⇒ `semi_terminator=87` **全为假阳性**（enum `case Hearts = 'v';`／`case Hearts;`、match `default => …`）。v2 = 先算 switch/enum 的 token 区间、只在 switch 区间内分类，终止集扩 `:` `;` `=` `=>` `,`，臂序列按花括号深度取本层。v1→v2 同输入合成控制：`switch=10 / brace=8` 两代全等、`semi_arm 6→6`、`nonlast_default 4→3`（差的一枚正是修掉的过计）⇒ 修 scanner 只收窄假阳性。**已知低估边界（明示）**：v2 以花括号深度为界 ⇒ 替代语法体内嵌套花括号 switch、以及 `case 1: { … }` 带花括号臂体内的臂不计入外层（二者语料面均 0）。
- 破坏面评估：面 B 的两行改动位于**共享前端** ⇒ 触发三模式行为变化（见 D-1）；面 C 的 AST 加字段是**结构改动**但可做到其余两模式不读 ⇒ 若采甲路线（只改 AOT）预期**冻结基线 68 语料发射中性**（4 枚 switch 全为控制臂形态，default 末臂或无 default ⇒ `default_slot` 恒等现语义），**该中性未影子实测**。

---

## 5. 修复路线（优先级 / 影响面 / 落地成本 —— 成本列一律标「实测」或「未实测」，禁列估算）

| 路线 | 内容 | 优先级 | 影响面 | 落地成本 |
|---|---|---|---|---|
| **R-B1** | `parser.zig:3571` + `:3583`（**当代次实测 `:3580` + `:3592`**，见页顶代次更正 ①）两处 `eat(.colon)` 改为「`.`colon` 或 `;` 二者取其一」（并同步更正 `// or .fat_arrow` 这句失效注释）⇒ 消 5 枚假拒绝。**★前置＝先建门 N**（臂终止符位的 PHP 真值注册门，承 CODEGEN-010 门 L 的做法；R-5 实测否证了「直接小改」口径，见 §7-7） | **P1** | 共享前端 ⇒ **tree/bytecode 同从「静默空输出」变「真执行」**（§2.3 ★）⇒ 需 D-1 裁决。<br>是否**同时发 PHP 风格的 Deprecated**：AOT 无警告发射位 ⇒ 属 P2 消息面（承 §3.6 的同类残差） | **实测**（门 K 42s／24 形 = 1.8 s/形，R-5 后代次复跑 31s = **1.3 s/形**；跨模式探针 13s／6 形）；验收链沿用 CODEGEN-010 §3.6 的 **六门 16m18s + 主回归 13m50s + 影子 26m25s = 56m33s**（实测值；R-5 批同构链 = **十门**口径，实测值随 CODEGEN-010 §3.8 登记）。面 B 语料面 0 ⇒ 影子预期零漂移，但**仍需实测** |
| **R-C1** | **AST 加位次字段**：`ast.zig:186` 的 `switch_stmt` 增 `default_slot: ?u32`（= default 应插在 `cases` 的第几个位置前，由 `parser.zig` 在收集 `cases` 时计数写入，唯一构造点 `:3616`／**当代次 `:3633`**）⇒ 其余模式不读该字段即**行为不变** | P1（面 C 前置） | 结构改动，但读取方**逐个 opt-in** ⇒ 与 D-2 分叉旗标同族；需先定形态（甲＝加字段；乙＝把 default 作为 `.default` 条目塞进 `cases` ⇒ **三处消费侧全被波及**，`vm.zig:10154`/`generator.zig:682`/`ir:3124` 都要处理 `.default` tag ⇒ 波及面大得多） | **未实测**（纯加字段＝一处写、零处读；成本待形态裁决后补） |
| **R-C2** | `ir_generator.zig` 按位次重排臂链：`:3211-3221` 的「下一臂」改为**按源码序**（default 参与链）、`:3236-3237` 的 default 体尾改为「有后继臂则链入，否则 merge」 | P1 | **仅 AOT**；`ir_generator.zig` 为宪法 §一 **超大文件**（9743 行）⇒ 改前必须 grep 既有模式、禁止凭推测写代码；派发侧 `:3156-3191`（比较链 / `.switch_` terminator 的 `.default`）**语义正确无需动**（未匹配 → default 与位次无关） | **未实测**（新增**永久门 M**（原名拟「门 L」，已被 CODEGEN-010 任务 #127 占用）待建；无既有验收链可直接套，因语料面 0 ⇒ 主回归/影子只能证「不破坏」，证明「修对了」必须靠门 M） |
| **R-C3** | （**需 §五 明示才做**）`vm.zig:10186` 的 `if (!matched …)` 改为按源码序 fall-through 进 default；`generator.zig:700-720+` 同型改造 | P2（非 AOT 侧） | 解释器/字节码模式的**更红的面孔**（控制臂实测已红，§2.3 ★★）⇒ 超出本单默认方向 | **未实测** |
| **R-M1** | VM 两模式**静默吞掉解析失败**（rc=0、零输出）是否改为可见报错 | P2（流程面） | 属其他模式；且官方若存在只看 rc 的 VM 门，会把「编译失败」读成「运行成功但无输出」（承 CODEGEN-010 §7-5 同族） | **未实测**；按 §五 本轮**不修** |

**门控声明**：本单全部改动落点均在**编译前端 / AST / IR**，属宪法 §六「有风险 / 涉及逻辑歧义 / 设计非 AOT 逻辑调整」⇒ **任一路线落地前均需老铁点头**；§五「默认仅 AOT」与面 B 的共享前端属性**天然冲突**（改 parser 必动三模式），故 **D-1 是本单第一个必答项**。

**待裁决问题（本单开张）**：
- **D-1（必答）**：面孔 B 走 **甲＝共享前端直改**（三模式同获正确行为，VM 的静默空输出面消失）还是 **乙＝旗标门控只改 AOT**（承 CODEGEN-010 D-2 先例，VM 维持现状）？
- **D-2**：面孔 C 的 AST 形态取 **甲＝加 `default_slot` 字段**（推荐，消费方 opt-in）还是 **乙＝default 塞进 `cases` 序列**（三处消费侧全改）？
- **D-3**：面 C 落地时是否**一并修 VM/bytecode**（§2.3 已实测它们各自更红／同红）？
- **D-4**：门 K 是否升格为**本单验收门**（当前为 CODEGEN-010 的资产），或另建**永久门 M** 专盯面 C 的六形＋控制臂（推荐后者：面 C 的补充形仍在 `/tmp` 一次性形里，未固化 ⇒ 无门即无回归保护）？（**2026-10-09 任务 #127 代次更正**：原拟名「门 L」已被 CODEGEN-010 占用 ⇒ 本单拟建门改名 **门 M**，另为 R-B1 预留 **门 N**，见页顶 ③ 与 §6）

---

## 6. 复测路径（体验流程）

```bash
cd /Users/wangjianjun/products/parser            # ★ --compile 必须仓库根，越界即假 compile_fail

# 永久侧门 K（面孔 A/B/C 共用资产，24 形，实测 42s = 1.8 s/形）
timeout 300 bash fuzzy_scripts_720/tmp/c010_brace_switch_gate_tmp.sh
# 注册读数：C010K_DONE shapes=24 same=8 over_accept=4 diff_php_ok=1 both_reject=6 aot_only_red=5 run_red=0 repo_build_residue=0
#   本单关注列：aot_only_red=5（面 B，落地后 →0）与 diff_php_ok=1（面 C 的 k_default_first，落地后 →0）
#   ★ 面 A 的 over_accept=4 归 CODEGEN-010 §7-15c（路线 R-5），不属本单

# 跨模式探针门 C010KM（6 形 × php/tree/bytecode/AOT，实测 13s）
timeout 300 bash fuzzy_scripts_720/tmp/c010km_crossmode_probe_tmp.sh > fuzzy_scripts_720/tmp/c010km_crossmode_probe_tmp.txt
# 判读：面 B 两形必须「php 有臂体输出 且 tree/bytecode/AOT 三侧同有该输出」才算收口；
#   面 C 的 c_ctl_default_last（控制臂）当前 tree=ab（红）⇒ 若只做 AOT-only（D-3 未点头），该行必须仍记为已知 VM 红面，
#   禁止把它当本单新增回归；跨 run 需先把 `/private/tmp/c010km.XXXXXX` 路径归一（`diff_rows=0` 已实测）

# 语料面复扫（两枚扫描器互证；GRAND 预期 switch=7 brace=7 nonlast_default=0 semi_arm=0 colon_arm=37）
timeout 90 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/c010k_brace_switch_corpus_scan_tmp.php fuzzy_scripts_720
timeout 90 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/c010k_case_order_terminator_scan_tmp.php fuzzy_scripts_720
#   ★ 一旦 nonlast_default / semi_arm 由 0 变 >0 ⇒ 语料新增了受面构造 ⇒ 本单从「零回归数据可依赖」升级为「有面可测」，
#     落地批必须先跑主回归再动代码

# 面 C 的六形目前仍是「一次性 `/tmp` 探针」形态（未固化为永久门）⇒ 复测需按 §2.2 表逐形手写：
#   每形一个文件、仓库根 `--compile --no-debug-info --output=/tmp/…/aot_compile_c*`、`timeout 120` 编译 + `timeout 10` 运行
```

**建议（落地批的前置，按「优先级 + 影响面 + 落地成本」三列）**

| 建议 | 优先级 | 影响面 | 落地成本 |
|---|---|---|---|
| 把 §2.2/§2.3 的面 C 六形固化为**永久门 M**（★原拟名「门 L」已被 CODEGEN-010 任务 #127 占用 ⇒ 改名，形集不变；含 `c_ctl_default_last` 控制臂，判据列 = `default 末臂 ⇒ 必须 SAME`） | **P0 前置**（无门则修复批「只能证明不破坏，不能证明修对了」） | 新增一个 `fuzzy_scripts_720/tmp/c011m_*` 脚本，零 `src/` | **实测可套用**：同族门的实测单价 = 门 K `1.8 s/形`、门 L 修复后 `1.4 s/形` ⇒ 6 形 ≈ **9–11s**（D-4 裁决后建） |
| ~~R-B1 与 CODEGEN-010 的 R-5（面 A 硬化）同批~~ **【前提已变，2026-10-09 任务 #127】**：R-5 已按「继续推进」授权**单独落地并验收**（旗标 `strict_switch_case_list`，AOT-only），⇒ 同批省一次链的理由不再成立 ⇒ 本行作废，改为下行 | — | — | — |
| **R-B1 落地前必须先建「PHP 合法面」守卫门**（= 承门 L 的做法：先把 `case expr;`／`default;` 与**邻位单枚分号**的 PHP 真值注册进表，再改 `:3580`/`:3592`）| **P0 前置**（R-5 实测否证了「一行」这类小改口径：门 L 的注册读数里 `l_semi_arm_list`/`l_semi_only`/`l_alt_semi_arm` 三枚**今日绿形**只因豁免支才没被砸红 ⇒ R-B1 触碰的是**同一处臂终止符判定**） | 零 `src/`；新增/复用门表 | **实测**：门 L 已含 `l_semi_*` 三枚臂表位分号形与 `switch (1) { case 1; }` 的**臂体位**分号形**不重叠** ⇒ R-B1 需自建门（暂名 **门 N**，避免与拟建门 M 撞号），预算 ≈ 门 L 的 33s／23 形 |
| 面 C 修复批**必须带发射期金丝雀**（`default_slot` 越界 ⇒ 编译期报错） | P1（防 §3.2 的「假执行」复发） | `ir_generator.zig` 单点断言 | **未实测**；先例承 CODEGEN-005/006 系列 |
| VM/bytecode 的 `tree=ab` 控制臂红面**单列一张工单**（不并入本单 AOT 批） | P2 | 属其他模式（§五） | **未实测** |

---

## 7. 遗留 / 待裁决 / 流程项

1. **VM 两模式静默吞解析失败**（§2.3 副产品）：`--mode=tree`／`--mode=bytecode` 对 `Parse error` **rc=0、零输出、无错误行**（实测两形：分号臂、缺 `}` 的 `if`；原始输出仅性能统计段，`Function calls: 0`）。⇒ 非 AOT 面 ⇒ 按 §五 **未修**，且若官方门任何一腿看 VM 的 rc，会把「编译失败」读成「绿」（承 CODEGEN-010 §7-5「`--compile` 解析失败仍 rc=0」同族，但 VM 侧**连日志都没有**，更危险）。
2. **面 C 的补充六形尚未进门**（D-4）：当前只有门 K 内的 1 形（`k_default_first`）受保护 ⇒ 修复批若无**门 M**（原拟名「门 L」已被 CODEGEN-010 占用），`c_lastcase_fall_into_default`（假执行面）**不受任何回归保护**。
3. **`// or .fat_arrow` 失效注释**（§3.1）：`parser.zig:3571`/`:3583` 两处（当代次实测 `:3580`/`:3592`，见本页顶部「任务 #127 代次更正 ①」）。删除或改写属「涉及删除代码 / 注释误导源」⇒ §六 点头；与 CODEGEN-010 §7-10 的死桩 `isKeywordUsableAsIdentifier` 同类处置（只登记）。
4. **Deprecated 消息面**：PHP 对该写法打 **Deprecated 两行**（`PHP Deprecated: …` + 裸 `Deprecated: …`）。AOT 无 deprecation 发射位 ⇒ 本单只保证「接受并执行」，消息等值列 **P2**（承 §3.6 的 P2 消息面残差口径）。
5. **PHP 8.5 是否永久保留该写法未验证**：实测真值取自本机 PHP 8.5.8；若上游未来移除分号终结符，R-B1 会退化为「AOT 比 PHP 宽容」⇒ 复测时先记 `php -l` 的 Deprecated 行为再判桶。
6. **本单资产全部未提交**：门 K 脚本/表/快照/两枚扫描器（与 CODEGEN-010 共享）、跨模式探针脚本/读数、本工单、以及 CODEGEN-010 的 §3.7 与 R-3 批资产 ⇒ 待「提交」二字（承 §7-9 D-7 口径，门数已含门 K ⇒ 官方门链问询范围 +1）。
7. **姊妹面 A 已落地，本单两面孔未受影响（2026-10-09 任务 #127 实测登记）**：CODEGEN-010 路线 R-5（花括号 `switch` 臂表位严格化，新旗标 `Parser.strict_switch_case_list`）已落地并验收 ⇒ **本单尚未落地的证据是实测的、不是声明的**：① 门 K 硬守卫列 `aot_only_red` **落地前后恒 = 5**（面 B 五枚假拒绝一字未变）；② 门 K 唯一 `DIFF_PHP_OK_AOT_DIFF`（面 C 的 `k_default_first`）在前后读数中**恒为 1** ⇒ 面 C 的臂序缺陷未被面 A 的改动掩盖；③ 门 L 的 23 形**不含**臂终止符位（`case expr;`）与 `default` 非末臂两族 ⇒ 对本单两面孔零覆盖面。**新前置（由 R-5 的否证推得，非推测）**：面 A 的落地形态是「旗标 + 单枚前导分号豁免」而非「一行」⇒ 同一函数内的臂终止符位（R-B1）**同样需要先注册 PHP 真值再改**（见 §6 建议表「门 N」行）；旗标面则**不外溢**：`strict_switch_case_list` 只在臂表位判定，`eat(.colon)` 两处不读该旗标 ⇒ R-B1 若选择旗标门控需**另立旗标**，与 D-1 裁决一并定形态。

---

## 8. 与 AOT-CODEGEN-010 的边界

| 面孔 | 归属 | 判据 |
|---|---|---|
| A：花括号 `switch` 首 `case` 前的裸语句被静默跳过（4 枚 `OVER_ACCEPT`） | **CODEGEN-010** §7-15c / 路线 R-5 | ~~`:3595` 去掉 `is_alternative and`~~ ⇒ **该形态被任务 #127 实测否证**；实际落地 = 旗标 `Parser.strict_switch_case_list`（`:38`/`:82`）+ 单枚前导分号豁免支（`:3601–3606`）+ 严格支（`:3612`），**已落地并验收**（CODEGEN-010 §3.8）。R-3 批（`Parser.strict_alt_closers`）的姊妹面，同源于旗标引入时的**故意保守** |
| B：`case expr;`／`default;` 假拒绝（5 枚 `AOT_ONLY_RED_COMPILE`） | **本单** R-B1 | `:3571`/`:3583`（当代次 `:3580`/`:3592`）的硬 `eat(.colon)`，与旗标、与关键字大小写**均无关**；★ 与面 A 的「臂表位单枚分号」**同函数不同文法位** ⇒ 落地前需自建门 N（§7-7） |
| C：`default` 臂位次丢失（1 枚 `DIFF` + 5 枚补充实测） | **本单** R-C1/R-C2（+ R-C3 待 §五） | 根在 `ast.zig:186` 形态缺字段，三模式各自重排 ⇒ 与 `parser.zig` 文法位不同层 |
