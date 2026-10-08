# 持引用迭代（`foreach as &$v` / `array_walk &$val`）期间容器增长：迭代器结构悬垂导致 SIGSEGV + 元素集合语义与 PHP 不一致

**问题 ID**: AOT-REF-003
**优先级**: **P0（运行期段错误 rc=139，无栈无消息）** + P1（语义差：PHP 会访问迭代期间新增的元素，AOT 停在调用时集合）
**状态**: **OPEN（2026-09-30 立项取证完成；2026-10-03 只读代码复核补充 §7.1「IR 站点实测 + 锁协议」两节，原「α 只改 ref 路径」口径被实测推翻并拆为 α′/α″）** —— 本工单**仍未动任何源码**，落点与旁支待 §10 裁决
**发现日期**: 2026-09-30（AOT-REF-002 R-1b 判据缺口排查过程中实测暴露）
**归因**: **非 `b21cdfd`（REF-002 R-1a/R-1b）引入** —— 用 `git show b21cdfd^:src/aot/runtime_lib_template.zig` 换回修复前模板重编译同一批探针，崩溃与语义差逐项相同（见 §5）
**上游**: [AOT-REF-002](AOT-REF-002-iter-ref-slot-dangling.md) R-3（本文把它从「理论风险」升级为「实测崩溃」）；[AOT-REF-001](AOT-REF-001-container-ref-slot-dangling.md) D2

---

## 1. 一句话机理

AOT 的数组迭代器 `ArrayIterator` 在 init 时**按值捕获** `PHPArray.Elements.Iterator`（std `ArrayHashMapUnmanaged` 的迭代器，内部持有桶数组指针与桶内偏移），并且用 `current: ?Elements.Entry` **跨轮缓存** `key_ptr`/`value_ptr`。而 `Elements` 是 hash 布局，**插入新键会整体搬迁桶数组**，且搬迁位置不稳定（不同于 PHP `ArrayHash` 的「插入序 = 位置」）。于是迭代期间容器一旦增长：

- 下一轮 `iter.iter.next()` 在**已释放的旧桶数组**上推进 ⇒ **SIGSEGV**（`ref_lock_count` 只在 `PHPArray.release`（:2078）里延迟**释放**，管不住**搬迁**）；
- 即使侥幸没崩，`php_array_iter_key`/`php_array_iter_value_ref` 里的 `entry.key_ptr.*` 是野指针读；
- 且 AOT 停在调用时的元素集合，PHP 的持引用迭代会访问到新增元素。

## 2. 复现（永久探针，勿删）

```php
$a3 = mkb(5);                                  // ['k0'=>0, …, 'k4'=>4]
$v3 = 0;
foreach ($a3 as $key => &$ref) {               // 持引用迭代
    $v3++;
    if ($v3 === 1) {
        for ($j = 0; $j < 200; $j++) {
            $a3['g' . $j] = $j;                // 首轮向被遍历容器自身追加 200 键 ⇒ 强制桶搬迁
        }
    }
    if ($v3 > 400) { break; }                  // 兜底：防语义正确时无限推进（真值 visited=205 时不触发）
}
```

（与 `ref003_crash_min_tmp.php` 一致；该文件另有 `fwrite(STDERR, …)` 段落用于定位崩溃点，但 **AOT 产物在段错误时不落 stderr**，故标记实际不可见 —— 归因改由「探针拆分 + stdout 末行位置」完成。）

| 文件 | 形态 | PHP 8.5.8 | AOT（`b21cdfd` 当前） |
|---|---|---|---|
| `fuzzy_scripts_720/tmp/ref003_crash_min_tmp.php` | 持引用 + 首轮追加 200 键（体内不读 key/值） | `C1 byref-grow visited=205 count=205 g199=199` | **rc=139 SIGSEGV，stdout 空** |
| `fuzzy_scripts_720/tmp/ref003_crash_v1_keyonly_tmp.php` | 同上但每轮读 `$key` | `visited=205 keys=k0,…,g0,…` | **rc=139** |
| `fuzzy_scripts_720/tmp/ref003_liveset_bisect_tmp.php` | F1–F7 因子矩阵 | 全部正常 | F1/F2 输出后 **rc=139**（F3 崩） |
| `fuzzy_scripts_720/tmp/ref003_liveset_bisect2_tmp.php` | F4–F7（F4 先崩） | 全部正常 | **rc=139，stdout 空** |
| `fuzzy_scripts_720/tmp/ref003_crash_attr_tmp.php` | W1 对照 / W2 增长后 break / W3 增长后 continue | `W1 visited=5` `W2 visited=1` `W3 visited=205` | **2026-10-01（RC-4 落地后）**：`W1` ✓ `W2` ✓ 逐字节等值，**崩溃面只剩 W3（`rc=139`）** ／ 历史读数（`b21cdfd`）：`W2 visited=5`（臂尾 `break` 连同内层 `for` 未在臂内发射，见 §6，现已收口）/ W3 `rc=139` |

```bash
cd /Users/wangjianjun/products/parser
timeout 10 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/ref003_crash_min_tmp.php
timeout 300 ./zig-out/bin/php-interpreter --compile --no-debug-info \
  --output=/tmp/aot_compile_ref003_crash_min_tmp fuzzy_scripts_720/tmp/ref003_crash_min_tmp.php
timeout 10 /tmp/aot_compile_ref003_crash_min_tmp; echo "rc=$?"   # 139
```

## 3. 因子 bisect（2026-09-30 实测，真值 = `/opt/homebrew/bin/php`）

