# AOT-CODEGEN-013 · elseif 合取 + else 臂 return ⇒ 生成码语句序倒置，Zig 判 `unreachable code`，合法 PHP 在 AOT 编译失败（并残留 0 字节 +x 产物）

**问题 ID**: AOT-CODEGEN-013
**优先级**: **P0**（**合法 PHP 直接编译失败**，且失败形态会伪装成「运行了但没输出」——见 §5 判据陷阱）
**性质**: **仅 AOT 发射侧**（`native_linker.zig` 生成码语句序；解释器/字节码模式不经此路径）
**状态**: **R-A / R-C 已落地并全链验收（2026-10-12），F-9 同批已落地（§9：四处「打印 Fatal 后继续」落点改为可捕获 Error，门 R 9 形 `same=8 diff=1`、未捕获面 rc=0→255、主回归 Fail_* 0）**；F-8 / F-10 登记待裁决 ⇒ **F-8 已拆半：F-8a `isDefaultValueAvailable()`/`isOptional()` 由 R-141 落地（恒 SAME），现仅 F-8b `getDefaultValue()` 为 f170 最后阻塞点（待设计分叉，见 012 §14.4）**。详见 §7–§9。
**发现日期**: 2026-10-12（由交接 §4.2「f170 新面孔」的归因轮产出）
**触发档**: 默认档（`--compile --no-debug-info`，实测 `-OReleaseFast` 与 `-OReleaseSmall` 同现）

> 文件名 `aot-silent-zero-byte-output` 沿用自本单被推翻的旧论断（见下方自纠块）；实际缺陷以标题为准。重命名会断掉变更文档/门 Q 里的引用，**待老铁点头再改**。

> ⚠️ **本单前身论断已被推翻（自纠）**：本会话早前我在 f170 上读出「AOT 产物 rc=0 且 stdout/stderr 零字节」，并据此立了一整页「静默全量输出丢失」假设（入口 `return err` 吞异常等）。**该论断是错的**：f170 根本没跑起来——`--compile` rc=1、编译失败、但**残留了一个 0 字节且带 +x 位的产物**，我用 `-x` 判据把它当成"产物存在"执行了。这正是我当日刚写进规则的判据陷阱（`-x` 必须搭配 `-s`），我自己踩了。原假设全部作废，真身以本文为准。

## 1. 真身：三条件同时成立即编译失败（逐条件实测收缩）

```
① if/elseif/else 链中存在 **elseif，且其条件为 `&&` 合取**
② **else 臂以 `return` 结束**
③ **if-chain 之后仍有语句**
```

| 探针 | 形态 | 结果 |
|---|---|---|
| q1 | 三条件齐备（合取用 `strlen($c) > 0`） | **COMPILE_FAIL** `main.zig:287:20: error: unreachable code` |
| q2 | 三条件齐备（合取用 `class_exists($c)`，方法内 + 属性/局部写） | **COMPILE_FAIL** `main.zig:298:20: error: unreachable code` |
| c1 | 去 ① 的合取（`elseif (is_string($c))`） | OK，AOT == PHP |
| c2 | 去 elseif（合取放进无 elseif 的 `if`） | OK，AOT == PHP |
| c3 | 去 ②（else 臂改为赋值而非 return） | OK，AOT == PHP |

⇒ 合取里的具体函数无关（`strlen` / `class_exists` 均触发）；属性写 vs 局部写无关。

## 2. 机制：发射到 `return` 之后的语句

q2/f170 生成码实测（`KEEP_TEMP` 副本）：

```zig
// Generated main.zig（f170 副本，:2759-2761；映射 PHP 源码 :58 与 :61）
    reg_36.release(runtime.runtime_allocator);
return if (false and reg_61.isNull()) reg_61 else runtime.php_coerce_value(reg_61, "mixed", …);  // ← else 臂的 return $concrete
    reg_88 = reg_67;        // ← if-chain 之后的语句（PHP :58 的 $this->instances[$id] = $object）
    _ = reg_88.retain();
```

