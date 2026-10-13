# AOT-CODEGEN-012 · PHP 类名不区分大小写查找缺失：运行期类表精确匹配 ⇒ 跨大小写类使用全灭（new / instanceof / 静态调用 / class_exists / ::常量）；`extends` 与 `::class`/`get_class` 拼写保真已绿

**问题 ID**: AOT-CODEGEN-012
**优先级**: **P1**（合法 PHP 跨大小写类使用即命中；同族缺陷 = AOT-CODEGEN-010 §8 #6 函数名 CI，R-124/R-127 已修）
**性质**: 运行期类表查名（`runtime_lib_template.zig findClass` 精确匹配 + `php_instanceof` 直接名比较）⇒ **仅 AOT**（解释器/字节码的类表为独立实现，本单不涉）
**状态**: **R-1/R-2/R-3/R-131/R-132/R-136/R-137a/R-138/R-141/R-142/R-143/R-144/R-145/R-146/R-147 已落地并验收**（R-138 = 内省枚举族八项落地 + 永久侧门 P 建成，2026-10-12，详见 §12；R-141/142/143 = F-8a 参数默认值面、F-12/F-12b 参数名面，详见 §14–§16；**R-144 = F-5/F-7 PCRE flags/offset 全族收口 + 新立并修复 F-13（`preg_match` 实参 ≥4 时引用装填丢失），详见 §17**）。⚠️ **§10 的 R-137b/R-137c 记录为假阳性**（抛出支从未入库，已由 R-138 重落，更正见 §10 内联与 §12.0）。**门 P 现行读数（R-147 定档）= 59 形 `same=54 diff=5`**，5 枚恰为注册红 `v2/i1/i2/f12/f15`（F-8b／F-3×2／F-18 漏报／**F-21 嵌套异常区域**）；**r10 与 n15 已分别由 R-146／R-145 转绿，f14（F-20 handler 倒灌）由 R-147 转绿**；**n15 = F-1 已于 R-145 转绿**，其守卫移交 F 组 f1…f13（合法性矩阵，全部 PHP 8.5.8 实测）。R-144 轮为 39 形 `same=34 diff=5`（历史快照）；R-138 建成代次为 35 形 `same=31 diff=4`（见 §12.7，仅作历史快照）。**门 S 现行读数（R-144 建成轮）= 47 形 `same=47 diff=0`，判据即 `diff=0`（本门无注册红）**，修复前 30 形 `same=9 diff=21`（§17.1/§17.5）。门 M 19 形 `red=0 green=19`、门 D8 14/14、门 N 7/7、门 O 6/6、门 Q `same=5`、门 R `same=8 diff=1`、普查门 B `diff_impl=3`；`zig build test` 21/21 & 326/326；主回归 08:32:40 **Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 0 / Skip 1**（失败明细仅 1 行 `f004 SKIP` ⇒ 回收枚 0；判据取明细行存在性而非汇总数，见 [[feedback-aot-regression-rules]] 规则 27）；影子 `total=68 same=0 diff=68 miss=0 invalid=0` @1037s，且 **new-side 列相对 R-144 代 `changed_rows=68 / unchanged=0`** ⇒ R-145 因入口守卫进入每个 `main.zig`，**是一次彻底的影子重冻事件**（前缀 `be305cfa` 须在「提交」时按当代次重冻）。**当前代次（R-147 定档）**：`runtime_lib_template.zig` `4ff0befc7c5b50d4fcfb8b1fd1f057e7`（R-147 未变）／`native_linker.zig` `49a3da31660fef4963b8eb50d7587987`（未变）／`ir_generator.zig` `0242d8b5a960a8b8e06b063494f6ec23`（未变）／**`optimizer.zig` `6cffa137f766bdd2a13769c7ba3314b5`（本轮新增守卫）**／二进制 `8b5c65a1f34af70977e73e6c4dea2bd7`（**R-147 改优化器 ⇒ 已重建**，`fec549b26ab4d58f77bfa5316f61445e` 作废）／门 P 脚本 `eab47607d8d4d02979ed17dcdc76bb3b`／门 S 脚本 `f3c2c9e6b1a319cd76a297217212fb54`（未变）；影子 new-side 整列已落盘 `fuzzy_scripts_720/tmp/c010_shadow_newside_r147_tmp.txt`（68 行，表身 md5 `628aa13b3778359d1210c6800901f687`）；原 `3d5c0c8aa86954d389f533c1b1c184e9`（门 P 39/57 形代）；本批中途代次 `0b9cf3a7…`/`d40ee9a9…` 与 R-144 轮 `5c0ecf42…`/`86174723…`、R-145 中途轮 `67a60675…`（模板）与门 P `5904939b…`、R-144 轮 `5c0ecf42…`/`86174723…`、R-138 轮 `b356e19e…` 均作废（见规则 25）。**待裁决**：F-3（门 P 注册红 i1/i2）；F-1 已落地（R-145，§18）、F-2 已落地（R-146，§19）；**F-20（f14，P1，try 前语句异常被无关 catch 吞）已落地（R-147，§20.2–§20.3）＋新立 F-21（f15，同底座：嵌套 try 区域栈缺失，本批只建常驻臂）**＋F-4 去重（删代码，§17.7 记「裸侧未动」的理由）／F-6（`debug_backtrace`）／F-8b（设计分叉，§14.4）／F-10（删功能，登于 013）／**F-13b、F-14、F-15（§17.7）**／**F-16（入口未捕获异常上报，R-145 已修，§18.3）、F-17（trait 名限定的 Deprecated 文本，§18.7）**；F-5/F-7/F-12/F-12b 已落地；**F-11 未登记（编号保留，勿误读为存在该项）**。门 M 终态 **17 形 `red=0 green=17`**（链 XI 同口径全绿：影子 68/68、主回归 Pass 67/Skip 1、门 D8/H/H2/I/E/F/G 注册值保持，2026-10-11 07:05:35 报表）：门 M `red=5→0 green=3→8 compile_fail=0 bad_probe=0 residue=0`（链 VIII 同口径全绿：影子 68/68 零漂移、主回归 Pass 67/Skip 1、门 D8/H/H2/I/E/F/G 与 R-127 代注册值一致；二进制随链 VIII 代 `5c436e9e…` 后续树，runtime 模板不改变解释器二进制 md5）；落地含两处自纠（php_instanceof 重写误删 Throwable 块 ⇒ 补回；伪接口比较 eqlIgnoreCase ⇒ `instanceof stringable` 双拼写 ✅）；变更文档 `docs/changes/2026-10-11/AOT-CODEGEN-012_类名族CI_R128_2026-10-11_fbe6382a.md`
**发现日期**: 2026-10-11（R-127 收尾轮顺带取证；与函数名 CI 同族，PHP 类名本不区分大小写）
**触发档**: 默认档（`--compile --no-debug-info`）

## 1. 取证电池（8 形实测，PHP 8.x vs AOT）

| 形 | 探针 | PHP | AOT | 判定 |
|---|---|---|---|---|
| c1 | `class MyClass { public $v = 7; } new myclass()` | `7` | `Fatal: Class "myclass" not found` | **红** |
| c2 | `new MyClass(); $o instanceof myclass` | `y` | `n` | **红** |
| c3 | `myclass::SM()` 静态方法 | `5` | `Fatal: Class "myclass" not found` | **红** |
| c4 | `class_exists("myclass")` | `y` | `n` | **红** |
| c5 | `myclass::K` 类常量 | `3` | `error: ClassNotFound` | **红** |
| c6 | `myclass::class` | `myclass`（原拼写） | `myclass` | 绿（编译期字面量，**拼写保真守卫**） |
| c7 | `class Child extends base {}`（父类跨大小写） | `2` | `2` | 绿（既有路径已 CI，**守卫**） |
| c8 | `get_class(new MyClass())` | `MyClass`（声明拼写） | `MyClass` | 绿（**拼写保真守卫**） |

## 2. 机制到行（实文核对）

| 锚点 | 结论 |
|---|---|
| `runtime_lib_template.zig:18275 findClass` | `registry.get(name)` **精确匹配**；全运行期类查名的唯一收敛点（grep 实测 **104 调用者**：new 实例化 / instanceof 元数据 / class_exists / 静态调用 lookup_meta（:20303）/ 类常量 / 接口检查 …） |
| `:20006 php_instanceof` | **不走 findClass**：`std.mem.eql(obj.class_name, name)`（:20014）+ `meta.isSubclassOf(name)`/`implementsInterface(name)`（:20018-19）自行精确比较 ⇒ 需单独规范化 |
| `:20303` 静态调用 lookup_meta | `findClass(class_name) orelse throwException("Class ... not found")` ⇒ findClass 折形即覆盖（c3） |
| `:19898 php_class_exists` | `findClass(name) != null` ⇒ 覆盖（c4） |
| extends（c7）绿 | 父类解析走编译期 `resolveClassName` 族（ir_generator），已有 CI 等价路径 ⇒ 不动 |

## 3. 修复路线（同函数族 R-124/R-127 模式）

| 路线 | 内容 | 影响面 |
|---|---|---|
| **R-1** | `findClass` 精确未命中回落 **CI 线性扫描**（命中路径零额外开销；miss 才扫描）；**104 调用者一次性全族受益**（c1/c2 元数据/c3/c4/c5） | 运行期全部类查名（语义 = PHP 对齐；热路径精确命中不触发扫描） |
| **R-2** | `php_instanceof` 前置**规范名解析**：`findClass(name) → meta.name`（未注册则原样）——Throwable/Stringable 伪接口特判不受影响（未注册 ⇒ 原样比较） | instanceof 比较 |

**守卫（不得破坏）**：c6/c8 拼写保真（`::class`/`get_class` 返回声明拼写）；c7 extends 既有绿；`get_declared_classes` 族枚举不受别名污染（CI 回落是查侧、不动注册侧）。

## 6. R-129 复查轮（2026-10-11）：编译期族复查全绿 + 注册侧重复声明校验（R-3）落地

**复查探针（登记复查项收口）**：implements 跨大小写（`4` ✅）、静态属性（`9` ✅）、类类型提示（`6` ✅）、catch 子类（`C` ✅）——编译期族**全绿**（覆盖依据 = findClass CI 回落 + 既有编译期路径）。

**新红面 = 注册侧重复声明无校验**：`class Foo {} class foo {}`（跨大小写）AOT 打 `both`（CI 回落使其成为未定义行为）；`class Dub` 精确双声明 AOT 空输出；PHP 均 `Fatal: Cannot redeclare class`（接口/trait 同族）。

**R-3 落地（同轮三处自纠，均由实测抓回）**：
1. `registerClassWithLocation(meta, file, line)`（新增）：CI 查重 ⇒ PHP 形 Fatal（含 `Stack trace:\n#0 {main}` 块——首轮漏印 ⇒ 门 norm 截断不对称被门 M 扩形抓回）；`{main}` 须转义 `{{main}}`（Zig fmt 占位符陷阱，`too few arguments` 编译错被门 M 5s 全红抓回）。
2. 发射器 **dedup**：完全同名重复声明跳过第二份 meta 构建（`const X_meta` Zig 符号重定义会让编译失败）⇒ 仅发 `registerClassRedeclare(name, file, line)`；跨大小写双声明符号不同 ⇒ 正常双 meta、由运行期 CI 查重 Fatal。
3. **占位覆盖**（主回归 f173 抓回）：内部预注册类（Mutex/Channel/Atomic 族，无 decl_locations 记录）遭用户同名声明时**放行覆盖**（用户优先，R-124 函数侧同款原则）；用户 vs 用户（有位置记录）⇒ Fatal 保持。报报名/prev 位置取**首声明**（PHP 语义）。

**验收**：门 M 扩至 **12 形 `red=0 green=12`**（+d5 跨大小写双类/d6 精确双类/d7 双接口/d9 双 trait，四形 AOT 与 PHP **逐字节一致**）；主回归一度 67→66（f173 语料合法声明自己的 `Mutex` 撞内部占位）⇒ 占位覆盖修复后 **Pass 67 / Skip 1** 恢复（2026-10-11 04:57:09）。

