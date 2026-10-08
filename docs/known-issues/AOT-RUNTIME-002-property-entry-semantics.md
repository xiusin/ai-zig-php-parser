# AOT-RUNTIME-002 · 属性入口语义四组偏差：实例侧三组（readonly/强转消息用实例类名、越权 `private` 未回退「不可见即不存在」、强转失败把 `TypeError` 对象写进 typed 槽）+ 静态入口族 G4（零类型校验、未初始化无表示、可见性 fail-open、消息类名反向、存储按类名分槽、动态类名限定双环 = IR 写侧缺 `$` 分支 + 模板动态读侧拒对象）

**问题 ID**: AOT-RUNTIME-002
**优先级**: P1（**P0 三项**：G3 = 声明为 `int` 的属性槽里可以是异常对象；G4-a = typed 静态属性错型写全程静默；G4-e = 子类名/`static::` 的静态写对声明类不可见 ⇒ LSB 计数器静默错值；G1/G2/G4-b/c/d 为消息/告警/可见性面）
**性质**: 运行时侧为主（`src/aot/runtime_lib_template.zig` 属性写入/读取入口）；**G4-c 成因在发射侧**（`native_linker.zig:24249-24252` 的 scope 注入）⇒ 不能只靠模板收口；**G4-f 成因已由任务 #117 实测更正为「IR 生成侧 + 模板侧」两处**（`ir_generator.zig` 七处写/引用源站点缺 `$` 前缀分支 ⇒ 交出字面 `"$cls"`；`php_get_static_property_dynamic:20200` 的对象入参支缺）⇒ 原先「`native_linker.zig` 写侧动态类名 helper 缺失」的措辞不精确，`ClassNotFound` 的制造者是 **IR 站点**而非发射器
**状态**: **OPEN（实例侧三组逐形实测；G3 机制已于任务 #115 取证到行（§3 G3 四步链 + 5/5 侧门复现）；静态入口族 G4 已由任务 #116 逐形实测（侧门 C 9 形 + 2 枚替身探针），并否证了「静态侧同形 G3」的预期；G4-f 已由任务 #117 归因到行（侧门 D 9 形 + 生成码实参字面量通道 ⇒ 双成因见 §3 G4-f 节，「parser 把变量名当类名」候选已否证）；修复涉及语义改动 + 消息文本变更 + 发射侧 scope 形态，按宪法 §六 待老铁裁决，未动一字节源码）**
**发现日期**: 2026-10-07（任务 #114，语料 `f004_oop_deep_inheritance_magic.php` 被官方回归 SKIP 后的覆盖回收；G4 于同日晚些由 #116 按 §7 第 2 项立族）
**触发档**: 默认档（`--compile --no-debug-info`），无需抬档

**代次锚点（本轮实测，非记忆）**

| 资产 | md5 | 行数 |
|---|---|---|
| `zig-out/bin/php-interpreter` | `1f15e4ce9b5c9cdaaef7cabf5efb9c76` | — |
| `src/aot/runtime_lib_template.zig` | `008b7b639f1069cb73e443064e115ed1` | 30810 |
| `src/aot/native_linker.zig` | `fbe6382a2e0904b6740d771b88c409c7` | 32797 |
| `src/aot/ir_generator.zig`（G4-f 的 6 处 `.static_property_set` 发射站点 + 1 处引用赋值源站点所在文件，任务 #116 实测代次、#117 逐站点归因于同代次） | `cb53c2da7d4fe2e1f62b728511f7c3ea` | 9732 |
| `fuzzy_scripts_720/tmp/f004_ro_unser_tmp.php` | `672c82ed3addba063c8032863b64a4e6` | 237 |
| `fuzzy_scripts_720/tmp/runtime002_isolation_tmp.tsv`（本工单主门读数） | 门尾行 `RT002_DONE shapes=12 same=3 diff=9` | `ELAPSED=58s` |
| `fuzzy_scripts_720/tmp/rt002_g3_probe_tmp.tsv`（G3 侧门 A 读数，任务 #115） | 门尾行 `G3PROBE_DONE shapes=5 same=0 diff=5 polluted=5 compile_fail=0` | `ELAPSED=25s` |
| `fuzzy_scripts_720/tmp/rt002_g3_uninit_tmp.tsv`（G3 侧门 B 读数，任务 #115） | 门尾行 `G3UNINIT_DONE shapes=2 same=1 diff=1 state_lost=1 compile_fail=0` | `ELAPSED=10s` |
| `fuzzy_scripts_720/tmp/rt002_static_entry_gate_tmp.sh`（静态入口侧门 C，任务 #116 新立） | `884626b931f7fe390470384ca41c4319`（首跑为 `7c04989803aeea5ffe57b97bad8c8b4e`；随后仅修订头部注释措辞、零逻辑改动 ⇒ md5 移动） | 145（首跑 141） |
| `fuzzy_scripts_720/tmp/rt002_static_entry_tmp.tsv`（侧门 C 读数，任务 #116） | 门尾行 `STATENTRY_DONE shapes=9 same=1 diff=8 protect_lost=5 compile_fail=0`；**跨 run 自证**：头部注释修订后复跑，9 形逐字节读数与首跑全等 | `ELAPSED=42s`（首跑）/ `44s`（复跑）⇒ 4.7 s/形 |
| `fuzzy_scripts_720/tmp/st_lsb_alias_probe_tmp.php`（LSB 替身探针 ①，静态方法形） | `4d39b7245199cb6deaa033c7ef080a63` | 28 |
| `fuzzy_scripts_720/tmp/st_lsb_ctor_probe_tmp.php`（LSB 替身探针 ②，**f004 原形**：提升构造器内 `static::$entityCount++`） | `5572775a8baf481f8d91937e75fcab82` | 26 |
| `fuzzy_scripts_720/tmp/rt002_dynname_gate_tmp.sh`（动态类名侧门 D，任务 #117 新立；除等值比对外**额外单列 `emit` 列** = 生成码中 `php_(get|set)_static_property(_dynamic)?(` 调用行的**实参字面量** ⇒ 零插桩拿到「IR 交出的类名到底是什么」） | `62ec8bac5e13c45a5b73533ee9c3dced` | 142 |
| `fuzzy_scripts_720/tmp/rt002_dynname_tmp.tsv`（侧门 D 读数，任务 #117） | 门尾行 `DYNNAME_DONE shapes=9 same=4 diff=5 cnotfound_fatal=5 compile_fail=0`；**跨 run 自证**：头部注释修订后复跑，9 形逐字节读数与首跑全等 | `ELAPSED=35s`（首跑）/ `35s`（复跑）⇒ 3.9 s/形 |
| `fuzzy_scripts_720/tmp/st_dyn_write_probe_tmp.php`（跨模式替身探针：同一形在 PHP / AOT / 解释器模式三侧对照，本轮**只测不改**非 AOT 侧，见 §7-13） | `ca956602d75e3f1269bd0911b80a86e4` | 19 |

---

## 1. 为什么必须另建一张门（口径，勿删）

替身探针 `f004_ro_unser_tmp.php` 用 `$argv[1]` + `if/elseif` 链派发 12 形。该链的生成码直读证明其本身落入 **AOT-CODEGEN-008 第二面**（详见该工单 §3B，逐行发射计数实测）：

- 源 `:220`/`:222`/`:224` 三条 `elseif` 条件**发射指令数 = 0** ⇒ `type_inherit`/`type_self`/`dyn_ro` 三形根本不可命中；
- 源 `:234`（链后 `echo "DONE\n"`）**整段零发射**（`"DONE\n"` 全文件仅 3 处引用，挂在 `:178`/`:190`/`:196`）⇒ 该族九形 AOT 一律无 `DONE`。

⇒ 在这张探针上量到的 DIFF 里，**「缺 `DONE`」「缺异常消息整行」不能算属性语义偏差**。故本轮另建 **C008-free 隔离门**：每形一个独立 PHP 文件、纯直线语句、**不含任何 `if/elseif` 链**，由门脚本自带 prelude 现场生成到 `mktemp` 目录（不新增常驻 `.php` 资产）。

隔离门文件：`fuzzy_scripts_720/tmp/rt002_isolation_gate_tmp.sh` → 读数 `fuzzy_scripts_720/tmp/runtime002_isolation_tmp.tsv`。
隔离门有效性自证：**12 形两侧都输出 `DONE`**（`fatal_ro` 形按 PHP 语义在 `DONE` 前终止，两侧一致）⇒ CODEGEN-008 无法介入，剩下的 DIFF 全是运行时语义面。

| 通道 | shapes | SAME | DIFF | 成本（实测） |
|---|---|---|---|---|
| 替身探针（链派发，含 C008 干扰） | 12 | 2（`valid`/`ro_ok`） | 10 | `ELAPSED=14s`（1 次编译 + 24 次运行） |
| **隔离门（直线语句，C008-free）** | 12 | **3** | **9** | `ELAPSED=58s`（12 次编译 + 24 次运行） |

---

## 2. 隔离门实测矩阵（12 形，逐字节判据 = 归一化合并 stdout+stderr）