| 因子 | PHP 真值 | AOT 实测 | 判定 |
|---|---|---|---|
| F1 **按值** foreach + 追加 3 键 | `visited=5 count=8 n1=111` | `visited=5 count=8 n1=111` | ✅ 等值 ⇒ 按值侧走 `php_array_iter_init_snapshot`（:7768，`cloneShallow` :7810）天然安全，**问题精确在持引用侧** |
| F2 **持引用** foreach + 追加 3 键（不搬迁量级） | `visited=8 count=8` | `visited=5 count=8` | ❌ **纯 live-set 语义差**：追加 3 键时 PHP 已访问新键，AOT 未访问 ⇒ 与「是否搬迁」无关，是集合可见性缺陷 |
| F3 持引用 + 追加 200 键 | `visited=205` | **SIGSEGV** | ❌ 崩溃（R-3 实物化） |
| W1 持引用 + 追加到**另一个**数组 | `visited=5` | `visited=5` | ✅ 等值 ⇒ 崩溃归因精确到「被遍历容器自身搬迁」 |
| W2 持引用 + 追加后 `break` | `visited=1` | **2026-10-01（RC-4 落地后）`visited=1 count=205 g199=199` 逐字节等值**（此前为 `visited=5`） | ✅ **等值且不再崩** ⇒ W2 升格为本工单的**正向对照**：同一容器在同一迭代内被追加 200 键（真发生搬迁），只要 `break` 生效、迭代器不再推进，就不触发 `next()` ⇒ 反证崩溃点在**搬迁后的下一次 `next()` 推进**，不在 key/引用槽读取。旧 `visited=5` 读数属发射侧缺陷 [CODEGEN-005 RC-4](AOT-CODEGEN-005-foreach-body-if-arms-lost.md)（臂尾 `break` 连同内层 `for` 丢失），**与本文无关，已另行收口** |
| W3 持引用 + 追加后 `continue` | `visited=205` | **SIGSEGV** | ❌ 崩溃：崩在**下一次 `next()` 推进**，而非崩在槽读取 |
| F4b 持引用 + 追加 3 键 + 写引用 | `visited=8 k0=4242` | （并入 bisect2 前未取到，F4 崩溃遮蔽） | ⏳ 前置阻塞（RC-4）**已于 2026-10-01 落地解除** ⇒ 判据不再被污染；复测排在 §5 的 P0 裁决之后 |
| F5 持引用循环正常结束后的残留 `$ref` 别名 | `last=4 k3=4 count=5` | 未达（前序崩溃） | ⏳ 同上；`ref003_crash_attr_tmp` 的崩溃面现已**收窄到 W3 一处**（W1/W2 等值），F5 只需越过 W3 即可取数 |
| F6/F7 `array_walk` + 追加 | `visited=8` / `visited=65 k0=5566` | REF-002 侧实测：`visited=60`、写回落空 | ❌ 属本文 L1/L2（见 §4） |

## 4. 与 AOT-REF-002 §3.1 的分工

| 表现 | 归属 | 依据 |
|---|---|---|
| 持引用 `foreach` 期间追加 ⇒ 崩 / 少访问 | **本文（迭代器结构 + live-set）** | §3 F2/F3/W3 |
| `array_walk` 回调内追加 ⇒ `visited` 停在调用时集合、写回读不到 | **本文 L2（容器换代）**：追加导致全局变量指向新容器，walk 仍在旧容器上推进 | `ref002_r1b_isolated_tmp` X1/X2：AOT `k1=1`（应 4242/5566），且**修复前/后模板逐字节相同** ⇒ 与裸槽悬垂（R-1b）无关 |
| `foreach` 取引用 → 容器扩容 → 写引用丢写 | **REF-002 R-1a（已 CLOSED）** | 探针 E `k1` 由 `1`→`888`，且 pre/post 换模板实证（REF-002 §5-1） |

⇒ 结论：**R-1a 装槽只解决「引用单元地址」问题；「迭代器/Entry 地址」与「换代归属」两问题在本文，未收口。**

## 5. 归因实证（换回修复前模板重编译）

`fuzzy_scripts_720/tmp/ref003_prepost_attr_tmp.sh`（pre = `b21cdfd^` 模板，post = 工作区模板；结束 `RESTORED_MD5=008b7b639f1069cb73e443064e115ed1` 与换前一致，`git status` 干净）：

| 探针 | PRE（修复前） | POST（`b21cdfd`） | 判定 |
|---|---|---|---|
| `ref003_crash_min_tmp` | rc=139 | rc=139 | 崩溃**早于** R-1a/R-1b 存在 |
| `ref003_crash_v1_keyonly_tmp` | rc=139 | rc=139 | 同上 |
| `ref003_crash_attr_tmp` | W1 ✓ / W2 visited=5 / W3 rc=139 | 逐项相同 | 崩溃与 break 丢失均**非本提交引入** |
| `ref003_liveset_bisect_tmp` | F1 ✓ / F2 visited=5 / F3 rc=139 | 逐项相同 | live-set 语义差**非本提交引入** |
| （对照）`ref002_iso_e_byref_grow_then_write_tmp` | `k1=1` | `k1=888` | ✅ 同一方法**能**测出 R-1a 的效果 ⇒ 该方法有区分力，上述「逐项相同」是真结论而非方法失效 |
| `ref002_r1b_isolated_tmp`（X1/X2/X3） | `k1=1 / k1=1 / d4=400` | 逐项相同 | R-1b 改动的可观测面为**零**（被 L2 掩盖，见 §4） |
| **（2026-10-01 复测）`ref003_crash_attr_tmp`** | — | W1 `visited=5` 与 PHP 逐字节等值 / W2 PHP `visited=1 count=205 g199=199` vs AOT `visited=5 count=205 g199=199` / 进程 `run_rc=139` 且 stdout 停在 W2 之后（⇒ 崩在 W3） | **不换模板**、直接用当前工作区树（`b21cdfd`）重编译 ⇒ 与 09-30 逐项相同 ⇒ 读数稳定，且 §6 的 RC-4 症状在当前树仍 100% 复现。**读数更正（同日结构化 dump）**：W2 的 `count=205 g199=199` 并非「内层 for 在臂内正确发射」，而是内层 for 被丢到 foreach **之外**重发一遍的结果 ⇒ 该两列**不可**用作 F4b/F5 的验收判据 |
| **（2026-10-01 RC-4 ①+② 落地后）`ref003_crash_attr_tmp`** | — | W1 ✓、**W2 首次逐字节等值**（`visited=1 count=205 g199=199`）、崩溃面收窄至 **W3 一处**（`rc=139`，stdout 停在 W2 之后） | **三点崩溃序列**（发射侧唯一变量）：`b21cdfd` W2 不崩（内层 for 被丢到循环外 ⇒ 迭代期根本没增长）→ 仅 ① W2 崩（增长真的进了迭代期）→ ①+② W2 不崩且等值、W3 仍崩（`break` 让迭代器不再推进，`continue` 继续推进）⇒ **崩溃点定位在「搬迁后的下一次 `next()` 推进」**，与 §3 的归因一致，且本行读数**可**作为 F4b/F5 复测的干净基线 |