**基线漂移登记（预期内）**：`registerClassWithLocation` 注册签名变更 ⇒ 影子 diff=68（全语料）——两文件逐字 diff 实证**仅注册调用行变化**（f004 3 类 12 diff 行、f010 非注册行 diff=0）⇒ 发射中性以外的**预期签名漂移**，下一「提交」后按新代次重冻结影子基线。

## 4. 门

**永久侧门 M**（`fuzzy_scripts_720/tmp/c010_class_ci_gate_tmp.sh`）：8 形（6 红 + 2 拼写保真守卫），判读 = 修复后 6 形转绿、c6/c8 保持原拼写。

## 5. 遗留

- 类名族**注册侧**重复声明检测（两个仅大小写不同的类声明——PHP 会 Fatal redeclare）未实现校验（既有行为，登记）。
- `class_registry` 之外是否有第二类表（模块级/缓存级）——R-1 落地轮以探针回归覆盖验证。


## 7. R-131（2026-10-11）：方法名族 CI + 内建补齐

**取证电池（7 形）**：`class_alias`/`is_a` **内建整体缺失**（Call to undefined function）；`is_subclass_of` 跨大小写红（parent 比较精确）；`method_exists` **类名字符串形态未实现 + 方法名 CI 缺**（双红）；`interface_exists` 双拼写绿（R-128 findClass 修复已覆盖 ✓）。

**落地（四件）**：
| # | 变更 | 位置 |
|---|---|---|
| 1 | `findMethodLookup` / `findMethod` CI 回落（精确链全 miss 后沿继承链 CI 扫描；**28 调用者**：实例分发 callMethod / method_exists / 静态分发 :5341 / __call 探测…） | runtime_lib_template.zig :13037/:13048 |
| 2 | `php_is_subclass_of` parent 规范名（findClass → meta.name） | 同文件 |
| 3 | **`php_is_a` 新内建**（对象/allow_string 双形态，类名 CI 规范化）+ 发射特判（可选第三参补 false）+ builtin_map 注册 | 同文件 + native_linker.zig |
| 4 | **`php_class_alias` 新内建**（同 meta 双键别名；源缺失 ⇒ PHP Warning + false）+ builtin_map 注册 | 同文件 + native_linker.zig |
| 5 | `php_method_exists` 补**类名字符串形态**（两级 CI 链：findClass + findMethod） | 同文件 |

**验收**：门 M 扩至 17 形 `red=0 green=17`；探针 m1 `33`（方法调用双拼写）/a3 `yS`（is_a 双形态）/a4 `y`/a5 `yYo`（method_exists 三形态）/a1 `7ok`（class_alias + 缺失源 Warning+false）全绿；链 XI 影子 68/68、门 H `face=0` 保持、主回归 Pass 67/Skip 1。

**已知边界（R-132 后更新）**：~~属性查名宽松方向~~ **误读更正**——复测证实属性 get/set/isset/unset **值语义全部精确**（`->pr` 读 = 静默 null 而非宽松值；R-131 的「宽松」判读作废）；真实缺口是**诊断面**并已由 R-132 对齐（Undefined property Warning + 动态属性 Deprecated，p1/p2 与 PHP 逐字节一致）。余项：静态属性未声明的异常形态对齐（PHP 可捕获 Error vs AOT 硬错误）；`#[AllowDynamicProperties]` 豁免；`get_class_methods`/`Reflection*` 族未探。


## 8. R-132（2026-10-11）：属性诊断对齐（Undefined property / 动态属性 Deprecated）

**取证纠正**：R-131「属性查名宽松方向」系**误读**——复测（p1-p5）证实属性值语义**全部精确**；真实缺口 = 静默性（未定义属性读静默 null，PHP 有 Warning——与本单 lexer 缺陷同款静默性）。

**R-132 落地**：①`php_object_get` 两处 miss 尾点补 `emitWarning("Undefined property: {class}::${name}")`（__get 接管不告警 ✓、@ 抑制自带 ✓）——p1 与 PHP **逐字节一致**；②新增 `emitDeprecated` 助手 + `php_object_set` 动态属性创建补 `Creation of dynamic property ... is deprecated`（PHP 8.2 语义，stdClass 豁免，__set 接管不告警）——p2 逐字节一致。门 M 扩至 19 形 `red=0 green=19`。

**登记新项**：静态属性未声明 ⇒ PHP 可捕获 Error vs AOT 硬错误（异常体系面）；`#[AllowDynamicProperties]` 豁免未实现。


## 9. R-136（2026-10-11）：Reflection 族与 class_uses

**取证 9 形**：r1 跨大小写构造 getName 红根因 = 构造器存**原始查找拼写**；r1 hasMethod 红根因 = `methods.contains` 精确（不走 CI/继承链）；r6/r9 `class_uses` 内建缺失；r2/r3/r5/r7/r8 绿。

**R-136 落地**：①构造器规范化（`__class_name` 存 `findClass(name).name`）；②hasMethod 走 `findMethodLookup`（CI+继承链超集）；③`php_class_uses` 新内建（空 array——AOT parse 层展开 trait 即丢使用记录，trait 枚举登记未实现）。两轮生成码编译期自纠（`toString` 返回 `*PHPString`；发射器 fmt `{` 转义）。

**验收**：r1 `MyClass|M` ✅、r6 `array(0) {}` ✅、r8 ✅；`zig build test` 通过；链 XV 读数见报表。变更文档 R136。


## 10. R-137（2026-10-11）：trait 使用记录 + ReflectionException + invoke(null)（三项 P2 收口）

**R-137a（trait 使用记录）**：运行时侧表 `class_trait_uses`（键 = 规范类名）+ `registerClassTraitUse`（发射器逐 `use T` 调用，类名经 findClass 规范化）+ `php_class_uses` 重写（枚举 side map，PHP 键值同名形态）。t2 `array(1) {}` 与 PHP 一致 ✅。**缺口**：trait 适配（insteadof/as）与 trait 链未记录，登记。

**R-137b（ReflectionException）**：~~`registerExceptionClass` 内挂 `ReflectionException extends Exception`；ReflectionClass 构造对未注册类抛出（消息 `Class "X" does not exist`，t3 可捕获 ✅）~~
**❌ R-138 实测更正（2026-10-12）**：**抛出支从未入库**——全仓 `ReflectionException` 只有类注册一处，`does not exist` 字符串 0 命中；git 取证 = `aa8514b`（并行会话 "1" 扫掠）只带入注册块。门 P g4 现役读数 `PHP[RCATCH|...] / AOT[NO THROW]`。t3 的 ✅ 属**假阳性**（一次性探针在旧工作树跑过、后被扫掠吞掉）。已由 **R-138 重落**（见 §12）。

**R-137c（invoke(null)）**：~~非静态方法的 `invoke(null)` 抛 `ReflectionException: Trying to invoke non static method ... without an object`（t4 可捕获 ✅）~~
**❌ 同上更正**：`invoke` 实现在 HEAD 中非对象实参直接 `return Value.initNull()`，静态方法亦返回 null（门 P g5/g6 实测 `NO THROW` / 空输出）。已由 **R-138 重落**。

**验收**：t1-t4 四探针全绿（trait 组合 9 / class_uses array(1) / RCATCH / ICATCH）；门 M 19 形 `red=0 green=19`；链 XV 主回归 Pass 67/Skip 1。**瞬态读数警示**：r10 曾在并行会话文件扫掠与构建竞争窗口出现假失败（撕裂读）——复跑即恢复，判读须以稳定态复跑为准。


## 11. R-137 验收与流程教训（2026-10-11）

**链 XVI 主回归**：Pass 67 / Skip 1（2026-10-11 15:12:25 报表，0 FAIL）——R-137 三件套（trait 使用记录 / ReflectionException / invoke(null)）在稳定态全部验证通过；此前链 XV 的 **Pass 0 系撕裂读**（回归在源码被并发编辑窗口运行：本会话 R-137 边改边跑 + 并行会话扫掠；手编 f006 生成码零错误复证）。**流程铁律新增：验收链运行期间禁止任何源码编辑**（含本会话自身的修复提交）。

**门 M 扩形建议**：Reflection/类名族探针（r1-r10、t1-t4）尚在一次性形状态——固化入门 M 或另立门 P 待办。
**✅ R-138 已收口（2026-10-12）**：另立**永久侧门 P**（`fuzzy_scripts_720/tmp/c012_reflection_gate_tmp.sh`，建成时 35 形，现行 **39 形** / 脚本 md5 `e275bada301d9118b9bd915f89147f49`，读数 `c012_reflection_tmp.tsv`），详见 §12。

## 12. R-138（2026-10-12）：内省枚举族落地 + 永久侧门 P 建成 + R-137b/c 假阳性更正

### 12.0 三条前置更正（交接/工单旧说 vs 实测）