| 形 | 语句 | PHP 真值 | AOT | 判读 | 分组 |
|---|---|---|---|---|---|
| `priv_read` | `$c->secret`（继承来的 `private string`，越权读） | `PHP Warning:` + `Warning:` 两行 `Undefined property: MChild::$secret` ⇒ `read=null` ⇒ `NO_ERROR` | `Error: Cannot access private property MChild::$secret` | **DIFF** | **G2** |
| `priv_write` | `$c->secret = "X"`（越权写） | `PHP Deprecated:` + `Deprecated:` 两行 `Creation of dynamic property MChild::$secret` ⇒ `NO_ERROR`（动态属性写入成功） | `Error: Cannot access private property MChild::$secret` | **DIFF** | **G2** |
| `prot_read` | `$c->limit`（继承来的 `protected int`，越权读） | `Error: Cannot access protected property MChild::$limit` | 同文本 | **SAME** | 控制臂 |
| `ro_write_same_scope` | `$c->limit = 9`（越权写 protected，未捕获） | `PHP Fatal error: Uncaught Error: Cannot access protected property MChild::$limit`，rc=255 | 同文本，rc=255 | **SAME** | 控制臂 |
| `type_inherit` | `$c->total = "str"`（继承来的 `public int`） | `TypeError: Cannot assign string to property **MBase**::$total of type int` | `... to property **MChild**::$total ...` | **DIFF** | **G1** |
| `type_self` | `$c->count = "str"`（本类 `public int`） | `TypeError: ... MChild::$count of type int` | 同文本 | **SAME** | 控制臂 |
| `dyn_ro` | `$k="uuid"; $c->$k = "X2"`（动态名写 readonly） | `Error: Cannot modify readonly property **MBase**::$uuid` | `... **MChild**::$uuid` | **DIFF** | **G1** |
| `val_dyn` | 同 `dyn_ro` + 回读槽 | `... MBase::$uuid` + `slot='U001' type=string` | `... MChild::$uuid` + **槽值两侧相同** | **DIFF（仅消息）** | **G1** |
| `val_self` | `$c->count = "str"` + 回读槽 | `TypeError: ... MChild::$count ...` + `slot=0 type=integer` | 消息 **SAME**，但 `slot=\TypeError::__set_state(array('file'=>...,'line'=>50,'message'=>'Cannot assign string to property MChild::$count of type int',)) type=object` | **DIFF** | **G3** |
| `val_tinherit` | `$c->total = "str"` + 回读槽 | `TypeError: ... MBase::$total ...` + `slot=0 type=integer` | 消息类名错（`MChild`）**且**槽内为 `\TypeError` 对象（`type=object`） | **DIFF** | **G1 + G3** |
| `fatal_ro` | `BUser::__unserialize` → `parent::__unserialize` 内写 `readonly`（f004 原违规） | `PHP Fatal error: Uncaught Error: Cannot modify readonly property **BBase**::$uuid`，rc=255 | `... **BUser**::$uuid`，rc=255 | **DIFF** | **G1** |
| `class_const` | `MChild::class` / `$c::class` / `self::`+`static::`+`parent::` | `lit=MChild`、`var=MChild`、`scope=self=MChild static=MChild parent=MBase` | `lit=MChild`、**`var=`（空串）**、**`parent=parent`** | **DIFF** | **另立 → AOT-CODEGEN-009**（发射侧，不属本单） |

**同形对照（`valid`/`ro_ok`，替身探针链派发但仍两侧 SAME 的正向面）**：深继承链 `__serialize`/`__unserialize` 回填、`final` 方法、按类 `static::$entityCount` 晚期静态绑定计数、`__toString`+`sprintf`+`implode`、`json_encode` 嵌套数组 —— **AOT 与 PHP 逐字节等值**。⇒ 本单不涉及序列化语义，readonly 的「禁止二次写」本身也被正确强制（只是消息里的类名归属错）。

---

## 3. 三组偏差的锚点（本轮 `grep` 实文核对，行号为当代次）

### G1 · 消息类名归属：应为**声明类**，实为**实例类**（4 处）

入口 = `php_object_set_dynamic`（`src/aot/runtime_lib_template.zig:19304`）与 `php_object_set`（`:19433`）。两处结构对称，都在 `findPropertyDeclaringClass(meta, ...) -> decl` 之后用 `meta.name`（实例类元名）而非 `decl.class.name`（声明类名）：

| 站点 | 当前实文（实测） | PHP 真值口径 |
|---|---|---|
| `:19331` | `"Cannot modify readonly property {s}::${s}", .{ meta.name, name }` | 声明类（`fatal_ro`/`dyn_ro` 实测） |
| `:19457` | `"Cannot modify readonly property {s}::${s}", .{ meta.name, property_name }` | 声明类 |
| `:19335` | `try coercePropertyType(decl.prop, value, meta.name)` | 声明类（`type_inherit` 实测） |
| `:19461` | `try coercePropertyType(decl.prop, value, meta.name)` | 声明类 |

`coercePropertyType`（`:18902`）把 `class_name` 参数原样填进全部 16 条（复验口径：段内 `grep -c "to property"` 于 `:18902`–`:19125` = 16） `Cannot assign ... to property {s}::${s} of type ...` 消息（`:18914`/`:18924`/`:18934`/`:18960`/`:18968`/`:19012`/`:19024`/`:19032`/`:19043`/`:19050`/`:19062`/`:19071`/`:19079`/`:19087`/`:19108`/`:19114`）⇒ 入参改一处即全族生效，**消息构造点本身无需逐条改**。

**反证（必须保留，不得顺手改）**：可见性 `Cannot access {private|protected} property` 消息 PHP 用的是**实例类**。实测三条控制臂 `prot_read`（`:19145`）、`ro_write_same_scope`、`type_self` 全部 SAME ⇒ `:19145`/`:19187`/`:19232`/`:19271`/`:19325`/`:19451` 六处（读侧 `php_object_get`/`php_object_get_ref` 等 + 写侧两处 access 分支）**一律不许改成 `decl.class.name`**。本单立项前曾假设「七处可见性站点都要改」，该假设已被 `prot_read` 实测否证。

另注：`:20342`/`:20388` 两处 access 消息已在用 `decl.class.name`（另一入口，本门未覆盖），属**未判定面**，落地前需单独探针。

### G2 · 越权 `private` 未回退「不可见即不存在」

PHP 8.3 实测口径分裂，且 AOT 两侧都只有一条 `Error`：

| 操作 | PHP 真值 | AOT |
|---|---|---|
| 越权**读** `private`（无 `__get`） | `Warning: Undefined property: <实例类>::$p`（stderr + stdout 两行）→ 值 `null` → **不抛** | `Error: Cannot access private property ...`（抛） |
| 越权**写** `private`（无 `__set`） | `Deprecated: Creation of dynamic property <实例类>::$p`（两行）→ **写入动态属性成功** → 不抛 | `Error: Cannot access private property ...`（抛） |
| 越权读/写 `protected` | `Error: Cannot access protected property ...`（抛） | 同文本（SAME） |

缺失能力实测：`grep -n 'Undefined property' src/aot/runtime_lib_template.zig` 与 `grep -n 'Creation of dynamic property' src/aot/*.zig` **均 0 命中** ⇒ 这两条消息在 AOT 运行库里根本不存在，不是「措辞不同」而是「整条语义支路缺失」。
可复用先例（本轮实文核对）：`emitWarning(msg)`（`:5811`）已按 PHP 双通道输出 `PHP Warning:  {msg} in {file} on line {n}` 到 stderr、`\nWarning: {msg} in {file} on line {n}` 到 stdout，并带 `isErrorSuppressed()` 与 `@` 抑制；Deprecated 双行先例见 `:5832`（`emitDeprecatedStrGetcsvEscape`）与 `:6255`（`emitDeprecatedFloatToInt`）。

### G3 · 强转失败把 `TypeError` 对象写进 typed 槽（不变量破坏，最重）

`val_self`/`val_tinherit` 实测：PHP 侧异常抛出后槽内仍是**旧值/声明默认值**（`slot=0 type=integer`）；AOT 侧异常同样被上层 `catch` 拿到（消息文本正确），但随后回读该 `public int` 属性得到的是 **`\TypeError` 对象本身**（`var_export` 展开为 `__set_state(array('file'=>...,'line'=>50,'message'=>...))`，`gettype()=object`）。

后果：声明类型约束在运行时被静默破坏，之后任何对该属性的读/算术/序列化都会拿到一个异常对象（而非 `int`），且不会再报错。

**机制已取证到行**（任务 #115，2026-10-07；零插桩只读实文 + 独立侧门实测，**未动用 `-ODebug` 通道**）。四步链条，每步都是当代次实文：

| # | 站点（实文） | 作用 |
|---|---|---|
| ① | `coercePropertyType`（`:18902`）的 **16 条失败分支全部**写作 `return throwThrowable("TypeError", msg, runtime_allocator);`（段内实测 `to property` = 16 行 ∧ `throwThrowable("TypeError"` = 16 行，逐一对应：`:18915`/`:18925`/`:18935`/`:18961`/`:18969`/`:19013`/`:19025`/`:19033`/`:19044`/`:19051`/`:19063`/`:19072`/`:19080`/`:19088`/`:19109`/`:19115`） | 交出异常对象作为**返回值** |
| ② | `throwThrowable`（`:20816`）签名是 `!Value`，而它的**成功分支**就是异常对象：`:20821 Value_initObject(obj)` → `:20826 setException(exception)` → `:20827 return exception` | **不返回 Zig error**，只置 pending 标志 + 交出对象 ⇒ ①的 `return` 在 `coercePropertyType` 眼里是「强转成功」 |
| ③ | 两个调用点把该 payload 当强转结果消费并**立刻写槽**：`php_object_set:19461` `const coerced = try coercePropertyType(...)` → `:19462 try obj.setProperty(property_name, coerced)`；`php_object_set_dynamic:19335` → `:19336` | 异常对象进槽的那一行 = **`:19462` / `:19336`** |
| ④ | `PHPObject.setProperty`（`:18495`）内**零类型校验**，且先释放旧值再存新值：`:18524-18526 old_value.release(...)` → `:18529 value.retain()` → `:18532 putProperty(...)` | 旧值既被覆盖又被释放，槽内只剩异常对象，且无任何后续纠错机会 |

