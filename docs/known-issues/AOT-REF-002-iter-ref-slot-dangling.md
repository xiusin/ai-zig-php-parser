# 迭代期引用的同源残留：foreach-by-ref / array_walk 仍交出容器裸槽指针

**问题 ID**: AOT-REF-002
**优先级**: P1（UAF 风险类别与 AOT-REF-001 D2 同类，但触发需「迭代期间容器增长」这一更窄的时序；生产语料 68 脚本未踩到）
**状态**: **R-1a / R-1b 已落地（2026-09-30，`make_ref` 装槽，纯模板 2 处）并经「修复前后模板区分实证」收口**（R-1a 有效、R-1b 当前不可达）；**R-3 已升级为实测 P0 崩溃并转入 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) 立项**；R-2/R-4/R-5/R-6 仍为登记待裁
- **R-1a 生效实证**：`ref002_iso_e_byref_grow_then_write_tmp` 的 `k1` 由修复前 **`1`**（写入落到已搬迁裸槽）变 **`888`**（写回容器并可读回）⇒ 机理收口成立；剩余 `hits=20` vs PHP `60` 属 §3.1-1「持引用迭代的元素集合语义」，非本工单范围。
- **不回退**：`ref002_iso_c_walk_ref_nogrow_tmp`（`array_walk` 无扩容）保持 **IDENTICAL**（`x=4242 y=4242 count=2`）；`ref002_iso_d_byref_grow_tmp` 与修复前逐项一致（`k0=777 count=60`，差异同样只在 `hits`）。
- **R-1b 判据结论（2026-09-30 实证收口，见 §5-1）**：隔离探针 `ref002_r1b_isolated_tmp.php` 的 X1/X2 段修复前后**逐字节相同**（PHP `k1=4242/5566`，AOT `k1=1`），而同一「换回 `b21cdfd^` 模板重编译」的方法在探针 E 上能测出 `k1 1→888` ⇒ 方法有区分力。归因：AOT 里回调内向被遍历容器追加会先经过**容器换代**（`$b` 指向新容器、walk 仍在旧容器推进），R-1b 的「同一容器搬迁、旧槽悬垂」打击点当前**到不了** ⇒ R-1b 与 R-2 同类，属当前不可达的正向加固（改动保留，零回归零漂移已证）；复测须待 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) 收口。**顺带实证**：`ref_iter_slot_stale_probe_tmp` 的 `array_walk` 段（`visited=60 b0=0`）同样 pre/post 相同 ⇒ 它确非 R-1b 判据。
**发现日期**: 2026-09-30（AOT-REF-001 D2 收口时同批扫描 `Value.initRef(` 全部产出点）
**上游**: [AOT-REF-001](AOT-REF-001-container-ref-slot-dangling.md)（D0/D2 已于 2026-09-30 CLOSED；本文登记其未覆盖的其余引用产出点）

---

## 1. 取证：D2 修完后仍交出裸槽地址的 3 个产出点

`grep -n "Value.initRef(" src/aot/runtime_lib_template.zig` 在**修复前**模板（30803 行）命中 8 处，其中 **3 处指向容器内部槽地址**（R-1a/R-1b/R-2），与已修复的 `php_array_get_ref`（:4852，现改为 `make_ref` 装槽）属同一失效形态。

**修复后重测（2026-09-30，模板 30810 行）**：命中降至 **6** 处，其中指向容器槽的产出点仅剩 **1** 处（R-2 `php_object_get_ref`，不可达）；其余 5 处均指向 `make_ref`/`php_make_ref_from_value` 分配的堆 cell（:3066/:3067/:12753）或注释（:4851/:7985），属正确用法。下表行号已按修复后文件重新 grep：