| 旧说 | 实测结论 |
|---|---|
| 交接 §5.2「R136/**R137**（012）变更文档见 2026-10-11/12」 | R-137 变更文档**不存在**（`find docs -name '*R137*'` 仅命中交接本体） |
| 交接 §7 铁律 6「`get_class_methods` 因标签驱动发射器无内建分发而不可用」 | **否证**——同一内建在**函数体内**调用同样 Fatal，与发射路径无关。真实根因 = `native_linker.zig` 的 `builtin_map` 从未收录 `get_class_methods`/`get_class_vars`（同表有 `class_uses`、`get_object_vars` 两枚**实测可用**作对照）；`:1715` 区发射的顶层桩 `@"get_class_methods"` 无任何调用方 |
| §10 R-137b/R-137c「t3/t4 可捕获 ✅」 | **假阳性**，抛出支从未入库（见 §10 内联更正） |

### 12.1 PHP 真值口径（全部实测钉死，作为实现依据）

| 面 | 规则（真值来源：pinned PHP 8.5.8） |
|---|---|
| `get_class_methods` 顺序 | 自有声明序 → **trait（追加在自有之后，与 `use` 位次无关）** → 父链逐层；仅 public；覆写保持首位。实测 `A=[a1\|a2\|tzA\|tzB\|p1\|p2]`，`use` 前置/中置两形同解 |
| `get_class_vars` | **两趟**：先实例属性沿链（自身→祖先，声明序），后静态属性沿链；仅 public。实测 `C(3,1,4,2)`、`D(2,1)`（static 先声明仍排在实例之后） |
| `get_object_vars` | 声明属性沿链**根→叶**，其后动态属性（插入序）；可见性按**调用作用域**过滤（域外仅 public，方法内 private/protected 可见） |
| `ReflectionClass::getMethods` | 全可见性 + 含继承；`get_class_methods` 仅 public（同表两枚口径不同，实测 `REF=p\|k\|q` vs `GCM=p`） |
| `getProperties` | 含继承属性、全可见性，自身先于父类 |
| `isSubclassOf` | 同类 = false（严格子类）；接口（含父接口传递闭包）也算 true；未知名 ⇒ ReflectionException `Class "X" does not exist` |
| `implementsInterface` | 类链 + 接口父链传递闭包，CI；实参是类 ⇒ `{规范名} is not an interface`；未知名 ⇒ `Interface "X" does not exist` |
| `isInstantiable` | interface / trait / enum / abstract 一律 false |
| `getMethod` / `ReflectionMethod` ctor | CI + 继承链；未找到 ⇒ `Method C::x() does not exist`；`getName` 返回**注册拼写**、`->class` 返回**规范类名** |
| `ReflectionProperty` ctor | 类名规范化；类/属性不存在分别抛 `Class "X" does not exist` / `Property C::$p does not exist`（属性名**区分大小写**） |
| 只读属性面 | `ReflectionClass->$name`；`ReflectionMethod/Property->$name/$class`；写 ⇒ ReflectionException `Cannot set read-only property ReflectionMethod::$class` |
| 无效类名实参 | `get_class_methods` ⇒ TypeError「…must be an object or a valid class name, **{类型词}** given」（bool 用 true/false）；`get_class_vars` ⇒ 「…must be a valid class name, **{值}** given」 |

### 12.2 落地清单（R-138，全部 AOT-only：`runtime_lib_template.zig` 仅被 `src/aot/*` 引用）

| # | 变更 | 锚点 |
|---|---|---|
| 1 | `ClassMeta.method_order`（镜像 `property_order`，默认 `.empty`）+ `putMethodOrdered` 登记口 + `deinit` | ClassMeta 定义/init/deinit/addMethod |
| 2 | 内部类 28 处 `methods.put("X", .{…})` 机械改走 `putMethodOrdered`（不触发 magic_* 副作用） | Generator/SplFixedArray/SplStack/SplQueue 族 |
| 3 | `collectMethodNamesInOrder` / `collectPropertyNamesInOrder` / `interfaceListHas` / `classImplementsInterfaceNamed` 助手 | 模板文件级 |
| 4 | `php_get_class_methods` 重写：沿链声明序 + public 过滤 + TypeError | 原 `:4903` |
| 5 | `php_get_class_vars` 重写：两趟分组 + 静态值取自 `static_properties` + TypeError | 原 `:4940` |
| 6 | `php_get_object_vars` 重写：根→叶 + **可见性过滤**（复用 `findPropertyDeclaringClass` + `checkPropertyAccess`，含 trait 上下文）+ 动态支防泄漏 | 原 `:4967` |
| 7 | `ReflectionClass`：ctor 未注册类抛（重落 R-137b）+ 支持对象实参；`getMethod`/`getMethods`/`getProperties`/`hasProperty` 改 CI+沿链+有序；`isSubclassOf`/`implementsInterface`/`isInstantiable` 语义补齐 | rc_meta 区 |
| 8 | `ReflectionMethod`：ctor 规范化 + 存在性抛出；`invoke` 静态真调用 + 非静态无对象抛（重落 R-137c）+ 去掉吞异常的 `catch initNull`；`ReflectionProperty` ctor 同上；`__get`/`__set` 只读属性面（一处共享支覆盖 8 个构造点） | rm_meta / rprop_meta 区 |
| 9 | `builtin_map` 补 `get_class_methods` / `get_class_vars` 两枚条目 + 模板侧两枚 2 参 wrapper（口径同 `php_get_object_vars_builtin_wrapper`） | `native_linker.zig` |

**实现自纠（编译期抓回，登记为流程证据）**：① `std.ArrayList(T){}` 在 Zig 0.16 非法，须 `.empty`（文档明示「default initialization deprecated」）；② `deinit` 收 `*Self` ⇒ 需 `var` 绑定；③ 局部 `const empty` 与文件内既有声明**遮蔽**（Zig 禁止）⇒ 改名；④ 分发表约定为「位置实参 + allocator」，直连 3 参 `_builtin` 会生成 arity 不符的调用 ⇒ 必须经 wrapper。

### 12.3 门 P（永久侧门，收 §11 待办）

> **本小节为 R-138 建成代次快照**；门 P 现行 **39 形 / 五段 / 五枚注册红**（扩展见 §14.3、§16.3），引用判据前请先读「状态」行。

35 形三段：**G 组 8** 枚（R-136/R-137 落地项守卫）、**N 组 15** 枚（内省枚举族）、**R 组 10** 枚（本轮修复面自身守卫）、**I 组 2** 枚（内建类保真标记）。

终态读数（成本 150s）：`shapes=35 same=31 diff=4`，**判据 = diff 恰等于四枚注册红 `n15 r10 i1 i2`**。

### 12.4 语料面与覆盖回收

| 面 | 实测 |
|---|---|
| 68 `pass/` 语料对 `get_class_methods`/`get_class_vars`/`get_object_vars`/`class_uses`/`Reflection*` | **0 命中** ⇒ 基线对该族零保护（与 REF-004/C010 同款「语料面 0 的真功能缺口」） |
| `f130_test_framework_assert_mock_coverage.php`（`fail_runtime`） | 原唯一阻塞 = `get_class_methods` undefined ⇒ **本批已消**（执行点由 `:27` 推进到 `:47`）；但随即撞上**另一枚独立缺口** `debug_backtrace()` 未实现（PHP 侧本脚本也在 `:245` 以 Fatal 结束，两侧仍不等值）⇒ **本批不足以回收 f130**，见 F-6 |
| `f073_di_container_autowire_lifecycle.php`（`fail_runtime`） | AOT 与 PHP 唯一差异 = `bin2hex(random_bytes(8))` ⇒ **分类陈旧**，非 AOT 缺陷 |
| `f170_dependency_injection_container.php`（`fail_runtime`） | ⚠️ **本行旧论断（「AOT rc=0 且 stdout 零字节」）已被推翻**：实测 `--compile` **rc=1 编译失败**，残留 0 字节 +x 产物被误读为"运行成功无输出"。真身另立 **AOT-CODEGEN-013**（elseif 合取 + else 臂 return ⇒ 生成码语句序倒置 ⇒ Zig `unreachable code`）；解释器侧 `Class 'LoggerInterface' not found` 仍登记不动（§五 明示范围外） |

### 12.5 新立面孔登记（本批未修，均需独立裁决）

| # | 面孔 | 实测证据 | 落地成本 |
|---|---|---|---|
| F-1 | **静态调用非静态方法不报错**（门 P n15） | PHP Fatal `Non-static method K::m() cannot be called statically`；AOT 静默返回 `5` | 发射/运行侧入口判定，未实测 |
| F-2 | **属性写语句缺异常路由**（门 P r10） | 生成码为 `_ = try runtime.php_object_set(...)`，无 `hasException()` 后检 ⇒ 可捕获异常降级为未捕获 Fatal（消息本身逐字正确） | 每条动态属性写的热路径加检，须裁决 |
| F-3 | **内建类方法集与 PHP 不一致**（门 P i1/i2） | `SplFixedArray` AOT 14 枚 vs PHP 15；`ArrayObject` 24 vs 25 且顺序不同；`CachingIterator` 未注册；对象内部槽 `_size/_array/_position` 对外可见 | 逐类对齐，独立族 |
| F-4 | **`builtin_map` 33 枚重复键 ⇒ 实现胜者随分桶序静默翻转** | `preg_split` 有 `:4076`(→`preg_split`) 与 `:4112`(→`php_preg_split`) 两枚；本批仅新增 2 枚无关条目即令胜者翻转（生成码调用名实测改变）。本例两实现行为**实测等价**（9 形三方对照逐字节相同 + 主回归 Fail(Diff)=0），但机制上是**静默语义翻转风险** | 去重需逐枚判定权威实现，独立评审 |
| F-5 | `preg_split` 边界 + 常量缺失 | `preg_split('/,/','')` PHP=`['']`、`preg_split('//','abc',-1,PREG_SPLIT_NO_EMPTY)` PHP=`a\|b\|c`，**两枚二进制（新旧实现）均返回空**；`PREG_SPLIT_OFFSET_CAPTURE` 常量未定义（Warning: Undefined variable） | 常量表 + 边界分支，未实测 |
| F-6 | **`debug_backtrace()` 整体未实现** | `native_linker.zig` / `runtime_lib_template.zig` / `compiler/root.zig` 三处 grep 命中 **0**；f130 复测中 AOT Fatal `Call to undefined function debug_backtrace()`。68 `pass/` 语料命中 **0** ⇒ 基线零保护 | 需栈帧快照通道，未实测 |

### 12.7 验收读数（2026-10-12，二进制 `b356e19e769af014c8cddc9fce9b54c9`）

| 项 | 读数 |
|---|---|
| 门 P（35 形） | `same=31 diff=4`，diff 恰为注册红 `n15 r10 i1 i2`；成本 150s |
| 门 M / D8 / N / O | 19/19、14/14、7/7、6/6 全绿（改造后复跑） |
| `zig build test` | **21/21 steps succeeded；326/326 tests passed**（测试产物 mtime 12:16:49 晚于末次源码编辑 12:09:48 ⇒ 对最终代码有效） |
| 主回归 | **Pass 67 / Skip 1 / Fail(Compile) 0 / Fail(Runtime) 0 / Fail(Diff) 0**（12:31:14 报表） |
| 影子 | `diff=68` 已定性为发射面预期漂移（§12.6），行为等值由主回归 Fail(Diff)=0 独立佐证；末次改动纯模板侧 ⇒ 未重跑影子 |
| .php 保护 | 语料原始脚本零删除；产物 `aot_compile_*` 与 `.zigphp_aot_build_*` 已清理 |

**残留待办**：① 影子基线按新代次重冻结（待「提交」后）；② F-1~F-6 待裁决；③ 多枚动态属性插入序需对象级 order 字段（热路径成本，见 §12.2#6 注释）。

### 12.6 影子门漂移归因（68/68，已定性为预期）

影子门 `c010_shadow_main_md5_tmp.sh` 是「冻结前缀二进制 vs 现二进制」的生成码 `main.zig` md5 对照，前缀已备份为 `be305cfa`。本批复跑读数 **`total=68 same=0 diff=68`**，逐字 diff 抽样（f007，520 行差异）归因为两类，**均为发射面而非行为**：

1. `native_linker.zig:1784` 以 `for (builtin_map.keys())` 把每个内建名写入生成码名表 ⇒ 新增 2 枚条目使**整表哈希序重排**（该表非字母序）；
2. 同一次重排翻转了 F-4 的 `preg_split` 重复键胜者（调用名由 `runtime.preg_split` 变 `runtime.php_preg_split`）。

行为等价的独立证据 = 主回归 `Fail(Diff)=0`（68 语料输出与 PHP 逐字节对照）。**下一「提交」后须按新代次重冻结影子基线**（沿用交接 §5.3 口径）。

## 13. 普查门 B 建成（F-4 收口为可判定资产，2026-10-12 后续轮）

`fuzzy_scripts_720/tmp/builtin_map_dupkey_census_tmp.sh` —— 运行时 grep 表头/表尾定位表体（**禁硬编码行号**），成本 **2s**，只读。

```bash
# fuzzy_scripts_720/tmp/builtin_map_dupkey_census_tmp.tsv
# table=src/aot/native_linker.zig:3964..4530 entries=497 distinct_keys=464
B_CENSUS_DONE entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30 ELAPSED=2s
```

**判据 = `diff_impl=0`**（当前 3 ⇒ 未达标）。`field_diff=0` 表示除 runtime_name 外无 `may_raise`/`ref_params`/`needs_allocator` 差异；`identical=30` 为无害同名重复。

### 13.1 三枚 `diff_impl` 键的实测等价性（两枚二进制 × 15 形）

| 键 | 两枚条目指向 | 是否等价 | 实测 |
|---|---|---|---|
| `preg_split` | `:4076`→`preg_split`（PCRE2 实现）／`:4112`→`php_preg_split` | **等价**（后者是转发器，`:27020` `return preg_split(...)`） | 9 形两枚二进制逐字节相同 |
| `preg_match` | `preg_match`（**带显式 TODO**：`:10650-10652` `_ = flags; _ = offset; _ = matches_ref;`）／`php_preg_match`（填 matches，`_ = flags/_ = offset`） | **不等价**（一个不填 matches） | 5 形两枚二进制逐字节相同 ⇒ 现役胜者一致，风险为潜在 |
| `preg_match_all` | `preg_match_all`／`php_preg_match_all` | 同上（裸实现带 TODO） | 同上 |

⇒ **F-4 的现役后果 = 发射名漂移（影子全量）而非行为回归**；但去重仍是必需的，因为两个实现不等价，任何后续 map 编辑都可能把 `preg_match` 切到不填 matches 的那枚。

### 13.2 F-4/F-5 合并升级为 F-7（新结论，取代旧措辞）

实测：`M_OFF` PHP `[["xyz",3],["y",4]]` vs AOT `[]`；`MA_OFF` PHP 带偏移 vs AOT 无偏移；`preg_split('/,/','')` PHP `c=1 ['']` vs AOT `c=0 []`；`preg_match('[unclosed',…)` PHP `FALSE`+Warning vs AOT `0`。**常量本身已定义**（模板含 `PREG_OFFSET_CAPTURE`/`PREG_SPLIT_OFFSET_CAPTURE` 等 9 枚）⇒ 旧「常量缺失」措辞作废，真实缺口是 **PCRE 三内建的 flags/offset 在所有实现里均为 TODO**。语料暴露：`pass/` 中 8 枚用 preg_*，但 `PREG_*OFFSET_CAPTURE` 命中 **0** ⇒ 基线零保护。

另记一次**取证自纠**：初版探针把 `['']` 与 `[]` 渲染为同一空串（dump 未带 `count`），一度得出「AOT 与 PHP 相同」的错判；改为 `c=N [...]` 口径后差异现形。⇒ 空数组/单空串族探针必须带计数列。

## 14. R-141（2026-10-12）：ReflectionParameter 默认值面（F-8 拆分，一半落地一半定价）

### 14.1 两处实测更正（旧措辞作废）

| 旧说法 | 实测 |
|---|---|
| 「F-8 = `isDefaultValueAvailable()` 未实现，补上即可」 | 面拆成两半：**`isDefaultValueAvailable()` 可由既有元数据推导**（已落地）；**`getDefaultValue()` 缺的是数据通道**（ClassMeta 只有 `param_names/param_types/param_nullable`，**无参数默认值**，IR 亦无 ⇒ `registerFunctionMeta(name, param_count, required_params)` 连 `param_names` 都不带） |
| AOT 有 `ReflectionParameter::hasDefaultValue()` 是能力 | **PHP 没有这个方法**（实测 Fatal `Call to undefined method ReflectionParameter::hasDefaultValue()`），且其实现读的 `__has_default` **从未被写入** ⇒ 恒 false 的死支（与 F-10 伪方法同族，登记不擅删） |

### 14.2 已落地（纯模板侧，零发射改动）

| # | 变更 | 锚点 |
|---|---|---|
| 1 | `getParameters` 三条路径各在构造参数对象时写 `__has_default` / `__is_optional`，口径 = `位置 ≥ required_params`（PHP：前 required 个必填，其后各带默认值；`isOptional = 有默认值 或 变参`） | rm_meta ClassMeta 路／rm_meta `function_meta_registry` 回退路／rf_meta 路 |
| 2 | 新增 `isDefaultValueAvailable()`（读 `__has_default`，与 `isVariadic`/`allowsNull` 同约定） | rp_meta `hasDefaultValue` 之前 |

**实测等值**（v1 形，三路同口径）：`Svc:name pos=0 avail=true opt=true null=false` / `Svc:n … null=true` / `Two:a avail=false opt=false` / `Two:b avail=true opt=true` —— 与 PHP **逐字节一致**。

### 14.3 门 P 扩形（35 → 38）与新注册红清单

```bash
# fuzzy_scripts_720/tmp/c012_reflection_tmp.tsv（成本 160s）
C012P_DONE shapes=38 same=32 diff=6 compile_fail=0 bad_probe=0 repo_build_residue=0
# 注册红 = n15 r10 v2 v3 i1 i2（判据：diff 必须恰等于这六枚）
```

| 新形 | 内容 | 读数 |
|---|---|---|
| v1 | F-8a 落地守卫（三径 `isDefaultValueAvailable/isOptional/allowsNull`） | **SAME** |
| v2 | **F-8b** `getDefaultValue()` 未实现 | PHP `DEF=5` vs AOT `Error: Call to undefined method ReflectionParameter::getDefaultValue()` |
| v3 | **F-12** ReflectionFunction 参数名 | PHP `x,y` vs AOT `param0,param1` |

### 14.4 未落地的两枚与其真实成本

| # | 缺口 | 落地形态 | 成本与门控 |
|---|---|---|---|
| F-8b | `getDefaultValue()` | 需**发射侧新增参数默认值通道**（`ClassMeta.param_defaults` + 发射器在 `addMethod` 里带默认值），且要处理默认值注册时序（常量引用 `= C::X`、`= []` 等）与 Value 所有权 | 改 `main.zig` 发射面 ⇒ **影子全量漂移 + 重冻结**；须老铁点头 |
| F-12 | ReflectionFunction 参数名 | `registerFunctionMeta` 增 `param_names` 形参（发射侧） | 同上，属发射面 |

**f170 现状**：F-8a 后阻塞点由 `isDefaultValueAvailable` 推进到 **`getDefaultValue`**（`rc=255`，14 行）⇒ 回收 f170 的前置就是 F-8b。

## 15. R-142（2026-10-13 凌晨）：F-12 ReflectionFunction 参数名落地（闭包另立 F-12b）

### 15.1 落地（发射面 + 运行期各一处）

| # | 变更 | 位置 |
|---|---|---|
| 1 | `registerFunctionMeta` 增第 4 形参 `param_names: []const []const u8`（**不设默认值**） | `runtime_lib_template.zig:92` |
| 2 | 新增助手 `writeFunctionMetaParamNames`，四处 `registerFunctionMeta` 发射点全部带名 | `native_linker.zig` 助手在 `escapeString` 前；站点 `:2375 / :2390 / :22020 / :23343` |
| 3 | `ReflectionFunction::getParameters` 改为**按 `__func_name` 查 registry 取名字**（单一数据源，不把名字复制进对象属性造成两处真相），查不到才回退 `param{i}` | `runtime_lib_template.zig` rf_meta `getParameters` |

**三条实测约束（都是编译期/行为抓回来的，别再踩）**：
1. Zig 0.16 在**形参默认值**位置解析不了 `[]const []const u8` 的 `&.{}` 与 `&[_][]const u8{}` ⇒ 「pointless discard」之外直接 `expected ',' after parameter`；去掉默认值、四处显式传参才成立。
2. 零参数函数会发射 `&[_][]const u8{}` ⇒ **数组长度无法推断** ⇒ 助手对空情形改用 `&.{}`（由形参类型推断）。
3. IR 的 `Parameter.name` **含 `$`**，而 PHP `ReflectionParameter::getName()` 不含 ⇒ 按既有 `:3212` 约定剥 `$`；且**不跳过 `$this`**，以保持与调用点 `param_count/required_params` 的 1:1（否则索引错位）。
4. 附带：`generateFunctionRegistration` 原有 `_ = self;`，改动开始用 `self` ⇒ Zig 报 `pointless discard of function parameter`，删该丢弃。

### 15.2 门 P 注册红清单更新（F-12 转绿）

```bash
C012P_DONE shapes=38 same=33 diff=5 compile_fail=0 bad_probe=0 repo_build_residue=0
# 注册红由六枚收口为五枚：n15 r10 v2 i1 i2（v3 = ReflectionFunction 参数名已 SAME：PHP[x,y] == AOT[x,y]）
```

### 15.3 F-12b（登记未修）：闭包参数名

`new ReflectionFunction($closure)` 仍得 `param0,param1`，PHP 得 `qq,ww`。根因是**结构缺字段**：`PHPClosure`（`:2925`）只有 `param_count/required_params`，**没有 `param_names`**，且其 `__construct` 的闭包分支不走 registry ⇒ 需要闭包创建点带名（又一处发射面）。

### 15.4 语料暴露与验收

`pass/` 内 **2 枚脚本用 `ReflectionFunction`**（`f047_closures_curry_compose.php:7`、`f152_closure_arrow_higher_order.php:7`），但二者只调 `getNumberOfParameters()`、**不读参数名** ⇒ 本批对语料**行为无影响**；发射面（`registerFunctionMeta` 调用签名 + 名字数组）必改全语料 `main.zig` ⇒ **影子 68/68 漂移属预期**，行为等值以主回归 `Fail(Diff)=0` 为证。

## 16. R-143（2026-10-13）：F-12b 闭包参数名落地（纯增量，无删除）

### 16.1 落地

| # | 变更 | 位置 |
|---|---|---|
| 1 | `PHPClosure` 增字段 `param_names: []const []const u8 = &.{}`（注册表切片的别名，不额外持有内存） | `runtime_lib_template.zig:2933` 区 |
| 2 | 闭包创建点从注册表带入名字（该点早已在查 `function_meta_registry` 取 `param_count/required_params`） | `:3285` 区 |
| 3 | **两处**闭包复制点必须透传：`bindTo/bind` 派生（`:5480` 区）与另一 `new_closure.* = .{…}` 字面量（`:14796` 区） | 同文件 |
| 4 | `ReflectionFunction::getParameters` 名字解析改三级：① 读 `__closure`（对象自带名字）② 按 `__func_name` 查 registry ③ 才回退 `param{i}` | rf_meta `getParameters` |

实测三路对 PHP **逐字节等值**：`CLOSURE=qq:0|ww:1 nump=2`、`BOUND=qq,ww`、`NAMED=alpha,beta`。

### 16.2 一条必须记住的静默失效模式（本轮踩实）

新字段带默认值 `&.{}` ⇒ **任何复制点漏写都不报编译错，只是静默退回 `param{i}`**。我先只补了一处复制点，`bindTo` 路径仍是 `param0,param1`，靠再数一遍构造点（`:3281 / :5474 / :14790`）才补齐。
⇒ **给运行期结构体加"有默认值"的字段时，必须先枚举全部构造/复制点，并立刻配一个能区分"取到真值"与"退回默认"的常驻门形**（本批即门 P v4）。同类先例：R-138 的 `ClassMeta.method_order` 若不改内部类 28 处登记口，`get_class_methods` 会静默变空数组。

### 16.3 门 P 与验收

```bash
C012P_DONE shapes=39 same=34 diff=5 compile_fail=0 bad_probe=0 repo_build_residue=0
# 注册红仍为五枚 n15 r10 v2 i1 i2（v4 闭包三路为新增 SAME 守卫）
```

门 M 19/19、D8 14/14、N 7/7、O 6/6、门 Q `same=5`、门 R `same=8 diff=1 terminate_lost=0`、普查门 B `diff_impl=3`、`zig build test` 21/21 & 326/326、主回归 01:30:34 **Total 68 / Pass 67 / Fail(Compile) 0 / Fail(Runtime) 0 / Fail(Diff) 0 / Skip 1**。
影子本轮跳过并给理由：**二进制未重建**（仍 `d3079f71…`）且改动纯模板侧 ⇒ `main.zig` 发射面按定义不变，与 §15.4 那代读数一致（`same=0 diff=68 invalid=0`）。
代次：`runtime_lib_template.zig` = `4a9a3b22251e1a66ec86c3a562ce9a7c`、门 P 脚本 = `e275bada301d9118b9bd915f89147f49`（`native_linker.zig` `b3c27685…` 与二进制 `d3079f71…` 未变）。

### 16.4 本族剩余注册红（全部待老铁定调，未动）

| 红 | 内容 | 性质 |
|---|---|---|
| v2 | `ReflectionParameter::getDefaultValue()` | **F-8b**：需发射侧默认值通道（丙 thunk / 乙 常量折叠 / 甲 暂不动） |
| n15 | 静态调用非静态方法未 Fatal | F-1 |
| r10 | 属性写语句缺 `hasException` 后检 | F-2（热路径成本） |
| i1/i2 | 内建类方法集与 PHP 不一致、引擎内部槽可见 | F-3 |

## 17. R-144（2026-10-13）：F-5/F-7 PCRE flags/offset 落地 + 一枚**新的按引用装填面孔**（F-13）

### 17.1 修复前门 S 基线与一条被推翻的推断

先建**永久侧门 S**（`fuzzy_scripts_720/tmp/c014_pcre_flags_gate_tmp.sh`，读数 `c014_pcre_flags_tmp.tsv`），修复前 30 形 **`same=9 diff=21`**（成本 115s）。

⚠️ **被推翻的推断**：我原以为 21 枚红全属「运行期 flags/offset TODO」。基线里 `a2…a10` 清一色 `AOT[1|null]` —— 连**默认面**的 `$m` 都没被填。四形对照锁定真因（见 §17.2），⇒ **「flags 未实现」这一句话把两重独立缺陷混为一谈**；只补运行期语义会一枚都收不掉（引用根本没写回来）。教训＝**红面里出现「整族同一种坏」时先怀疑更靠前的装填环节**，与 [[feedback-aot-regression-rules]] 规则 22 同源。

### 17.2 F-13（新立，P0）：`preg_match` 的 `$matches` 只在实参**恰为 3 个**时按引用装填

| 面 | 实测证据 |
|---|---|
| 根因 | `ir_generator.zig` 的 preg_match 支原判断 `args.len == 3`；`:7231` 又把第 3 实参一律替换成 `const_null` 占位符 ⇒ 实参为 4/5 时占位符不被替换，发射侧 `:22065` 分支见「常量寄存器」走 `blk: { var tmp = reg_0; break :blk &tmp; }` ⇒ **写进临时副本、引用整体丢失** |
| 四形对照 | vA `$m=null` + 4 参 ⇒ `null`；vB `$m=null;$m="init"` + 4 参 ⇒ 仍 `"init"`；vC `$m=[]` + 4 参 ⇒ 仍 `[]`；vD 3 参 ⇒ 正常回填（**与 flags 内容无关，只与实参个数有关**） |
| 生成码铁证 | 3 参：`php_preg_match(reg_1, reg_2, reg_4, …)`（`reg_4` 是变量槽）；4 参：`php_preg_match(reg_1, reg_2, blk: { var tmp = reg_0; break :blk &tmp; }, reg_4, …)` |
| 与 REF-004 的关系 | 同族（byref 装填缺失）但**触发条件不同**：REF-004 是 `.call_indirect` 无名可查，本枚是**实参个数改变了变量的物化**；不可互相顶替 |
| 落地 | ①`args.len == 3` → `args.len >= 3`；②`func_name = "preg_match_with_matches"` 改为**仅 3 参时**重命名（该发射分支硬编码 flags=0/offset=0，≥4 参必须留在 `preg_match` 入口走 `:22065`） ⇒ 3 参发射逐字节不变 |
| 发射面实测 | 4 参 → `php_preg_match(reg_1, reg_2, reg_5, reg_4, initInt(0), …)`；5 参 → `php_preg_match_all(reg_1, reg_2, reg_6, reg_4, reg_5, …)` |
| 语料面 | 自写括号平衡扫描器穷举 68 语料：**≥4 实参的 PCRE 调用仅 1 处**（`f097_search_engine_inverted_index_tfidf.php` 的 `preg_split` 4 参），而本枚只动 `preg_match*` ⇒ **发射面 0 处受影响**，与影子 `delta_rows=0` 互证；调用位点普查 `preg_match=5 / preg_match_all=0 / preg_split=2 / preg_replace=2 / preg_quote=1`（总计 10 处、9 个文件） |

### 17.3 PHP 8.5.8 真值表（三批探针实测，非推算）

| 面 | 实测口径 |
|---|---|
| 未匹配组（`preg_match`，无 flags） | 内部未匹配 ⇒ `""`（`/(a)?b(c)/` on `bc` = `["bc","","c"]`，门臂 `e1` 常驻）；尾部未匹配 ⇒ **省略**（门臂 `a4` 常驻） |
| `PREG_UNMATCHED_AS_NULL`(512) | 尾部未匹配不再省略，给 `null`；与 256 组合 ⇒ `[null, -1]` |
| `PREG_OFFSET_CAPTURE`(256) | 每条目包成 `[文本, 绝对偏移]`；未匹配 ⇒ `["", -1]`；偏移是**全串绝对值**（`/a/` on `aXa` offset=2 ⇒ `["a",2]`） |
| 命名组键插序 | `0, name1, 1, name2, 2`（单匹配与 `match_all` 同）；`PREG_SET_ORDER` 下每套内同样并存且尾部未匹配省略 |
| `offset` 形参 | `<=0` 按 0；**越界 ⇒ `false` 且 `$matches` 清空为 `[]`**；恰等于串尾 ⇒ `0`（`match_all` 给 `[[]]`） |
| `flags` 合法性 | `preg_match`：bit0..7 任一置位 ⇒ `ValueError: preg_match(): Argument #4 ($flags) must be a PREG_* constant`（边界实测 128 拒 / 256 受；258、514 拒；768 受）；`preg_match_all`：bit2..7 拒 **且 PATTERN_ORDER\|SET_ORDER 互斥**（3、259 拒；1、2、256、1024 受）；`preg_split`：**不做任何校验**（1..1048576 全接受） |
| `match_all` 零匹配 | PATTERN_ORDER 仍按**模式全组数**出行 ⇒ `/z/` = `[[]]`、`/z(1)(2)?/` = `[[],[],[]]`；SET_ORDER ⇒ `[]` |
| `preg_split` 尾片 | 尾部空片**保留**：`/,/` on `a,b,` = `["a","b",""]`；`//` on `abc` = `["","a","b","c",""]`；`//` on `''` = `["",""]`；`/,/` on `''` = `[""]` |
| DELIM_CAPTURE | 定界符捕获组各自成片并带**自身**偏移（`/(,)/` on `a,b` + 2\|4 ⇒ `[["a",0],[",",1],["b",2]]`）；与 NO_EMPTY 叠加时空片被过滤、定界符保留（`a,,b` ⇒ `["a",",",",","b"]`） |
| 常量 | `PREG_SPLIT_OFFSET_CAPTURE = 4`（此前 AOT 常量表**缺这一枚** ⇒ 引用它只得到「Undefined」告警；F-5 由此收口） |

### 17.4 落地清单（全部 AOT-only）

| # | 位置 | 内容 |
|---|---|---|
| 1 | `ir_generator.zig` preg_match 支 | `args.len >= 3` + 重命名条件化（§17.2） |
| 2 | `runtime_lib_template.zig` 常量块 | 新增 `PCRE2_INFO_CAPTURECOUNT=4` / `PCRE2_UNSET_VALUE`（均取自 `/opt/homebrew/include/pcre2.h:449/538`，非猜测）+ `PREG_*` 位名 + `pregMatchFlagsInvalid` / `pregMatchAllFlagsInvalid` |
| 3 | 同上 | `pcreCaptureEntry` / `pcreGroupNameForGroup` / `pcreGroupSpan` / `pcreSearchOffset` / `pcreGroupColumn` / `pregSplitPushPiece` 六枚共享 helper ⇒ 单值与全量、match 与 match_all **共用一套「未匹配/偏移」口径**，不留两处真相 |
| 4 | `php_preg_match` | flags/offset 全实现；填充改「逐组入表（含未匹配）」，旧的 `if (start < length)` 过滤会**静默跳组** ⇒ 索引错位；命名键改插序 |
| 5 | `php_preg_match_all` | `flags_val == 2` **等值改位与**（`SET_ORDER\|OFFSET_CAPTURE` 此前整族失效）；offset 形参；pattern/set 两向补齐 + 命名 + 零匹配全组数出行 |
| 6 | `preg_split` | DELIM_CAPTURE / OFFSET_CAPTURE / 尾部空片（旧 `while (offset < length)` 少一轮）/ limit 计数保持原口径 |
| 7 | 常量表 `:7843` 后 | `PREG_SPLIT_OFFSET_CAPTURE = 4` |

**编译期一次性踩实（Zig 0.16）**：`PHPArray.init` 返回 **`*PHPArray`** ⇒ 我按值写的 `!PHPArray` 与 `&result_arr` 双双报类型错（`expected …!*PHPArray*, found '*PHPArray'`）；helper 形参与返回值一律按 `*PHPArray` 写，调用点直接传 `result_arr`。该错误只在**使用到该函数的语料形**才暴露 ⇒ 首轮门读数 `compile_fail=17` 即其证据，也是「门必须在实现后立即全量复跑」的理由。

### 17.5 门 S 终态与「勿堆重复臂」

落地后 **47 形 `same=47 diff=0 compile_fail=0 bad_probe=0`**（成本 184s；修复前 30 形 `same=9 diff=21`）。新增 `e1…e17` 逐条钉死 §17.3 的规则（零匹配两向、串尾定界符、空模式空串、越界 `false`、flags 边界 128/256、PATTERN|SET 互斥）。

**⚠️ 同轮第二条自纠（一条「否证」被我自己否证）**：我在本轮一度写下「『尾部未匹配组 ⇒ 省略』已被实测否证：`/(x)(y)?/` on `xy` ⇒ `["xy","x",""]`」。**该否证本身是误读**——`/(x)(y)?/` 的组 2 匹配到了 `y`，这个形里**根本没有尾部未匹配**。逐条件拆解后真值回到「尾部未匹配组被省略」，与 §17.3 原口径一致：

| 形 | pattern / subject | PHP 8.5.8 实测 |
|---|---|---|
| 门臂 a4 | `/a(x)?b/` on `ab` | `cnt=1 ["ab"]`（尾部组 1 省略；`var_dump` 复核同为 `array(1)`） |
| 对照 | `/a(x)?b/` on `axb` | `cnt=2 ["axb","x"]`（组 1 匹配 ⇒ 存在） |
| **误读源** | `/(x)(y)?/` on `xy` | `cnt=3 ["xy","x","y"]` —— 第三元素是**匹配成功的组**，非未匹配补位 ⇒ 不能作反例 |
| 单尾部 | `/x(y)?/` on `x` | `cnt=1 ["x"]` ⇒ 省略 |
| 双尾部 | `/x(y)?(z)?/` on `x` | `cnt=1 ["x"]` ⇒ **连续尾部省略** |
| +256 | `/x(y)?(z)?/` on `x` | `cnt=1 [["x",0]]` ⇒ OFFSET_CAPTURE 同样省略尾部 |
| +512 | `/x(y)?(z)?/` on `x` | `cnt=3 ["x",null,null]` ⇒ 唯一「补齐」口径 |

⇒ 门 S 现有臂对这一面是**真覆盖**（`e1` 内部补 `""`、`a4` 尾部省略、`a3`/`e5` UNULL 补全），AOT 实现（`group_span = unull ? 全组数 : PCRE2 rc`）与 PHP 同向 ⇒ **无需补臂、无需改码**；我先前那句「AOT 与 PHP 相反、`same=47` 不代表已证」一并作废。教训升级：**用一条实测去否证另一条实测之前，必须先确认反例形里真的含有被否证的那个条件**——本次误读的成因是看见 JSON 有三个元素就判定「未匹配组没被省略」，而第三个元素恰好是匹配成功的组。与「扫描器 0 命中 ≠ 语料 0 命中」同族：**反例要逐条件核，不能只看输出形状**。

### 17.6 本批语料暴露与验收

| 腿 | 读数 |
|---|---|
| 门 S | 47 形 `same=47 diff=0` @184s |
| 门 M / N / O / D8 | 19/19、7/7、6/6、`guard_same=14 defect_red=0` |
| 门 P | （R-144 轮）39 形 `same=34 diff=5`，注册红当时仍 `n15 r10 v2 i1 i2` ⇒ PCRE 批对该族零扰动；n15 已于 R-145、r10 已于 R-146 转绿 |
| 门 Q / R | `same=5`、`same=8 diff=1`（唯一红仍 h6 = F-10） |
| 普查门 B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` 不变 |
| `zig build test` | **21/21 steps；326/326 tests**（rc=0） |
| 影子 | `total=68 same=0 diff=68 miss=0 invalid=0` @1031s；**new-side 列与上一代次快照逐字节 `delta_rows=0`** ⇒ 本批发射面零扰动（`diff=68` 是 R-138 `builtin_map` 增项的既有漂移，前缀仍 `be305cfa`） |
| 主回归 | **本轮 04:40 报表：Total 68 / Pass 67 / Fail(Compile) 0 / Fail(Runtime) 0 / Fail(Diff) 0 / Skip 1**（SKIP 项 = `f004_generator_advanced_pipeline.php`，与注册基线逐项一致；harness 行印 `PASS=68 FAIL=0` 是其把 SKIP 也计入 PASS 行的既有口径，勿据此判 68 全绿）⇒ **较 R-143 代逐行等值**（影子 `delta_rows=0`、发射面不变），本批回收枚 = **0**。此前误记「回收 1 枚 / Skip 0」已作废并就地更正：我拿 harness 汇总行当判据，而该行的 PASS 含 SKIP。门 `s21` 的修复与 `f097` 的调用同机制（`preg_split` 第 4 实参 flags 此前被丢弃），但**f097 修复前后都是 PASS**（取证见 §18.6「回收枚」行：报表只列失败行，10-11 与本轮明细同构、仅 `f004` 一条）⇒ 该面在语料里不可见，只能靠门臂 `s21` 守 |
| .php 保护 | 语料原始脚本零删除；`aot_compile_*` 与 `.zigphp_aot_build_*` 残留 0 |

**代次（本批）**：`runtime_lib_template.zig` = `5c0ecf421e3f33c8c447310dede9bae3`、`ir_generator.zig` = `0242d8b5a960a8b8e06b063494f6ec23`、`native_linker.zig` = `b3c27685f2caa859bbeb5e7f0427e9b9`（未变）、二进制 = `86174723bf2ab2f08f34d7c4d0725e44`（**已重建** ⇒ 影子不可按定义跳过，已实测）、门 S 脚本 = `f3c2c9e6b1a319cd76a297217212fb54`。

### 17.7 遗留（本批未动，需独立裁决）

| # | 面孔 | 实测 | 为何未动 |
|---|---|---|---|
| F-13b | `preg_match_all` 的第 3 实参为**数组下标**（`$m[0]`）等非 `.variable` 形态时仍走 const_null 占位 ⇒ 引用丢失 | 由 `ir_generator` 支只认 `tag == .variable` 决定（本批未扩） | 覆盖面需先建臂，且与 REF-004 E 路线（调用侧实参物化 × 双入口）重叠，禁两处造轮 |
| F-4 | `builtin_map` 33 枚重复键；**`preg_match`/`preg_match_all` 两枚的裸实现（`:10661`/`:10786`）本轮刻意未动** | 现役胜者实测为 `php_preg_match`（三实参即回填）⇒ 本批语义全落在 canonical 侧；裸侧仍是 `_ = flags` / `== 2` 旧口径 | 把裸侧改为委托 = **删除其现有实现体**，按宪法 §六.3 须先点头；一旦改委托，`diff_impl=3` 可归零且分桶序翻转不再有风险 |
| F-14（新登记） | 非法正则模式：PHP `preg_split(',/', 'a')` ⇒ `Warning: preg_split(): No ending delimiter ',' found` + **`false`**；AOT 编译失败路径 ⇒ 返回 **`[subject]`** | 实测两向不同形（`preg_match('[unclosed',…)` PHP `FALSE`+Warning vs AOT `0`，§13.2 亦记） | 属告警/错误返回族（与 F-9 同族不同位），且需发射期告警通道，未实测成本 |
| F-15（新登记） | 未定义常量时 AOT 告警文案为 `Undefined variable PREG_SPLIT_OFFSET_CAPTURE`，PHP 8 为 `Undefined constant` | 门 k2 基线可见（本批已把常量补上 ⇒ 该形转绿，但文案面仍在其它未定义常量上） | 诊断文案族，独立于本单修复面 |

### 17.8 门 M/N/O/D8 的 TSV 逐字节自证（修门未扰动读数）

复跑后 `c011_default_slot_tmp.tsv`、`c011_terminator_tmp.tsv` 与开跑前快照 **md5 全等**；`c010_class_ci_tmp.tsv` 仅末行 `ELAPSED=66s → 67s` 一行不同，19 条判定行逐字节不变 ⇒ 本轮为门 S 补 `AOT_BIN`/`ONLY` 两项能力**未扰动既有门读数**（同 §12.7 的「先修门后引用」口径）。

### 17.9 回归自查（本会话对自己上一条修订的更正）

我在本轮早先做「代次标注一致性修订」时，把 012 状态行写成 **「待裁决 … F-11/F-12 见 §14–§16」**，而 `grep -rn "F-11" docs/` 证明 **F-11 从未被登记**——是我从 F-12 的编号倒推出来的空位。已就地更正为「F-11 未登记（编号保留，勿误读为存在该项）」。⇒ 同 §17.1 的错误属一类：**序列里的空位不是条目**；写枚举 ID 清单前必须逐 ID grep 其登记位置。

## 18. R-145（2026-10-13）：F-1 静态调用非静态方法收口 + 一枚入口级新面孔 F-16

### 18.1 F-1 的判据不是「限定符写法」，而是「调用处有没有 $this」

我最初的写法是「`self::`/`parent::`/`static::` 一律豁免」，被实测否证 ⇒ **误杀实例方法里的 `static::m()`**（PHP = 5）。十形矩阵实测（PHP 8.5.8，全部进入门 P F 组常驻）：

| 臂 | 形态 | PHP 真值 |
|---|---|---|
| f1 `K::s()` | 静态方法 | `9` |
| f2 顶层 `K::m()` | 非静态、无作用域 | **Error，且可被 catch** |
| f3 `(new K)->m()` | 实例调用 | `5` |
| f4 实例方法内 `K::m()` | 显式自身类名 | `5`（**合法**） |
| f5 实例方法内 `self::m()` | | `5` |
| f6 实例方法内 `static::m()` | | `5` |
| f7 实例方法内 `parent::bm()` | 父类非静态 | `2` |
| f8 实例方法内 `Base::bm()` | 显式祖先类名 | `2` |
| f9 `Other::go()` 内 `Base::bm()` | 异类无亲缘 | **Error，跨帧可捕获** |
| f10 **静态方法**内 `self::m()` | | **Error** ⇒ 豁免不能只看限定符 |

⇒ 正确口径：**合法 ⟺ 调用处真有 $this（实例方法上下文）且限定类名与所属类同族**；顶层、静态方法、异类均 Fatal。

### 18.2 两路派发都要设闸，且判据来源不同（一处漏设即漏报）

| 路 | 触发条件 | 判定依据 | 位置 |
|---|---|---|---|
| 编译期直调 | 类名与方法名均可静态解析 ⇒ 生成 `@"K::m"(...)`，**不经运行期查名** | `method_is_static_map`（登记点与 `addMethod(.{.is_static = …})` 同源）+ `current_function_has_this` + IR 父链同族 | 新增 `staticEmitCallIsIllegal`（`native_linker.zig`），发射点接在 `.static_method_call` 直调支入口 |
| 运行期查名 | 动态类名 `$c::m()`、`static::` 等 | `ClassMethod.is_static` + `scopeClassMatches(lookup.owner)`（`getCurrentScopeClass` 沿 `ClassMeta.parent`） | `php_call_static_with_ctx` |

⚠️ **实测到的结构性约束**：`php_call_static` / `php_call_static_dynamic` 两个入口都以 `initNull()` 顶替 ctx（生成码 `php_call_static("static", "m", …, runtime.Value.initNull(), …)`）⇒ **运行期拿不到调用处 $this**，所以「静态方法上下文里 `self::m()`/`static::m()`」这一向只能靠编译期闸门；若某条形既走运行期又是作用域常量限定，本面会**漏报**（当前实测无此形，登记为残余风险）。

### 18.3 F-16（新立，P1，随 F-1 暴露）：入口只在 `__main__` 返回 error 时上报未捕获异常

`throw` 在无 handler 的帧里按既有口径 **返回 `Value.initNull()`**（`native_linker.zig:19492-19497` 注释写明「让调用方的 hasException() 检查路由」），而入口只写了 `catch |err| { if (hasException()) php_handle_uncaught_exception(); return err; }` ⇒ 正常返回时**没人上报**。实测修复前：

| 形 | PHP | AOT（修复前） |
|---|---|---|
| 顶层 `throw new LogicException("top-level")` | stderr `PHP Fatal error: Uncaught LogicException…` + **rc=255** | 仅 `PRE|`，**rc=0** |
| f2 / n15 静态调用致命面 | 同上 + rc=255 | `9|` 后静默，rc=0 |

⇒ 与 F-9 同族（「rc=0 让 CI 把致命当通过」）但**位置不同**：F-9 修的是 `php_object_call` 四个落点，本枚是**进程入口**。落地＝在入口 `__main__` 调用之后补一条 `if (runtime.hasException()) php_handle_uncaught_exception();`。修复后两形均 `rc=255` 且 Fatal 文本与 PHP 逐字同形（行号/路径差异按 §七.5 忽略）。

### 18.4 我自己引入的风险与复现（两条都做了实测）

1. **不可捕获回归**：直调支我最初照 `return error.RuntimeError;` 写 ⇒ f9 的异常冒成 Zig error 穿过 try ⇒ 实测「Uncaught + 文本打印两遍」；改为与 `.throw` 同形态 `return runtime.Value.initNull()` 并置 `return_generated = true` ⇒ f9 转 SAME。**结论：新增抛点必须复用既有 throw 终止符形态，不能自创错误传播方式。**
2. **unreachable-code（CODEGEN-013 同族）**：致命调用后面还有语句时，发射的 `return` 之后不得再排语句。实测形 `Other::go(){ $x = Base::bm(); echo "AFTER"; return $x; }` ⇒ 编译通过、AFTER 不打印、rc=255 与 PHP 一致 ⇒ 未复发。

### 18.5 门 P 扩形与注册红变化

门 P **39 → 52 形**（成本 206s）：新增 F 组 **f1…f13**（f1…f10 = 合法性矩阵；f11/f12/f13 = 动态类名路，见 §18.8），并加 `ONLY=` 子集开关。
读数 **`same=47 diff=5`**，注册红 = **`r10 v2 i1 i2 f12`**（n15 转绿，其守卫移交 f2/f9/f10；**新增一枚红 f12 = F-18 漏报**，属「本批故意不强修」，不是回归）。
代次自证：门脚本注释定稿后（md5 `5904939bd07eb24bba4011cf4e6dc69c`）**已在最终态复跑一次门 P**，读数与中途那次（`17936935…`）**逐字段相同**（`shapes=52 same=47 diff=5`、红集合相同）⇒ 纯注释改动未扰动臂集与读数。

### 18.6 验收读数（R-145 最终态，全链在 md5 定档后重跑）

| 腿 | 读数 |
|---|---|
| 门 P | **52 形 `same=47 diff=5`**，注册红 `r10 v2 i1 i2 f12`（n15 转绿；f12 = F-18 漏报）@206s |
| 门 S | 47 形 `same=47 diff=0 compile_fail=0 bad_probe=0` @186s |
| 门 M / N / O / D8 | 19/19 @67s、7/7 @24s、6/6 @20s、`guard_same=14 defect_red=0` @49s |
| 门 Q / R | `same=5` @22s、`same=8 diff=1 terminate_lost=0` @38s（唯一红 h6 = F-10） |
| 普查门 B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` @1s（本批未碰 `builtin_map`） |
| `zig build test` | **21/21 steps；326/326 tests passed** |
| 影子 | `total=68 same=0 diff=68 miss=0 invalid=0` @1037s；**new-side 列相对 R-144 代 `changed_rows=68 / unchanged=0`** ⇒ 入口守卫进入每个 `main.zig`，**本批是一次彻底的影子重冻事件**（R-144 是 `delta_rows=0` 的发射中性，两者性质不同，勿混用）；前缀仍 `be305cfa`，须在「提交」时按当代次重冻 |
| 主回归 | 08:32:40 报表 **Total 68 / Pass 67 / Fail(Compile) 0 / Fail(Runtime) 0 / Fail(Diff) 0 / Skip 1**（失败明细仅 1 行 = `f004 SKIP`）⇒ **入口新增的未捕获上报未误伤任何正常收尾脚本**（F-16 的主要风险面已实测排除）。**回收枚 = 0**，且取证方式已改为「查失败明细行的存在性」而非汇总数（详见 §18.7 自纠条与 [[feedback-aot-regression-rules]] 规则 27） |
| .php / 残留 | `find fuzzy_scripts_720 -name '*.php' | wc -l` = 403（与开跑前一致）；`aot_compile_*` / `.zigphp_aot_build_*` = 0 |

代次（最终）：`runtime_lib_template.zig` = `67a606758c6e88df516a9c5a7c909888`、`native_linker.zig` = `49a3da31660fef4963b8eb50d7587987`、`ir_generator.zig` = `0242d8b5a960a8b8e06b063494f6ec23`（R-145 未再变）、二进制 = `fec549b26ab4d58f77bfa5316f61445e`、门 P 脚本 = `5904939bd07eb24bba4011cf4e6dc69c`、门 S 脚本 = `f3c2c9e6b1a319cd76a297217212fb54`；本批中途代次 `6b9…`/`0b9cf3a7…`/`d40ee9a9…` 一并作废（见规则 25）。

### 18.7 本批遗留

| # | 面孔 | 状态 |
|---|---|---|
| ~~F-1 残余~~ | 「静态方法上下文经动态类名调非静态方法」这一向 | **已升格为 F-18 并建成常驻臂 f11/f12/f13**，见 §18.8 |
| F-17 | trait 名限定调用 `Tr::tm()`：PHP 给 `Deprecated` 两条 + Error；AOT 直接 Error、无 Deprecated 文本 | 新登记（告警族，与 F-15 同区） |
| **F-18** | **动态类名路 `$c::m()` 的静态性只能漏报、不能误杀**（门 P 注册红 f12） | 见 §18.8 四向实测表 + 一次已回退的失败尝试 |

### 18.8 F-18（新立并登记，本批**故意不强修**）：动态类名路 `$c::m()` 的静态性只能漏报、不能误杀

门 P 新增 f11/f12/f13 三形专门打这条路，PHP 真值与 AOT 现状（实测）：

| 臂 | 形 | PHP 8.5.8 | AOT（R-145 终态） |
|---|---|---|---|
| f11 | 实例方法内 `$c = "Base"; $c::bm();`（同族） | `4` + `TAIL` | `4` ✅ |
| f12 | **静态方法**内 `$c = "Base"; $c::bm();` | `CAUGHT\|Error\|Non-static method Base::bm() cannot be called statically` + `TAIL` | `4` ⇒ **漏报**（注册红） |
| f13 | 隔代 `C extends B extends A` 内 `A::am()` | `7` | `7` ✅ |
| 另测 | 顶层 `$c = "K"; $c::m();` | Error（可捕获） | Error ✅ |

**为什么本批不收**：我试过把 `.static_method_call` 两支都改成透传 ctx、运行期只看 ctx 判 $this —— 结果 **f11 从合法变致命（假阳性）**，f12 仍不可捕获。⇒ 说明 **AOT 实例方法桩的 `ctx` 并不可信作 $this**（要么入口 `php_call_static` 包装层恒传 `initNull`，要么 `php_object_call` 派发时没把对象当 ctx 传下去），要正确判必须先把「调用帧是否有 $this」这个事实可靠地送到运行期，属独立的 ctx 管道问题。

⇒ 取舍：**「宁可漏报不可误杀」**——误杀是把合法 PHP 判死（比原来更坏，且影子/主回归都可能新增红），漏报只是维持 F-1 修前的状态。回退后 f11/f13 转绿、f12 作为第 5 枚注册红常驻门 P。
| F-2（r10） | **早前登记的归因两条都被本轮取证否证**：① 「属性写语句缺 `hasException` 路由」——`native_linker.zig:24010-24032` 明确发射了该路由；② 「抛出与消息本身逐字正确，只是不可捕获 ⇒ 跨帧传播坏了」——**对照臂实测**：同 try/catch 结构下「普通函数内 `throw new LogicException`」AOT 与 PHP **逐字节等值（CAUGHT + TAIL）** ⇒ 跨帧捕获链路是好的。⇒ 断点只在 **ReflectionMethod 只读属性写这一条落点**（AOT 给 `Fatal error … #0 {main}` + rc=255，PHP 给 `CAUGHT|ReflectionException|Cannot set read-only property ReflectionMethod::$class` + `TAIL`），且消息文本本身仍逐字正确。下一轮归因应查该形实际走的是哪一支发射（`:22895` 组 vs `php_object_set_dynamic` / `attachReflectionReadOnlyProps` 的 `__set` 路），而非再改通用传播 | 待重新归因（范围已收窄到单点） |

## 19. R-146（2026-10-13）：F-2（r10）收口，并长出一枚更危险的新面孔 F-20

### 19.1 归因：上一轮收窄到单点后，一次命中

抛出点是本工单 **R-138 自己写的** `reflectionRoSet`（`git log -S 'error.ReflectionReadOnlyProperty'` 指到 `1d48649`，全仓仅此一处使用）：

```zig
// src/aot/runtime_lib_template.zig:5021（修复前）
_ = throwThrowable("ReflectionException", msg, alloc) catch {};
return error.ReflectionReadOnlyProperty;   // ← 断点
```

发射侧生成的路由本身**是对的**（实测取到生成码）：

```zig
// .zigphp_aot_build_*/main.zig
_ = try runtime.php_object_set(reg_4, "class", reg_3);
if (runtime.hasException()) { …; current_block = 1; continue; }   // 1 = catch 块
```

⇒ 但 `try` 在 `hasException()` **之前**就把 Zig error 抛出整个状态机 ⇒ 异常冒到入口 ⇒ 表现为「Uncaught + rc=255」而非「CAUGHT + TAIL」。修法＝改成 F-9 已定型的形态（`return throwThrowable(...)`，异常置位 + 正常返回，让上层 `hasException()` 路由）：

```zig
// src/aot/runtime_lib_template.zig:5021（修复后）
return throwThrowable("ReflectionException", msg, alloc);
```

脏写风险已核：上层 `php_object_set` → `tryMagicSet`（`:19508`）对返回值是 `_ = try …`（只取 bool），`php_object_set` 随后返回 `initNull()` ⇒ 异常对象不会入任何槽 ⇒ 不重演 RUNTIME-002 的 G3。

### 19.2 F-20（新立，P1，注册红 f14）：try **之前**语句的未捕获异常被后一个 try 的 catch 吃掉

最小复现（三形对照，实测）：

| 形 | PHP 8.5.8 | AOT |
|---|---|---|
| c：`$rp = new ReflectionProperty("C","nope"); echo "AFTER_CTOR";` | Fatal + **rc=255**，AFTER 不打印 | 同形（Fatal + rc=255）✅ |
| c2：同一行构造放进 try 里 | `CAUGHT\|ReflectionException\|Property C::$nope does not exist` + TAIL | 逐字等值 ✅ |
| **c3：构造在 try 之前，后面另起一个 try/catch** | Fatal + **rc=255** | **`CONSUMED` + rc=0** ⇒ 前一语句的挂起异常被**无关 try 的 catch** 消费 |

取证到行的关键事实：**发射顺序是正确的**（`php_object_new_with_constructor` 在 `// Try block begin` 之前），错在**该指令发射时 `current_exception_handler` 已非空** ⇒ 生成出 `current_block = 1`（= 后一个 try 的 catch）。⇒ 归属缺陷在块级 `exception_handler`（`ir_generator.zig:3356` `try_block.exception_handler = catch_block` 与 `:536` 的上下文回填 + 发射侧 `:18028/:26203` 按块取值），**不推测、不盲改**：需要一轮专门的 IR 块归属归因（与 CODEGEN-006 派发归属族、F-13 的「实参个数改变物化」同族症状：跨作用域的状态泄漏）。