**为什么消息文本却是对的**（发射侧实测）：属性赋值的生成码在 `php_object_set` 调用后**确实**带异常守卫 —— `native_linker.zig:23915-23925`（注释原文「属性可见性检查可能抛出 PHP 异常（Error），需要检查并路由到 catch 块」）发射 `if (runtime.hasException()) { ... current_block = <handler>; continue; }`。⇒ 路由没错、时机错：守卫跑在 `:19462` 的存储**之后**，所以「异常被正确抛出 + 槽已脏」同时成立。可变属性名形走通用调用（`ir_generator.zig:4367`/`:4917`/`:5356` 把 `.func_name = "php_object_set_dynamic"`），实测同样污染 ⇒ 任何发射侧守卫都拦不住存储，**修复点只能在模板内 coerce 与 store 之间**。

**三条候选的判决（全部实测/实文，非推断）**

| 候选 | 判决 | 依据 |
|---|---|---|
| 1 · `coercePropertyType` 交出异常 Value，`:19336`/`:19462` 因而写入 | **PROVEN（成立，唯一机制）** | ①②③④ 四步逐行实文 + 侧门 5/5 形复现 |
| 2 · 异常经 `try` 冒泡前，写回发生在 `throwThrowable` 之后的某条兜底路径 | **DISPROVEN（否证）** | `throwThrowable` 根本不走 error 分支（②），故 coerce 边界处**无任何冒泡**；写回是 coerce 的下一条直线语句，不存在「兜底路径」 |
| 3 · `php_set_property` 族另一入口写入 | **DISPROVEN（否证）** | 模板内属性写入入口只有 `php_object_set_dynamic:19304` 与 `php_object_set:19433` 两枚（`grep -n 'pub fn php_object_set\|pub fn php_set_property'` 实测），`grep -n coercePropertyType` 全模板计数 = **3**（定义 `:18902` + 调用者恰好 `:19335`/`:19461`）；读侧四枚入口（`php_object_get:19122`、`php_object_get_ref:19171`、`php_object_get_direct:19203`、`php_object_get_safe_value:19212`，区间 `:19122-19303`）内 `coercePropertyType` 命中 **0** ⇒ 读回不再强转，脏槽无从「被第二次写」 |

**G3 入口 × coerce 分支矩阵（独立侧门实测，`fuzzy_scripts_720/tmp/rt002_g3_probe_run_tmp.sh` → `rt002_g3_probe_tmp.tsv`）**

主门无法覆盖这张矩阵：`val_dyn` 在 readonly 支就 `return`（`:19332`），从未打到 `:19335`。侧门 5 形（纯直线、每形独立编译）实测：

| 形 | 写入入口 | 命中的 coerce 失败分支 | PHP 槽真值 | AOT 槽 | 槽面 |
|---|---|---|---|---|---|
| `g3_set_int` | `php_object_set`（字面名）`:19461→:19462` | `:19025`（string → `int`） | `slot=0 type=integer` | `\TypeError::__set_state(...)` `type=object` | **POLLUTED** |
| `g3_dyn_int` | `php_object_set_dynamic`（可变名）`:19335→:19336` | `:19025` | `slot=0 type=integer` | 同上 | **POLLUTED** |
| `g3_dyn_array` | 同上 `:19335→:19336` | `:19080`（int → `array`） | `slot=array ( ) type=array` | 同上 | **POLLUTED** |
| `g3_set_class` | `php_object_set` `:19461→:19462` | `:19109`（instanceof 失败） | `slot=NULL type=NULL` | 同上 | **POLLUTED** |
| `g3_dyn_null` | `php_object_set_dynamic` `:19335→:19336` | `:1925`（null → 非 nullable） | `slot=0 type=integer` | 同上 | **POLLUTED** |

门尾读数：`G3PROBE_DONE shapes=5 same=0 diff=5 polluted=5 compile_fail=0`，`ELAPSED=25s`（= 5.0 s/形，与主门 58s/12 形 = 4.8 s/形同档）。⇒ **两个入口都脏，四类分支都脏** ⇒ 缺陷不在某个类型分支或某个入口，而在 ② 的「异常对象即成功返回值」这一条共性约定与 ③ 缺少 coerce↔store 之间的守卫。

**G3 的第二重后果（侧门 B 实测，`rt002_g3_uninit_probe_run_tmp.sh`）：污染还会摧毁「未初始化态」本身**

对**无默认值**的 typed 属性做失败的强转写，PHP 的真值是该属性**保持未初始化**，读它即 `Error: Typed property UHolder::$n must not be accessed before initialization`；AOT 读出的是异常对象，且**不再报任何错**。两形对照（同 prelude，唯一差别是有无前置失败写）：

| 形 | 前置 | PHP 真值 | AOT | before_init(php/aot) | 判读 |
|---|---|---|---|---|---|
| `g3_uninit_polluted` | `$k="n"; $c->$k = "str"`（失败写）之后读 | `Error: ... must not be accessed before initialization` | `read=\TypeError::__set_state(...)` ⇒ 无错 | **php=YES / aot=NO** | **DIFF · 状态被摧毁** |
| `g3_uninit_clean`（控制臂） | 无任何前置写，直接读 | 同上 `Error` | **同文本**；`isset=0 propset=1`；随后 `$c->n = 7` ⇒ `read=7` 两侧一致 | php=YES / aot=YES | **SAME** |

门尾读数：`G3UNINIT_DONE shapes=2 same=1 diff=1 state_lost=1 compile_fail=0`，`ELAPSED=10s`（= 5.0 s/形）。

三条推论（都靠这张控制臂对才成立，非推断）：
1. AOT 的「typed 属性未初始化态」**本身实现是对的**（控制臂逐字节等值，含 `isset=0 propset=1` 与 before-initialization 错误）⇒ **R-2 不需要动未初始化态**，修复面仍是 2 处守卫；
2. 未初始化态的丢失**完全由那一次多余写入造成**：AOT 的「未初始化」没有独立表示，而是**用 properties map 里键的缺失**来表达 —— 读侧守卫 `php_object_get:19150-19154`（`if (obj.getPropertyDirect(property_name) == null) → throwThrowable("Error", "Typed property {s}::${s} must not be accessed before initialization")`）。而污染那次写入走了 `setProperty:18532 putProperty(name, value)` ⇒ **键被插入** ⇒ 守卫必然放行，属性从「未初始化」变成「已初始化 = 异常对象」。这是比「槽值不对」更重的一重：它连带废掉了 PHP 的未初始化保护；
3. 两形在污染后都能继续合法赋值（`after_ok=5` / `after_ok=7` 两侧一致）⇒ **没有任何后续站点会察觉**，属彻底静默。

⇒ **R-2 的验收必须同时含侧门 A 与侧门 B**：侧门 A 的 `slot_face` 全 clean + 侧门 B 的 `state_lost=0`（`g3_uninit_polluted` 转 SAME、控制臂必须仍 SAME）。

**本门顺带实测到的新面（登记，属 G1 家族的消息文本面）**：`g3_set_class` 里 nullable 类类型属性的消息，PHP = `Cannot assign GOther to property GHolder::$b of type **?GBase**`，AOT = `of type **GBase**`（`?` 丢失）。是否落在 `type_name` 存的就是去 `?` 的裸类名（即声明侧而非消息侧）——**本轮未取证**，需读属性表构建处才能判。

**修复选型（供裁决，本轮一行代码未改）**

| 方案 | 内容 | 代价与风险（实测口径） |
|---|---|---|
| ①（首选） | 在 `:19335` 与 `:19461` 之后、各自 `setProperty` 之前加「已置 pending 异常 ⇒ 直接返回，不写槽」的守卫（2 处，纯模板） | 零错误模型改动；语义与模板内 6 枚 `_ = try throwThrowable(...)` 丢弃 payload 的既有约定一致。**但**：模板内目前 `hasException()` 使用点为 **0**（唯一命中是 `:17615` 一条注释，说明路由由生成码负责）⇒ ① 会在模板内引入新惯用法，需实文复验不与模板内其余 **31 处**「`return throwThrowable`」（`grep -c` 实测）语义冲突 |
| ② | 改 `coercePropertyType` 的 16 条分支返回真 error | 牵动全模板 `!Value` 错误模型 + 16 处消息构造，覆盖面远大于收益 ⇒ 不建议 |
| ③ | 发射侧把 `:23915-23925` 守卫提前到模板函数内部不可行 ⇒ 只能改发射形态（属性赋值改「先 coerce 再分支写」两句式） | 改 `native_linker.zig` ⇒ **必触发冻结基线漂移** + 全门链复跑；收益与 ① 相同 ⇒ 不建议 |

### G4 · 静态属性入口族（任务 #116 实测；实例侧三组偏差在静态入口**既不同形、又各自更严重**）