## 6. 同批判定的第二个独立缺陷（发射侧，非本文修复范围；**RC-4 已于 2026-10-01 落地**）

W2 形态 —— 持引用 `foreach` 体内 `if ($w2 === 1) { for (…) { … } break; }`：**修复前**臂尾 `break` 及其**所属的内层 `for` 整块**均未在臂内发射（PHP `visited=1`，AOT `visited=5`）。这与 [AOT-CODEGEN-005](AOT-CODEGEN-005-foreach-body-if-arms-lost.md) 的 RC-1（后置单语句 `if-break` 臂）同族但形状不同：本轮 16 探针门覆盖的是「**后置另一个 if 里**的 break」，未覆盖「**同一臂内、内层循环之后**的 break」。**已取证（2026-10-01，见 CODEGEN-005 §4「RC-4」与 §7 行 7）**：该 `break` 在 IR 里没有自己的块，被折叠进内层 `for` 的出口边（`for_cond_` 假边直接指向外层 `foreach_cleanup_`）；三个循环生成器的臂尾派发救援判据只覆盖「内层出口复用本 if 的 `if_merge_`」，本形没有 else 块 ⇒ 判据落空 ⇒ 派发区间被 `loop_end` 截空 ⇒ 零发射零标记，块随后在循环外被重发（⇒ 上一条的 `count=205` 读数）。**对本工单的后果（2026-10-01 更新）**：RC-4 **已落地**（①+②，纯新增 +145 行，见 CODEGEN-005 §4「分步落地实测」）⇒ W2 首次逐字节等值、Y 系列读数不再被发射侧污染，F4b/F5 复测的**前置阻塞已解除**；本工单剩下的只有自身的 P0 —— W3/F3 在「搬迁后的下一次 `next()` 推进」处 `rc=139`，需 §10 行 1 的裁决后才动 `runtime_lib_template.zig`。

## 7. 修复方案（优先级 / 影响面 / 落地成本）

| 优先级 | 方案 | 影响面 | 落地成本 |
|---|---|---|---|
| **P0** | **止血（必做，先于语义）**：`ArrayIterator` 不再按值持有 `Elements.Iterator`，改为持有**键序列 + 位置下标**：init 时把当前键复制为 `[]Value`（字符串键 de-dupe 一次），此后 `current` 由「位置 → 键 → 现场 `getPtr(key)`」求得；每轮 `next` 前重新读 `elements` 的当前长度 ⇒ 桶搬迁后不再有任何旧指针被解引用 | `src/aot/runtime_lib_template.zig` 单文件：`_init`（:7818，构造 :7879-7881）、`_init_ref`（:7888-7912）、`_valid`（:7914，判据 :7926）、`_key`（:7930，读 `key_ptr` :7941）、`_value`（:7953）、`_value_ref`（:7974，`+= 1` :7979）、`_next`（:8039，`iter.current = iter.iter.next()` :8051）、`_free`（:8144，锁清零 :8171-8174）——**其中 `_valid`/`_key`/`_next`/`_free` 为按值与持引用共用**（见 §7.1 结论 1）；另可评估摘掉 `has_active_refs`+`convertToMixed` 那套锚形态补救 | 中（模板单文件，实测触及 **8 个函数 + 1 个结构体**，其中 4 个函数为按值/持引用共用；探针门现成）。「摘掉 `has_active_refs` + `convertToMixed`」受 §7.1 锁协议行④约束：**须按四个写入口分别取证后才可评估**，禁止与本批同做 |
| **P0** | **迭代期换代检测改为「按长度增长」而非「快照冻结」**：新键 append 后按插入序可见 ⇒ 直接满足 F2/F3/W3 的 PHP live-set 语义（与上一条同源于「位置 + 键」模型，无需另写机制） | 同上 | 与上一条合并实现 |
| P1 | **`array_walk` 走同一模型**（L2）：回调参数由 `make_ref` 装槽后，容器换代应把 Ref 单元随搬迁带走，而不是让全局变量换新容器；需先定位换代发生点（`php_array_set` 的共享判定） | 回调迭代 + 赋值下沉 | 中高（触及 COW 判定，回归面大） |
| P1 | 把 F2/F3/W1/W2/W3 五形纳入 720 语料生成模板（当前语料 68 脚本 **0 覆盖** ⇒ 这条 P0 崩溃在语料里是隐形的） | 测试资产 | 低（需重冻结基线一次） |
| P1 | 发射期金丝雀：`break` 后若同一臂仍有语句未发射 ⇒ 报警（覆盖 §6 的 RC-4 已取证形态） | 1 处判据 | 低 |
| P2 | 压测 R-6 与新键序列的内存上界（键复制是 O(n) 额外内存，长数组持引用迭代会显著上升） | 性能/内存 | 低（探针已有量级：200k 元素） |