**是否本批引入 —— 已用冻结前缀否证**：同一 c3 形分别用现二进制（`fec549b2…`）与前缀 `be305cfab370f56e515d6e9cd63b10ea`（R-122 代冻结，早于 R-138）各编译一次 ⇒ **输出逐字相同**（`CONSUMED` + `TAIL` + rc=0），而 PHP = Fatal + rc=255。⇒ **F-20 是既存缺陷**，与 R-145／R-146 的抛出形态改动无关；也正因门 P 此前无臂，它一直没被记录。候选归因点 `ir_generator.zig:3356`（`try_block.exception_handler = catch_block`）与 `:536` 块回填、发射侧 `:18028`／`:26203` 按块取 handler —— **均只列为候选，未取证**。

### 19.3 门 P 终态与代次

门 P **52 → 57 形**（脚本 md5 见下），新增 W 组：`w1`（r10 原形 `->class`）、`w2`（姊妹形 `->name`）、`w3`（`ReflectionClass::$name` 第三支）、`w4` **控制臂**（用户类普通 `public int $ro` 必须仍可改 ⇒ 防我把只读判定扩大化），以及注册红 `f14`。

读数 **`same=52 diff=5`**，注册红 = **`v2 i1 i2 f12 f14`**：`r10`/`n15` 两枚转绿（F-2／F-1 收口），新增 `f14`（F-20）。