两点事实：

1. **语句序倒置**：else 臂的 `return` 被发射在其**后继语句之前**，Zig 遂判其后语句 `unreachable code` ⇒ `CompilationFailed`。链上 `false and reg_61.isNull()` 为折出来的恒假可空判定，与本缺陷非因（r11/c2 同样有合取却不失败，说明触发者是 elseif+else-return 的块合并路径）。
2. 该形态与 **CODEGEN-008「echo 臂尾并入隐式 else」** 同属 if-chain 臂尾合并族（臂尾以 `return` 结束时，merge 块的后继语句被排到臂尾之后）——修复宜与 008 对齐判定，勿单点补丁。

## 3. 语料面与覆盖影响

| 面 | 实测 |
|---|---|
| `pass/` 68 语料 | 全绿（`Pass 67 / Skip 1 / Fail(Compile)=0`）⇒ 通过集内无此形态；官方 harness 判 `compile_exit != 0`（`run_regression.sh:56`）⇒ **harness 不受 §5 陷阱污染**，历史读数可信 |
| `fail_runtime/f170_dependency_injection_container.php` | **现役受害者**：`make()` 的 `elseif (is_string($concrete) && class_exists($concrete))` + `else { return $concrete; }` + 其后 `:58/:61` ⇒ 一直编译失败。此前被归入 `fail_runtime`（运行期失败）实为**分类错误**，应属 `fail_compile` |
| `fuzzy_scripts_720/f130_…php` | 不受本缺陷影响（其阻塞为 `debug_backtrace()`，见 012 §12.5-F-6） |

⇒ 修复后 f170 能否回收仍存疑：解释器模式另有 `Class 'LoggerInterface' not found`（PHP 可解析，AOT 侧未注册该接口），属独立面孔（老铁已裁决解释器面登记不动，AOT 侧待归因）。

## 4. 修复路线（待老铁点头，未动源码）

| 路线 | 内容 | 影响面 | 成本 |
|---|---|---|---|
| R-A | 发射侧：臂尾以 `return` 结束时，**不得把 merge 块后继语句排到其后**（改为归入 merge 块或按臂尾终止符路由），与 CODEGEN-008 的臂尾判定同源 | `native_linker` if-chain 渲染主干 | 中；须门 Q + 影子 + 主回归全套 |
| R-B | 先做**普查**：扫全语料 `elseif (… && …)` + `else { return` 形态命中数，判断这是 f170 孤例还是族 | 只读 | 1 轮 ≈10 分钟 |
| R-C | 修 `--compile` 失败残留 0 字节 +x 产物（失败即删产物） | 工具链健壮性 | 小；与本单修复解耦，可先行 |

## 5. 判据陷阱（本单的元教训，已并入记忆规则 22）

```bash
# 错：编译失败时产物为 0 字节但仍带 +x 位 ⇒ 被当成"运行成功、无输出"
[ -x "$P" ] && timeout 10 "$P"
# 对：
[ -x "$P" ] && [ -s "$P" ] && timeout 10 "$P"
```

配套证据：`--compile` 失败打印 `Error: Compilation failed with 2 errors` / `error: CompilationFailed` 且 **产物 size=0、mode=-rwxr-xr-x**；`run_regression.sh` 用 rc 判据故无此问题，但仓库内多枚门脚本历史上用 `-x` 单判 ⇒ 任何 `diff=N` 且 `ELAPSED≈5s/形` 的读数应先怀疑判据而非编译器。门 Q 与新修正的门 P 均已按 `-x && -s` 落地。

## 6. 资产

- 永久侧门 Q：`fuzzy_scripts_720/tmp/c013_elseif_conj_gate_tmp.sh`，读数 `c013_elseif_conj_tmp.tsv`，成本 ≈90s。
- **基线读数（修复前，2026-10-12）**：`C013Q_DONE shapes=5 expect_fail=2 unexpected_fail=0 same=3 unexpected_ok=0 bad_probe=0 residue=0`
- 判据：`expect_fail=2` 且 `unexpected_fail=0`；R-A 落地后应转 `expect_fail=0`（并把 q1/q2 并入 SAME 桶）。