## 7.1 实现细化（2026-10-03 只读代码复核；**本轮未改一行代码**，待裁决）

崩溃点的代码事实（`src/aot/runtime_lib_template.zig`）：

| 事实 | 位置 | 结论 |
|---|---|---|
| `Elements.Iterator` 按值持有 `mixed_it: ArrayHashMapUnmanaged.Iterator` | :1815-1821 | 该迭代器结构体内捕获 `entries`/`key_index` 的切片指针；map 扩容即搬迁 ⇒ 指针悬垂 |
| `packed` 侧 `next()` 每轮重读 `elements.packed_values.items[index]` | :1822-1835（:1830 取元素指针） | packed 路径不持旧切片 ⇒ 仅 `index` 与 `*const Elements` 生命周期问题，不是本崩溃源 |
| `php_array_iter_init_ref` 先 `convertToMixed()` 再 `array.elements.iterator()` | :7888-7912（:7897 转 mixed，:7908 建迭代器） | **持引用 foreach 必走 mixed** ⇒ 必落入上面那条按值持有的悬垂路径 |
| 释放保护只在非 ref 入口成对：`php_array_iter_init` 有 `retain()`（:7871）+ `ref_lock_count += 1`（:7875）+ `has_active_refs`（:7876），而 `php_array_iter_init_ref` **只有** `has_active_refs`（:7895）+ `retain()`（:7902），**不累加 `ref_lock_count`** | :7871-7876 对 :7894-7903 | 两点须知：① 这些标志只防**释放**，不防**搬迁** ⇒ 现有锚形态补救与本崩溃正交；② ref 入口缺 `ref_lock_count` 是本次复核新发现的不对称，是否为独立缺陷**未取证**，禁止顺带动（另立探针） |
| `ref_lock_count` 的**四个写入口径互不同源**（2026-10-03 只读复核逐行实测）：`php_array_iter_init`（:7818）**每迭代器** `+= 1`（:7875）；`php_array_iter_value_ref`（:7974）**每轮读引用**都 `+= 1`（:7979）；`php_array_iter_free`（:8144，该迭代器 `ref_count` 归零分支内）把计数**整表清零** `= 0` 同时置 `has_active_refs = false`（:8171-8174）；`RefWrapper.deinit`（:7746-7752）则 `-= 1` 递减且归零时清 `has_active_refs` | :7875 / :7979 / :8171-8174 / :7747-7751 | 四点须知：① 该计数**唯一消费者**是 `PHPArray.release` 的延迟释放门（:2077-2081，`> 0` 即不释放）⇒ 语义只覆盖「释放」，与桶**搬迁**无关，不能指望它挡住本工单的 P0 崩溃；② 「每轮 +1」与「清零」之间**没有配对关系** ⇒ 计数值不代表活跃迭代器个数，`init_ref` 又不累加，按持引用 foreach 走的那条路径其锁实际由 `_value_ref` 的按轮累加提供；③ 由 ② 可推出**代码事实**：同一容器上另一个迭代器先 `free`，会把仍在使用的迭代器锁一起清零（`has_active_refs` 同被清）；其**可观测危害**（能否真导致迭代期释放/UAF）**未取证**；④ 对 §7 P0 行「同时可摘掉 `has_active_refs` + `convertToMixed` 补救」的约束：摘除必须**按这四个写入口分别取证**，禁止与迭代器数据模型改造同批（否则崩溃归因失效，见 §8）。若要复核 ③，探针形状 = 同容器双迭代器（一按值一持引用）+ 期间 grow + 先 `free` 其一，观察另一迭代器是否读到已释放槽；**本轮未写该探针、未取数**；⑤ **归并登记**：本行的「清零 vs 递减」即 [AOT-REF-002](AOT-REF-002-iter-ref-slot-dangling.md) 已登记的 **R-4**（其 §3 表 :8173 对照 :7749），本轮实测把它从「一处清零写法不当」扩展为「四个写入口径互不同源」⇒ **同一站点不得在两工单各修一次**，落地时以 REF-002 R-4 的口径为准、本文只提供新增证据 |
| `ArrayIterator` 结构体按值内嵌 `iter: PHPArray.Elements.Iterator` | :7760-7766（2026-10-03 复核：:7760 声明、:7761 `array`、:7762 `iter`、:7763 `current`、:7764 `freed`、:7765 `ref_count`、:7766 结束；与 [AOT-REF-002](AOT-REF-002-iter-ref-slot-dangling.md) R-3 的字段行号一致） | 改造点即此字段 + `current` 的求值方式 |

两条 foreach 入口的分工（**实测 + 代码双向印证**，非推断）：

- foreach 的迭代器入口由 **`ir_generator.zig` :2913** 按 `foreach_data.value_by_ref` 分支发射：按值 ⇒ `php_array_iter_init_snapshot`（模板 :7768，内部 `cloneShallow` :7810 后再建迭代器），持引用 ⇒ `php_array_iter_init_ref`（模板 :7888）。`native_linker.zig` 只在 builtin 表（:4148-4156）**登记**这些符号名，本身不发 foreach 的迭代调用。
- §3 的 F1（按值 + 追加 3 键）逐字节等值 ⇒ 按值侧天然安全。**故崩溃面精确限定在 ref 路径**。
- 但共享的 `php_array_iter_init`（:7818）另有库内调用点：:5136、:11883（`source` 可为用户活容器）、:7844（Iterator 对象的当前值）、:7800/:7852（对象属性快照）⇒ 这些点是否也会遇到「迭代期活容器搬迁」**尚未取证**，不可当作已知安全。

foreach 迭代器 API 的**逐站点实测**（2026-10-03 只读复核，以 `src/aot/ir_generator.zig` 的发射名为准，非推断）：