### 19.4 验收读数（R-146 态，全链重跑）

| 腿 | 读数 |
|---|---|
| 门 P | **57 形 `same=52 diff=5`**，注册红 `v2 i1 i2 f12 f14`（r10、n15 双转绿）@227s |
| 门 S | 47 形 `same=47 diff=0` @186s |
| 门 M / N / O / D8 | 19/19 @69s、7/7 @25s、6/6 @21s、`guard_same=14 defect_red=0` @50s |
| 门 Q / R | `same=5` @21s、`same=8 diff=1 terminate_lost=0` @38s |
| 普查门 B | `dup_rows=33 diff_impl=3 field_diff=0 identical=30` @2s（未碰 map） |
| `zig build test` | **21/21 steps；326/326 tests passed** |
| 主回归 | 09:27:56 **Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 0 / Skip 1**（明细 1 行 `f004`）⇒ 与 R-145 代逐行同构，**改抛出形态未扰动语料、未冒新增红** |
| 影子 | **未跑**（本批纯模板侧、二进制 `fec549b2…` 未重建 ⇒ 发射面按定义不变）。抽样代证：`f016`=`f21c7080f205cd0b46e7e9092ecd69a1`、`f097`=`a4926b5feb1b06cb9030d00e73f884db` 与 R-145 登记的 new-side 列**逐字节相同** |
| .php / 残留 | `fuzzy_scripts_720/pass/*.php` = 68、`fuzzy_scripts_720` 全部 `.php` = 403（与开跑前一致）；`aot_compile_*` / `.zigphp_aot_build_*` = 0 |