| # | 位置 | 交出的指针指向 | 悬垂触发条件 | 现有防护 |
|---|---|---|---|---|
| R-1a | `php_array_iter_value_ref`（函数 :7974-7995，裸槽产出点 :7988 ⇒ **已改 `make_ref`**） | `array.elements.mixed` 的 `getPtr(key)` 槽 | foreach by-ref 迭代期间容器插入新键 ⇒ `ArrayHashMapUnmanaged` 重分配桶数组 | 仅靠 `has_active_refs=true` + `convertToMixed()`（`php_array_iter_init_ref` :7893-7899）**锚住形态**，锚不住后续扩容 |
| R-1b | `php_array_walk`（函数 :25549-25581，裸槽产出点 :25569 ⇒ **已改 `make_ref`**） | `entry.value_ptr`（迭代器当前桶槽） | 回调内向同一数组追加元素 ⇒ 桶数组搬迁，回调继续写 `$val` | 修复前**无任何防护**（未置 `has_active_refs`，未转 mixed，直接 `@constCast(entry.value_ptr)`） |
| R-2 | `php_object_get_ref`（函数 :19171，裸槽产出点 :19200） | 对象属性 map 的 `entry_ptr` | 属性地图增长 | 该函数**发射次数为 0**（AOT-REF-001 §4 实锤），当前不可达 ⇒ 属死能力 + 潜在雷 |

另有两处**引用单元生命周期**问题（不是悬垂，是野读与计数）：

| # | 位置 | 问题 |
|---|---|---|
| R-3 | `ArrayIterator.current: ?Elements.Entry`（字段 :7763，赋值于 :7881/:7909/:8051，消费于 :7940/:7963/:7978）＋ **按值捕获的 `iter: Elements.Iterator`（:7762）** | **已实测崩溃（2026-09-30，升级为 P0）**：持引用 `foreach` 期间向被遍历容器追加 200 键 ⇒ AOT **rc=139 SIGSEGV**（崩在下一次 `next()` 在旧桶数组上推进），且体内只读 `$key` 同样崩 ⇒ 与 R-1a 装槽无关。对照「追加到另一个数组」不崩 ⇒ 归因精确到容器搬迁。详见 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) §2–§3 |
| R-4 | `ref_lock_count` 清零（:8173） | 迭代器释放时 `ref_lock_count = 0` 而非 `-= 1`（对照正确写法 :7749）；多个并发引用迭代时，先结束者会把其余持锁一并抹平 ⇒ 数组可能被提前释放，其余引用彻底悬垂 |
| R-5 | `val_deref`（:3034） | 跟随引用链**无跳数上限**；同批新增的 `derefVal`（:3045）有 64 跳防护。理论自引用环可致挂死 |
| R-6 | 引用 cell 无回收（`make_ref` :3055、`php_make_ref_from_value` :12747） | cell 由 `allocator.create(Value)` 分配，Ref 不参与 retain/release 计数 ⇒ 容器换代时旧 cell 不归还。上界 = 「曾成为引用的元素个数」，长时间运行有增量 |

## 2. 复现代码（永久探针，勿删）

`fuzzy_scripts_720/tmp/ref_iter_slot_stale_probe_tmp.php`：foreach by-ref 首轮内向 100 键数组追加 200 键（强制搬迁）；`array_walk` 回调内向 60 键数组追加 120 键后写 `$val`。判据为「引用写入写回容器 + 增长后容器读回同值」。

```bash
cd /Users/wangjianjun/products/parser
timeout 10 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/ref_iter_slot_stale_probe_tmp.php
timeout 300 ./zig-out/bin/php-interpreter --compile --no-debug-info --output=/tmp/aot_compile_ref_iter_slot_stale_probe_tmp fuzzy_scripts_720/tmp/ref_iter_slot_stale_probe_tmp.php 2>/tmp/aotc_ref_iter.err
timeout 10 /tmp/aot_compile_ref_iter_slot_stale_probe_tmp
```

## 3. 实测对照（2026-09-30，真值 = `/opt/homebrew/bin/php` PHP 8.5，逐字节比对）