### 6.1 代次与资产登记（R-A/R-C 落地后，2026-10-12 22:0x 实测）

| 项 | md5 |
|---|---|
| `src/aot/native_linker.zig` | `d91e22c4995f9fb7b9fbef23e900a02f` |
| `src/aot/runtime_lib_template.zig` | `070ca44561fa7f83c651868a41f71a03` |
| `zig-out/bin/php-interpreter`（**冷编译后代次**，见下注） | `d1443020e764e3b5097e82b8f76e8528` |
| 门 Q `c013_elseif_conj_gate_tmp.sh` | `895f28c5b2e1fb42c032f10a77aecd2f` |
| 普查门 B `builtin_map_dupkey_census_tmp.sh` | `e9389e2e169779b2df870e3f4f811568` |
| 门 P `c012_reflection_gate_tmp.sh` | 登记值 `e275bada301d9118b9bd915f89147f49`（39 形代次，见 012 §16.3）——**上表原写 `2da21310…` 属自相矛盾**：同一张表已把 `runtime_lib_template.zig` 记为 `070ca445…`（35 形代次），而 `2da21310…` 是该代次的门 P 脚本，两者本可共存；此处保留两代值并注明适用读数 |
| 影子门 `c010_shadow_main_md5_tmp.sh`（已加 invalid 桶 ⇒ 旧登记 `cb818314…` 作废） | `d69e5587ecd4a8bc3a65b74434553592` |

**上表为 R-139 代次快照，三行已漂移**（`git status --porcelain -- src/` 2026-10-13 01:37 实测 `native_linker.zig`/`runtime_lib_template.zig` 仍为 M）：现行 `runtime_lib_template.zig` = `4a9a3b22251e1a66ec86c3a562ce9a7c`、二进制 = `d3079f71fad7007a9b023b8eafb46b06`、门 P 脚本 = `e275bada301d9118b9bd915f89147f49`（39 形 / `same=34 diff=5`，注册红 `n15 r10 v2 i1 i2`）⇒ 三门中 **Q/B/影子 md5 未变**，其读数仍可按上表引用；门 P 与模板/二进制代次**必须取现行值**，不得再引用上表 `2da21310…`/`070ca445…`/`d1443020…` 做等价捷径。

⚠️ **二进制 md5 不可跨冷编译引用**：`.zig-cache`（曾膨胀至 ~153 GB，`z/` 6.5 万条目）被清空后重编译，源码未变而 md5 由 `f8f2a66d…` 变为 `d1443020…` ⇒ 判代次优先用两枚源码 md5，二进制 md5 只在同代次内有效。影子腿在磁盘满那一轮曾产出 4 枚假 SAME（两侧同为 `NOT_EXECUTABLE`），invalid 桶加入后复跑为 `same=0 diff=68 miss=0 invalid=0`。

## 7. R-A / R-C 落地与验收（2026-10-12，本单已 CLOSED 到「发射缺陷」这一层）

| 项 | 内容 | 位置 |
|---|---|---|
| **R-A** | else 臂尾 PHI 物化加守卫：`!self.return_generated and !self.break_generated` | `native_linker.zig` 「PHI 消解（非 coalesce 情况）」站点（原 `:10727`）。**守卫口径取自本文件既有先例** `:17515` 同一函数的调用条件 ⇒ 非新造判据 |
| **R-C** | 新增 `deleteStaleProduct()`，在两处 `error.CompilationFailed` 返回前删除残留产物 | `native_linker.zig` `invokeZigCompiler` 尾部（沿用本文件 `getCwd().deleteFile(io, path) catch {}` 既有形态） |

**门 Q 终态（R-A 后，判据已升级为「五形全等值」）**：

```bash
C013Q_DONE shapes=5 expect_fail=0 unexpected_fail=0 same=5 unexpected_ok=0 bad_probe=0 residue=0 ELAPSED=22s
```