| IR 站点（`ir_generator.zig`） | 发射的运行时函数 | 按值 / 持引用是否分支 | 模板实现位置 |
|---|---|---|---|
| :2913 | `php_array_iter_init_snapshot` 或 `php_array_iter_init_ref` | **分支**（`foreach_data.value_by_ref`） | :7768 / :7888 |
| :2947 | `php_array_iter_valid` | **共用**（无分支） | :7914（:7926 判据为 `iter.current != null`） |
| :2974 | `php_array_iter_key` | **共用** | :7930（:7941 `switch (entry.key_ptr.*)`） |
| :2997 | `php_array_iter_value_ref` 或 `php_array_iter_value` | **分支** | :7974 / :7953 |
| :3035 | `php_array_iter_next` | **共用** | :8039（:8051 `iter.current = iter.iter.next()`） |
| :3054 | `php_array_iter_free` | **共用** | :8144（:8171-8174 把 `ref_lock_count` 整表清零） |

由此得三条**代码级结论**（后续裁决必须以此为前提）：

1. `ArrayIterator`（模板 :7760-7766）**没有模式字段**，五个字段为 `array` / `iter: Elements.Iterator` / `current: ?Elements.Entry` / `freed` / `ref_count`；`current`（:7763）是**唯一**跨轮载体，赋值于 :7881 / :7909 / :8051（三处均为 `iter.current = iter.iter.next();`），消费于 :7940 / :7963 / :7978（三处均为 `if (iter.current) |entry|`），其 `key_ptr`/`value_ptr` 即悬垂源 ⇒ 将数据模型改为「键序列 + 位置下标」**必然**触及 `_valid`（:7926）、`_key`（:7941）、`_next`（:8051）、`_free` 这四个**按值与持引用共用**的函数，改不动这四处就没有「只改 ref 路径」。
2. 故原文「α ⇒ 按值与 snapshot 路径字节不变」的说法**在源码层面不成立**，已在下方口径表更正为 α′/α″ 两种真实形态。
3. `native_linker.zig` 的 builtin 表在 :4152、:4153、:4154、:4156 登记了 `php_array_iter_value_ref_reuse`、`php_array_iter_valid_ref`、`php_array_iter_next_ref`、`php_array_iter_free_ref` **四个函数名**，而模板侧 `grep -c` **全为 0**（一个都不存在），`ir_generator.zig` 亦**从不发射**这些名字（全仓仅这 4 处登记）⇒ 这是「一条已规划、未落地的分派 API」的残留；旁证另有两处孤儿注释：模板 :7928-7929「`引用迭代器valid`」与 :8056「`引用迭代器next（返回state）`」都挂在**共用**函数头上。含义有二：① α″ 若要新建 ref 专用入口，**可直接复用这套已登记的名字**，不必自创；② 登记即暴露 ⇒ 用户 PHP 脚本若调用同名函数会解析到不存在的运行时符号（链接期失败），是否清理属 §六「删代码须先问」范畴，**本批未动**。

由此产生一个必须裁决的落点口径（三者不可既要又要）：

| 口径 | 内容 | 影响面 | 代价 |
|---|---|---|---|
| **α′ 共用结构体加模式位**（本轮复核后建议先做） | `ArrayIterator` 增模式位与可选「键序列」字段，`_valid`/`_key`/`_next`/`_free` 四个共用函数内按模式分支；持引用走键序列，按值走原 `iter: Elements.Iterator` | **纯模板批**：AOT 编译期由 `native_linker.zig` :32219-32236（**历史读数，行号已作废** ⇒ 当前实测 `fn copyRuntimeLib` `:32378`、模板路径数组 `:32393`，见 §11.1）把 `src/aot/runtime_lib_template.zig` **以符号链接**作为临时工程的 `runtime_lib.zig` 打入 ⇒ 只改模板即覆盖产物；按值侧**行为**不变但四个共用函数的**源码被触** ⇒ 冻结基线漂移应先验为 0 并实测复验 | 模式位与分支常驻按值热路径（每轮多一次判分），`ArrayIterator` 体积变大；键序列字段对按值迭代器为死重 |
| **α″ 新建持引用专用迭代器** | 新增 `ByRefArrayIterator` 与 `_init_ref`/`_valid_ref`/`_next_ref`/`_key_ref`/`_value_ref`/`_free_ref` 一套入口（可复用结论 3 那四个已登记未实现的名字）；模板侧按值路径**真正字节不变** | **双组件批**：`ir_generator.zig` :2947、:2974、:3035、:3054 四处共用站点必须按 `value_by_ref` 分支 ⇒ 发射侧改动 ⇒ 基线漂移**不再先验为 0**，须按 RC-4/RC-5 那样跑全套门 | 隔离最干净（按值侧零风险），但同时触及 664KB `native_linker`（builtin 表）与 234KB `ir_generator` 两个超大文件，落地与复测成本最高 |
| **β 改共享 `Elements.Iterator`** | 数据模型统一改为键序列 | 根治所有调用点 | 触及对象属性遍历、`array_*` 库函数、`array_walk` ⇒ 回归面为全部迭代路径，且按值侧要额外保证「冻结不转 live-set」 |

内存/性能量级（供 §7 P2 对照，**按 ArrayKey 为 16 字节 tagged union 计算，实际尺寸须在实现时以 `@sizeOf` 实测回填**）：键序列快照为 O(n) 额外内存；200k 元素的持引用迭代 ⇒ 约 3.2MB 临时占用，随迭代器释放。建议只在 ref 模式分配，且优先复用迭代器自身的 arena 生命周期，避免逐键 de-dupe 分配。

落地顺序建议（每步单独可复测，禁止合并成一次大改）：