侧门 C：`fuzzy_scripts_720/tmp/rt002_static_entry_gate_tmp.sh` → `rt002_static_entry_tmp.tsv`
读数：`STATENTRY_DONE shapes=9 same=1 diff=8 protect_lost=5 compile_fail=0`，`ELAPSED=42s`（= 4.7 s/形）

| 形 | 形状 | PHP 8.5.8 实测 | AOT 实测 | 判据 |
|---|---|---|---|---|
| `st_ok_write`（控制臂） | 合法静态写 + 回读 | `t=integer v=3` | 同文本 | **SAME**（通道本身可用，其余差异非门坏） |
| `st_type_bad` | `STBad::$v = "abc"`（typed int）后回读 | `TypeError: Cannot assign string to property STBad::$v of type int` + `Error: Typed static property STBad::$v must not be accessed before initialization` | `t=string v='abc'`，**无任何消息**，rc=0 | DIFF · 类型强制缺失（G4-a） |
| `st_type_coerce` | `STCoerce::$v = "42"` | 弱模式强转 ⇒ `t=integer v=42` | `t=string v='42'`（静默错型） | DIFF · 强转缺失（G4-a 静默面） |
| `st_uninit_read` | 声明无默认值的 typed 静态属性直接读 | `Error: Typed static property STUn::$s must not be accessed before initialization` | `read=NULL`，无消息 | DIFF · 未初始化态在静态侧**无表示**（G4-b） |
| `st_priv_read` | 全局作用域读声明类自己的 `private static` | `Error: Cannot access private property STPriv::$p` | `p=1` **读到值** | DIFF · 可见性 fail-open（G4-c） |
| `st_priv_write` | 同上写 | 同上 `Error`（写与回读两行皆错） | `p=5` **写成功** | DIFF · 同上，且写入落库 |
| `st_inherit_priv_read` | 以**子类名**读父类 `private static` | `Error: Cannot access private property STPaC::$p`（名 **called class**） | 同前缀但名 `STPa`（**declaring class**） | DIFF · 消息类名归属反了（G4-d）；两侧都报错 ⇒ 本形不计入 `protect_lost` |
| `st_inherit_type_bad` | 以子类名写父类 typed 静态属性 | `TypeError: … property **STTb**::$v of type int`（名 **declaring class**）+ before-init `Error` | 无消息，且随后 `t=NULL v=NULL` | DIFF · G4-a + G4-e 叠加 |
| `st_child_write_alias` | `STAlC::$v = 8`（合法写）后分别按父/子名回读 | `via_parent=integer/8 via_child=integer/8`（**单槽**） | `via_parent=NULL/NULL via_child=integer/8` | DIFF · 静态存储按类名分槽（G4-e） |

两枚永久替身探针（一形一文件，非门，只作对照与 f004 覆盖回收）：

| 探针 | PHP | AOT |
|---|---|---|
| `fuzzy_scripts_720/tmp/st_lsb_alias_probe_tmp.php`（静态方法内 `static::$counter` 自增 + 两种限定符回读） | `self=integer/2 who='LsbChild'` / `static=integer/2` / 父名写 100 后 `child_read=100 parent_read=100` | `self=integer/0 who='none'` / `static=integer/0` / `child_read=2 parent_read=100`，rc=0 |
| `fuzzy_scripts_720/tmp/st_lsb_ctor_probe_tmp.php`（**f004 原形**：提升构造器内 `static::$entityCount++`，3 次实例化后按两种限定符/两个类名读） | `via_static=3 via_self=3` / `child_static=3 child_self=3` / 越权读 protected ⇒ `Error: Cannot access protected property LsbEnt::$entityCount` | `via_static=1 via_self=1` / `child_static=3 child_self=1` / `direct_base=1`（越权读**成功**），rc=0 |

⇒ 同一枚计数器 PHP 报 3、AOT 报 1；`self::` 与 `static::` 在 AOT 里读到**两个不同槽**，PHP 里是**同一个槽**。`f004:2` 的自述意图正是「static属性共享」。

**机制锚点（全部实文核对，行号为当代次 `runtime_lib_template.zig 008b7b63…`/`native_linker.zig fbe6382a…`）**

| 面 | 锚点 | 结论 |
|---|---|---|
| G4-a | `php_set_static_property:20361-20395` 全函数体内**无** `coercePropertyType` 调用（实文核对），直接落 `meta.setStaticProperty:20393` → `ClassMeta.setStaticProperty:17806-17812`（仅 release/retain/put，零类型、零 readonly 守卫） | 实例侧 16 条强转分支与 16 条消息构造在静态侧**一条都不参与**；不是「消息类名错」而是**整段校验缺失** |
| G4-b | 注册期 `native_linker.zig:3394-3414`：**所有**静态属性都发一次 `setStaticProperty`，无默认值时 `else` 支 `:3410-3412` 存 `runtime.Value.initNull()` ⇒ `static_properties` 里**恒有键** | 「键缺失」在静态侧无法表达未初始化 ⇒ 读侧 `:20347-20350` 的 `val == null` 支对已声明属性是死支。对照实例侧 `:18317 if (!prop_def.has_default) continue;`（不存键）⇒ **同一信息（`has_default`）在实例侧被用、在静态侧被忽略**，这就是两侧未初始化语义差异的全部来源 |
| G4-c | 发射侧 `.static_property_get` 的具体类名分支 `native_linker.zig:24249-24252` 用 `ClassContext.init(m, m)` ⇒ scope 被设成**目标类自身**；`checkPropertyAccess:17895-17896` 判 private 的条件正是 `scope.name == declaring_class.name` ⇒ 恒真 | `:20339`/`:20385` 的守卫在「以声明类名访问自己的 private 静态属性」时**必然放行**；只有子类名访问才触发（`st_inherit_priv_read` 实测两侧皆报错）。属**发射侧**成因，不是模板可单独收口 |
| G4-d | `:20342`/`:20388` 用 `decl.class.name`，而 access 消息 PHP 实测名 **called class** | 与实例侧规律**同向**（可见性消息用实例/调用类，类型消息用声明类）；§7 第 2 项原先「静态侧可能该用声明类」的猜测被实测否定方向 |
| G4-e | `setStaticProperty:17811` 落 `self`（解析到的 meta），`getStaticProperty:17815-17829` 只向 `parent`/接口**向上**回退 | 非对称：`父写子读` 可得、`子写父读` 必失 ⇒ 子类名/`static::` 的一切写入对声明类不可见（LSB 计数器静默错值）。修复面 = 写侧把存储目标改为 `findPropertyDeclaringClass:17861-17872` 命中的 `decl.class`（未声明的动态静态属性仍落 `meta`）；读侧无需改 |
| G4-f | 「写侧无动态 helper」仍成立（`grep` 全 `src/aot` 的 `static_property_dynamic` 只命中读侧 `php_get_static_property_dynamic:20198` 及其注册/发射 3 处，写侧 **0 处**），**但这不是 `ClassNotFound` 的直接成因** ⇒ 任务 #117 归因到行为**两条独立环**（详见下一节） | `$c::$v = 6` 与 `$o::$v = 7` 两形实测均**编译成功、运行致命** `error: ClassNotFound` rc=1；侧门 D 把致命面扩到 **5 形**并拿到生成码实参字面量 ⇒ 病根在 **IR 站点**（交出 `"$cls"`/`"$o"`），模板侧另有一枚独立的对象入参缺口 |

**对「静态侧同形 G3」预期的否证（重要，勿按 G3 推 G4）**：G3 的污染依赖「模板把 `throwThrowable` 的异常对象当成功 payload 返回、调用方绑定它」。静态侧两处 `.static_property_*` 站点在调用后**立刻** `hasException()` 路由（读 `:24262-24271`、写 `:24303-24312`），且写侧返回值被 `_ =` 丢弃 ⇒ 异常对象**进不了寄存器**。实测印证：静态侧没有任何形出现「槽里躺着 TypeError 对象」，它的病是**根本不校验**（G4-a）与**分槽**（G4-e）。

**本轮纠正的两条前置假设**
1. 「readonly 静态属性跨类写消息类名」这一形**不存在**：PHP 8.5.8 实测 `class R{public static readonly int $r=7;}` 直接致命 `Static property R::$r cannot be readonly`（且 readonly 属性本就不可带默认值）⇒ 侧门 C 不含 readonly 静态形，勿再按 G1 类比补形。
2. 「AOT 读缺失静态属性会打一条 `ERROR: Property … not found`」不成立：该串与 PHP 的 `Typed static property …` 文本在 KEEP_TEMP 生成产物（`runtime_lib.zig`）中均 **0 命中**；而行为侧的静默 NULL 已由 G4-b 的死支解释。原因归属（死支 / 生成期裁剪）本轮**未取证**，不影响读数。

### G4-f · 动态类名限定静态属性（任务 #117 归因到行：**两条独立环**，修复面 = 三处同动）

侧门 D：`fuzzy_scripts_720/tmp/rt002_dynname_gate_tmp.sh` → `rt002_dynname_tmp.tsv`
读数：`DYNNAME_DONE shapes=9 same=4 diff=5 cnotfound_fatal=5 compile_fail=0`，`ELAPSED=35s`（= 3.9 s/形）
取数通道：门在等值比对外**单列 `emit` 列** —— 读 `KEEP_TEMP` 生成码（`main.zig`）里 `php_(get|set)_static_property(_dynamic)?(` 调用行的**实参字面量**，零插桩即可回答「IR 交给模板的类名到底是什么」。
隔离口径：静态属性一律**不带类型**（`public static $v = 5;`）⇒ 把 G4-f 与 G4-a（零 coerce）/G4-b（未初始化无表示）隔开，本门只测「类名操作数解析」这一面；每形专属类名（静态属性为进程级全局）。