代次：`runtime_lib_template.zig` = `4ff0befc7c5b50d4fcfb8b1fd1f057e7`；`native_linker.zig` = `49a3da31…`（未变）、`ir_generator.zig` = `0242d8b5…`（未变）、二进制 = `fec549b26ab4d58f77bfa5316f61445e`（未重建）、门 P 脚本 = `3d5c0c8aa86954d389f533c1b1c184e9`、门 S 脚本 = `f3c2c9e6…`（未变）。R-145 中途轮模板 `67a60675…`、门 P 脚本 `5904939b…` 作废（见规则 25）。

## 20. R-147（2026-10-13）：F-20 修复（阻断 handler 倒灌）+ 新立 F-21（同底座）

### 20.1 归因 A/B：不是 IR 生成，是优化器的块合并把 handler 倒灌

| 手段 | entry 块头 | c3 行为 |
|---|---|---|
| `--aot-max-iterations=0`（关优化） | `0 => { // entry`（**无 handler**） | `PHP Fatal error: Uncaught ReflectionException…` + **rc=255** ≡ PHP |
| 默认档（1 轮） | `0 => { // entry (handler: 1)` | `CONSUMED` + `TAIL` + rc=0 |

⇒ 定性到 `optimizer.zig` 的 `cleanupCFGInFunction`（`:4263` 调 `tryMergeBlockWithSingleSuccessor`，`:4373` 把后继块的 handler 转移到前驱块），其原注释自陈「若 try_block 并入 entry，entry 必须继承 try_block 的 exception_handler」——**这正是缺陷本身**：发射侧路由**完全按块级 handler** 决定（`.try_begin`/`.try_end` 在发射侧只输出注释、不改状态），于是块内「try 之前」的语句也被路由进 catch。