1. **P0-a 搬迁止血**：ref 路径改键序列，语义仍按 init 时键序（不引入 live-set）⇒ 判据 = W3 不再 `rc=139`，且 F2 仍为 `visited=5`（证明本步只治崩溃不动语义）；
2. **P0-b live-set 增长**：`next()` 前按当前长度补收新键 ⇒ 判据 = F2 `visited=8`、F3 `visited=205`、W3 `visited=205` 与 PHP 逐字节等值；
3. **P1 再动 `array_walk`（L2）**：COW 换代点（`php_array_set` 共享判定）单独取证后另批处理；
4. 摘除 `has_active_refs` + `convertToMixed` 的补救只在 P0-a 复验通过之后评估，且不得与 P0-a 同批。

## 8. 风险

- **不做 P0 止血的后果**：任何 `foreach ($a as &$v)` 且循环体内向 `$a` 追加键的业务脚本 ⇒ 进程段错误退出（无提示、无栈），属最恶劣失效形态。语料 68 脚本零覆盖该形状，所以「回归全绿」不代表安全。
- 止血方案改的是**迭代器数据模型**，波及 `foreach` 全部读写路径（含对象属性遍历复用点 `php_array_iter_init_snapshot`）⇒ 必须先出计划并逐项过 §9 全门，禁止直接改。
- 摘除 `has_active_refs` + `convertToMixed` 是次生收益但**不得与本批同做**（否则崩溃归因失效）。
- 按值 `foreach` 的快照语义（F1 已等值）**不可被顺带改成 live-set**：PHP 按值 foreach 期间追加确实不访问新元素（F1 `visited=5`），改了会引入新缺陷。
- **非 AOT 路径的同类隐患（只登记，未动）**：`src/aot/runtime_lib.zig`（被 `src/main.zig` :13 与 `src/aot/root.zig` :84 引用，**不是** AOT 产物所用文件 —— AOT 走模板符号链接，见 §7.1 α′ 行）里存在同名迭代器导出 :3148-3201，其中 `php_array_iter_value_ref`（:3195）**直接 `return php_array_iter_value(iter_val);`**（:3197）⇒ 该侧的持引用读值本就退化成值拷贝。按宪法 §五「发现其他模式问题必须先问」，本工单**不顺手修、不并入模板批**。
- **死登记风险（§7.1 结论 3）**：`native_linker.zig` :4152、:4153、:4154、:4156 登记的 `php_array_iter_value_ref_reuse`/`_valid_ref`/`_next_ref`/`_free_ref` 在模板中**不存在**。保留 ⇒ 用户 PHP 脚本以同名函数调用时会在链接期失败（非静默错误，但不可用）；删除 ⇒ 属 §六「删代码须先问」。二者均**待裁决**，本工单未动。

## 9. 验收门（修复时）

1. §2 的 5 个探针 + §3 的因子矩阵全部与 PHP 逐字节等值（`rc=0`，无 139）；
2. `ref002_iso_*` 全部门不回退（尤其 C/D/E 与 17 形等值门 `c005_probe_run_tmp.sh` `same=17/17`）；
3. `scripts/regression_test_720.sh`：FAIL_DIFF=0 / SKIP=1（f004）；
4. **口径决定门数**：走 **α′**（仅模板）⇒ 冻结基线全量漂移 `diff=0 norow=0` + `f12_determinism_tmp.sh` `mismatch=0` + `s7_baseline_spotcheck_tmp.sh` `ok=5 bad=0`，免 `zig build test`；走 **α″ 或 β**（触及 `ir_generator.zig` / `native_linker.zig`）⇒ 属**发射侧改动**，上述三门一项不能省，且**必须**加跑 `timeout 120 zig build`（实测建议 240 上限）与 `zig build test`，漂移出现时逐脚本解释后才可重冻结；
5. 新增量级压测（200k 元素持引用迭代）RSS 与耗时记录在案，与 §7 P2 对照；
6. 批次期间禁止编辑模板、禁止 `zig build`、禁止并发编译；复测前排查 PPID=1 孤儿。

## 10. 待裁决