q1/q2（原编译失败形）现与 PHP 逐字节等值，三条控制臂 c1/c2/c3 保持等值 ⇒ **修复未越界**。

**R-C 的 A/B 实证**（用「临时 cwd + 故意损坏的模板副本」制造真实编译失败，未触碰仓库源码）：

| 二进制 | compile rc | 产物 |
|---|---|---|
| 修复前（前缀 `be305cfa`） | 1 | **残留 size=0、mode=-rwxr-xr-x**（正是本会话误判的根源） |
| 修复后 | 1 | **无该文件** ✅ |

**全链验收（二进制 `d1443020e764e3b5097e82b8f76e8528`，磁盘清理后冷编译重跑）**：门 M 19/19、D8 14/14、N 7/7、O 6/6、**门 P `same=31 diff=4`（恰为四枚注册红，无新增）**、门 Q `same=5`、普查门 B `diff_impl=3` 不变、`zig build test` 21/21 & 326/326、主回归 **Pass 67 / Skip 1 / Fail(Compile) 0 / Fail(Runtime) 0 / Fail(Diff) 0**；影子 `same=0 diff=68 miss=0 **invalid=0**`。

**f170 现状**：由「从未编译成功」变为 **compile_rc=0、产物 1,128,104 B、可运行**，输出 51 行 vs PHP 30 行 ⇒ 阻塞点后移，露出下面两枚。

## 8. 本单修复后暴露的两枚新面孔（登记，未修）
| # | 面孔 | 实测证据 | 归属建议 |
|---|---|---|---|
| F-8 | **`ReflectionParameter::isDefaultValueAvailable()` 未实现** | f170 运行期首条 fatal `Call to undefined method ReflectionParameter::isDefaultValueAvailable()` | 属 AOT-CODEGEN-012 Reflection 族（门 P 扩形覆盖） |
| F-9 | **未捕获 fatal 不终止执行**（★比本单原论断更危险的一枚） | 隔离探针 `class K {} (new K)->nopeMethod();`：PHP = `A` + Fatal + **rc=255**；AOT = `A` + Fatal + **`B` 仍执行** + **rc=0**，且 fatal 文本重复两次。f170 内共出现 **14 条** fatal 而脚本一路跑到底 | 独立成单（错误语义/出口协议族）——**它才是"输出丢失/多余"类误读的真上游**：rc=0 会让任何 CI 把致命错误当成通过 |

⇒ 本单 CLOSED 范围 = 「elseif 合取 + else 臂 return ⇒ unreachable code 编译失败」这一层（发射缺陷）。§5 判据陷阱与门 Q/影子 invalid 桶为流程资产，长期有效。

## 9. F-9 已落地（2026-10-12 同日第三批：致命错误终止语义）

**根因**：`php_object_call` 内四处「打印 Fatal 文本 / 返回静默 null」的落点既不设异常也不终止 ⇒ 后续语句照跑、进程 **rc=0**（f170 曾 7 次 fatal 跑到底）。PHP 真值：这些都是**可捕获 Error**，未捕获则 rc=255 中止。

| # | 站点（改后行号） | 改前 | 改后 |
|---|---|---|---|
| 1 | `runtime_lib_template.zig:20366` Closure 未知方法 | `fileWriteAll(2,"PHP Fatal error: …")` ×3 + `return initNull()` | `throwThrowable("Error", "Call to undefined method Closure::{m}()")` |
| 2 | `:20376` 非对象接收者 | 打印固定串 `Call to a member function on a non-object` + `return initNull()` | `"Call to a member function {m}() on {type}"`，类型词复用本文件 `phpArgTypeWord`（int/null/string/true/false…） |
| 3 | `:20386` `callMethod` 的 `error.MethodNotFound` | 打印 Fatal（缺 `in file:line` 与栈）+ `return initNull()` | `"Call to undefined method {class}::{m}()"` |
| 4 | `:20327` 字符串伪方法未命中 | `return error.UnknownMethod`（**全仓唯一产生点、零消费者** ⇒ 被 `catch initNull` 吞成静默 null） | `"Call to a member function {m}() on string"` |