| 形 | 形状 | PHP 8.5.8 | AOT | 生成码 `emit`（实测） | 判据 |
|---|---|---|---|---|---|
| `dyn_read_lit`（控制臂） | `DynA::$v` 字面类名读 | `read=5` | `read=5` | `php_get_static_property("DynA", "v")` | **SAME** ⇒ 门自身可用 |
| `dyn_read_str` | `$cls='DynB'; $cls::$v` | `read=5` | `read=5` | `php_get_static_property_dynamic(&[_]runtime.Value{reg_2, reg_3}, runtime.runtime_allocator)` | **SAME** ⇒ 动态支真的被走到，且读侧交出的操作数**可判别** |
| `dyn_read_paren` | `($cls)::$v` | `read=5` | `read=5` | 同上（仍走 dynamic helper） | **SAME** ⇒ 括号形对 parser 透明 |
| `dyn_read_obj` | `$o = new DynC; $o::$v` | `read=5` | `error: ClassNotFound` rc=1 | **已经**发射 dynamic helper | DIFF · **成因二**（模板侧独立环），与 IR 无关 |
| `dyn_write_lit`（控制臂） | `DynI::$v = 9` 合法写 + 字面名回读 | `via_lit=9` | `via_lit=9` | `php_set_static_property("DynI", "v", reg_0)` | **SAME** ⇒ 写侧合法路径可用 |
| `dyn_write_str` | `$cls::$v = 9` | `via_lit=9` | `error: ClassNotFound` rc=1 | `php_set_static_property("$cls", "v", reg_1)` | DIFF · **成因一**：变量名被当**字面类名**交出 |
| `dyn_write_obj` | `$o::$v = 9` | `via_lit=9` | `error: ClassNotFound` rc=1 | `php_set_static_property("$o", "v", reg_1)` | DIFF · 同上 |
| `dyn_write_paren` | `($cls)::$v = 9` | `via_lit=9` | `error: ClassNotFound` rc=1 | 与 `dyn_write_str` **逐字节同形**（首实参仍是 `"$cls"`） | DIFF · 同上 ⇒ 非 parser 分派差异，纯 IR 站点缺支 |
| `dyn_ref_source` | `$r = &$cls::$v`（引用赋值的**源**侧） | `ref=5 via_lit=3` | `error: ClassNotFound` rc=1 | `php_get_static_property("$cls", "v")` | DIFF · 与写侧**同一个环**（站点缺 `$` 支），并额外压住「引用装槽能否传播回静态槽」 |

**成因一 · IR 写/引用源站点缺 `$` 分支（共 7 处，代次 `ir_generator.zig cb53c2da…` 实文核对）**

| # | 站点（条件首行 → 发射行） | 归一化实文与结论 |
|---|---|---|
| 1 | `:4379` → `:4392` | 只判 `self`（非 trait 时替换为声明类）与 `static`（保留运行时 LSB），**无** `$` 前缀支 ⇒ `"$cls"` 原样进 `.static_property_set` |
| 2 | `:4749` → `:4759` | 同形 |
| 3 | `:4922` → `:4935` | 同形 |
| 4 | `:5361` → `:5372` | 同形 |
| 5 | `:5915` → `:5928` | 同形 |
| 6 | `:6051` → `:6068` | 同形 |
| 7 | 引用赋值源 `:4547`（`:4554` 取名）→ `:4564` `.static_property_get` | 只判 `self`/`static`（`or` 合并），**无** `$` 支 ⇒ 与写侧同构，实测致命面一致 |

现成先例（唯一已补支的站点，勿另起形态）：`generateStaticPropertyAccess:8443` 的 `:8449` 判 `class_name.len > 0 and class_name[0] == '$'` ⇒ `getVarRegister` 命中则 `.load`、否则 `.global_get` 取变量值，配常量属性名，再 `call php_get_static_property_dynamic`（`:8458-8462`）⇒ **七处照该形状补支即可**，DRY 上宜抽公共 helper 而非七份拷贝。

**成因二 · 模板动态入口不接受对象（独立第二环）**：`php_get_static_property_dynamic:20198-20204` 的 `:20200` 实文为 `const class_name = if (args[0].isString()) args[0].asString().data else "";` ⇒ 非字符串入参（对象/整数）坍缩成**空类名**，`findClass("")` 落空 ⇒ `ClassNotFound`。`dyn_read_obj` 实测「helper 已发射但仍死」正是这一环的判据。同一 `else ""` 形状在 `php_get_class_constant_dynamic:20210` **逐字复制** ⇒ 与 **AOT-CODEGEN-009** 的 `class_const` 面同病（不同函数、同一缺口）；PHP 侧 `$o::$v` 的类名应取 `$o` 的**实例类**（`dyn_read_obj` php=`read=5`）。

**否证的前置候选**：`parser.zig:2531-2558`（`.double_colon` 处 `class_name_id` 的 switch 把 `.variable` 分支的 name 直接当类名，只有非变量左节点才落 `.dynamic_static_property_access`）。若该分支是病根，`dyn_read_str` 不可能 SAME ⇒ **否证**；该 switch 交出的实为「保留原始 token 文本（含 `$`）」的可判别的名字，读侧正是靠它工作。

**⇒ 修复面 = 三处同动，缺一无效**：
① 七处 IR 站点补 `$` 前缀支（照 `:8449`）；
② 新增写侧模板入口 `php_set_static_property_dynamic`（实测全 `src/aot` 仅读侧一枚）并在发射侧注册；
③ 把动态入口的 `else ""` 改为按值类型解析类名（读侧 `:20200`；`class_const` 侧 `:20210` 若一并修 ⇒ 与 CODEGEN-009 并批）。
只做 ① ⇒ 对象形仍死于 ②；只做 ②③ ⇒ 写侧与引用源仍死于 ①。


---

## 4. 语料面与风险