### 20.2 修复：一条守卫，方向与既有嵌套守卫对称

```zig
// src/aot/optimizer.zig  tryMergeBlockWithSingleSuccessor（紧随既有「嵌套 try 禁并」守卫之后）
// 反向同理：不得把 try_body 的 handler 倒灌进一个已有指令且自身不在 try 内的前驱块。
if (block.exception_handler == null and succ.exception_handler != null and
    block.instructions.items.len > 0)
{
    return false;
}
```

- 只跳过合并、不改控制流：两臂之间仍是线性 fallthrough，仅多一个块。
- 既有守卫（`block.handler != null and succ.handler != null and 不等 ⇒ 禁并`）管的是「外层 catch 尾跳内层 try_body」，新增的是**反向**（无前驱 handler 时不得继承后继）⇒ 两条合起来才封住倒灌的两个方向。

### 20.3 修复验证（三形 + 门禁）

| 形 | PHP | AOT 修复前 | AOT 修复后 |
|---|---|---|---|
| c3（try 前语句抛未捕获异常） | Fatal + rc=255 | `CONSUMED` + rc=0 | **Fatal + rc=255** ✅ |
| c2（正常 try/catch + 循环内 throw/catch + 兜底） | 三支全等 | 全等 | 全等 ✅（未扰动） |
| 门臂 f14 | — | DIFF | **SAME** ✅ |