| 探针 | 打击点 | PHP 真值 | AOT 实测 | 判定 |
|---|---|---|---|---|
| `ref002_iso_a_break_foreach_tmp` | 对照：foreach 体内单语句 if + break（无扩容、无引用） | `hits=4 count=20` | `hits=4 count=20` | 等值 |
| `ref002_iso_b_foreach_snapshot_tmp` | 对照：按值 foreach + 体内 `for` 扩容（无 break、无引用） | `hits=20 count=60` | `hits=20 count=60` | 等值 |
| `ref002_iso_c_walk_ref_nogrow_tmp` | 对照：`array_walk` 的 `&$val` 写回，**无扩容** | `x=4242 y=4242 count=2` | 同 | 等值 ⇒ 闭包形参引用绑定本身没问题 |
| `ref002_iso_d_byref_grow_tmp` | by-ref foreach，顺序为**先写后扩容** | `hits=60 k0=777 count=60` | 修复前 `hits=20 k0=777 count=60` / **修复后同值** | 写入落地（引用每轮重取，未踩窗口）；差异只在迭代集合，R-1a 未改变本探针观测 |
| `ref002_iso_e_byref_grow_then_write_tmp` | by-ref foreach，顺序反转：**取引用 → 扩容 → 写** | `hits=60 k1=888` | 修复前 `hits=20 **k1=1**` → **修复后 `hits=20 k1=888`** | **R-1a 收口实证**：修复前写入落在已搬迁的裸 mixed 槽（UAF 写 + 写丢失），装槽后写回容器可读回；剩余 `hits` 差属 §3.1-1 |
| `ref_iter_slot_stale_probe_tmp`（`array_walk` 段） | `array_walk` 回调内追加 120 键后写 `$val` | `visited=180 b0=4242 count=180` | 修复前 `visited=60 b0=0 count=180` / **修复后逐字相同** | R-1b 代码已按同源机理改为 `make_ref`，但本探针的 `b0=0` 由 §3.1-1（只访问调用时 60 元素）+ 回调内 `$b` 追加导致 **COW 换代**（写回旧容器、读回新容器）共同解释 ⇒ **不构成 R-1b 判据**，须另建隔离探针 |

### 3.1 同批判定的两类**非引用**问题（不属 AOT-REF-002 修复范围 ⇒ 2026-09-30 已立项 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md)）

1. **持引用迭代的迭代集合语义**：PHP 在 by-ref `foreach`（D/E：`hits=60`）与 `array_walk`（`visited=180`）中会访问迭代期间追加的元素，AOT 停在迭代开始时的元素集合（`hits=20` / `visited=60`）。按值 `foreach`（探针 B）两侧一致 ⇒ 边界精确在「持引用的迭代」。**新增量级事实（REF-003 §3 F2）**：只追加 3 键（远不到搬迁门限）时 PHP `visited=8` 而 AOT `visited=5` ⇒ 这是**纯集合可见性**缺陷，与桶搬迁无关；而追加 200 键时 AOT 直接 **SIGSEGV（rc=139）**。
2. **发射侧语句丢失**：`ref002_iso_f_break_after_nested_for_tmp` 中，foreach 体内「`if ($hits === 1) { for(...) }` + `if ($hits > 3) { break; }`」**两个臂整块未发射**（PHP `hits=4 count=60`，AOT `hits=20 count=20`）。与引用无关，另立工单 [AOT-CODEGEN-005](AOT-CODEGEN-005-foreach-body-if-arms-lost.md)。

> 触发因子 bisect 探针 `ref002_iso_g_flag_and_break_tmp` / `ref002_iso_h_no_break_tmp` / `ref002_iso_i_no_nested_for_tmp` **已于 2026-09-30 实跑**，并与其余探针（A/B/F/J + 同族 K/L/M/N/O/P/Q/R/S）组成 `fuzzy_scripts_720/tmp/c005_probe_run_tmp.sh` 探针门（共 **16** 个）；当前（RC-1+RC-2+RC-3 二进制 + R-1a/R-1b 模板）实测 `same=16/16 differs=0`，全部与 PHP 真值逐字节等值。引用专属探针 C/D/E 不在该门内，由 `ref002_iso_run_tmp.sh` 单独复测（判据见 §3）。