| 维度 | 结论 |
|---|---|
| 68 语料面（官方门扫描口径 = `run_regression.sh:9`/`:98`/`:109`，只遍历 `fuzzy_scripts_720/pass/f*.php`）| **声明面在语料内、偏差面为 0**：`readonly` 属性声明本身绿语料就有 —— `f031_builder_fluent_immutable.php:43-48`（6 枚）、`f040_flyweight_forest_pool.php:7-9`（3 枚）（ripgrep 实测），但两枚都只在自身构造器内合法赋值 ⇒ **G1（跨类写 readonly 的消息类名）/ G2（越权 `private`）/ G3（强转失败后槽污染）三个偏差面的可观测命中 = 0**。此前「唯一含这些形的脚本是 f004」的措辞不精确，已按实测收窄为「唯一**触发偏差面**的脚本是 f004，且它被 SKIP」 |
| 语料面 0 的三条可证伪论据 | ① `grep -E 'catch \((TypeError\|Throwable\|Error)' pass/*.php` → **0 命中** ⇒ 没有任何绿语料捕获类型/致命错误，而 G1 的消息文本与 G3 的槽回读都必须先捕获才可能被比对到；② 未捕获即 PHP fatal ⇒ 走 skip-before-compile 被整枚排除（`run_regression.sh:43-49`），语料内唯一 fatal 正是 `f004`（`regression_failures.tsv:1` = `SKIP\|f004_oop_deep_inheritance_magic.php\|PHP_error_exit=255`）；③ 反向印证：G2 在 PHP 侧只是 Warning/Deprecated（rc 仍为 0），若语料内存在越权 `private` 访问，AOT 侧抛 `Error` 必然产出文本差 ⇒ 会是 `FAIL_DIFF`，而报表 `Fail (Diff)=0`/`Pass=67` ⇒ 该面确实为 0 ⇒ 冻结基线对本单三组偏差**零保护力**，修复不触发 `baseline_main_zig_md5.tsv` 漂移 |
| G4 语料面（静态入口，任务 #116 穷举） | **限定符穷举**：`grep -ohE '[A-Za-z_$][A-Za-z0-9_$]*::\$' pass/*.php` 全部命中只有两种限定符 —— `self` **18 处**（f010:80、f025:84/85/91/99、f065:43/49/51/59、f072:11、f163:27/28/109/113/117/127/132）与 `static` **2 处**（f004:12、f004:37）；**字面类名 `Foo::$p` 与动态名 `$c::$p`/`$o::$p` 写形 = 0 处**。⇒ ① `self::` 恒解析到声明类，写读同槽 ⇒ 与 PHP 一致 ⇒ 基线 67/67 绿的**原因被定位**（不是该族无病，是语料没用触发它的限定符）；② 唯一 `static::` 写形在 **f004**，正是官方门 skip-before-compile 排除的那枚脚本 ⇒ G4-e 的语料面 0 **完全依赖 f004 被跳过**，一旦按 §7 流程项把 f004 覆盖回收，枚内计数器即静默错值（替身探针实测 3⇄1）；③ 按判据 3/4：扫描器 0 命中 ≠ 语料 0 命中，且「语料 0」≠「机制不可达」——G4-a/b/c/d/e 全部**机制可达**，任何子类名或 `static::` 写即命中 |
| 机制可达 | 可达：任何「子类实例 + 基类声明的 readonly/typed 属性」即命中 G1；任何越权 `private` 访问即命中 G2；任何强转失败的属性写即命中 G3；任何「子类名/`static::` 写静态属性 + 声明类名或 `self::` 读」即命中 G4-e，任何 typed 静态属性错型写即命中 G4-a |
| 静默性 | G1/G2 仍抛异常或仍输出文本，不静默；**G3 静默破坏类型不变量**（异常被正确抛出，槽却脏了），并且**静默废掉 AOT 自己已实现的未初始化保护**（侧门 B：污染后 `before_init` 从 php=YES 变 aot=NO，而控制臂两侧 SAME ⇒ 除多余写入外无别的原因）⇒ 污染后仍能合法改写，全链路无一处察觉；**G4 比 G3 更静默**：G4-a（错型不报错）、G4-b（未初始化读回 NULL）、G4-e（写进影子槽、声明类读不到）三族**全程 rc=0 且无任何消息**（侧门 C 实测 5 形 `protect_lost`），G4-c 越权读写直接成功；只有 G4-f 不静默（运行致命 `error: ClassNotFound` rc=1；侧门 D 实测致命面 = **5 形**，其中 4 形为写/引用源侧的 `"$cls"`/`"$o"` 字面名、1 形为对象读形 `dyn_read_obj` 的模板环 ⇒ 见 §3 G4-f 节） |
| 假绿风险 | 官方门的 skip-before-compile 会把「PHP 侧就致命的脚本」整枚排除在 AOT 覆盖外 ⇒ 建议另立流程项（§7）。**本风险对 G4 是实打实的**：语料唯一 `static::` 写形就在被 SKIP 的 f004 内 ⇒ 全绿基线对该族零暴露 |
| 修复的破坏面 | G1 只改 4 处入参 ⇒ 消息文本变（对语料 0 命中，但会影响所有历史探针的期望输出）；G2 需新增两条消息 + 一条「声明但不可见 ⇒ 走动态属性」支路，属**语义新增**；G3 已取证 ⇒ 破坏面收敛为 **2 处模板守卫**（`:19335→:19336`、`:19461→:19462` 之间），不改错误模型；另 G3 侧门顺带量到 nullable 类类型消息丢 `?`（PHP `of type ?GBase` vs AOT `of type GBase`），该面**归属未取证**（§7-6）。**G4 按成因分三层**：模板侧（G4-a 补 coerce、G4-b 未初始化表示 + 新消息文本、G4-d 两处消息入参、G4-e 写侧存储目标改 `decl.class`）⇒ 不动基线；发射侧（G4-c 的 `ClassContext.init(m, m)` @`native_linker.zig:24249-24252`）⇒ **触发冻结基线漂移**，须先影子实测覆盖面；新增入口（G4-f 写侧动态类名 helper 与发射支路）⇒ **覆盖面已由任务 #117 实测为「三处同动」**：7 处 IR 站点（`ir_generator.zig:4379/:4749/:4922/:5361/:5915/:6051` 六处写 + `:4547` 引用源）补 `$` 支、新增写侧模板入口 `php_set_static_property_dynamic`、模板动态入口 `:20200`（及同形 `:20210`，属 CODEGEN-009）的 `else ""` 改为按值类型解析 ⇒ 缺一无效；其中 IR 侧改动落在 `ir_generator.zig`（与 R-8 同为编译链上游）⇒ **落地前须按 R-8 口径先影子实测覆盖面**，模板侧两处不动基线 |

---

## 5. 修复路线（优先级 / 影响面 / 落地成本 —— 成本列为「实测」或「未实测」，禁列估算）

| 路线 | 内容 | 优先级 | 影响面 | 落地成本 |
|---|---|---|---|---|
| **R-1** | G1：`:19331`/`:19457` 的 `meta.name` → `decl.class.name`；`:19335`/`:19461` 的 `coercePropertyType(..., meta.name)` → `decl.class.name`（共 4 处，纯模板） | P1 | 只影响 readonly/强转两类消息文本；可见性消息**零改动**（已有三条控制臂实测锁定） | 模板改动 ⇒ 需 `timeout 120 zig build`（实测编译代次移动 ⇒ 冻结编译器 md5 变），基线 `main.zig` md5 **不漂移**；隔离门复跑实测 `58s` |
| **R-2** | G3：**归因轮已由任务 #115 完成**（零插桩只读实文 + `rt002_g3_probe_run_tmp.sh` 侧门 5 形 ⇒ 进槽行 = `:19462`/`:19336`，`-ODebug` 通道未被需要）⇒ 剩余仅为「coerce 与 store 之间加守卫」落地批（§3 G3 修复选型 ①） | **P0**（不变量） | 2 处模板守卫；**不改** `coercePropertyType` 的 `!Value` 错误模型（选型 ② 才会牵动，已否证为首选） | 归因轮实测成本 = 侧门 A `25s` + 侧门 B `10s`（均 5.0 s/形）+ 只读实文核对（零编译）；落地批成本口径与 R-1 同档（模板改动 ⇒ `timeout 120 zig build` + 主门 `58s` + 侧门 A `25s` + 侧门 B `10s`，基线 `main.zig` md5 不漂移）。**硬验收三项**：侧门 A `polluted=0`（且 `same` 只能到 4，`g3_set_class` 的残差属 §7-6）、侧门 B `state_lost=0` 且控制臂 `g3_uninit_clean` **必须仍 SAME**、主门 `val_self` 转 SAME |
| **R-3** | G2：在 `php_object_get`（`:19137-19146`）与写侧（`:19317-19327`/`:19443-19453`）把「`decl` 命中但 `is_private` 且作用域不可见」改为**fallthrough 到未声明分支**：读 → `emitWarning("Undefined property: {meta.name}::${name}")` + `null`；写 → Deprecated 消息 + `obj.setProperty` 动态写入 | P1 | 新增两条消息与一条语义支路；`protected` 支路必须保持抛 `Error`（控制臂已实测） | 需新增 `emitDeprecated`（复用 `:5832` 双行先例）；实测复跑 = 隔离门 `58s` + 全门链 |
| **R-4** | `class_const` 形另案：见 AOT-CODEGEN-009（发射侧 `ir_generator.zig`），**本单不含** | P1 | — | — |
| **R-5** | G4-a：在 `php_set_static_property:20393` 存储之前对 `decl.prop` 走 `coercePropertyType`，消息类名用 **`decl.class.name`**（`st_inherit_type_bad` 实测 PHP 名声明类），失败即不存储 | **P0**（静默错值/错型） | 静态写全链路；与实例侧 R-1（消息类名）/R-2（失败不写槽）**口径同源** ⇒ 三者可并批，但 R-5 是**新增校验**而非改文本，覆盖面大于 R-1 | 纯模板 ⇒ `timeout 120 zig build`，基线 `main.zig` md5 不漂移（语料 0 命中，§4 穷举实测）；复测 = 侧门 C `42s`（实测）+ 主门 `58s`（实测） |
| **R-6** | G4-e：写侧存储目标由 `meta` 改为 `findPropertyDeclaringClass:17861-17872` 命中的 `decl.class`（命中且 `is_static` 时），未声明的动态静态属性仍落 `meta`；读侧保持向上回退不动 | **P0**（数据丢失 + LSB 计数器静默错值；`f004:2` 自述意图即此形） | 一切「子类名 / `static::` 写 + 声明类名 / `self::` 读」；**语料当前靠 f004 被跳过才全绿** ⇒ 与 §7 流程项强耦合，回收 f004 前落地最安全 | 纯模板；实测复跑 = 侧门 C `42s` + 两枚替身探针（各 1 次编译，逐字节对照）；`st_child_write_alias` 与 `st_lsb_*` 为该批硬验收项 |
| **R-7** | G4-d：`:20342`/`:20388` 的 `decl.class.name` → `meta.name`（called class）共 2 处 | P1 | 只影响静态 access 消息文本；`st_inherit_priv_read` 实测锁定期望（`STPaC`） | 纯模板 2 处；复跑侧门 C `42s` |
| **R-8** | G4-c：发射侧 `native_linker.zig:24249-24252` 把 `ClassContext.init(m, m)` 的 scope 改为**调用方真实作用域**（否则 `checkPropertyAccess:17895-17896` 恒真） | P1 | 越权静态读写全族 + 所有依赖该 scope 的静态路径；**成因在发射侧** ⇒ 不可用模板单独收口 | **未实测**（须先影子实测覆盖面：改 scope 会影响 `self::`/`parent::` 解析与语料 18 处 `self::$` 形）；一旦落地 ⇒ 冻结基线漂移 + 全门链复跑 |
| **R-9** | G4-b：静态侧「已声明未初始化」表示缺失 ⇒ 需先把注册期 `native_linker.zig:3410-3412` 的 `initNull()` 预存改为不存键（或引入哨兵），再补 PHP 文本 `Typed static property {s}::${s} must not be accessed before initialization`（生成产物中该串 0 命中，实测） | P2 | 静态读路径 + 注册期发射形态（`:3394-3414` 属 `native_linker.zig`）⇒ 与 R-8 同处发射侧，宜并批评估；类常量亦存于同一 `static_properties` map（`:20219-20222`）⇒ 改「键缺失」语义前必须先核常量/枚举面 | **未实测**（`has_default` 在实例侧已被用 `:18317`、静态侧被忽略 ⇒ 方向可行，但未验证注册支路是否被 `__enum_cases`/`__attributes` 等寄生键共用） |
| **R-10** | G4-f：**归因轮已由任务 #117 完成**（侧门 D 9 形 + `emit` 实参字面量通道 ⇒ 逐站点归属定案，`parser.zig:2531-2558` 候选否证）⇒ 剩余为落地批，且必须**三处同动**：① 7 处 IR 站点（`ir_generator.zig:4379/:4749/:4922/:5361/:5915/:6051` + 引用源 `:4547`）补 `$` 前缀支，形态照读侧 `:8449`（宜抽公共 helper，勿七份拷贝）；② 新增写侧模板入口 `php_set_static_property_dynamic`（对称于读侧 `:20198`）并在发射侧注册；③ 模板动态入口 `:20200` 的 `else ""` 改为按值类型解析类名（对象 ⇒ 实例类），`class_const` 同形 `:20210` 若一并修则与 CODEGEN-009 并批 | P1（非静默：直接致命 ⇒ 不产「假绿」，但属「PHP 合法语法 AOT 不可用」的覆盖缺口；按 §七-8 前半句**禁止以简化脚本绕过**） | 致命面实测 5 形（4 写/引用源 + 1 对象读）；语料面 0（§4 穷举：动态名限定形在 68 语料内 **0 处**）⇒ ① 的分支只对动态名生效，理论上发射中性，**但该中性未影子实测** | 实测复跑 = 侧门 D `35s` / 9 形（= 3.9 s/形）+ `timeout 120 zig build`（②③ 属模板，① 属 IR ⇒ 编译代次移动）。**未实测项**：改动 ① 对语料 `main.zig` 的影子实测（须逐字节确认 68 形不漂移，禁以「语料 0 命中」推定发射中性）；改动 ③ 对 `class_const` 面的连带（属 CODEGEN-009，未定价）。**硬验收**：两条控制臂 `dyn_read_lit`/`dyn_write_lit` **必须始终 SAME**，`dyn_read_str`/`dyn_read_paren` 不得回退，5 枚致命形中 4 枚随 ①+② 转 SAME、`dyn_read_obj` 必须 ③ 才消 ⇒ 只落 ①② 时 `same` 上限为 8 |