口径依据：仓库既有先例 `:20081`（抽象类实例化 `return throwThrowable("Error", …)`），未新造机制。

**永久侧门 R**（`fuzzy_scripts_720/tmp/c013_fatal_term_gate_tmp.sh`，读数 `c013_fatal_term_gate_tmp.tsv`，9 形 39s）——**判据把 rc 计入载荷**，只比 stdout 无法区分「正确中止」与「打印后继续」：

```bash
C013R_DONE shapes=9 same=8 diff=1 terminate_lost=0 compile_fail=0 bad_probe=0 residue=0 ELAPSED=39s
```

| 形 | 内容 | 读数 |
|---|---|---|
| h1–h5 | 五形可捕获面（对象缺方法／int／null／Closure／string 接收者） | 全 SAME，消息与 PHP **逐字节等值** |
| t1–t3 | 未捕获面（含 t3「中止前已产出的输出必须保留」） | 全 SAME 且 **rc=255**（改前 AOT rc=0 且 `B`/`TAIL` 照打） |
| h6 | AOT 独有字符串伪方法面（`toUpper/trim/length`） | **唯一预期 DIFF**（PHP Fatal，AOT 返回字符串）⇒ 见 F-10 |

**建门自纠（登记为取证教训）**：首版门 R 九形全报 `BAD_PROBE_PHP_EMPTY`、整轮仅 1 秒——我的 `norm()` 函数体是 `sed …`（从 stdin 读）却按 `norm "$file"` 调用 ⇒ 参数被吞、恒空。⇒ **凡"全部形同时报同一种坏"且耗时远小于 `s/形` 基线的读数，先怀疑门自身**（与规则 22 同源）。

**全链复跑**（模板侧改动，二进制仍 `d1443020…` 未重建 ⇒ 影子按定义不变，上轮已取 `diff=68 invalid=0`，本轮跳过并说明理由）：门 M 19/19、D8 14/14、N 7/7、O 6/6、**门 P `same=31 diff=4`（四枚注册红未变）**、门 Q `same=5`、门 R `same=8 diff=1`、普查门 B `diff_impl=3`、`zig build test` 21/21 & 326/326、主回归 23:24:43 报表 **Total 68 / Pass 67 / Fail(Compile) 0 / Fail(Runtime) 0 / Fail(Diff) 0 / Skip 1** ⇒ 修复对语料**行为中性**。

**f170 现状**：改前 rc=0 / 51 行 / 7 次 fatal 跑到底；改后 **rc=255 / 14 行 / 1 次 fatal 即止**（PHP rc=0 / 30 行）⇒ 终止语义已 PHP 一致，当时剩余阻塞是 F-8。**代次更正（2026-10-13 01:37）**：F-8 已拆为两半 ⇒ `isDefaultValueAvailable()`/`isOptional()`（F-8a）由 R-141 落地并恒 SAME，**现仅剩 F-8b `getDefaultValue()`（门 P v2 注册红）为 f170 的最后一个阻塞点**；该轮门 P 读数 `same=31 diff=4`（35 形）已被现行 39 形 `same=34 diff=5` 取代，值见 012 §16.3 与本页 §6.1。

### 9.1 本批新增登记（未修）

| # | 面孔 | 实测 |
|---|---|---|
| F-8 | `ReflectionParameter::isDefaultValueAvailable()` 未实现 | f170 现首个致命即此；属 012 Reflection 族，宜扩门 P |
| F-10 | **AOT 独有的字符串伪方法面**（`$s->toUpper()/trim()/length()/replace()/split()/concat/…`）| 门 R h6：PHP = `Fatal Error: Call to a member function toUpper() on string`，AOT 返回 `"AB C"` ⇒ 与 PHP 语义相反的扩展面（本次刻意**未动命中路径**，只改未命中落点）。收与不收属产品决策，须老铁裁决 |