## 4. 修复方案（优先级 / 影响面 / 落地成本）

| 优先级 | 方案 | 影响面 | 落地成本 |
|---|---|---|---|
| P1 | **R-1a 单行收口 ✅ 已落地（`b21cdfd`，模板 :7988）**：`php_array_iter_value_ref` 返回 `make_ref(value_ptr, runtime_allocator)`。**签名刻意不动**：发射层按函数名 + 单参数形状识别（`ir_generator.zig:2993-3001` 发射 1 参调用，`native_linker.zig:5203`–`:5241` 按同名做引用 alloca 识别（2026-10-03 实测：识别注释 :5203、收集 `php_array_iter_value_ref` 结果寄存器 :5210–:5216、匹配写往 alloca 的 store :5222–:5228、挂上 `current_iter_value_ref_regs` :5240；消费点 :19602 的「引用重绑定不写穿旧引用」判据；原登记 `:5200` 已漂移）），而 `make_ref` 返回值仍是 Ref 形态 `Value`（`runtime_lib_template.zig:3067` 的 `return Value.initRef(cell);`，函数定义同文件 :3055；原记 `:3067` 未标文件）⇒ 零发射侧改动、零基线漂移。**未一并做**：`php_array_iter_init_ref` 的 `has_active_refs` + `convertToMixed`（:7893-7899）锚定移除属次生收益，需单独门后再动 | 纯模板；foreach by-ref 全部改持稳定单元 | 实测 +4 行（含 3 行 WHY 注释）+ 全量回归，已全绿 |
| P1 | **R-1b 同法 ✅ 已落地（`b21cdfd`，模板 :25569）**：`php_array_walk` 的 `args_buf[0]` 改 `make_ref(@constCast(entry.value_ptr), allocator)`（`allocator` 用该函数形参，无需全局）。**判据缺口**：现有探针不能证成它（见 §5-1），须另建隔离探针补取证 | 纯模板 1 处 | 实测 +3 行（含 2 行 WHY 注释） |
| P1 | **R-3**：`ArrayIterator` 不缓存 `Entry`，每次 `current` 消费改为按 key 重新 `getPtr` 或缓存 key-only | 迭代器读写 3 个消费点 | 低中；注意 `Elements.Iterator` 与 `mixed` 双形态 |
| P2 | **R-4**：清零改 `-= 1` | 1 处 | 极低，但改释放时机，必须与 R-1/R-3 同批验证 |
| P2 | **R-5**：`val_deref` 补链长上限，与 `derefVal` 对称 | 1 函数（全站引用读写都走它） | 极低；上限语义为「断链后写回自身槽」，需在文档明确 |
| P2 | **R-6**：先量化（`=&` 循环压测取 `memory_get_usage` 与 RSS 斜率），不可接受再引入 `RefCell{ Value, ref_count }` 并统一 `asRef()` 出口（34 处站点） | 引用的整个生命周期 | 中高；建议在 D1 之后排 |
| 待裁决 | **R-2**：`php_object_get_ref` 属 D1 的配套设施，单独修无意义（无调用方） | — | 与 D1 同批 |

## 5. 验收门（沿用 AOT-REF-001 §7，全绿方可收口）