1. 是否按 §7 的 P0（键序列 + 位置下标模型）立项修复 —— 这是**迭代器数据模型改造**，不是行级补丁，需你确认后才动 `src/aot/runtime_lib_template.zig`；
2. `array_walk` 的换代（L2）与 by-ref `foreach` 是否同批（本文建议**分批**：先止血 + live-set，再动 COW 判定）；
3. ~~§6 的 RC-4（发射侧）是否先于本工单落地？~~ **已落地（2026-10-01，①+② 纯新增 +145 行，门实测见 CODEGEN-005 §4；2026-10-03 提交为 `0ff09cf`）** ⇒ 本工单的 F4b/F5 复测前置阻塞解除，W2 转为正向对照。**同次验收暴露的 RC-5 现状（2026-10-03 实测）**：facet-1（臂尾 `continue` + if 有真实延续块 ⇒ merge 体兄弟语句丢失）已由 CODEGEN-005 方案 B 关闭（F-B/F-D/F-E 三形转等值；口径差异面的影子扫描实测为「4 个探针共 **6 处**收尾站点、每处从区间 5 块中放行 **1** 块，68 语料 **0** 处，见 CODEGEN-005 §7 行 12 的影子扫描记录」，基线漂移门已实测 `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0` ⇒ 语料零漂移、未重冻结基线）；facet-2（F-F while / F-H for 的 then 路径过执行延续块；准确口径为**臂尾未把外层 latch 续进到臂缩进** —— 出口边记录权缺失，见 CODEGEN-005 §4 ④/⑤。原登记「`continue` 未翻译」已由 2026-10-03 静态取证否证，**同日 trace 取证轮亦已闭环**）**2026-10-04 更新**：facet-2 经用户裁决走「方案 R：一条机制覆盖 F-F/F-H」并**已落地**（工作区未提交，净增 +72/−18，相对 HEAD 累计 +128/−23，blob `3ae7b34e`；站点① while :16299–:16303 / 站点② for :14711–:14721 + 共用谓词 :951 与例程 :959）⇒ **F-F / F-H 转逐字节等值、RC-5 八形合串整份输出 `IDENTICAL`**，§5 七门在该二进制上串行复测全绿（漂移门 `DRIFT_DONE total=68 ok=68 diff=0` ⇒ 语料零漂移、未重冻结），落地记录见 CODEGEN-005 §4「facet-2 落地记录」与 §7 行 15。**RC-5 两 facet 至此全部闭环，且全程与本工单无耦合**（不涉及迭代器推进/引用装槽）⇒ 本工单的 P0 裁决不再受任何发射侧开放项阻塞；八形门与 RC-4 诊断门的**唯一红点仍归本工单**（`ref003_crash_attr_tmp` W1/W2 等值、输出止于 W2、`rc=139`）。
4. **改造落点口径**（§7.1，**原「α 只改 ref 路径 ⇒ 按值侧字节不变」的说法已被本轮 IR 站点实测推翻**：`_valid`/`_key`/`_next`/`_free` 四个函数由按值与持引用**共用**，改数据模型必被触及）：现剩三种真实形态，需你点选 ——
   - **α′**：`ArrayIterator` 加模式位 + 可选键序列字段，四个共用函数内分支 ⇒ **纯模板批**、门数最少，代价是按值热路径每轮多一次判分、结构体变大；**本工单推荐先做此项**（W3 崩溃 + F2/F3 live-set 都能在 α′ 内收口）；
   - **α″**：新建 `ByRefArrayIterator` 与一套 `*_ref` 入口（可复用 §7.1 结论 3 那四个已登记未实现的名字）⇒ 按值侧源码零触，但必须改 `ir_generator.zig` 四处共用站点（:2947/:2974/:3035/:3054）⇒ **发射侧批**，门数按 §9 第 4 条右支；
   - **β**：统一改共享 `Elements.Iterator` ⇒ 根治所有调用点，回归面为全部迭代路径。
   建议顺序：α′ 复测通过后，再按证据决定是否升级为 α″/β；三者禁止混批。
5. **是否拆两步过门**（§7.1 落地顺序）：P0-a 只治搬迁（语义仍冻结，判据 = W3 不再 `rc=139` 且 F2 仍 `visited=5`）→ P0-b 才引入 live-set（判据 = F2/F3/W3 全等值）。合并做会失去「崩溃已止血」与「语义已改」之间的归因隔离。
6. **本轮只读复核新暴露的三个旁支（均未动代码、均未取数，需你逐项点头才做）**：
   - 6a `ref_lock_count` 多迭代器共存危害（§7.1 锁协议行 ③）：是否先写「同容器双迭代器 + 期间 grow + 先 `free` 其一」探针取证，再决定是否纳入本工单；
   - 6b `native_linker.zig` :4152/:4153/:4154/:4156 四个未实现的 `*_ref` 死登记（§8）：**删除**（属 §六 删代码确认）／**保留并实现**（即 α″ 的落点）／**保留不动**，三选一；
   - 6c 非 AOT 侧 `src/aot/runtime_lib.zig` :3195-3197 的 `value_ref` 退化（§8）：按宪法 §五 属「其他模式的问题」，是否一并修复需你明确同意，否则只登记。

---

## 11. 锚点代次刷新（2026-10-04，D 批代次 `9490bf9f` 实测；只读复核，零代码改动）

> CODEGEN-006 的 A + D 两批在 `src/aot/native_linker.zig` 插入了 117 行 ⇒ 本工单里指向该文件的行号需刷新。**分段偏移表与六个校验点见 [AOT-PERF-001 §8](AOT-PERF-001-默认优化档位与函数级状态机回退.md)**（同一张表，本文不重复推导）。

> **适用边界（本轮实测得出，很重要）**：那张分段表只对**记在 `3ae7b34e` 代次**上的锚点成立。本工单 §11.2 里四个 `*_ref` 登记的实际偏移是 **+126** 而非 +91 ⇒ 它记在更早的代次（RC-4 `0ff09cf` 树）上。⇒ **结论：跨代次偏移不可相加推算，任何要动手的锚点一律按符号 grep 实测**（流程规约 (b) 的又一次实证）。

### 11.1 本工单实际要动的锚点，当前树实测值

| 用途 | 工单旧锚点 | 当前实测（`9490bf9f`） | 判定依据 |
|---|---|---|---|
| AOT 取运行时模板的符号链接段（α′ 的入口证据） | `native_linker.zig:32219-32236` | **`fn copyRuntimeLib` `:32378`，模板路径数组 `:32393`** | grep `runtime_lib_template.zig` 全文件**唯一命中** `:32393` ⇒ 旧值无论按哪一代偏移都推不出该位置，**属历史读数，禁止再用作定位锚**（流程规约 (b)） |
| RC-5 站点②（for 外层 latch 交还，与本单同源风险） | `:14711`–`:14721` | **`:14828`–`:14838`** | +117 段，符号 `if (self.in_cond_br_branch)` / `processed.remove(exit_idx)` / `return exit_idx` 逐行核对 |
| RC-5 站点①（while 乱序出口交还） | `:16299`–`:16303` | **`:16416`–`:16420`** | +117 段，符号 `isOuterLoopLatch(shared_merge_blk.label) and self.in_cond_br_branch` |
| 共享谓词 `isOuterLoopLatch` / `findExitEdgeSourceIdx` | `:951` / `:959` | **`:951` / `:959`（未变）** | 两处插入均在其后（偏移 +0 段） |

### 11.2 判定为「仍然有效」的锚点（本轮 `git status` 实测这些文件零改动）