### 20.4 F-21（新立，注册红 f15；与 F-20 **同底座**，本批不强修）

实测把范围收窄到一支，其余三支其实是对的：

| 面 | PHP | AOT |
|---|---|---|
| 同 try 多臂选择：`catch (OutOfRangeException)` → `catch (LogicException)` | `SECOND-ARM\|L` | **逐字相同** ✅（f16 臂） |
| 子类匹配：`catch (RuntimeException)` 收 `MyEx` | `SUBCLASS-OK\|MyEx` | 相同 ✅ |
| 本层无匹配 + `Throwable` 兜底 | `FALLBACK\|R` | 相同 ✅ |
| **嵌套** try 且内层唯一臂类型不符 ⇒ 应由外层接管 | `OUTER-OK\|nested` | **`WRONG-CATCH`** ⇒ 进不匹配的内层臂（f15 注册红） |

⇒ 类型过滤器存在且基本正确，缺的是**异常区域的嵌套/外溢表示**（本层全部臂不匹配时应向外层 handler 继续抛，AOT 直接进臂）。与 F-20 同因（块级 handler 无区域栈），故**留作下一轮同一改动的两半**，本轮只建常驻臂（f15 红 + f16 正确面守卫，防按 F-21 时把已对的三支改坏）。

### 20.5 F-20/F-21 均非本批引入（冻结前缀 A/B）

| 形 | 现二进制 | 前缀 `be305cfab370f56e515d6e9cd63b10ea`（R-122 代） |
|---|---|---|
| c3 | 修复前 `CONSUMED` + rc=0 | **相同** ⇒ F-20 既存 |
| 嵌套 c2 | `WRONG-CATCH` | **相同** ⇒ F-21 既存 |

### 20.6 验收读数（R-147）

| 腿 | 读数 |
|---|---|
| 门 P | 59 形，注册红 = `v2 i1 i2 f12 f15`（**f14 转绿**）；`shapes=59 same=54 diff=5 compile_fail=0 bad_probe=0 residue=0` @237s ⇒ **判据满足** |
| 门 S | `shapes=47 same=47 diff=0` @192s |
| 门 M / N / O / D8 | 19/19 @69s、7/7 @24s、6/6 @21s、`defect_red=0 guard_same=14` @50s |
| 门 Q / R | `same=5` @22s、`same=8 diff=1 terminate_lost=0` @38s |
| 普查门 B | `dup_rows=33 diff_impl=3 field_diff=0 identical=30` @2s（未碰 map） |
| `zig build test` | **21/21 steps；326/326 tests passed** |
| 影子 | `total=68 same=0 diff=68 miss=0 invalid=0` @1092s（前缀仍 `be305cfa`，`diff=68` 是 R-145 入口守卫的既有漂移）；**跨代 new-side 整列不可比（见 §20.8）**⇒ 改用 §20.7 静态可达界 + 抽样复核：本轮 `f016`=`f21c7080f205cd0b46e7e9092ecd69a1`、`f097`=`a4926b5feb1b06cb9030d00e73f884db` 与 R-145/R-146 登记值**逐字节相同**（两枚均无 `try` ⇒ 与守卫不可达一致）；本轮整列已落盘 `fuzzy_scripts_720/tmp/c010_shadow_newside_r147_tmp.txt` |
| 主回归 | 10:23:30 报表 **Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 0 / Skip 1**（失败明细仅 1 行 `f004_oop_deep_inheritance_magic.php SKIP PHP_error_exit=255`）⇒ 与 R-145/R-146 代逐行等值，**本批回收枚 = 0**（判据取明细行存在性，harness 汇总行的 `PASS` 含 SKIP，见 [[feedback-aot-regression-rules]] 规则 27） |

### 20.7 扰动面上界：只有含 `try` 的函数才可能受影响（静态可达 + 实测 grep）

守卫的触发前置是 `succ.exception_handler != null`，而 `block.exception_handler` 在整个 AOT 侧**只有两枚赋值点**，且都在 try 区域：

```zig
// src/aot/ir_generator.zig
:536   block.exception_handler = context.catch_block;
:3356  try_block.exception_handler = catch_block;
```

（`optimizer.zig:4386` 是转移、不是新来源。）⇒ 不含 `try` 的函数里 `exception_handler` 恒 null ⇒ 守卫恒不命中 ⇒ 合并决策与合并前的 IR 与 R-146 代**逐字节相同**。

| 面 | 实测 |
|---|---|
| 语料含 `try {` 的脚本 | **7 枚**：`f006`、`f009`（×2）、`f031`、`f034`、`f048`、`f067`、`f090`（`grep -rlE "\btry\s*\{"` 逐枚计数） |
| 其余 61 枚 | 守卫不可达 ⇒ 发射面**必然零扰动** |
| 主回归 | 覆盖全部 68 枚运行时输出（含上述 7 枚）⇒ 若守卫改了行为会显红 |

⇒ 本批发射面扰动**上界 7/68**，且该 7 枚的运行时面由主回归直接判定。

**守卫开/关 A/B 实测**（资产 `fuzzy_scripts_720/tmp/c018_f20_guard_ab_tmp.sh`，@70s 重编译 + 14 次 AOT 编译；对照二进制装 `/tmp/noguard`，**不覆盖**验收代次 `8b5c65a1…`）：

| 语料（含 `try` 的 7 枚） | 守卫开（R-147） | 守卫关 | 判定 |
|---|---|---|---|
| `f006_oop_observer_event_dispatcher` | `8001f7a3…` | `8001f7a3…` | **未变**（该形的 try 前无「有指令且单后继进 try_body」的合并位） |
| `f009_oop_decorator_chain_command` | `e11c94dc…` | `c17438e5…` | 变 |
| `f031_builder_fluent_immutable` | `e86c95f2…` | `32fd307e…` | 变 |
| `f034_template_method_pipeline` | `1836db77…` | `30e4b531…` | 变 |
| `f048_match_pattern_dispatch` | `850b7268…` | `5671f5df…` | 变 |
| `f067_json_parser_schema_path_diff` | `cb8d9ded…` | `09565356…` | 变 |
| `f090_promise_future_async_concurrent` | `d133cdf4…` | `9f5dc5d2…` | 变 |

⇒ **`AB_DONE shapes=7 changed=6 unchanged=1`** ⇒ 真实扰动面 = **6/68**（上界 7 收紧为 6；其余 62 枚由静态不可达 + `f016`/`f097` 抽样逐字节相同作证）。
运行时面：主回归 10:23 报表 **Pass 67 / Fail_* 0 / Skip 1**、逐行与上一代等值 ⇒ 这 6 枚的**输出不变**，变的只是 CFG 切块（守卫只 `return false` 跳过合并，不多不少一个块，线性 fallthrough 保持）。
复测安全：脚本带 `trap restore EXIT INT TERM`，实测 `RESTORE_OK`（`optimizer.zig` 复原 `6cffa137…`）、`canonical_bin_still=8b5c65a1…`、`repo_residue=0`。

### 20.8 取证现状：本轮**没有**可用的 68 行前代 new-side 列（含一次自我纠正）

先纠正本工单写作时的一处口径错误：影子门**只哈希 `main.zig`**，而模板代码整体进 `runtime_lib.zig`——本轮同一 KEEP_TEMP 目录内实测 `grep -c "Cannot set read-only property"` ⇒ `main.zig` = **0**、`runtime_lib.zig` = **3**（此前 §19「纯模板侧 ⇒ 发射面不变」只是推断，现已实证）。这条同时意味着：`delta_rows=0` 只能证「发射器三件套（`native_linker`/`ir_generator`/`optimizer`）未动或动了不生效」，**不能**当作「运行面不变」的证据。

本轮清点现存快照，结论是**跨代 68 行比较做不了**：

| 文件 | 行数 | mtime | 判定 |
|---|---|---|---|
| `/tmp/c015_shadow_prev_newside.txt` | 68 | 10-13 06:54 | 影子腿**开跑前**截的，属 06:5x 那一轮（R-145 中途轮）⇒ 发射器状态与定档代不同 |
| `/tmp/c015_shadow_now_newside.txt` | **5** | 10-13 06:55 | 影子腿**开跑 1 分钟**时截的 ⇒ `/tmp/c015_shadow_delta.txt` 头部即 `1,68c1,5`，该次比较无效 |
| `fuzzy_scripts_720/tmp/c010_r5_presnap/`、`c010_genB_snapshot/` | 68 | 10-08/10-09 | 早于 R-138，不可比 |
| R-145 定档 / R-146 的整列 | — | — | **未落盘**（TSV 被本轮覆盖），文档只登记了 `f016`/`f097` 两枚抽样值 |

抽查也否证了「拿 06:5x 中途轮当基线」：`f004`（**无 `try`**）在 `prev`=`edc843ae…`／`now`=`8a3cbd10…`／本轮=`834353f1…`（同一二进制两次独立编译逐字节相同）三列互不相同 ⇒ 差异来自发射器代次，不是本轮守卫；用它算出的任何 `changed_rows` 都归不了因。

⇒ 本轮发射面判据改为两条**可实测**的：① §20.7 静态可达界（61 枚守卫不可达）＋抽样复核 `f016`=`f21c7080…`、`f097`=`a4926b5f…` 与 R-145/R-146 登记值是否仍逐字节相同；② 对 7 枚含 `try` 的语料做**守卫开/关 A/B**（关守卫重编译一次、只编这 7 枚，再把 `optimizer.zig` 复原重编译），得到 `changed_rows ∈ [0,7]` 的确切值。R-147 整列 new-side 已在腿收尾后落盘为 `/tmp/c017_shadow_r147_newside.txt`（**断言行数=68**），作为后续轮次的前代基线。

纪律（写入记忆）：**跨代比较前必须先断言快照行数**（成对表 136 行 / 单列 68 行），腿未收尾的表一律不得用作等值证据；每轮影子收尾后**立刻**落盘 new-side 单列，否则下一轮就没有基线。