1. ~~新增探针 `ref_iter_slot_stale_probe_tmp` 与 PHP 真值逐字节等值~~ ⇒ **本项未达成，且已判定该探针不构成 R-1b 判据**（其残留差由 §3.1 的两条非引用问题解释：持引用迭代的元素集合语义 + 回调内 COW 换代）。
   **区分力实证已完成（2026-09-30，`fuzzy_scripts_720/tmp/ref002_r1b_prepost_tmp.sh`：pre = `git show b21cdfd^:` 模板，post = 工作区模板，结束 md5 校验还原）**：
   - 新建隔离探针 `ref002_r1b_isolated_tmp.php`（X1 回调内 `use (&$b)` 追加 40 键后写 `&$val`；X2 经 `$r = &$c` 引用单元追加；X3 只写不追加。判据刻意只看写回值、不打印 visited/count ⇒ 与 §3.1 两条解耦）。结果：PHP `X1 k1=4242 / X2 k1=5566 / X3 d4=400`，AOT `X1 k1=1 / X2 k1=1 / X3 d4=400`，且 **pre 与 post 逐字节相同**。
   - 同一方法在探针 E 上给出 `pre k1=1` → `post k1=888` ⇒ **方法具备区分力**，上述「pre/post 相同」是真结论而非方法失效。
   - **结论**：R-1b 改动的**可观测面当前为零** —— 在 AOT 里，回调内对被遍历容器的追加会先经过容器换代（`$b` 指向新容器，walk 仍在旧容器推进），因此「同一容器搬迁、旧槽地址悬垂」这一 R-1b 打击点根本到不了 ⇒ R-1b 与 R-2 同类，属**当前不可达的正向加固**（保留改动，零回归零漂移已证）。**复测前置**：须待 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) 的换代/live-set 缺陷收口后再取判据。
   **实际采用的 R-1a 收口判据（已被 pre/post 独立证实）**：① 探针 E `k1` 由 `1` 变 `888`；② 探针 C（`array_walk` 无扩容）保持 IDENTICAL 不回退；③ 全门零回归零漂移；
2. 4 个 AOT-REF-001 探针结论不回退（D2 探针必须继续 IDENTICAL）；
3. `scripts/regression_test_720.sh`：FAIL_DIFF=0 / SKIP=1（f004）；
4. 纯模板改动 ⇒ 72 项冻结基线抽查 `ok=5 bad=0`（发射零漂移）；
5. `f12_determinism_tmp.sh`：`total=68 mismatch=0 notemp=0`；
6. 批次期间禁止编辑模板、禁止 `zig build`、禁止并发编译；复测前排查 PPID=1 孤儿进程。

## 6. 风险评估

- **破坏性**：R-1a/R-1b 为纯模板、向 PHP 语义收敛，非破坏式；但 foreach by-ref 改持 cell 后，「迭代期间数组增长」的可见元素集合语义需与 PHP 对齐（PHP 对 by-ref foreach 期间的追加有明确行为），需探针逐项验证。
- **性能（已由永久微基准探针 `fuzzy_scripts_720/tmp/ref002_r1a_perf_tmp.php` 实测，200k 元素、同进程先后跑 by-value 与 by-ref 两条路径，3 次取区间）**：
  - **ReleaseFast**：by-value 10.8–12.1ms → by-ref 23.1–23.7ms，比值 **1.96–2.15x**，净增 ≈**12.4ms / 200k ≈ 62ns/轮**。
  - **ReleaseSmall**（`--compile` 默认档，小脚本）：by-value 36.4–37.2ms → by-ref 55.5–56.0ms，比值 1.49–1.54x。
  - **PHP 8.5.8 同探针**：by-value 1.347ms / by-ref 3.690ms（比值 2.74x）。
  - 归因口径：by-ref 相对 by-value 的增量含「每轮 cell 分配（槽已是 Ref 时走 `make_ref` :3057-3059 复用分支不增）」+「读侧 `val_deref`」+「迭代起始 `has_active_refs`/`convertToMixed` 锚形态」三项的**聚合**成本，本轮**未做分项归因**；换到的是 UAF 写丢失的消除（探针 E `k1` 由 `1` 变 `888`）。
  - 注意：AOT 该微基准的**绝对值**显著高于 PHP（by-value 10.8ms vs 1.35ms，ReleaseFast），属**既有** foreach 装箱/查表特征，**非本改动引入**；定性前须先固定 PHP 侧 opcache/JIT 前提，勿据此立项。
- **不可达项**：R-2 当前发射不可达，单独修复不改变任何可观测行为，收益为零、风险为正，应与 D1 合并。

## 7. 待裁决