| 文件 | 本工单引用的锚点 | 判定 |
|---|---|---|
| `src/aot/runtime_lib_template.zig` | `:1815-1821`（`Elements.Iterator` 按值内嵌）、`:5136`、`:7746`–`:8173` 全部迭代器函数、`:11883` | **有效**：md5 仍为 `008b7b639f1069cb73e443064e115ed1`，`git status` 干净 ⇒ 行号不可能漂移（抽查 `:1815`/`:1821`/`:5136`/`:7768` 四处内容仍对得上） |
| `src/aot/ir_generator.zig` | `:2913`、`:2947`、`:2974`、`:2997`、`:3035`、`:3054`（α″ 需分支的四个共用入口） | **有效**：文件 9732 行，`git status` 干净 |
| `src/aot/runtime_lib.zig`（非 AOT 侧，§五 只登记不动） | `:3195-3197`、`:3148` | **有效**：同上，零改动 |

**⚠️ 一处失效锚点 + 一处代次推算反例（本工单 §7.1 结论 3 / §10 6b 引用的四个 `*_ref` 死登记）**

- 它们**在 `native_linker.zig` 的 builtin 表**，不在模板；旧范围 `:4148`–`:4156`（builtin 表内 `php_array_iter_*` 连续登记段）在当前代次 `9490bf9f` 的**实测**位置是 **`:4273`–`:4282`**（`:4273` `php_array_iter_init` 起、`:4282` `php_array_iter_free_ref` 止）（四个符号逐个命中：`php_array_iter_value_ref_reuse` `:4278`、`php_array_iter_valid_ref` `:4279`、`php_array_iter_next_ref` `:4280`、`php_array_iter_free_ref` `:4282`）；模板侧 `grep -c` 仍为 **0** ⇒ **死登记状态未变**，α″ 落点判断不受影响。
- 该处偏移是 **+126**，而按 §8 分段表（`3ae7b34e` → `9490bf9f`，`:982`–`:9058` 段）应为 **+91** ⇒ **说明这条锚点记在比 `3ae7b34e` 更早的代次（RC-4 `0ff09cf` 树）上**。这正是流程规约 (b) 的反例实证：**跨代次偏移不可连加推算，凡要动手的锚点必须按符号 grep 实测**。

⇒ **对 §10 裁决的实际意义**：α′ 是**纯模板批**（其全部落点锚点仍有效，可直接照行号开工），α″ 需动 `ir_generator.zig` 四处共用入口（锚点亦有效），两条路线的定位成本都未因 A/D 两批上升；只有涉及 `native_linker.zig` 的复测步骤需按 11.1 的新行号走。

### 11.3 §11.1 新值的再刷新（2026-10-05，当前工作区代次 `fbe6382a`／32797 行实测；只读巡检，零代码改动）

§11.1 的「当前实测」列钉在 **D 批代次 `9490bf9f`**，其后 R9-B 批（IPD helper +117 行）与 2026-10-05 四批合一、以及 #74 纯注释批（在 `:15620` 处净增 1 行）继续推行 ⇒ 该列的 `native_linker.zig` 值**已再度失效**。本轮按符号/字面量逐条 grep 实测（非偏移推算）：

| 用途 | §11.1 登记（`9490bf9f`） | **当前树实测（`fbe6382a`）** | 实测依据（该行内容） |
|---|---|---|---|
| `fn copyRuntimeLib`（α′ 入口证据） | `:32378` | **`:32512`** | `grep -n "fn copyRuntimeLib"` 唯一命中 |
| 模板路径 join 字面量 `"src/aot/runtime_lib_template.zig"` | `:32393` | **`:32527`** | 全文件**唯一命中**，仍为 `&[_][]const u8{ base, "src/aot/runtime_lib_template.zig" }` ⇒ 「唯一命中」这一判定依据本身复验通过 |
| RC-5 站点②（for 外层 latch 交还） | `:14828`–`:14838` | **`:14961`–`:14971`** | `:14961` = `if (self.in_cond_br_branch) {` ⇒ `:14962` `processed.remove(exit_idx)` ⇒ `:14963` `last_loop_fallthrough_idx = exit_idx` ⇒ `:14970` `return exit_idx;` |
| RC-5 站点①（while 乱序出口交还） | `:16416`–`:16420` | **`:16550`–`:16554`** | `:16550` = `if (isOuterLoopLatch(shared_merge_blk.label) and self.in_cond_br_branch) {` ⇒ `:16553` `return exit_idx;` |
| 共用谓词 `isOuterLoopLatch` / `findExitEdgeSourceIdx` | `:951` / `:959` | **`:951` / `:959`（仍未变）** | 两处定义均在所有插入点之前；`sed -n '951p;959p'` 逐字为 `fn isOuterLoopLatch(label: []const u8) bool {` / `fn findExitEdgeSourceIdx(` |
| §11.2 的 builtin 表连续登记段（四个 `*_ref` 死登记） | `:4273`–`:4282` | **`:4391`–`:4399`** | 逐符号命中：`php_array_iter_init` `:4391`、`_value_ref_reuse` `:4395`、`_valid_ref` `:4396`、`_next_ref` `:4397`、`_free_ref` `:4399`；同轮 `grep -c` 模板侧该四名为 **0** ⇒ §11.2「死登记状态未变、α″ 落点判断不受影响」的判定**复验通过**，仅行号需按本行走 |

**对 §10 裁决的意义不变**：α′ 的全部落点在 `runtime_lib_template.zig`（最后提交 `b21cdfd`，工作区干净，md5 `008b7b63…`）⇒ 模板行号（含 §11.2 的 `+126` 那条）**无需重测**；α″ 的四处在 `ir_generator.zig`（最后提交 `9b2ddf5`，干净）⇒ 同样无需重测。只有「按发射侧复测」的步骤要改用本小节的 `:14961`/`:16550`/`:32512` 三处行号。**OPEN 状态与「本工单仍未动任何源码」的口径维持。**