**门控声明**：以上任一路线落地前需老铁点头（宪法 §六：语义改动 + 消息文本变更 + 可能新增运行时支路）。`继续推进` 类指令本轮只覆盖取证与登记。

---

## 6. 复测路径（体验流程）

```bash
cd /Users/wangjianjun/products/parser

# 1) C008-free 隔离门（本工单主门；每形独立编译，故耗时 ~1 分钟）
timeout 600 bash fuzzy_scripts_720/tmp/rt002_isolation_gate_tmp.sh
# 当前代次预期：RT002_DONE shapes=12 same=3 diff=9，ELAPSED=58s
# 修复后预期   ：same=11 diff=1（唯一残红 = `class_const`，归 CODEGEN-009；R-1 消 `type_inherit`/`dyn_ro`/`val_dyn`/`fatal_ro`，R-2 消 `val_self`/`val_tinherit`，R-3 消 `priv_read`/`priv_write`）

# 2) G3 入口 × 分支侧门（任务 #115 新立；主门覆盖不到 `php_object_set_dynamic` 的 coerce 支，两门必须同跑）
timeout 300 bash fuzzy_scripts_720/tmp/rt002_g3_probe_run_tmp.sh
# 当前代次预期：G3PROBE_DONE shapes=5 same=0 diff=5 polluted=5 compile_fail=0，ELAPSED=25s
# R-2 修复后预期：same=4 diff=1 polluted=0（除 g3_set_class 外，其余 4 形的差异**只在槽面**：消息两侧逐字节相同 ⇒ 守卫一落地即转 SAME；
#                          `g3_set_class` 必仍红，残差为 nullable 消息丢 `?`（§7-6），与 G3 无关）

# 3) G3 未初始化态侧门 B（控制臂对；R-2 的第二硬验收项）
timeout 200 bash fuzzy_scripts_720/tmp/rt002_g3_uninit_probe_run_tmp.sh
# 当前代次预期：G3UNINIT_DONE shapes=2 same=1 diff=1 state_lost=1，ELAPSED=10s
# R-2 修复后预期：same=2 diff=0 state_lost=0（polluted 形转 SAME；控制臂 g3_uninit_clean 必须仍 SAME ⇒ 它证明修复没碰未初始化态）

# 4) 替身探针（链派发，含 CODEGEN-008 干扰，用于对照，不得单独作验收）
timeout 200 bash fuzzy_scripts_720/tmp/f004_ro_unser_tmp.sh
# 当前代次预期：ROUNSER_DONE shapes=12 same=2 diff=10，ELAPSED=14s

# 5) 静态入口侧门 C（任务 #116 新立；与主门/侧门 A/B 互不重叠；本单门链现为**五门**，须同跑）
timeout 300 bash fuzzy_scripts_720/tmp/rt002_static_entry_gate_tmp.sh
# 当前代次预期：STATENTRY_DONE shapes=9 same=1 diff=8 protect_lost=5，ELAPSED=42s（= 4.7 s/形）
# 修复后预期（按面拆分，勿笼统引用）：
#   R-5（G4-a 补 coerce）单独落地 ⇒ 仅 st_type_coerce 转绿（same=2）；st_type_bad / st_inherit_type_bad
#     只消掉「无 TypeError 消息」这一面，其 before-init `Error` 残差属 G4-b ⇒ 必须等 R-9 才能转 SAME
#   R-6（G4-e 存储归声明类）⇒ st_child_write_alias 转绿，并消掉 st_inherit_type_bad 的 NULL 影子槽残差
#   R-7（G4-d 消息名改 called class）⇒ st_inherit_priv_read 转绿
#   R-5+R-6+R-7 同批 ⇒ same 上限 = 4（control + coerce + child_write + inherit_priv_read）
#   余 5 形：st_priv_read / st_priv_write 需 R-8（发射侧，未定价）；st_uninit_read / st_type_bad /
#   st_inherit_type_bad 需 R-9（未初始化表示 + 新消息文本）⇒ 全部落地才 same=9
#   **控制臂 `st_ok_write` 必须始终 SAME**；`protect_lost` 需 R-5+R-8 才归 0
timeout 120 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/st_lsb_alias_probe_tmp.php   # PHP 真值：self=integer/2 … child_read=100 parent_read=100
timeout 120 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/st_lsb_ctor_probe_tmp.php    # PHP 真值：via_static=3 via_self=3 / child_static=3 child_self=3 / direct_base=Error

# 6) 动态类名侧门 D（任务 #117 新立；除等值外单列 emit 实参字面量 ⇒ 判「IR 交出了什么类名」）
timeout 300 bash fuzzy_scripts_720/tmp/rt002_dynname_gate_tmp.sh
# 当前代次预期：DYNNAME_DONE shapes=9 same=4 diff=5 cnotfound_fatal=5 compile_fail=0，ELAPSED=35s（= 3.9 s/形）
# R-10 分批落地后的按面预期（勿笼统引用）：
#   只补 ①（7 处 IR 站点 `$` 支）⇒ 写侧生成的调用指向**不存在的** `php_set_static_property_dynamic` ⇒ 编译/链接失败
#     （本门 `compile_fail` 由 0 上升）⇒ 这是「三处同动、缺一无效」最硬的实证，勿期待致命面转 SAME
#   ①+②（新增 php_set_static_property_dynamic）⇒ 4 枚写/引用源形转 SAME，same 上限 = 8（`dyn_read_obj` 必仍红，残差属 ③）
#   ①+②+③（动态入口 else "" 改按值类型解析）⇒ same=9，cnotfound_fatal=0
#   **两条控制臂 `dyn_read_lit` / `dyn_write_lit` 必须始终 SAME**；`dyn_read_str` / `dyn_read_paren` 不得因写侧改动回退
timeout 120 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/st_dyn_write_probe_tmp.php   # PHP 真值：via_lit=9 / DONE（rc=0）；跨模式对照读数见 §7-13
```

判读口径：等值 = 归一化合并 stdout+stderr 逐字节（`norm()` 规则见门脚本头部注释）；**exit 码只记录不判等**；消息类名差异单列 `msg_class_diff`，不被 §七-5（栈行号/路径豁免）覆盖。

---

## 7. 遗留 / 待裁决 / 流程项

