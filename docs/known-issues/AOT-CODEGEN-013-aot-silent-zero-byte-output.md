# AOT-CODEGEN-013 · elseif 合取 + else 臂 return ⇒ 生成码语句序倒置，Zig 判 `unreachable code`，合法 PHP 在 AOT 编译失败（并残留 0 字节 +x 产物）

**问题 ID**: AOT-CODEGEN-013
**优先级**: **P0**（**合法 PHP 直接编译失败**，且失败形态会伪装成「运行了但没输出」——见 §5 判据陷阱）
**性质**: **仅 AOT 发射侧**（`native_linker.zig` 生成码语句序；解释器/字节码模式不经此路径）
**状态**: **OPEN（2026-10-12 R-138 后续轮立案；最小复现已到手，永久侧门 Q 已建成并登记基线；未动一字节源码）**
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