1. ~~是否把 R-1a + R-1b（各 1 行）并入下一批~~ ⇒ **已闭环**（用户「继续推进已知问题的修复」授权，2026-09-30 与 CODEGEN-005 RC-3 合并进提交 `b21cdfd`，全门零回归零漂移）；
2. R-3/R-4（迭代器缓存与锁计数）是否同批——它们改的是**释放时机**，回归面比 R-1 大；
3. R-6 是先量化再决策，还是直接上 `RefCell`（后者动 34 处 `asRef()` 站点，属结构性改造）。**起点已备好**：R-1a 的每轮装槽成本已由 `ref002_r1a_perf_tmp.php` 实测（ReleaseFast ≈ +62ns/轮），R-6 的压测只需在此探针上加 `memory_get_usage` / RSS 斜率即可判定上界是否可接受。

## 8. 锚点代次刷新（2026-10-05，当前工作区代次 `fbe6382a`／32797 行实测；只读巡检，零代码改动）

§P1 行内登记的 `native_linker.zig` 发射层识别块锚点属 **2026-10-03** 代次，其后 A／D／R9-B 三批（`497edc6`）与 #74 注释批插行 ⇒ 已漂移。**模板侧与 IR 侧逐字未漂移**，故 R-1a/R-1b 的落地行号无需改写。按符号 grep 实测（非偏移推算）：

| 锚点 | 旧登记（2026-10-03） | **当前树实测** | 实测依据（该行内容） |
|---|---|---|---|
| 识别块整体 | `native_linker.zig:5203`–`:5241` | **`:5446`–`:5484`** | 块首行注释 `// 检测 foreach 引用变量的 alloca（php_array_iter_value_ref → store 模式）` |
| 第一遍：收集结果寄存器 | `:5210`–`:5216` | **`:5453`–`:5459`** | `:5453` 为「第一遍」注释，`:5457` = `inst_scan.op.call.func_name == "php_array_iter_value_ref"` 判据 |
| 第二遍：匹配写往 alloca 的 store | `:5222`–`:5228` | **`:5465`–`:5473`** | `:5465` 为「第二遍」注释，`:5471–:5473` = `iter_value_ref_regs.contains(store_op.value.id)` ∧ `alloca_registers.contains(store_op.ptr.id)` ⇒ `foreach_ref_allocas.put(...)` |
| 挂 `current_iter_value_ref_regs` | `:5240` | **`:5483`**（同块内 `current_foreach_ref_allocas` 挂载在 `:5481`，两处 `defer` 复位 `:5482`/`:5484`） | `self.current_iter_value_ref_regs = &iter_value_ref_regs;` |
| 消费点（引用重绑定不写穿旧引用判据） | `:19602` | **`:19907`** | 该行注释即「如果 value 来自 php_array_iter_value_ref，是引用重绑定，不写穿旧引用」 |
| R-1a 落地行（`make_ref` 装槽） | `runtime_lib_template.zig:7988` | **`:7988`（未变）** | `return try make_ref(value_ptr, runtime_allocator);`；同文件 `:7974` 为函数头 `php_array_iter_value_ref` |
| R-1b 落地行 | `runtime_lib_template.zig:25569` | **`:25569`（未变）** | `args_buf[0] = try make_ref(@constCast(entry.value_ptr), allocator);`；函数头 `php_array_walk` 在 `:25549` |
| R-1a 发射形态（单参数调用） | `ir_generator.zig:2993`–`:3001` | **未变**（`:2997` = `if (foreach_data.value_by_ref) "php_array_iter_value_ref" else "php_array_iter_value"`） | `runtime_lib_template.zig` 最后提交 `b21cdfd`（2026-09-30）、`ir_generator.zig` 最后提交 `9b2ddf5`（2026-08-25），两文件工作区干净 ⇒ 其后各批未触碰 |

⇒ 「R-1a 有效、R-1b 当前不可达」的收口判定与「判据缺口须另建隔离探针」的待办均不依赖发射侧行号，**状态维持**；本轮刷新只影响将来复测时 `native_linker.zig` 侧的定位成本（识别块与消费点各 1 处）。