1. ~~**G3 机制未取证**（§3 G3 三候选）⇒ R-2 的第一批只能是归因轮，不能直接改模板。~~ **已由任务 #115 闭环**：候选 1 = PROVEN、候选 2/3 = DISPROVEN（判据见 §3 G3 表）；进槽行 = `runtime_lib_template.zig:19462`（字面名入口）与 `:19336`（可变名入口），根因在 `throwThrowable:20827` 把异常对象作为**成功返回值**交出；`-ODebug` 归因通道未被需要。⇒ R-2 现在只剩「加 2 处守卫」的落地批（仍待裁决）。
2. ~~`:20342`/`:20388` 已用 `decl.class.name` 的两处 access 消息属**未覆盖入口**，需一张「静态/引用属性读写入口」探针才能判是否同形。~~ **已由任务 #116 闭环**（侧门 C 9 形实测）：静态入口**与实例侧不同形**，且这 2 处消息的归属方向被实测纠正 —— access 消息 PHP 名 **called class**（`st_inherit_priv_read` 实测 php=`STPaC`/aot=`STPa`）⇒ R-7 应改 `meta.name`；type 消息 PHP 名 **declaring class**（`st_inherit_type_bad` 实测 php=`STTb`）⇒ R-5 应传 `decl.class.name`。同轮否证「静态侧同形 G3」（发射侧调用后立刻 `hasException()` 路由 + 写侧返回值 `_ =` 丢弃）。**引用形参绑定面仍开放**（见第 7 项）。
3. `class_const` 面（`$var::class` 空串、`parent::class` 未解析）已另立 **AOT-CODEGEN-009**，含生成码级归因与语料面实测。
4. **流程项（建议，非本单代码）**：官方回归的 skip-before-compile（`run_regression.sh:43-49`）对「PHP 侧就致命」的语料会**整枚丢弃 AOT 覆盖**且报表只计 Skip ⇒ 建议增加「PHP 致命 ⇒ 仍编译 AOT 并只比对致命消息文本」的子档，或至少把 Skip 形逐形拆成永久探针（f004 已按此法回收，见 `f004_ro_unser_tmp.*`）。是否落地需老铁裁决（属测试流程改动，不改编译器）。
5. 替身探针 `f004_ro_unser_tmp.php` 的链派发形已确认受 CODEGEN-008 影响 ⇒ **该文件不可作为 CODEGEN-008 的验收门**（验收用 `c008_chain_tail_gate_tmp.sh`），只作本单 §2 的对照面。
6. **新面（#115 侧门顺带量到，归属未取证）**：nullable 类类型属性的强转消息 AOT 丢 `?` —— PHP `Cannot assign GOther to property GHolder::$b of type **?GBase**` vs AOT `of type **GBase**`（`g3_set_class`，逐字节实测见 `rt002_g3_probe_tmp.tsv`）。待判：是属性表存的 `type_name` 本就去了 `?`（声明侧，`ir_generator`/`native_linker` 构建类元数据处）还是 `coercePropertyType:19108` 拼消息时未带 nullable ⇒ 属 G1 家族消息面，**本单暂不计入 R-1 的 4 处改动**（改了也不消此面）。
7. ~~**未测留口**：无默认值的 typed 属性首次强转失败后……未实测。~~ **已由侧门 B 闭环**（`rt002_g3_uninit_probe_run_tmp.sh`，读数见 §3「G3 的第二重后果」）：PHP 真值 = 属性保持未初始化且读它报 `Error: ... must not be accessed before initialization`；AOT 读出异常对象且**不报错**（`state_lost=1`），而控制臂 `g3_uninit_clean` 两侧逐字节 SAME ⇒ AOT 的未初始化态本身正确，丢失纯由多余写入造成。~~**仍开放**：静态 typed 属性 `:20342`/`:20388` 族~~ ⇒ **该口已由任务 #116 侧门 C 的 `st_uninit_read` 闭环**，但结论与实例侧**不同机制**：静态侧不是「未初始化态被污染摧毁」，而是**从未初始化态根本没有表示**（注册期 `native_linker.zig:3410-3412` 恒存 `initNull()` ⇒ 键恒在、读侧 `:20347-20350` 死支，见 §3 G4-b）。**仍开放（两项）**：① 引用形参绑定到 typed 属性（`forceTypedValue` 族）后回读；② `unset($obj->p)` 后回读未初始化态。两口都需一张「交叉入口 × 未初始化」探针，与 G4 无关。
8. ~~**G4-f 的发射站点逐站点归因未做**（R-10 的前置）~~ **已由任务 #117 闭环**（侧门 D 9 形 + `emit` 实参字面量通道，读数与机制见 §3「G4-f · 动态类名限定静态属性」）：定案为**两条独立环** —— 成因一 = `ir_generator.zig` 的 7 处站点（6 写 `:4379/:4749/:4922/:5361/:5915/:6051` + 引用源 `:4547`）只归一 `self`/`static`、缺 `$` 前缀支，把 `"$cls"`/`"$o"` 当字面类名交出；成因二 = 模板 `php_get_static_property_dynamic:20200` 的 `else ""` 使**对象**入参坍成空类名（`dyn_read_obj` 实测 helper 已正确发射却仍致命）。**否证**了「`parser.zig:2531-2558` 把变量名当类名」这一前置候选；括号形 `($cls)::$v = 9` 与裸变量形生成码**逐字节同形** ⇒ 非分派差异。⇒ R-10 的前置已消，现在只剩「三处同动」的落地批（仍待裁决）。
9. **反射写静态属性的引用计数疑点（新面，本轮只登记、未量化）**：`runtime_lib_template.zig:16894-16895`（`ReflectionProperty::setValue` 的静态支）实测为「新值 `_ = val.retain()` 有、**槽内旧值从未 `release`**、且绕过 setter 直接裸指针覆写 `cmeta.static_properties.getPtr(pname).?.* = val`」⇒ 与同一 map 的唯一正规入口 `ClassMeta.setStaticProperty:17806-17812`（旧值 `old.release(...)` + 新值 `retain()` + `put`）**全套不对称**。按该不对称推：每次反射写静态属性泄漏旧值一枚引用。⚠️ **未过泄漏门量化**（本轮无实测泄漏计数，禁止把「必然泄漏」当已证事实）⇒ 需一张「反射写 × N 次 + `alloc_counters`/泄漏门读数」探针才能定级；属 G4 家族的**内存面**，与 R-5/R-6 的类型/存储面互不重叠。
10. **静态侧未覆盖入口（仍开放）**：① `protected static` 的越权读写（侧门 C 只做了 `private` 两形，`protected` 需「族外作用域 + 兄弟类」才有区分度 ⇒ 尚未取形）；② 引用形参绑定到静态属性；③ `unset()` 后回读。三者与第 7 项的两个交叉入口可用**同一张「交叉入口 × 未初始化/可见性」探针**一次覆盖。
11. **跨工单联动（建议并批裁决）**：G4-f 的「模板动态入口 `else ""`」一支与 **AOT-CODEGEN-009** 的 `php_get_class_constant_dynamic:20210` 是**同一行代码形状的逐字复制**（同一 `isString()` 白名单、同一空串回落）⇒ 本单 R-10 的 ③ 与 CODEGEN-009 的对应面若分两批改，会两次触碰同一函数族；建议老铁裁决时**并成一批**（一次 `timeout 120 zig build` + 两门复跑），代价是验收要同时看侧门 D 与 CODEGEN-009 的门。
12. **探针大小写坑（任务 #117 收窄过程中实测出，已另立 AOT-CODEGEN-010）**：为定位「解释器模式 `var_export(静态属性, true)` panic」而逐臂收窄时，实测到 **PHP 关键字非全小写拼写在 AOT 会分裂出四种结局** —— `Echo`/`ECHO`/`Print` ⇒ **整句静默丢弃**（rc=0、空输出），`RETURN` ⇒ 函数**静默返回空值**，`FUNCTION`/`CLASS` ⇒ 注册落空 ⇒ 运行 `Class/Function not found`，`If`/`NEW`/`FOREACH` ⇒ 编译期 `Parse error`（而 `--compile` **退出码仍为 0 且不产出二进制**），大写 `ELSE` ⇒ **块被无条件执行**（多打一行）；机制锚点 = `lexer.zig:384-402` 把**原始文本**交给 `keyword_lookup.zig:6` 的 `std.StaticStringMap`（大小写敏感，87 枚键全小写）。⇒ 对本单的两条直接影响：① **本单全部探针（门 A–D、替身探针）一律用小写关键字**，故 §3 各表读数**不受该面污染**（已逐行核对）；② 任务 #117 早期把「`Echo $c, "\n";` 的 AOT 空输出」误读为疑似 G4-f 连带面，**现更正**为 CODEGEN-010 的静默丢弃形 ⇒ 与 `::` 类名解析无关。⇒ 该单**已立项、路线待裁决**，见 [AOT-CODEGEN-010](AOT-CODEGEN-010-keyword-case-insensitive-lexer.md)（含永久侧门 E 19 形实测 `shapes=19 same=8 diff=8 silent_empty=3 aot_fatal=3 compile_fail=3`，`ELAPSED=60s`；语料关键字位混合大小写 **0 处**，10 处命中全在字符串字面量内）。
13. **非 AOT 面（按宪法 §五只登记、未修，需老铁裁决是否立单）**：字节码/解释器模式（同一二进制不加 `--compile`）对「**静态属性读取参与字符串拼接（`.`）**」panic —— `thread panic: Stack underflow in popFast`，顶层帧报 `src/bytecode/vm.zig:2322`（`handleConcat`）。四臂收窄实测：`echo "b=" . C::$v` ⇒ panic、`$c = "b=" . C::$v;` ⇒ panic、`$c = "b=" . 5`（普通变量）⇒ **正常**、`echo "b=" . $o->v`（实例属性）⇒ **正常**、`echo "b=", C::$v, "\n"`（逗号形式，无 `.`）⇒ **正常**；`var_export(7, true)` 与 `var_export(C::$v, true)` 的差异**已被更正**为「是否与 `.` 拼接」而非 `var_export` 本身（同一二进制对动态类名形同样 panic ⇒ 与 G4-f 无因果）。⇒ 属解释器/字节码模式独立缺陷，**本单不含**，是否另立工单请老铁裁决。
