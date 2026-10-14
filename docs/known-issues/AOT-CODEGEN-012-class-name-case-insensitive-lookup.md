# AOT-CODEGEN-012 · PHP 类名不区分大小写查找缺失：运行期类表精确匹配 ⇒ 跨大小写类使用全灭（new / instanceof / 静态调用 / class_exists / ::常量）；`extends` 与 `::class`/`get_class` 拼写保真已绿

**问题 ID**: AOT-CODEGEN-012
**优先级**: **P1**（合法 PHP 跨大小写类使用即命中；同族缺陷 = AOT-CODEGEN-010 §8 #6 函数名 CI，R-124/R-127 已修）
**性质**: 运行期类表查名（`runtime_lib_template.zig findClass` 精确匹配 + `php_instanceof` 直接名比较）⇒ **仅 AOT**（解释器/字节码的类表为独立实现，本单不涉）
**状态**: **R-1/R-2/R-3/R-131/R-132/R-136/R-137a/R-138/R-141/R-142/R-143/R-144/R-145/R-146/R-147/R-148/R-148b/R-149/R-150/R-151/R-151b/R-154/R-155/R-156/R-158b 已落地并验收（★R-158b=F-42：`tryRemoveTrampolineBlock` 释放快转块前改道 `exception_handler`（`optimizer.zig` +29/−0）⇒ **门 Z** 面孔门 `dangling 6→0`、门 P `compile_fail 2→0`（`f35` 转绿、`f34` 转为语义红 ⇒ **新立 F-44**：`ir_generator.zig:3744 redirectThroughFinally` 在 finally 体内 throw 时把整个 finally 体重发一份；A/B 关 cfg_cleanup 实测仍双打 ⇒ 属暴露非引入，待裁决）；同时**否证 §30.6 两条口径**——「`.index` 陈旧」（`analysis.zig:273-275 rebuildCFG` 一直统一重编号）与「用 `Dead blocks removed` 当分母」（旗标只由三枚删块站点之一 `:3364` 递增，恰好漏掉肇事的 trampoline 面）；门 Z 全语料普查 `total=68 dangling=0 ok=68` ⇒ 语料对本族零暴露）／★R-156=F-22：门 P 注册红 `f26` 已回收，现行门 P = **78 形 `same=72 diff=4 compile_fail=2`**，四枚红 `v2 i1 i2 f12` + 两枚既存 panic 臂 `f34 f35`=新立 F-42；同时改判 F-36（与 Error 支无关，真机制＝file/line 在 setException 惰性注入 ⇒ 未抛出的异常对象取不到位置）并新立 F-43（`function_exists("php_bool_or")` AOT=true ⇒ helper 登记泄漏成 PHP 可见函数名，与 F-4 同族））**（R-138 = 内省枚举族八项落地 + 永久侧门 P 建成，2026-10-12，详见 §12；R-141/142/143 = F-8a 参数默认值面、F-12/F-12b 参数名面，详见 §14–§16；**R-144 = F-5/F-7 PCRE flags/offset 全族收口 + 新立并修复 F-13（`preg_match` 实参 ≥4 时引用装填丢失），详见 §17**）。⚠️ **§10 的 R-137b/R-137c 记录为假阳性**（抛出支从未入库，已由 R-138 重落，更正见 §10 内联与 §12.0）。**门 P 现行读数（R-149 定档）= **76 形 `same=71 diff=5`**，5 枚恰为注册红 `v2/i1/i2/f12/f26`（F-8b／F-3×2／F-18 漏报／**F-22 多语句 finally**）；**f33（原 F-23）已由 R-149 的 F-24c 转绿**——它不是独立缺陷，而是「`extends`/`implements` 父名被解析两次」的症状（工单 §22）；新建**门 T**（R-150 定档 **19 形**，F-24 族：7 枚注册红 `t2 t8 t9 t11 t12 t13 t19` + 1 枚注册 compile_fail `t17`；F-24a/t1·t4·t5·t14 与 F-24b/t6 已转绿，另新立 F-24e 与 F-25）；**F-21 六枚臂（f15 f17 f19 f20 f21 f23）已由 R-148 全部转绿**，catch 类型名解析六枚臂（f27–f32）同批转绿；其「嵌套外溢」旧措辞作废（真根因＝单臂 catch 不建派发块，见 §21.1）；**r10 与 n15 已分别由 R-146／R-145 转绿，f14（F-20 handler 倒灌）由 R-147 转绿**；**n15 = F-1 已于 R-145 转绿**，其守卫移交 F 组 f1…f13（合法性矩阵，全部 PHP 8.5.8 实测）。R-144 轮为 39 形 `same=34 diff=5`（历史快照）；R-138 建成代次为 35 形 `same=31 diff=4`（见 §12.7，仅作历史快照）。**门 S 现行读数（R-144 建成轮）= 47 形 `same=47 diff=0`，判据即 `diff=0`（本门无注册红）**，修复前 30 形 `same=9 diff=21`（§17.1/§17.5）。门 M 19 形 `red=0 green=19`、门 D8 14/14、门 N 7/7、门 O 6/6、门 Q `same=5`、门 R `same=8 diff=1`、普查门 B `diff_impl=3`；`zig build test` 21/21 & 326/326；主回归 **13:38:37（R-149 代）Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 0 / Skip 1**，且影子 vs R-148b 列 **`changed_rows=0`**（F-24c 与 F-24a/b 均语料发射中性实测：影子 vs R-148b、vs R-149 两次 `changed_rows=0`）（★R-148a 代曾掉到 Pass 66：本批自造的 `f006 catch (\Throwable)` 回归，已由 `resolveClassName` 收口复证，见 §21.9/§21.10）（失败明细仅 1 行 `f004 SKIP` ⇒ 回收枚 0；判据取明细行存在性而非汇总数，见 [[feedback-aot-regression-rules]] 规则 27）；影子 `total=68 same=0 diff=68 miss=0 invalid=0` @1037s，且 **new-side 列相对 R-144 代 `changed_rows=68 / unchanged=0`** ⇒ R-145 因入口守卫进入每个 `main.zig`，**是一次彻底的影子重冻事件**（前缀 `be305cfa` 须在「提交」时按当代次重冻）。**当前代次（R-149 定档）**：`ir_generator.zig` **`f3d13cb82395d945d2a246b2158589ea`**（R-149 F-24c；R-148b 值 `81dffec5…` 作废）／`optimizer.zig` `6cffa137…`（R-147）／二进制 **`1abad89e2166d15e32fc304e2d071c28`**／门 P 脚本 **`cb1a622797cc7b0519f38dc1f8ca3bb1`**（76 形）／影子基线列 `c010_shadow_newside_r148b_tmp.txt`（表身 `f19fb070…`，R-147/R-148a 两列并存）；旧值 `8b5c65a1…`／`bbff3b4a…`／`001bc245…`／`8dae7b2b…`／`eab47607…`／`37a86a66…` 作废。原「R-147 定档」：`runtime_lib_template.zig` `4ff0befc7c5b50d4fcfb8b1fd1f057e7`（R-147 未变）／`native_linker.zig` `49a3da31660fef4963b8eb50d7587987`（未变）／`ir_generator.zig` `0242d8b5a960a8b8e06b063494f6ec23`（未变）／**`optimizer.zig` `6cffa137f766bdd2a13769c7ba3314b5`（本轮新增守卫）**／二进制 `8b5c65a1f34af70977e73e6c4dea2bd7`（**R-147 改优化器 ⇒ 已重建**，`fec549b26ab4d58f77bfa5316f61445e` 作废）／门 P 脚本 `eab47607d8d4d02979ed17dcdc76bb3b`／门 S 脚本 `f3c2c9e6b1a319cd76a297217212fb54`（未变）；影子 new-side 整列已落盘 `fuzzy_scripts_720/tmp/c010_shadow_newside_r147_tmp.txt`（68 行，表身 md5 `628aa13b3778359d1210c6800901f687`）；原 `3d5c0c8aa86954d389f533c1b1c184e9`（门 P 39/57 形代）；本批中途代次 `0b9cf3a7…`/`d40ee9a9…` 与 R-144 轮 `5c0ecf42…`/`86174723…`、R-145 中途轮 `67a60675…`（模板）与门 P `5904939b…`、R-144 轮 `5c0ecf42…`/`86174723…`、R-138 轮 `b356e19e…` 均作废（见规则 25）。**待裁决**：F-3（门 P 注册红 i1/i2）；F-1 已落地（R-145，§18）、F-2 已落地（R-146，§19）；**待裁决 F-25 修法（甲 改模板捕获名⇒全 68 枚漂移需重冻／乙 只给撞名用户函数改 Zig 符号⇒零漂移、建议／丙 甲+乙）**；**新增 F-29「类声明提前登记」（R-153 归因）＝F-24d 的硬前置：AOT 启动期一次性登记所有类，PHP 在声明语句执行处登记（d8/d9 实测 `class_exists` PHP=n／AOT=y）⇒ 直接在登记处加「父类缺失即 fatal」会把 PHP 不报错的场景变成 over-fatal，两者必须一起排；语料面：未解析父/接口引用 0 枚、作用域内类声明 0 枚 ⇒ 双双看不见**；F-27 第 1 层（属性位）已落地（R-151b，§25.3）⇒ **R-154 更正：类型检查实为三条互不复用的链，R-151b 只收了属性位**（形参位 v9/v27/v28、`instanceof` 位 v5/v6 由 R-154 落地；返回值位的「绿」被证伪为新立 F-35，见 §28.2/§28.9）；F-28 已随 R-154 落地，并新建永久侧门 **门 V**（定档 **29 形 `same=18 diff=11 compile_fail=0 bad_probe=0`** @122s，登记轮修前 `same=10 diff=19`）；F-24d（t9/t11）待修；**★R-154 新立六张面孔（全部未修、待裁决，§28.4–§28.9）＝F-30：PHP 8.5.8 实测 `Error` **不再继承** `Exception`（`is_subclass_of('TypeError','Exception')=false`、`get_parent_class('Error')=false`），AOT 仍按旧层级过度捕获 ⇒ 跨切面／F-31：`throwException:21822` 把异常置成**字符串**伪值 ⇒ `catch` 永不命中且 fatal 文本类名错，调用点实测 **17 枚**，逐枚须先测真值异常类别／F-32：`PHPObject.toString:19437` 无 `__toString` 时 fail-open 返类名／F-33：`count()` 对非 Countable 返 0（语料高频，改前必须普查）／F-34：`spl_object_id()` 对闭包返 0／F-35：返回值类型位**完全不校验**（`: object` 返回 `int` 静默放行）；**★R-155（§29）＝门 W（20 形 `same=7 diff=13`）与门 X（9 形）建成 ⇒ 实测否证我自己提的「`php_count` 需补解引用」前置（x1/x2/x3 引用三形本就与真值等值 ⇒ 引用在载入侧已解）；F-33 第一批已落地（`php_count` 非 Countable ⇒ `throwThrowable("TypeError", …)` + 专用 helper `countArgTypeName`）⇒ 门 X `x6`/`x9` 转绿且 `x4` 按 §28.7.2 **设计留红**（接口判定须与 F-3 内建接口表同批，否则打红 `SplFixedArray`/`ArrayObject`）、门 V `v15` 转绿（`18/11`→`19/10`）；另新立 F-36（`new Error(...)->getFile()` 为空而 `new Exception(...)` 非空 ⇒ **Error 根与 Exception 根不等价**，「搬根」必须含构造期属性初始化）／F-37（`intdiv(1,0)` 打印 `error: DivisionByZero` 且 **rc=1** ⇒ Zig error 外逸，属 F-9/R-145「未捕获必须 PHP 风格 fatal + rc=255」族的漏网站点，门 R 现有臂抓不到）／F-38（`zig build test-aot` **6 处编译错误**全在 `test {}` 块内 ⇒ AOT 单测步骤长期失编译；运行期模板的编译验证实际由 AOT 产品编译承担，旧「`zig build test` 覆盖模板」口径作废，见 §28.13.2）**；**F-20（f14，P1，try 前语句异常被无关 catch 吞）已落地（R-147，§20.2–§20.3）＋**F-21（六枚臂 f15 f17 f19 f20 f21 f23）已落地（R-148/R-148b，§21：根因＝单臂 catch 不建派发块 + 末臂 else 落点；含本批自造的 `\Throwable` 回归收口）**＋**新立 F-22（f26，多语句 finally 与 pending 异常共存，属暴露非引入）与 F-23（f33，命名空间用户类 `extends \Exception` 后内建方法整族丢失，前缀 `be305cfa` 证非本批引入）待归因****＋F-4 去重（删代码，§17.7 记「裸侧未动」的理由）／F-6（`debug_backtrace`）／F-8b（设计分叉，§14.4）／F-10（删功能，登于 013）／**F-13b、F-14、F-15（§17.7）**／**F-16（入口未捕获异常上报，R-145 已修，§18.3）、F-17（trait 名限定的 Deprecated 文本，§18.7）**；F-5/F-7/F-12/F-12b 已落地；**F-11 未登记（编号保留，勿误读为存在该项）**。门 M 终态 **17 形 `red=0 green=17`**（链 XI 同口径全绿：影子 68/68、主回归 Pass 67/Skip 1、门 D8/H/H2/I/E/F/G 注册值保持，2026-10-11 07:05:35 报表）：门 M `red=5→0 green=3→8 compile_fail=0 bad_probe=0 residue=0`（链 VIII 同口径全绿：影子 68/68 零漂移、主回归 Pass 67/Skip 1、门 D8/H/H2/I/E/F/G 与 R-127 代注册值一致；二进制随链 VIII 代 `5c436e9e…` 后续树，runtime 模板不改变解释器二进制 md5）；落地含两处自纠（php_instanceof 重写误删 Throwable 块 ⇒ 补回；伪接口比较 eqlIgnoreCase ⇒ `instanceof stringable` 双拼写 ✅）；变更文档 `docs/changes/2026-10-11/AOT-CODEGEN-012_类名族CI_R128_2026-10-11_fbe6382a.md`
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

> **溯源注记（R-148b）**：本表 `off` 侧值此后**失去文件级佐证**——一次误跑的 A/B 脚本（见 §21.9 自纠 #1）覆盖了 `/tmp/c018_ab.log`，脚本自身的 `trap` 已把 `optimizer.zig` 复原（md5 回到 `6cffa137…`、守卫在位，实测确认），残留 `/tmp/noguard`、`/tmp/c018ab.*`、备份全部删除。`on` 侧 7 枚值已逐一与落盘的 R-147 整列 `fuzzy_scripts_720/tmp/c010_shadow_newside_r147_tmp.txt` 复核**逐字节相同** ⇒ 记录侧仍可查；脚本资产保留（`c018_f20_guard_ab_tmp.sh`，md5 `74d0a65057e5d7618f7ace6ca3eff489`），需要时可当代复跑。

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

## 21. R-148（2026-10-13）：F-21 归因改写并收口 + 新立 F-22（本批**暴露**而非引入）

### 21.1 §20.4 的「嵌套外溢」口径被实测否证：根因是单臂短路

R-147 把 F-21 记成「缺异常区域嵌套表示」，本轮逐形实测后**作废该措辞**。真值来自四形对照（PHP 8.5.8 pinned）：

| 形 | 构造 | PHP | AOT（修复前） | 判 |
|---|---|---|---|---|
| f17 | 顶层、**单臂**、类型不符 | Uncaught Fatal + rc=255 | `ARM` + rc=0 | 红 |
| f19 | 顶层、单臂、**union** `catch (A \| B)` 全不符 | Uncaught Fatal | `U` | 红 |
| f18 | 顶层、单臂、类型相符 | `MATCH` | `MATCH` | 绿 |
| f16/f22 | 多臂选择 / 嵌套内层相符 | 正确 | 正确 | 绿 |

⇒ 与「嵌套」无关，与**臂数**有关。根因在 `ir_generator.zig:3378`：

```zig
if (try_data.catch_clauses.len == 1) {
    // 单个 catch：直接在 catch_block 中生成   ← 无 peek_exception / 无 instanceof / 无 cond_br
} else if (try_data.catch_clauses.len > 1) {
    // 多臂才构造派发块（:3397 peek_exception、:3435 instanceof、:3448 cond_br）
```

⇒ **单臂 catch 完全没有类型过滤**（臂体首条就是 `.catch_` ⇒ `getException()` 无条件消费）。生成码直接可证：单臂形发射出 `// Catch OutOfRangeException` 后立刻 `reg = runtime.getException()`，而多臂形在 `catch_1` 块里有 `reg = runtime.peekException(); … try runtime.php_instanceof(...)`。

### 21.2 第二独立根因：末臂不匹配时的落点

派发链末臂的 else 落 `target_after_catch`（本层退出块），异常仍 pending 却不再路由 ⇒ 两副面孔：

| 面 | 实测（修复前） |
|---|---|
| 有外层 try（f20：内层两臂全不符、外层可接） | PHP = `OUTER-OK`；AOT = 只有 `TAIL`（外层永不接管） |
| 顶层无外层（f21：两臂全不符） | PHP = Fatal + rc=255（**无** TAIL）；AOT = `TAIL` 后再 Fatal ⇒ 继续执行了后续语句 |

⇒ f21 在 R-147 我曾口头记成「绿（靠 R-145 入口上报对上）」，本轮实测否证：**是红**（多打 `TAIL`）。

### 21.3 修复：两处同动，全在 `ir_generator.zig` 生成侧，不动发射侧

1. **取消单臂短路**：`len == 1 / len > 1` 合成一条 `len >= 1` 支 ⇒ 单臂也走派发块（臂体挪进独立 `catch_{ci}` 块）。
2. **末臂 else 改为重抛块**：新建 `catch_unmatched` 块（在本层 try 上下文**弹出之后**创建 ⇒ 按 `createBlock:534-537` 继承**外层** handler），块内两条既有指令完成外溢：

```zig
const pending = try self.emitWithResult(.{ .get_exception = {} }, .php_value);
self.setTerminator(.{ .throw = pending });
```

- 不新增 IR op、不改 `native_linker.zig`：`.throw` 终止符已有两条腿（有 handler ⇒ `current_block = handler`；无 handler ⇒ `return runtime.Value.initNull()` 交给调用方/入口上报，正是 R-147 验证过的那条形态）。
- 所有权实测核过：`getException()` 清空槽位并**转移所有权不释放**；`setException()` 做 `ex.retain()`；`.throw` 的清理循环 `if (reg_id == ex_reg.id) continue` 跳过异常寄存器本身 ⇒ 计数自洽（函数出口 `reg.release` 释放 1，槽位持 1，入口 `php_handle_uncaught_exception` 的 `getException()` + `defer ex.release` 归零）。
- **刻意不改**的一支：本层自带 `finally` 时 `propagate_target` 仍取 `target_after_catch`，否则会跳过 finally 语句块。

### 21.4 修复验证（10 臂快验全绿）

`ONLY="f14 f15 f16 f17 f18 f19 f20 f21 f22 f23"` ⇒ `shapes=10 same=10 diff=0 compile_fail=0 bad_probe=0` @41s（含 R-147 的 F-20 臂 f14 未回退）。六枚 F-21 红全部转绿。

### 21.5 F-22（新立，注册红 f26；本批**暴露**，非引入）

| 面 | PHP | AOT |
|---|---|---|
| f24 单臂不符 + 本层单语句 finally | `FIN` 后 Fatal + 255 | **逐字相同**（绿） |
| f25 嵌套、内层带 finally、内层臂不符 | `IFIN OUTER TAIL` | **相同**（绿） |
| f26 单臂不符 + 本层**多语句** finally | `A B C` 全跑完再 Fatal + 255 | 只 `A` 即被该语句的 `hasException()` 路由打断 |

前缀 `be305cfab370f56e515d6e9cd63b10ea`（R-122 代）复测 f26 = `ARM A B C` ⇒ 旧代并非正确，而是被「错臂先消费异常」掩盖 ⇒ **F-22 属本批修复暴露的独立面孔**（pending 异常在 finally 体内第一条语句处就被块级路由打断）。

- 语料面实测：**`pass/` 内 `} finally {` 子句 = 0 枚**（`f090` 的 `finally` 是用户方法名，非 finally 子句）⇒ 基线对该族零暴露。
- 候选修法（未落地、未定价）：进入 finally 块时 `saved = peek_exception` + `clear_exception`，块尾按 `saved` 是否为 null 条件重抛 ⇒ 需给「finally 体内新抛的异常」与「进入时已 pending 的异常」分别定价，且要处理二者共存。

### 21.5.1 F-22 归因升级到实文级 + 定价（R-154 备料轮完成，零 `src/` 改动，**为下一轮预置**）

| 问 | 实测证据 | 结论 |
|---|---|---|
| finally 在发射侧有特判吗？ | `grep -n finally src/aot/native_linker.zig` ⇒ **0 命中** | finally 完全是 **IR 层**结构；发射侧只按块级 `exception_handler` 做通用路由 |
| 块从哪来、handler 怎么继承 | `generateTryStmt:3329-3333` 建 `finally` 块（建块时当前 try 尚未 push ⇒ `createBlock` 给它**外层** handler）；`:3370 target_after_catch = finally_block orelse exit_block`；`:3360-3364` try 正常完成 ⇒ `br finally` | 与 R-148 的 `propagate_target` 是同一条链的两个入口；**改 finally 入口必须同时覆盖 `finally_dup_N`**（`redirectThroughFinally:3724-3753`，为 throw/return 复制体） |
| 症状的确切机制 | 体内第一条会抛的语句其后置 `hasException()` 命中**进入时已 pending** 的异常 ⇒ 直接跳外层 handler ⇒ 后续语句（`B`/`C`）被跳过 | 不是 handler 挂错，而是「pending 状态在 finally 入口没被摘走」 |
| 能否只把 handler 置 null 让体内不路由？ | 无 handler 时发射兜底是 `return error.RuntimeError`（与 `native_linker` 静态属性支同款） | **不可行**：会把「跑完 finally」变成「函数提前退出」⇒ 只能走「入口摘走 + 块尾放回」 |
| 引用计数允许「先 peek 再 clear」吗？ | `peekException()` 命中时 `_ = current_exception.retain()` 后才返回；`clearException()` 释放的是**全局那一份** | **安全**，`saved` 自持一份 ⇒ 这是修法成立的前提 |
| 块尾要不要区分「体内新抛」与「无新抛」？ | 入口已 clear ⇒ 体内任何新抛都在抛出点路由出去，**走不到块尾**；能到块尾就说明全局无 pending | ⇒ 块尾只需一个「若无 pending 则放回 `saved`」的动作，**不需要 IR 分支** |

**最小落地形态（三处，全 AOT 侧）**：① 模板新增 `php_restoreException(saved: Value) void`＝`if (!has_exception) setException(saved) else saved.release(runtime_allocator);`（**两半都必须写**：放回转移所有权、丢弃必须释放）；② `ir_generator:3329` 之后进入 finally 时发 `.peek_exception`（存 `saved_reg`）+ `.clear_exception`，块尾发一次对 `php_restoreException(saved_reg)` 的普通 call，复用既有「call 后 hasException 路由」把 pending 交还外层 handler；③ `redirectThroughFinally` 的 `finally_dup_*` 块同样处理。

| 维度 | 值 |
|---|---|
| 优先级 | **P1**（PHP 语义正确性；且是门 P 的注册红 `f26` ⇒ 修好即回收一枚，按规则 27 要用 BEFORE 报表明细行存在性判回收） |
| 影响面 | 含 `finally` 的脚本，**语料 0 枚** ⇒ 主回归与影子不可能红；门 P 的 `f24`（单语句 finally）/`f25`（嵌套 finally）为**硬守卫臂** |
| 落地成本 | 低-中：模板 1 函数 + `ir_generator` 3 处发射。⚠️ 动 `ir_generator` ⇒ **需 `zig build` 重建二进制 ⇒ 全部门读数与影子按新代次复跑（一链）** |
| 风险 | ① 引计数失衡（`php_restoreException` 两分支所有权必须都写对，漏放即泄漏/双释放）；② 与 R-147 的 `optimizer:4360-4371` 守卫交互：finally 块 handler 形状变化会影响块合并 ⇒ 复跑须逐枚看 `f24/f25/f26`，不能只看汇总数 |

### 21.6 语料发射面（本轮可算真跨代差值）

| 项 | 实测 |
|---|---|
| 语料 `} catch` 站点 | 8 处（f006×1、f009×2、f031×1、f034×1、f048×1、f067×1、f090×1），**全部单臂** ⇒ 本轮恒建派发器会改到这 7 枚脚本 |
| 前代基线 | R-147 已落盘 `fuzzy_scripts_720/tmp/c010_shadow_newside_r147_tmp.txt`（68 行，表身 md5 `628aa13b…`）⇒ **本轮首次能做真跨代 `changed_rows`** |
| 影子/主回归/其余门 | 链路在跑，读数见 §21.7 |

### 21.7 验收读数（R-148）

| 腿 | 读数 |
|---|---|
| 门 P（69 形） | 修复前登记轮十枚红 `v2 i1 i2 f12 f15 f17 f19 f20 f21 f23` @27s（10 臂 ONLY）／@297s（69 形全量）；**修复后定档 = `shapes=69 same=64 diff=5 compile_fail=0 bad_probe=0 residue=0` @291s**，红恰 `v2 i1 i2 f12 f26`（f26 = F-22） |
| 门 S | 47 形 `same=47 diff=0` @198s |
| 门 M / N / O / D8 | 19/19 @72s、7/7 @25s、6/6 @22s、`defect_red=0 guard_same=14` @52s |
| 门 Q / R | `same=5` @23s、`same=8 diff=1 terminate_lost=0` @40s |
| 普查门 B | `dup_rows=33 diff_impl=3 field_diff=0 identical=30` @1s（未碰 map） |
| `zig build test` | **21/21 steps；326/326 tests passed** |
| 影子 | `total=68 same=0 diff=68 miss=0 invalid=0` @1115s（前缀仍 `be305cfa`）；**跨代 new-side 差值首次可做**：本轮整列 68 行（哨兵 0、32 位十六进制 68/68）vs R-147 落盘列 ⇒ **`changed_rows=7`**，且逐枚为 `f006 f009 f031 f034 f048 f067 f090` ⇒ **恰等于含 `} catch` 的 7 枚脚本**，其余 **61 枚逐字节不变** ⇒ 发射面扰动与归因机制对齐（不再是 §20.7 那种类比论证） |
| 主回归 | **仍在跑**（报表 mtime 仍为上一代 `10:23` ⇒ 按规则 28 不取数，待腿收尾回填） |
| 代次 | `ir_generator.zig` `0242d8b5…` → **`8dae7b2b8f98918009dff36c2c81830e`**；`optimizer.zig` `6cffa137…`、模板 `4ff0befc…`、`native_linker.zig` `49a3da31…` 均未变；二进制 `8b5c65a1…` → **`bbff3b4a5cc18b31c8713e53aa95946a`**（75s 重建）；门 P 脚本 **`37a86a66a8b1515331450f31f41e332c`**（旧 `eab47607…` 作废）；本轮整列已落盘 `fuzzy_scripts_720/tmp/c010_shadow_newside_r148_tmp.txt` |

### 21.8 本批三处自纠

1. **又踩规则 28**：门仍在跑（TSV 30 行）时就读了「红集为空」并差点当成结论；改为「`C012P_DONE` 行存在才取数」后拿到真读数。
2. **门脚本形表两处复制**：`for s in` 与 DONE 行的 `shapes=$(echo …)` 各写一遍列表，我扩臂时只改前者 ⇒ DONE 印 `shapes=59` 而实跑 69。已改为单一来源 `ALL_SHAPES`（`bash -n` 通过）。
3. **R-147 口头记的「f21 绿」被实测否证**（多打 `TAIL`），已在本节改写；同时 §20.4「唯一错的是嵌套外溢」的措辞整条作废，改为「与臂数有关」。

### 21.9 ★本批引入的真实回归及其收口（R-148b）：门全绿 ≠ 语料全绿

恒建派发器落地后，门 P 69 形读数完全达标（`same=64 diff=5`、红恰为注册集），**但主回归掉了 1 枚**：

| 腿 | R-148a 读数 |
|---|---|
| 主回归 | **Total 68 / Pass 66 / Fail(Runtime) 1 / Skip 1**（11:40:13 报表） |
| 失败明细 | `f006_oop_observer_event_dispatcher.php FAIL_RUNTIME exit=255 \| Fatal error: Uncaught RuntimeException: Missing user in payload` |

⇒ **教训（写入门规）**：注册红集达标只证「已知红没扩大」，**不证没有新红**；本批的 `diff=5` 里根本没有 f006 的身影，因为它不在门 P 的形表内。语料是唯一能抓住「合法 catch 被我的派发器判成不匹配」的网。

**归因（生成码直接可证）**：`f006` 用 `catch (\Throwable $e)`（完全限定写法）。KEEP_TEMP 的 `main.zig` 里 interned 常量是 `"\\Throwable"`（带前导反斜杠），派发器把它当字符串交给 `php_instanceof` → `findClass`；`findClass`（模板 `:19016-19028`）**只折大小写、不剥前导 `\`** ⇒ 查表落空 ⇒ 新加的 `catch_unmatched` 重抛 ⇒ `Uncaught` + rc=255。旧代之所以"看起来对"，是因为单臂短路根本没有过滤这一步。

**修复（两步，最终形态只保留一步）**：

1. 先按「剥前导 `\`」补一枚 `normalizeCatchTypeName` ⇒ f006 与 PHP **逐字节相同**（`diff` 空、rc=0），`catch (\Throwable)`／`catch (\Exception)` 两形转绿。
2. 但随即用四形实测出**更完整的规则**（都在 `namespace App;` 下，PHP 8.5.8 pinned）：

| 臂 | 构造 | PHP | AOT（仅剥斜杠版） |
|---|---|---|---|
| ns1 | `catch (MyE)`（同命名空间用户类） | 接住 `NS-MATCH` | **Fatal** ⇒ 欠捕获 |
| ns2 | `catch (RuntimeException)`，抛 `\RuntimeException` | **Fatal**（非限定名解析到 `App\RuntimeException`） | 接住 ⇒ **过捕获** |
| ns3 | `catch (Throwable)` 同上 | **Fatal** | 接住 ⇒ 过捕获 |
| ns4 | `use RuntimeException as RE;` + `catch (RE)` | 接住 | **Fatal** ⇒ 欠捕获 |

⇒ 「剥斜杠」只是其中一个特例，正解是复用仓库既有的 **`resolveClassName`**（`ir_generator.zig:5736`：`self/parent/static` → 前导 `\` 剥离 → 限定名 → 别名表 → 导入表 → 当前命名空间前缀）。落地 = 四处取名点统一改走它（两处 `named_type` + 两处 `union_type`），**并删掉自己新造的 helper**，避免同仓两套类名解析口径。

**门 P 扩臂（69 → 76 形）**：`f27` 单臂 `\Throwable` 相符／`f28` 多臂限定名选择／`f29` 命名空间内用户类短名／`f30`+`f31` 命名空间内内建类短名**不得**接住／`f32` `use` 别名。

**顺带长出的新面孔 F-23（注册红 f33）**：`f29` 首版写成 `catch (MyE $e) { echo $e->getMessage(); }` 时仍红，实测暴露的是**另一件事**——`namespace App; class MyE extends \Exception {}` 之后 `getMessage()` 整族丢失（`Call to undefined method App\MyE::getMessage()`，而 `get_class`／`class_exists('App\MyE')` 两侧全等）。用冻结前缀 `be305cfa`（R-122 代）复测**逐字相同** ⇒ **非本批引入**；同时把臂拆成「f29 只测 catch 匹配（现绿）」+「f33 专测 F-23（登记红）」，防止两个缺陷挤在同一枚臂里互相掩盖。

**本批三处操作自纠**：

| # | 事项 | 处置 |
|---|---|---|
| 1 | 把上一轮已完成的**守卫 A/B 脚本**当成本轮该跑的命令发出去（该脚本会临时删 `optimizer.zig` 的守卫） | `TaskStop` 终止；脚本自带的 `trap restore` 已把文件复原（`optimizer.zig` md5 回到 `6cffa137…`、守卫在位），残留 `/tmp/noguard`、`/tmp/c018ab.*`、备份文件全部删除 ⇒ **兜底有效**，但该 A/B 日志被覆盖，只剩工单内记录值 |
| 2 | 新臂 `printf` 里反斜杠多转一层（`\\\\Throwable`）⇒ 六枚臂全被 `php -l` 预检拦成 `bad_probe=6` | 改为 `\\Throwable`；预检机制再次证明它比"跑出名堂再说"便宜（8 秒就报出来） |
| 3 | f29 首版把两个缺陷混在一枚臂里 | 拆为 f29 + f33，并按「注册红必须各自可归因」的原则重新登记 |

### 21.10 R-148b 验收读数（终态，全链 11:52–12:36）

| 腿 | 读数 |
|---|---|
| 门 P（**76 形**） | `shapes=76 same=70 diff=6 compile_fail=0 bad_probe=0` @306s，红集逐枚 = **`v2 i1 i2 f12 f26 f33`** ⇒ 与注册判据完全一致（F-21 六臂、catch 名解析六臂 f27–f32 全绿） |
| 门 S | 47 形 `same=47 diff=0` @188s |
| 门 M / N / O / D8 | 19/19 @68s、7/7 @24s、6/6 @20s、`defect_red=0 guard_same=14` @50s |
| 门 Q / R | `same=5` @22s、`same=8 diff=1 terminate_lost=0` @38s |
| 普查门 B | `dup_rows=33 diff_impl=3 field_diff=0 identical=30` @2s（未碰 map） |
| `zig build test` | **21/21 steps；326/326 tests passed** |
| 影子 | `total=68 same=0 diff=68 miss=0 invalid=0` @1039s（成对 136 行断言通过、哨兵 0、32 位十六进制 68/68）；整列已落盘 `fuzzy_scripts_720/tmp/c010_shadow_newside_r148b_tmp.txt`（表身 md5 `f19fb070ba1b86c34f02b3883de8e4dd`）＝**下轮前代基线** |
| **跨代差值 A**（R-148b vs R-148a `…_r148_tmp.txt`） | **`changed_rows=2` = `f006`、`f009`** ⇒ 恰为语料中用**前导 `\`** 写 catch 类型的两枚（其余 5 枚 catch 名不带 `\` ⇒ `resolveClassName` 原样返回，生成码逐字节不变）⇒ 归一化修复的扰动面被独立限定并实测闭合 |
| **跨代差值 B**（R-148b vs R-147 `…_r147_tmp.txt`） | **`changed_rows=7` = `f006 f009 f031 f034 f048 f067 f090`** ⇒ 恰为含 `try/catch` 的 7 枚（其余 61 枚逐字节不变），与「恒建派发器只触及 catch 站点」一致 |
| 主回归 | 12:36:14 **Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 0 / Skip 1**（明细仅 `f004` SKIP）⇒ **R-148a 那枚 `f006 FAIL_RUNTIME` 已消失，回归复证完成**；回收枚 0、与 R-145/R-146/R-147 代逐行等值 |
| 残留 / 语料 | `aot_compile_*`、`.zigphp_aot_build_*` = **0**；`pass/*.php` = 68、`fuzzy_scripts_720` 全部 `.php` = 403（与开跑前一致） |

### 21.11 代次（R-148b 终态）

| 资产 | md5 |
|---|---|
| `src/aot/ir_generator.zig` | **`81dffec55865459418bd1b14b37d558d`**（本批三连：`0242d8b5…` → `8dae7b2b…`（派发器+重抛）→ 剥斜杠中间版 `1c28f7a4…`（已废弃、未入库形态）→ 本值 `resolveClassName`） |
| `src/aot/optimizer.zig` | `6cffa137f766bdd2a13769c7ba3314b5`（R-147 未变） |
| `src/aot/native_linker.zig` | `49a3da31660fef4963b8eb50d7587987`（未变） |
| `src/aot/runtime_lib_template.zig` | `4ff0befc7c5b50d4fcfb8b1fd1f057e7`（未变） |
| 二进制 | **`1abad89e2166d15e32fc304e2d071c28`**（重建；`8b5c65a1…`／`bbff3b4a…`／`001bc245…` 均作废） |
| 门 P 脚本 | **`cb1a622797cc7b0519f38dc1f8ca3bb1`**（76 形，`ALL_SHAPES` 单一来源） |
| A/B 资产脚本 | `74d0a65057e5d7618f7ace6ca3eff489` |
| 影子基线列 | `c010_shadow_newside_r148b_tmp.txt`（当代）／`…_r148_tmp.txt`（R-148a）／`…_r147_tmp.txt`（R-147）三列并存，可继续做真跨代差值 |

### 21.12 提交态核对（12:38 实测，影响重冻与追溯）

| 事实 | 证据 |
|---|---|
| HEAD 已由老铁推进到 **`948c0c2`**（`fix(aot): fix preg_match flags, static call errors, and fatal termination`，提交时间 **10:54:10**） | `git log`／`git show --stat` |
| 该提交**把 R-148a 一起收进去了**（`src/aot/ir_generator.zig` +49 行，含单臂并入派发链与 `catch_unmatched` 重抛块） | `git show HEAD:src/aot/ir_generator.zig \| grep -c "catch_unmatched\|★F-21 修复一"` = **2** |
| ★**提交时的主回归是红的**：R-148a 那版带 `\Throwable` 回归，`f006 FAIL_RUNTIME`、**Pass 66**（11:40 报表才测出，晚于提交） | 提交消息写「All changes verified by full regression tests with no runtime or diff errors」，但 `948c0c2` 的时间戳早于该回归的实测时刻 ⇒ **消息与当时实测不符，属追溯风险点**，以本节为准 |
| **未提交的 src 只剩 R-148b**：四处 `resolveClassName` 切换（`git diff HEAD -- src/` = +5/−4，含删 helper 后残留的一枚空行） | 同上 |
| 未提交的文档与门资产：工单 012／变更文档／013 工单（`M`）+ **11 枚 `??` 门资产**（含门 P 76 形脚本、门 S、门 Q/R、普查门 B、A/B 脚本、三枚影子基线列等） | `git status --short` |
| P2 整理项：`ir_generator.zig:70` 有一枚多余空行（删自造 helper 的残留） | 未清——清它需重建并改代次值，留待与「提交」同批处理 |
| 影子重冻：HEAD 已推进 ⇒ 重冻前缀应取 **R-148b 代**列 `fuzzy_scripts_720/tmp/c010_shadow_newside_r148b_tmp.txt`（表身 `f19fb070…`）；R-147／R-148a 两列保留在库内供差值复算 | 见 §21.10 |

## 22. R-149（2026-10-13）：F-23 归因到底 ⇒ 升格为 F-24 族，建永久侧门 T，落地 F-24c（顺带闭 F-23）

### 22.1 起点：f33 不是「命名空间类丢方法」这么简单

R-148b 登记的 F-23（f33）只描述了一个症状。本轮五形对照把机制挖到根：**`extends` / `implements` 的类名被解析了两次**。

```zig
// src/compiler/root.zig:152-176  PHPContext.resolveName（parser 期，跨模式共用）
if (name_str[0] == '\\') return intern(name_str[1..]);   // ① 前导 \ 剥掉
if (self.imports.get(name_id)) |r| return r;             // ② use 别名/导入
if (self.current_namespace) |ns| return intern(ns \ name); // ③ 加当前命名空间
```
`class E extends \Exception` 的父名走 `parseExpression` ⇒ `.variable` 节点 ⇒ 上面 ①②③ **已经执行完**，节点里存的就是最终名 `Exception`。

```zig
// src/aot/ir_generator.zig:1531-1539（修复前）
break :blk try self.resolveClassName(parent_short_name);  // ← 又做一次 ①②③
```
AOT 的 `resolveClassName` 再跑一遍：拿到 `Exception`（不含 `\`）⇒ 落到「加当前命名空间」⇒ **`App\Exception`** ⇒ `findClass` 落空 ⇒ `parent = null` ⇒ 内建方法整族不可用。**同一处代码对另一方向也错**：`namespace App; class C extends \Base`（`Base` 其实定义在 `App` 内）⇒ parser 剥 `\` 得 `Base` ⇒ AOT 再加前缀得 `App\Base` ⇒ **错认了一个 PHP 认为不存在的全局类**。

⇒ 症状差异完全由「名字里还剩不剩 `\`」决定：同命名空间用户父类（`App\Base`，带 `\`）在 `resolveClassName` 的 case 3 原样返回 ⇒ **侥幸正确**（实测 t10/p4 = 绿）。这就是为什么语料全绿而族缺陷一直看不见。

### 22.2 门 T（新永久侧门，16 形）与五张子面孔

资产 `fuzzy_scripts_720/tmp/c019_fq_typepos_gate_tmp.sh`（md5 `374fdde3597cb27510ce0abd045dce25`）；判据写在门头，**禁只看 same 数**（4 枚是 compile_fail，不属 diff 桶）。

| 子面孔 | 臂 | 实测（PHP vs AOT） | 机制位点 |
|---|---|---|---|
| **F-24a** 生成码 Zig 字符串未转义 | **t1 t4 t5 t14**（`compile_fail`） | PHP 全可运行；AOT `error: invalid escape character: 'E'`，坏句为 `php_coerce_value(args[0], "\Exception", …)` | 发射侧参数/返回类型名直写进字面量（同文件已有转义先例 `:1406/:1626/:24859/:32626` 的 `'\\' => writeAll("\\\\")`） |
| **F-24b** 参数类型按字面名比较 | **t2 t6** | PHP 接受（`\Throwable` 收 `RuntimeException`；`use … as RE` 同理）；AOT 伪 `TypeError: must be of type \Throwable`／`must be of type RE` | 参数类型检查未做名字归一；**t6 与反斜杠无关**，是 `use as` 别名整族丢失 |
| **F-24c** 父名/接口名双重解析 | t7 t8(部分) t12(部分) t13 + 门 P f33 | 见 §22.1 | `ir_generator.zig` 类定义处 |
| **F-24d** 父/接口解析不到时静默继续 | **t9 t11** | PHP = `Error: Class "App\Exception" not found`／`Class "Base" not found` + rc=255；AOT 继续跑到方法调用才报 `undefined method`（甚至不报） | fail-open 家族（与 RUNTIME-002 G4 可见性 fail-open 同族） |
| 其余独立机制 | t8 `IO=F`（`instanceof \Throwable` 假）／t12 `get_class_methods` 缺内建族（= **F-3** 旧账）／t13 `implements \JsonSerializable` ⇒ `JSON={}` | 三条各自独立，禁与本族混臂（规则 31） | 待归因 |

绿臂（守卫）：**t3**（闭包参数 `\Exception` ⇒ 与 t1 相反，说明**闭包位点已转义**，F-24a 只在顶层函数/方法位点）、**t7**（F-24c 落地后转绿）、**t10**、**t15/t16**（R-148b 的 catch FQ 面）。

### 22.3 落地：F-24c（一处口径，两枚位点）

新增 `containerTypeRefName`（`ir_generator.zig`，紧接 `getFullClassName`），`implements` 与 `extends` 两枚位点改走它：

```zig
    fn containerTypeRefName(self: *Self, node: *const Node) !?[]const u8 {
        switch (node.tag) {
            .variable => return self.getString(node.data.variable.name),   // parser 已解析 ⇒ 原样
            .named_type => return try self.resolveClassName(self.getString(node.data.named_type.name)), // 原文切片 ⇒ 必须解析
            .literal_string => return try self.resolveClassName(self.getString(node.data.literal_string.value)),
            else => return null,
        }
    }
```

**两种来源必须分开**：`.variable`（表达式位点，已解析）vs `.named_type`（`parseType:4317-4333` 存**原文切片**，连前导 `\` 都保留——这正是 R-148b 里 `catch (\Throwable)` 需要归一的原因）。⇒ 我上一轮给 catch 位点接 `resolveClassName` 是对的，本轮把类定义位点**摘掉**它也是对的，两者不矛盾。

配套收益：**门 P 的注册红 f33（F-23）随 F-24c 转绿**（`ONLY="f33 f29 f30 f31 f32"` ⇒ `shapes=5 same=5 diff=0` @19s）。⇒ F-23 不是独立缺陷，只是 F-24c 的一个症状；已按「一臂一缺陷」把 t7 与 f33 分列。

### 22.4 语料中性论证与实测

| 面 | 实测 |
|---|---|
| `pass/` 内 `^\s*namespace` | **0 枚** ⇒ `resolveName` 的 ③ 与 `resolveClassName` 的 case 6 在语料里都不触发 |
| `pass/` 内 `^\s*use X\Y;` | **0 枚** ⇒ ②/case 4·5（别名/导入表）也不触发 |
| `pass/` 内 FQCN 类型位点（`\Name $x`／`, \Name $x`／`): \Name`） | **0 枚** ⇒ F-24a/b 语料不可达 |
| ⇒ 结论 | F-24c 对语料**应当发射中性**；影子 vs R-148b 列的 `changed_rows` 必须 **= 0**（实测待链路回填）；主回归必须仍 `Pass 67 / Fail_* 0 / Skip 1` |

### 22.5 遗留

| 优先级 | 项 | 说明 |
|---|---|---|
| P1 | F-24a 转义 | 4 枚编译失败；修法=复用既有转义先例，位点在参数/返回类型名的发射处（闭包位点已正确，可对照） |
| P1 | F-24b 参数类型名归一 | 伪 TypeError；**含 `use as` 别名整族**（与 `\` 无关），面比 F-24a 大 |
| P1 | F-24d fail-open | 父/接口解析不到应 `Error: Class "…" not found` + rc=255 |
| P1 | t8 `instanceof \Throwable` 假 / t13 `implements \JsonSerializable` ⇒ `{}` | 各自独立机制，未归因 |
| P2 | t12 `get_class_methods` 缺内建族 | 归 **F-3**（已登记，SPL/内建类保真族；§七.1 不考虑 spl） |
| P2 | `ir_generator.zig:70` 多余空行 | 与「提交」同批清 |

### 22.6 验收读数（R-149，全链 12:56–13:38）

| 腿 | 读数 |
|---|---|
| **门 T（新，16 形）** | `shapes=16 same=5 diff=7 compile_fail=4 bad_probe=0 residue=0` @51s；红 = `t2 t6 t8 t9 t11 t12 t13`，编译失败 = `t1 t4 t5 t14`，绿 = `t3 t7 t10 t15 t16` |
| 门 P（76 形） | `shapes=76 same=71 diff=5 compile_fail=0` @301s，红恰 = **`v2 i1 i2 f12 f26`**（**f33 转绿**）；最终版脚本复跑读数见门头（md5 `de57ba7027d26cfd7eed87b40fb7b790`，旧 `cb1a6227…` 作废） |
| 门 S / M / N / O / D8 | 47/47 @187s、19/19 @68s、7/7 @24s、6/6 @21s、`defect_red=0 guard_same=14` @49s |
| 门 Q / R / 普查门 B | `same=5` @22s、`same=8 diff=1 terminate_lost=0` @38s、`dup_rows=33 diff_impl=3 field_diff=0 identical=30` @2s |
| `zig build test` | **21/21 steps；326/326 tests passed** |
| 影子 | `total=68 same=0 diff=68 miss=0 invalid=0` @1039s（成对 136 行、哨兵 0）；**跨代差值 vs R-148b 列 `changed_rows = 0`**，且两列表身 md5 同为 `f19fb070ba1b86c34f02b3883de8e4dd` ⇒ §22.4 的「语料发射中性」由**推断升为实测**；R-149 列落盘 `c010_shadow_newside_r149_tmp.txt` |
| 主回归 | 13:38:37 **Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 0 / Skip 1**（明细仅 `f004` SKIP ⇒ 回收 0，与 R-145~R-148b 逐行等值） |
| 残留 / 语料 | `aot_compile_*`、`.zigphp_aot_build_*` = 0；`pass/*.php` 68、全部 `.php` 403 未变 |

代次：`ir_generator.zig` = **`f3d13cb82395d945d2a246b2158589ea`**；`optimizer.zig` `6cffa137…`／`native_linker.zig` `49a3da31…`／模板 `4ff0befc…` 未变；二进制 = **`6e13b29edb0e12122115b605a217bdb6`**（`1abad89e…` 作废）；门 T 脚本 = `374fdde3597cb27510ce0abd045dce25`；门 P 脚本 = `de57ba7027d26cfd7eed87b40fb7b790`。

## 23. R-150（2026-10-13）：F-24a / F-24b 落地，门 T 扩到 19 形，新立 F-24e 与 F-25

### 23.1 落地两枚

| 子面孔 | 修复 | 位点 |
|---|---|---|
| **F-24a** 生成码 Zig 字面量未转义 | 四处 `php_coerce_value(..., "<类型名>", ...)` 全部改走**既有** `self.escapeString(...)`（同文件 `:1406/:1626/:24859/:32626` 早有 `'\\' => writeAll("\\\\")` 先例） | `native_linker.zig:18777`/`:18804`（返回类型）、`:21311`/`:21326`（参数类型） |
| **F-24b** 类型名按字面比较 | IR 侧新增 `normalizeClassTypeName`，**只作用于类类型**：`mixed`／复合类型（含 `\|`、`&`）／`ConcreteType.fromString` 命中的内建标量／`self`·`parent`·`static`（留运行期 LSB）全部原样返回，其余走既有 `resolveClassName`（剥前导 `\`＋别名表＋导入表＋当前命名空间） | `ir_generator.zig`：函数参数 `:1045`、函数返回 `:992`、方法参数 `:2394`、方法返回 `:2409`/`:2549` 共五枚签名位点 |

★关键防呆：若不加「只对类类型」这层闸门，`namespace App` 下的 `int` 会被 `resolveClassName` 加前缀成 `App\int`——语料 **826 处标量类型参数**当场全炸。这条闸门是本次落地的前置条件，不是优化。

### 23.2 一枚我自己的错误推断（被臂否证，已收回）

我在归因 t2 时断言「`checkSingleType:6361` 只做类名全等，没有 instanceof」，并据此把 t2/t18 记成同一机制。**实测 t18 = SAME**（用户接口实参 + 子类实参都正确）⇒ 该函数下方确有 instanceof 分支，断言作废。补充两组单变量实测：

| 探针 | PHP | AOT |
|---|---|---|
| io1（全局文件）`$r instanceof Throwable` / `instanceof Exception` | true / true | **true / true** |
| t19（全局文件）`instanceof Throwable`（裸名）/ `instanceof \Throwable` / `instanceof \RuntimeException` | true / true / true | true / **false** / **false** |

⇒ t2 的红**不是**通用接口判定缺失，只限于「内建类实现内建接口」那一格 ⇒ 归 **F-3 内建保真族**；而 t8 的真正机制是 t19 这一格。

### 23.3 新立两张独立面孔

| ID | 臂 | 实测 | 说明 |
|---|---|---|---|
| **F-24e** | t19（t8 同根） | `instanceof` 右操作数写成完全限定名时判假（`\Throwable`、`\RuntimeException` 都 false，裸名 true） | `catch` 位点已在 R-148b 归一（t15/t16 绿），instanceof 右侧还没接同一口径 ⇒ 属 F-24b 的**另一个位点**，非新机制 |
| **F-25** | t17 | PHP `function i(): int` ⇒ AOT `error: capture shadows declaration of 'i'` ⇒ **合法 PHP 编译失败** | 与命名空间/反斜杠**完全无关**：发射模板里的循环捕获名（`i`）与用户函数名同名。本批 t5 首版（函数取名 `i`）误踩才暴露 ⇒ 独立的「生成码标识符卫生」族，疑与 `@__.__function_name__` / `@"<name>"` 引号包裹缺失同源，**需单独归因轮**（哪些字母会撞、撞面多大，均未实测） |

### 23.4 门 T 定档（19 形）

| 桶 | 枚 |
|---|---|
| 注册红（7） | `t2`（F-3 内建接口格）、`t8`＋`t19`（F-24e）、`t9`＋`t11`（F-24d fail-open）、`t12`（F-3 `get_class_methods`）、`t13`（`implements \JsonSerializable` 待归因） |
| 注册编译失败（1） | `t17`（F-25） |
| 守卫绿（11） | `t1 t3 t4 t5 t6 t7 t10 t14 t15 t16 t18` |
| 读数 | `shapes=19 same=11 diff=7 compile_fail=1 bad_probe=0` @74s；脚本 md5 `4160d5f21cb5ed9770e36f22af220bd5`（登记轮 16 形值 `374fdde3…` 作废） |

### 23.5 语料中性论证与验收

| 项 | 值 |
|---|---|
| 语料 FQCN 类型位点 | **0 枚**（`\Name $x`／`, \Name $x`／`): \Name` 全 0）⇒ 转义与归一在语料上都不改输出 |
| 影子 | `total=68 same=0 diff=68 miss=0 invalid=0` @1111s；**跨代差值 vs R-149 列 `changed_rows = 0`**，且整列表身 md5 与 R-149 完全相同（`f19fb070ba1b86c34f02b3883de8e4dd`）⇒ 「归一只动类类型、转义只动带反斜杠的名」这条中性论证**由实测闭合**（成对表 136 行、哨兵 0，按规则 29 先断言再比较） |
| 门 T（19 形，链上复现） | `same=11 diff=7 compile_fail=1 bad_probe=0` @75s |
| 门 P（76 形） | `same=71 diff=5 compile_fail=0` @300s，红仍 `v2 i1 i2 f12 f26` ⇒ 本批未扰动内省族 |
| S / M / N / O / D8 | 47/47 @195s、19/19 @70s、7/7 @26s、6/6 @21s、`defect_red=0 guard_same=14` @52s |
| Q / R / B / test | `same=5` @23s、`same=8 diff=1 terminate_lost=0` @40s、`dup_rows=33 diff_impl=3` @2s、**21/21 steps & 326/326 tests** |
| 主回归 | 14:46:02 **Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 0 / Skip 1**（明细仅 `f004` SKIP ⇒ 回收 0，与 R-145~R-149 逐行等值） |
| 残留 / 语料 | `aot_compile_*`、`.zigphp_aot_build_*` = 0；`pass/*.php` 68、全部 `.php` 403 未变 |
| 代次 | `ir_generator.zig` `f3d13cb8…` → **`5646baa7c6e4050f8c4435718b437c21`**；`native_linker.zig` `49a3da31…` → **`c261d2b2181db6815ee7b75613b53f16`**；`optimizer.zig` `6cffa137…`／模板 `4ff0befc…` 未变；二进制 → **`4cda590a23b6760794047683453dca16`**；门 T 脚本 `4160d5f21cb5ed9770e36f22af220bd5`；影子列新增 `c010_shadow_newside_r150_tmp.txt`（与 R-149 同内容） |

### 23.6 本批一处自纠（更正「我的更正」本身）

我在 14:42 公开宣称「又把影子完成说早了」，理由是当时手上那份是 14:22 的 62/137 行中间表。**复核后该自我更正本身是错的**：14:32:04 取数时 `C010_SHADOW_DONE` 已写入、成对表 137 行、哨兵 0，`changed_rows=0` 当场即成立；14:42 的重新导出与落盘只是**复核**（两次整列 md5 相同 `f19fb070…`），不是纠错。⇒ 记两条：① 规则 28 的判据（末腿 DONE 行 + 行数断言）本轮全程被满足，我却在腿外另起了一个「我好像又抢答了」的判断，属**未回看证据的口头自检**；② 反过来，「公开更正」若不经复算同样会引入新的错误陈述——与 §17.1 的 F-11 编造、规则 27 的汇总数误读同一族。结论数值不变：`changed_rows=0`、主回归 `Pass 67 / Fail_* 0 / Skip 1`。

## 24. R-151（2026-10-13）：F-24e 与 F-26 落地，门 T 定档 20 形

### 24.1 F-24e：instanceof 右操作数的完全限定名未归一

单变量判别（全局文件、同一表达式三种写法，PHP 8.5.8 pinned）：

| 写法 | PHP | AOT（修前） |
|---|---|---|
| `$r instanceof Throwable` | true | **true** |
| `$r instanceof \Throwable` | true | **false** |
| `$r instanceof \RuntimeException` | true | **false** |

⇒ 与 t8（命名空间内 `instanceof \Throwable` 判假）同根。定位到 `ir_generator.zig:5976 generateInstanceOf`：右操作数取的是 **`.named_type`**（即 `parseType` 存的**原文切片**，前导 `\` 原样保留），intern 后直接当类名交给 `php_instanceof` → `findClass`。⇒ 修复＝同一枚 `normalizeClassTypeName`（R-150 建的）接入 `.named_type` 与 `.literal_string` 两支，排在 `resolveSelfStaticParent` 之后（`self/static/parent` 由 helper 内的闸门原样放行，LSB 语义不受影响）。⇒ **门 T t8/t19 双双转绿**。

### 24.2 F-26：内省/类型函数的类名实参不剥前导 `\`（单点收口在 runtime）

四入口一次实测：

| 入口 | PHP | AOT 修前 | AOT 修后 |
|---|---|---|---|
| `class_exists('\Widget')` | true | **false** | true |
| `method_exists('\Widget','foo')` | true | **false** | true |
| `count(get_class_methods('\Widget'))` | 1 | **0** | 1 |
| `is_a(new Impl(), '\Iface', true)` | true | **false** | true |

修法＝在模板 `findClass` 顶部剥净前导 `\`，再用剥后的名字走「精确 get → CI 线性扫描」原路径：

```zig
pub fn findClass(name: []const u8) ?*ClassMeta {
    var lookup_name = name;
    while (lookup_name.len > 0 and lookup_name[0] == '\\') lookup_name = lookup_name[1..];
    if (class_registry) |registry| {
        if (registry.get(lookup_name)) |meta| return meta;
        ... eqlIgnoreCase(entry.key_ptr.*, lookup_name) ...
```

★为什么收在这里而不是各调用方：**本文件内 `findClass(` 有 121 处**，再叠内省函数、instanceof、动态类名静态调用等入口，逐处补必漏（同 R-150 的「同语义只留一个口径」）。成本＝无 `\` 时多两次首字符比较，热路径可忽略；且**纯模板改动不需重建二进制、不改 `main.zig`**（R-147 已实测影子只哈希 `main.zig`）。

### 24.3 门 T 定档（20 形）

| 桶 | 枚 |
|---|---|
| 注册红（5） | `t2`（内建类↔内建接口那一格 ⇒ F-3）、`t9`+`t11`（F-24d fail-open）、`t12`（F-3 `get_class_methods`）、`t13`（`implements \JsonSerializable` 待归因） |
| 注册编译失败（1） | `t17`（F-25 生成码标识符冲突） |
| 守卫绿（14） | `t1 t3 t4 t5 t6 t7 t8 t10 t14 t15 t16 t18 t19 t20` |
| 读数 | `shapes=20 same=14 diff=5 compile_fail=1 bad_probe=0` @83s；脚本 md5 `7ed12f90adacdfab2f03e2fa87df3f48`（R-150 的 `4160d5f2…` 作废） |

### 24.4 撤下一枚臂（t21）与它暴露的过宽容面

曾加 t21 测 `$obj instanceof "\Iface"`：**PHP 直接拒绝**该写法（`Parse error: unexpected double-quoted string`，rc=255），而 **AOT 接受并判 true** ⇒ 属「文法位过度宽容」族（门 H2 的 `over_accept` 口径）。但门 T **没有 `PHP_REJECT` 桶**，`php -l` 预检把它当坏探针拦下（`bad_probe=1`）⇒ 本轮不扩桶（扩桶＝改判读逻辑，与本批修复无关且会稀释读数），**撤下 t21**、把证据登记在此，待该族单独建门或给门 T 加桶时再做常驻臂。

### 24.5 语料中性论证与验收

| 项 | 值 |
|---|---|
| 语料 `instanceof \` FQ 写法 | 实测脚本数 **0** ⇒ instanceof 归一不改语料字符串（裸名走 `resolveClassName` 在无命名空间/无别名时原样返回） |
| 语料内省函数 FQ 实参 | **0 处** ⇒ F-26 的模板收口在语料上等价（无 `\` 时同路径同结果） |
| 全链（13 腿） | **在跑（15:0x 开跑），读数待回填**；判据 = 门 P 仍 `same=71 diff=5`、门 T `same=14 diff=5 cf=1`、影子 vs R-150 列 `changed_rows=0`、主回归 `Pass 67 / Fail_* 0 / Skip 1` |
| 代次 | `ir_generator.zig` `5646baa7…` → **`25e3033a7ef95a329a3a01dd3a4eee98`**；`runtime_lib_template.zig` `4ff0befc…` → **`8b275578a4ba3c8bd636a53abc883f1b`**；`native_linker.zig` `c261d2b2…`（R-150）、`optimizer.zig` `6cffa137…` 未变；二进制 **`f1ff7a0d868410b8b2d111f325e0d368`** |

### 24.6 本批两处自纠

1. **探针自身语法错误导致真值缺失两次**：我拿含 `instanceof "\Iface"` 的脚本去取 `class_exists` 族的 PHP 真值，PHP 整文件 parse error ⇒ 真值一行都没打出，我却已在话里把它当成「邻近位点证据」。改为**先 `php -l` 再取真值**、并拆成两枚独立探针（一枚合法四入口、一枚专测过宽容）⇒ 教训：门内建了 `php -l` 预检，手工探针同样必须先过预检，否则「PHP 侧空输出」会被误读成「PHP 不报错」。
2. **不在本轮扩门的判读桶**（见 §24.4）：`bad_probe` 不是红，也不是绿——它是「臂无效」，必须撤下而不是硬算进 diff。

## 25. R-151 / R-151b（2026-10-13）：F-24e、F-26 落地 ⇒ **又把语料改红了** ⇒ 追出 F-27 与 F-28

### 25.1 落地两枚

| ID | 位置 | 变更 | 门 |
|---|---|---|---|
| **F-24e** | `ir_generator.zig:5976 generateInstanceOf` | `.named_type`／`.literal_string` 两支在 `resolveSelfStaticParent` 之后统一走 R-150 的 `normalizeClassTypeName` ⇒ instanceof 右侧 `\Throwable`、`\RuntimeException` 不再原样进查表 | t8、t19 转绿 |
| **F-26** | `runtime_lib_template.zig:19016 findClass` | 顶部剥净前导 `\` 后再走「精确 get → CI 扫描」；单点覆盖本文件 **121 处** `findClass(` 调用方 | t20 转绿（`class_exists`／`method_exists`／`get_class_methods`／`is_a` 四枚 FQ 实参） |

### 25.2 ★F-26 把主回归改红了（规则 30 第二次应验）

R-151 链路 15:41:34 主回归 **Total 68 / Pass 65 / Fail(Runtime) 2 / Skip 1**：

```
f006_oop_observer_event_dispatcher.php  FAIL_RUNTIME exit=255 | Uncaught TypeError: Cannot assign unknown to property ClosureListener::$handler of type \Closure
f036_strategy_dynamic_pricing.php       FAIL_RUNTIME exit=255 | Uncaught TypeError: Cannot assign unknown to property ClosurePricing::$fn of type \Closure
```

而**同一轮**门 T 与门 P 全部达标 ⇒ 又一次「注册红没扩大 ≠ 没有新红」。

### 25.3 归因：F-27「闭包不被当作对象」（被 F-26 揭开的既存缺陷）

- `coercePropertyType` 的类名分支要求 `Value_isObject(value)`，而 AOT 闭包是独立 `.function` tag ⇒ 走「非对象 ⇒ TypeError」兜底，且该兜底的 `val_type` 链**没有 `isFunction` 一格** ⇒ 文案里的 `unknown`。
- **为什么以前不红**：声明写 `\Closure` 时 `findClass("\Closure")` 落空 ⇒ 整条类名分支被跳过（宽松放行）。F-26 让它命中 ⇒ 分支真执行 ⇒ 缺陷显形。**是 F-26 改了可达性，不是 F-26 写错逻辑**。
- 修法＝一枚共享谓词接两条路径（union 走 `tryCoerceSingleType`，单类型走 `coercePropertyType`，两处原来各有一份类名比较）：

```zig
// src/aot/runtime_lib_template.zig:19621-19631
fn stripLeadingNamespaceSep(name: []const u8) []const u8 { /* 剥前导 \ */ }
fn closureSatisfiesType(declared: []const u8, value: Value) bool {
    if (!value.isFunction()) return false;
    const d = stripLeadingNamespaceSep(declared);
    return std.ascii.eqlIgnoreCase(d, "Closure") or std.mem.eql(u8, d, "object") or std.mem.eql(u8, d, "mixed");
}
```
- 顺序上是**硬依赖**：F-27 必须先于 F-26 进树（否则基线带红）。本轮先落 F-26 再补 F-27，故中间那次链路读数（Pass 65）如实留在工单里，不回改。

### 25.4 F-27 的「既存性」证据边界（不硬断言）

- **能证的**：f006/f036 在 R-150 链（14:46:02）是 `Pass 67` 全绿，在 R-151 链（15:41:34）转红 ⇒ 「`\Closure` 拼法被 F-26 翻红」成立。
- **不能证的**：裸名 `public Closure $g` 在**旧代**是否也坏。我拿冻结前缀 `be305cfa` 复测，前缀那一代**连探针都编不过**：`main.zig:356:12: error: expected 4 argument(s), found 3`，且**留下了 0 字节可执行产物**（正是规则 22 那个坑，`run_rc=0` 但空输出）⇒ 前缀不可用作本面基线。
- 机制推断（`findClass("Closure")` 一直能命中 ⇒ 分支一直在执行 ⇒ 裸名应当早已坏）**只写成推断，不当结论**；要定死得等一次「关 F-26 的 A/B 重建」（同 §20.7 的守卫开关做法）。

### 25.5 新立 F-28（注册红 t23）

| 位点 | PHP | AOT（R-151b） |
|---|---|---|
| `get_class($closure)` | `Closure` | **空串** |
| `is_object($closure)` | `true` | **false** |

⇒ 与 F-27 **相邻但不同机制**（属性赋值判定 vs 内建函数取类名/类型谓词），按规则 31 单列一臂；同族疑还含 `get_debug_type`／`instanceof Closure`，**未测**。

### 25.6 探针自身的两处坑（都进了门）

1. t22 首版把闭包写成 `fn(): int { return 1; }` ⇒ PHP 直接 parse error（`fn` 是箭头函数，块体必须用 `function () {}`）⇒ 被门内 `php -l` 预检拦成 `bad_probe=1`。
2. 一次 `grep -m1 "^t22\t"` 读数被多行 TSV 截断，误看成「只剩一格坏」⇒ 改用按臂切分的记录解析器才看到四格全坏（`OBJ= | CLO= | NULLABLE=2 | TypeError…`）。⇒ 多行 TSV **禁止用行首匹配读数**。

### 25.7 门 T 定档与链路

| 项 | 值 |
|---|---|
| 门 T | **22 形 `same=15 diff=6 compile_fail=1 bad_probe=0`** @88s；红 = `t2 t9 t11 t12 t13 t23`，注册编译失败 = `t17` |
| 门 T 脚本 | `c019_fq_typepos_gate_tmp.sh` md5 = **`a40c45b6fe0f89a24d28ed83741cfc91`**（R-151 的 `7ed12f90adacdfab2f03e2fa87df3f48`、R-150 的 `4160d5f21cb5ed9770e36f22af220bd5` 作废）；链上复现 `same=15 diff=6 compile_fail=1` @90s |
| 模板 | `runtime_lib_template.zig` = **`1320306530d567611b7289388e433642`**（F-26 单枚落地时是 `8b275578a4ba3c8bd636a53abc883f1b`，加 F-27 共享谓词后为本值）；`ir_generator.zig` 仍 `25e3033a7ef95a329a3a01dd3a4eee98`、二进制仍 `f1ff7a0d868410b8b2d111f325e0d368`（F-27 是**纯模板改动 ⇒ 不需重建**） |
| 链路 R-151b（16:39 收尾） | 主回归 16:39:39 **Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 0 / Skip 1**（明细仅 `f004` SKIP）⇒ **F-27 复证，f006/f036 两枚红消失**；影子 `total=68 same=0 diff=68 invalid=0` @1124s，**vs R-151 列 `changed_rows=0`**（整列表身 md5 与 R-149/150/151 同为 `f19fb070…` ⇒ F-26/F-27 皆语料发射中性）；列落盘 `c010_shadow_newside_r151b_tmp.txt` |
| 链路其余腿 | T `shapes=22 same=15 diff=6 compile_fail=1` @90s、S 47/47 @198s、M 19/19 @73s、N 7/7 @26s、O 6/6 @22s、D8 `defect_red=0 guard_same=14` @53s、Q `same=5` @23s、R `same=8 diff=1 terminate_lost=0` @41s、B `diff_impl=3` @2s、`zig build test` 21/21 & 326/326 |
| ★假红一次（我的操作造成） | 链内门 P 读数 `same=70 diff=5 **compile_fail=1**`（g3「no product」），而**链后无并发复跑＝`same=71 diff=5 compile_fail=0`**、g3 与 PHP 逐字节相同 ⇒ 那枚 compile_fail 是**我在链路里并发跑手工 AOT 编译**（共享 `.zig-cache`、CPU 抢占）把链路那一发编译挤失败造成的**假红**，不是代码回归 ⇒ 规则 35：验收链运行期间禁止并发手工 AOT 编译；任何 `compile_fail` 在定档前必须无并发复跑一次 |
| 残留 / 语料 | `aot_compile_*`、`.zigphp_aot_build_*` = 0；`pass/*.php` 68、全部 `.php` 403 未变 |

## 26. R-152（2026-10-13）：F-25 归因轮（只读取证，零 src 改动）——发射模板捕获名与用户顶层函数名撞名

### 26.1 根因（一行）

```zig
// 生成的 main.zig（每个编译单元无条件发射）
fn initStaticStrings() void {
    if (static_strings_initialized) return;
    for (string_table, 0..) |str, i| {          // ← 捕获名 `str` / `i`
        static_strings[i] = runtime.PHPString.initStatic(str);
    }
```
```zig
pub fn @"i"(ctx: runtime.Value, ...) anyerror!runtime.Value {   // 用户 `function i()`
```
⇒ Zig 里 `@"i"` 与 `i` 是**同一个标识符**，而捕获不得遮蔽容器级声明 ⇒ `main.zig:21:35: error: capture shadows declaration of 'i'` ⇒ **合法 PHP 直接编译失败**（不是运行期问题，门/影子都看不见，只有 compile 面能抓）。

### 26.2 撞面普查（资产 `c020_f25_collision_census_tmp.sh`，75 形，逐名实编译）

| 声明种类 | 结果 |
|---|---|
| **顶层函数名** = 发射捕获名 | **22 枚 `COMPILE_FAIL`**：`i str value data result name entry err arg kv val old reg source sep_pos const_val ref_name src_val val_ptr s_ptr dval existing` |
| 顶层函数名 = `m` | `SAME` ⇒ 该捕获只在**特定构造**里发射（非无条件），撞面随文件形态变化 ⇒ 名单是「至少 22 枚」下界 |
| 探针无效 2 枚 | `file`／`current` 是 PHP 内建函数名，用户**无法**声明（`php` 侧就 fatal）⇒ 剔除，不算撞面 |
| **类名** = 上述 25 名 | 25/25 `SAME` ⇒ 类走 `X_meta` 一类带后缀的符号，不撞 |
| **全局变量名** = 上述 25 名 | 25/25 `SAME` ⇒ 全局变量走 `$` 前缀符号，不撞 |

⇒ 只有「**顶层函数**」这一类会撞；且 `str`/`i` 来自**无条件**发射的 `initStaticStrings`，其余 20 枚来自条件性模板。

### 26.3 语料可达性

| 项 | 实测 |
|---|---|
| `pass/` 内声明的函数名（含方法）去重 | 663 枚 |
| 与 22 枚撞名单交叠 | **1 枚 = `value`**，且它是**方法**（`f056_crdt_gcounter_lww_orset.php:14 public function value()`）⇒ 方法符号带类限定，不撞 |
| ⇒ 顶层函数撞面 | **0 枚** ⇒ 基线全绿是覆盖意外（同 F-21/F-24 族），修复的回归风险只能靠门臂与 A/B 守 |

### 26.4 三条修法（**未落地，需你定调**）

| 路线 | 做法 | 语料发射面 | 稳健性 |
|---|---|---|---|
| **甲** | 把发射模板自己的标识符统一改成双下划线前缀（`\|__zstr, __zi\|`，含条件模板里的 27 个捕获） | **全 68 枚 `main.zig` 漂移**（`initStaticStrings` 无条件发射）⇒ 必须重冻基线 | 只是把撞面挪到「用户函数名叫 `__zstr`」这种极端情况；仍有理论撞面 |
| **乙**（建议） | 只对**落在发射器标识符词表里的用户顶层函数名**做符号改名（Zig 符号 `__php_<name>`，**运行期名字字符串不变** ⇒ `get_functions`/`ReflectionFunction` 文案不受影响） | **零漂移**（改名的文件今天根本编不过 ⇒ 不在基线里） | 词表须与模板实际捕获集同步；需先确认函数符号与调用侧是否共用一处命名 helper（本轮 grep 未见中央 helper ⇒ **必须先把符号发射收口到一处**，这是乙的前置） |
| 丙 | 甲＋乙同时做（模板改名缩小词表 + 残留名再 mangling） | 同甲（需重冻） | 最稳，但一次吃掉两个改动面，归因不如乙干净 |

★我倾向**乙**，理由是它把「修复」与「基线重冻」解耦：**当前能编译的语料一个字节都不变**，出问题可一眼归因；甲会把 68 枚全推入漂移，正好撞上我们连续四批 `changed_rows=0` 才建立起来的中性判据。

### 26.5 本批纪律执行

链路已停才跑手工编译（规则 35）；`BAD_PROBE` 两枚按「臂无效 ≠ 红 ≠ 绿」剔除而非计入 diff；普查脚本落盘（`c020_f25_collision_census_tmp.sh` + `.tsv` 75 行）可当代复跑；本轮**零 `src/` 改动**、残留 0、`.php` 68/403 未变。

## 27. R-153（2026-10-13）：F-24d 归因轮（零 src 改动）⇒ 结论是**它不能单独修**，前置是新的 F-29

### 27.1 实测矩阵（PHP 8.5.8 pinned vs AOT `f1ff7a0d…`，两侧都跑 `FLAG=0/1` 两臂）

| 形 | 构造 | PHP | AOT | 判定 |
|---|---|---|---|---|
| d1 | 顶层 `class C extends NoSuchParent {}` | `Uncaught Error: Class "NoSuchParent" not found` + **rc=255**（`AFTER_DECL` 未打印） | `AFTER_DECL=y` + rc=0 | **红（fail-open）** |
| d2 | `class C implements NoSuchIface {}` | `Error: **Interface** "NoSuchIface" not found` + 255 | rc=0 `AFTER_DECL=ok` | **红**（文案与 d1 不同 ⇒ 检查必须知道槽位） |
| d7 | `implements I, NoSuchIface`（首项合法） | `Interface "NoSuchIface" not found` + 255 | rc=0 `OK` | **红**（逐子句判定，不是整体） |
| d5 | 同 d1 且随后 `new C()` | Fatal + 255 | rc=0 | 红（同族） |
| **d3** | `class C extends P {}` **写在 `class P {}` 之前**（顶层无条件） | **rc=0 `FORWARD=y`** | rc=0 相同 | 绿 ⇒ **前向继承合法**，检查不得假设声明顺序 |
| **d6** | 父类声明在 `if (FLAG)` 块内 | FLAG=0 ⇒ `Error: Class "P" not found` + 255；FLAG=1 ⇒ ok | **两臂都 ok** | 红（两型，见 F-29） |
| **d8** | 父类缺失的类声明写在**函数体内且函数未被调用** | rc=0，`class_exists("X")` = **n** | rc=0，`class_exists("X")` = **y** | 红 ⇒ **AOT 把类声明提前到启动期登记** |
| **d9** | 父类缺失的类声明写在 `if (FLAG)` 块内 | FLAG=0 ⇒ rc=0 `Y=n`（**不 fatal**）；FLAG=1 ⇒ Fatal + 255 | 两臂 `Y=y` 且不 fatal | 红（同 F-29） |

⇒ 结论 1：`Error` 文案分两种（`Class "X" not found` / `Interface "X" not found`），且**逐子句**判定。
⇒ 结论 2：PHP 的类链接发生在**声明语句执行处**（d8/d9 是反证：从不执行 ⇒ 从不报错、类也不存在），而 AOT 是**启动期一次性登记所有类**（`registerAllClasses`）。

### 27.2 为什么「登记处加 fatal」不能直接上

把检查加在 AOT 现有的登记位置，会把 **PHP 不报错**的 d8 / d9(FLAG=0) 变成致命 ⇒ 用一个 fail-open 换一个 **over-fatal**（比 fail-open 更坏：合法 PHP 直接崩）。⇒ **F-24d 的前置是 F-29**。

### 27.3 新立 F-29「类声明提前登记」（这才是根，且更宽）

| 面 | 实测 |
|---|---|
| `class_exists()` 判定 | d8：PHP `n` / AOT `y`；d9 FLAG=0：PHP `n` / AOT `y` ⇒ 凡「函数体内 / 条件块内 / 循环内的类声明」AOT 都当作已声明 |
| 连带效应 | ① 缺失父类是否 fatal 的时机（§27.2）；② 同名类在 PHP 里可因分支不同而「未声明」，AOT 恒声明 ⇒ `Cannot declare class` 族也失去判据 |
| 修复面（未落地） | 需要把类注册从 `registerAllClasses` 启动期改为**按声明位置发射登记**（顶层无条件类仍可启动期，函数/条件/循环内的类必须落到运行时语句）⇒ 触及 `ir_generator` 的类登记建模 + `native_linker` 发射 + 运行期形状；**语料 68 枚全部含类声明 ⇒ 必然全量漂移、需重冻** |
| 语料可达性 | 实测**作用域内类声明 = 0 枚**（88 处类声明全在顶层）⇒ F-29 在语料里不可见；而**未解析父/接口引用也 = 0 枚**（88 处全能在本文件解析）⇒ F-24d 同样不可见 ⇒ 二者只能靠门臂守 |

### 27.4 顺序与定价（**需你定调**，我未动代码）

| 步 | 内容 | 发射面 | 备注 |
|---|---|---|---|
| 1 | **F-29** 类声明按位登记 | 全 68 枚漂移（所有含类声明的脚本）⇒ 重冻基线 | 没有它，F-24d 无法正确修 |
| 2 | **F-24d** 链接失败 ⇒ `Error`（`Class`/`Interface` 两文案、逐子句、声明时机） | 依赖步 1 的发射形状，增量漂移小 | 门臂：d1 d2 d5 d6 d7 d8 d9 七形常驻（本批未建门；建议并入门 U 之后新开门或扩门 T，须先定「一臂一缺陷」的分法） |
| 备选 | 只做「**顶层无条件**类的启动期检查」（即 F-29 的极小子集） | 漂移同上但范围小，能收掉 d1/d2/d5/d7 四形，且 d8/d9 由「只查顶层类」天然规避 | 我倾向这条作为第一步：先按「声明是否在顶层无条件作用域」二分，顶层的立即查、非顶层的留给 F-29 |

### 27.5 本批纪律

零 `src/` 改动；d1–d9 九形两侧实测（含 `FLAG` 双臂）；语料可达性用两处静态普查（88 处引用全解析、作用域内类声明 0 枚）而非「影子没红」；链已停才做手工编译（规则 35）；残留 0、`.php` 68/403 未变。

## 28. R-154（2026-10-13）：F-28 落地 + 永久侧门 **V** 建成 ⇒ 更正 R-151b 对 F-27 覆盖面的说法，并新立 F-30…F-35 六张面孔

### 28.1 门 V 建成与定档（`c021_closure_obj_face_tmp.sh`，29 形）

| 项 | 值 |
|---|---|
| 建门起因 | 门 T 的 t23 只有两格（`get_class`/`is_object`），工单 §25.5 明文写着「同族疑还含 `get_debug_type`／`instanceof Closure`，**未测**」⇒ 本批先把这句话测穿 |
| 登记轮（修前） | **`same=10 diff=19 compile_fail=0 bad_probe=0`**（26 形段 @108s + 后补三臂 @14s 合并）；红 = `v1 v2 v3 v5 v6 v9 v13 v14 v15 v16 v17 v18 v19 v20 v21 v22 v26 v27 v28` |
| 定档轮（修后） | **`shapes=29 same=18 diff=11 compile_fail=0 bad_probe=0` @122s**（4.2 s/形）；残红 = `v13 v14 v15 v16 v17 v18 v19 v20 v21 v22 v26`（六张**未修**面孔，见 §28.4–§28.9） |
| 收敛八枚 | `v1 v2 v3 v5 v6`（F-28a/b/c/d）+ `v9 v27 v28`（F-27 第 2 层：函数形参 / 方法形参 / 可空方法形参） |
| 守卫臂 | `v4 v7 v8 v10 v11 v12 v23 v24 v25` 全程恒绿；**v11 是过度接受金丝雀**（`is_object(5/[]/"x")` 必须仍 false、`get_class(new stdClass)` 仍 `stdClass`）——加宽「什么算对象」的修复必须有这枚反臂，否则「绿」可能只是把非对象也放进了对象 |
| 探针坑（都进了门的注释） | ① `(string)$closure` 的**未捕获**形态不可用作回归臂：AOT 的 fatal 输出比 PHP 多一整块（`PHP Fatal error:` + 空行 + `Fatal error:`），结构差 ⇒ 永不 `same`，必须改成 `try/catch` + `get_class($t)` 的确定性形态；② `fn(): int {}` 与 `@$f->prop`（`@` 压不住 PHP 8 的 TypeError）都踩过，前者被 `php -l` 拦、后者会把三行臂截成一行 |

### 28.2 ★自我更正：类型检查有**三条互不复用的链**，R-151b 只收了第一条

我在 §25.3 写「F-27 ⇒ 四格 `object`/`Closure`/`?Closure`/union 全绿」，并把 `closureSatisfiesType` 的头注释写成「方法参数、返回值都必须先过这枚谓词」。**门 V 实测否证了这段描述**：

| 链 | 入口（落地后实测行号） | R-151b 后状态 | R-154 后 |
|---|---|---|---|
| ① 属性位 | `tryCoerceSingleType` / `coercePropertyType` | **已接谓词** ⇒ v23 绿 | 绿 |
| ② 形参位（函数 + 方法 + 可空） | `checkSingleType:6446`，`object` 伪类型分支在 `:6501` | **未接** ⇒ v9 / v27 / v28 三形红（`H::set(): Argument #1 ($c) must be of type object, Closure given`） | 已接（本批） |
| ③ `instanceof` 运算符（也是 catch 派发用的同一枚） | `php_instanceof:20891` | **未接** ⇒ v5 / v6 两形红 | 已接（本批） |
| ④ 返回值位 | 无检查 | 「绿」是**假绿** ⇒ 新立 F-35（§28.9），v24/v25 不得当收敛证据引用 | 未修 |

教训入规则：写「共享谓词已覆盖 X、Y、Z」时必须逐链给出**入口函数名 + 实测臂**，否则该句本身就是未测断言。模板头注释已就地更正为四条链的枚举（`:19611` 段）。

### 28.3 本批落地五枚（**纯模板改动** ⇒ 二进制 `f1ff7a0d…` 不变、`main.zig` 中性）

| # | 位点 | 修前 | 修后 | 收口臂 |
|---|---|---|---|---|
| 1 | `php_is_object:21759` | `Value_isObject(val)` | `Value_isObject(val) or val.isFunction()` | v1 |
| 2 | `php_get_class:21765` | 非对象 ⇒ `initBool(false)`（echo 成空串） | 前置 `.function` 分支返回 `"Closure"` | v2 |
| 3 | `php_gettype:24532` | `.function` 落到 `"unknown type"` | 与对象格合并：`Value_isObject(val) or val.isFunction()` ⇒ `"object"` | v3 |
| 4 | `php_instanceof:20891` | 第一行 `if (!Value_isObject) return false` | 早退前加 `closureSatisfiesType(class_name, obj_val)`，复用 R-151b 的共享谓词（规则 30：**不另造窄口径**） | v5 v6 |
| 5 | `checkSingleType:6501` `object` 伪类型 | `Value_isObject(arg)` | `Value_isObject(arg) or arg.isFunction()` | v9 v27 v28 |

未动 `Value_isObject` 本体 ⇒ 所有「取 `asObject()` 再解引用」的内部路径字节不变，本批不可能引入类型双关（这是 F-26/F-27 两次自造回归后定下的口径：**只在读侧加宽，不在谓词根加宽**）。

### 28.4 新立 F-30：PHP 8.5.8 起 **`Error` 不再继承 `Exception`**（本批最大意外）

pinned 真值源实测（`/opt/homebrew/bin/php` 8.5.8，五枚独立探针互证）：

| 探针 | PHP 8.5.8 | AOT（修前=修后，本批未触碰） |
|---|---|---|
| `get_parent_class('Error')` | **`false`**（无父类） | `false` ⇒ 两侧同值，但**这是巧合不是证据**：`php_get_parent_class` 首行 `if (!Value_isObject(obj_val)) return false` ⇒ AOT 的 `get_parent_class` 根本**不接受类名字符串**（PHP 接受）。⇒ v21 两格测的都是「字符串入参形态不支持」（并入 F-26 族的新子面），**父链证据只由 v19/v20 承担** |
| `get_parent_class('TypeError')` | `'Error'` | `false` ⇒ 红（v21，成因同上 ⇒ 不得引用为「父链正确/错误」的证据） |
| `is_subclass_of('TypeError','Exception')` | **`false`** | `true` ⇒ 红（v19） |
| `class_implements('Exception')` | `Stringable,Throwable` | 空 ⇒ 红（v22） |
| `count(5)` 外套 `catch (Exception)` / `catch (Throwable)` | 只有 **Throwable 臂**命中（`TypeError`） | 无此面（AOT 的 `count` 根本不抛 ⇒ 见 F-33） |
| v20：强转 `int` 形参收到 `"abc"`，三臂 `Exception`→`Error`→`Throwable` | `ERR-MATCH\|TypeError` | **`EXC-MATCH\|TypeError`** ⇒ 红 |

影响：`catch (Exception $e)` 在 8.5 里**不再**捕获引擎错误（`TypeError`/`ValueError`/…），AOT 仍按 7.x/8.0–8.4 的旧层级捕获 ⇒ 属「AOT 比真值更宽松」，且是**跨切面语义**（改内建异常类的父子链会同时改 catch 派发结果）。按 §五/§六：不改，等老铁定调；同时记「本仓库真值源 = 8.5.8」，此语义随 PHP 版本而变（同门 K 面 B 的 Deprecated 口径）。

### 28.5 新立 F-31：`throwException()` 把异常置成**字符串** ⇒ catch 永不命中 + fatal 类名错

`throwException:21822` 的实现是 `Value.initString(msg)` + `setException` —— 存的是一条**消息字符串**，不是对象。catch 派发用 `php_instanceof`（v13 实测：`catch (Throwable)` 完全接不到，直接 uncaught fatal），且 fatal 文本里的类名被写成 `Exception`（PHP 该位点是 `Error`）。

调用点 **17 枚**（实测行号）：`2909`、`5405`、`5425`、`5531`、`5554`、`5557`、`5560`、`5585`、`5588`、`5591`、`5599`、`5600`、`21216`、`21221`、`21224`、`21230`、`21236`。正确形态是既有的 `throwThrowable(class, msg, alloc):21829`（它 `findClass` 后建带 meta 的对象，R-144/R-146 都走这条）。

#### 28.5.1 六个信息族的 PHP 真值已测穿（纯 PHP 侧，链跑间隙取得，`/tmp/f31truth/`）

| 族 | AOT 现文本 | PHP 8.5.8 实测（类别 + 原文） | 落地形态 |
|---|---|---|---|
| 解包（4 枚：`5405` `5425` `5531` `5560`） | `Only arrays can be unpacked` | **`TypeError`** + `Only arrays and Traversables can be unpacked, int given`（**带实参类型**） | 换 `throwThrowable("TypeError", …)` 且消息需带 `valueTypeName(src)` |
| 空对象方法调用（2 枚：`5554` `5585`） | `Call to a member function on null` | **`Error`** + `Call to a member function doWork() on null`（**带方法名**） | 换 Error + 方法名入参 |
| 方法名非字符串（2 枚：`5557` `5588`） | `Method name must be a string` | **`Error`** + 同文本 ✅ | 只换类别 |
| 参数数组缺失（`5591`） | `Arguments must be an array` | **`TypeError`** + `call_user_func_array(): Argument #2 ($args) must be of type array, string given` | 换 TypeError + 全量重写消息（含函数名/参数号） |
| 未定义方法（`5600`，`5599` 为内部兜底） | `Call to undefined method` | **`Error`** + `Call to undefined method O::nope()`（**带 `类::方法`**） | 换 Error + 名字拼接；`5599` 的 `Cannot find class metadata` **不是 PHP 面向用户的错误**，需改成该位点的真实 PHP 错误 |
| 作用域缺失（`21216` `21221` `21224` `21230` `21236`） | `Cannot access self:: when no class scope is active` 等 | **两种结局，必须分开**：① 顶层 `self::class` ⇒ **可捕获 `Error`**，catch 后脚本继续（实测打印 `P6 Error` 后 `AFTER_SELF` 仍执行）；② 顶层函数里写 `parent::foo()` ⇒ **编译期 fatal** `Cannot use "parent" when no class scope is active`，**不可捕获**、整脚本不执行 | ①走 throwThrowable("Error")；②属编译期诊断，运行期模板改不动 ⇒ 归 `parser`/`native_linker` 侧，且要按「一臂一缺陷」单列门臂 |

⇒ F-31 不是「17 枚机械替换」：实测**四类异常类别 + 三种消息形态 + 一个编译期结局**。建议按族分批（每族一臂一轮 + 一链），首批取「只换类别、文本不动」的 2 枚（`Method name must be a string`）作为最小闭环验证 `throwException`→`throwThrowable` 的迁移是否影响门 R（F-9 fatal 终止语义）与门 P。

### 28.6 新立 F-32：无 `__toString` 的对象做字符串转换 fail-open

`PHPObject.toString:19423` 末路「默认返回类名」（`:19437`）⇒ `(string)$q` 得 `"Q"`，PHP 抛可捕获 `Error: Object of class Q could not be converted to string`（v14 红）。次生面：`magic_toString` 返回非字符串时也静默落到类名（未建臂）。语料面：`pass/` 内 `__toString` 声明存在，`(string)` 对象转换是否命中需单独普查后才敢改。

#### 28.6.1 F-32 的入口清单（R-154 备料轮穷举，`awk` 按「所在函数」分类，实测 **52** 处 `.toString(`）

| 桶 | 代表位点 | 落地要求 |
|---|---|---|
| **用户可见转换入口**（PHP 在此抛 `Error`） | `php_cast_string:20206`、`php_strval:24527`、`php_concat:7030/7036`、`php_concat_with_undef:7054/7062`、`php_interpolate:13242/13260`、`php_implode:11687/11706`、`php_sprintf:26756`、`php_coerce_value:6346`（`string` 形参位）、`tryCoerceSingleType:19661` / `coercePropertyType:19884`（`string` 属性位）、字符串族实参（`escapeshellarg:3844`、`escapeshellcmd:3891`、`file_put_contents:4020`、`fwrite:4077`、`str_getcsv×4:11719-11728`、`urlencode:23876`、`rawurlencode:23935`、`pack×2:27930/27947`、`preg_replace_callback:27352`） | 必须命中 `Error`；这些桶就是「修了才有真值」的面 |
| **数组键字符串化**（⚠️ **过度收紧雷区**） | `php_array_combine:22979`（`else` 支把非 int/string 的键 `toString` 后当字符串键） | PHP 8.1 起对象可作数组键（按对象哈希，**不**做字符串转换）⇒ 若把 `toString` 改成抛，这一支会由「能用」变「fatal」＝over-fatal。落地时必须单独给键路径走对象哈希语义，或保持宽松 |
| **内部/诊断**（不得抛） | `toString` 自身递归 `:2884`（ref 解引用）/`:2915`（对象支）、`php_get_class_vars:5122`（`catch` 后返空）、`enumFrom:21112`、`php_value_to_owned_string_slice:10005`、`valueCompare:22782/22784`、反射名/属性名转换约 12 处（`16134`、`16496/16529/16530`、`16799/16800`、`17284/17289`、`17449/17450`、`17802`、`2138/2149` 发射片段） | 这些位点拿到的是「名字」而非「值」，PHP 不会在此做对象转串；改成抛会把诊断路径打成 fatal（**这就是本批把 F-32 成本上修的原因**） |
| **未证 → R-156 静态定位** | `php_echo:7245` 通读到函数尾：分支只有 `null`/`bool`/`int`/`float`/`string`/`array`（数组支自带 `Array to string conversion` 告警），**既无对象支也无兜底 `else`**；`php_print` 只是转调 `php_echo` | ⇒ `echo $obj`/`print $obj` 对非 Stringable 对象今天是**静默零输出**（PHP 抛可捕获 `Error`）——比 `(string)$obj` 更隐蔽（没有类名可对照、也没有告警）。⇒ F-32 的收口清单必须含 `php_echo`+`php_print`；插值走 `php_interpolate`（发射点 `native_linker:23951`）、`.` 走 `php_concat`、显式转换走 `php_cast_string`/`php_strval`。⚠️ AOT 侧运行时读数（`echo $obj`、`$obj == "s"`）仍待链后实测，禁以静态读码代替 |

⇒ 结论更正：F-32 **不是**「把 `:19437` 那行改成抛」那么便宜。单点改会让数组键支与内部诊断支一起变 fatal；正确形态是「`toString` 保持宽松 + 新增 `toDisplayString()`（或带 flag 的严格版）在**用户可见入口**逐个替换」，或「单点改 + 给数组键/诊断支开例外」。两种形态都要先建臂：`(string)$obj`、`"$obj"`、`$obj . "x"`、`implode(",", [$obj])`、`sprintf("%s", $obj)`、`urlencode($obj)`、`array_combine([$obj], [1])`、`$obj == "s"`、`echo $obj`（9 形 ⇒ 追加进门 V 的 v40–v48 或单开一门）。

### 28.7 新立 F-33：`count()` 对非 Countable fail-open（返 0）

v15 一臂四输入实测：`count(5)` / `count("abc")` / `count(null)` / `count($closure)` PHP 全部 `TypeError`（消息 `count(): Argument #1 ($value) must be of type Countable|array, int given`），AOT 全部返回 `0`。与闭包无关的通用面 ⇒ **语料可达性未普查**（`count(` 在 pass/ 内高频），改动前必须先做「AOT 会不会本来就在被 PHP 的真值掩盖」的语料实测。

**落地位点（已实文核对，非推测）**：`php_count:11945`，fail-open 那行是 `:11956 if (!arr.isArray()) return Value.initInt(0);`；映射为 `native_linker:4182 .{ "count", bi(.{ .runtime_name = "php_count" }) }` ⇒ **纯模板改动**（影子中性）。★同一函数还有**第二张子面**：`:11947-11953` 判「是否 Countable」用的是 `findMethod("count")`（有没有 `count()` 方法），而不是 `implementsInterface("Countable")` ⇒ 一个「有 public `count()` 但未实现 `Countable`」的类今天会被 AOT 计数，而 PHP 抛 `TypeError`；反之「实现了 `Countable` 但 `count()` 不可见」的判定同样错位 ⇒ F-33 的落地必须**两半同动**（接口判定 + 非 Countable 抛 TypeError），只补 fatal 会留下第一半。语料规模实测：`count(` 在 pass/ 内 **184 处 / 47 文件**。

#### 28.7.1 Countable 判定面的 PHP 真值已测（`/tmp/f31truth/c2.php`，纯 PHP 侧）

| 形 | 构造 | PHP 8.5.8 实测 | 落地含义 |
|---|---|---|---|
| C1 | `class HasCountNoIface { public function count(): int { return 7; } }` ⇒ `count(new HasCountNoIface)` | **`TypeError`**：`count(): Argument #1 ($value) must be of type Countable|array, HasCountNoIface given` | ⇒ AOT 今天**过度接受**（走 `findMethod("count")` 得 7）⇒ 第一半必须换成接口判定，且消息要带**实际类名** |
| C2 | `implements Countable` + public `count()` | `3` | 正确形态的守卫臂 |
| C6 | `count(true)` | **`TypeError`**，文本为 `…, true given` | ★PHP 在这条消息里对 bool 打的不是 `bool` 而是 **`true`** ⇒ 消息用的不是 `valueTypeName`，落地时须按 `get_debug_type` 的**这条**口径实测复刻，禁直接套现有 `phpGetValueTypeName` |
| C7 | `count(1.5)` | **`TypeError`**，文本 `…, float given` | 同上 |
| — | `class PrivateCount implements Countable { private function count() }` | **编译期 fatal**：`Access level to PrivateCount::count() must be public (as in class Countable)` | 不是运行期面 ⇒ 按规则 38 从臂表剔除（合法 PHP 都无法声明），另属解析期可见性面 |
| — | `IteratorAggregate` 支 | — | 按宪法 §七（spl/生成器不在 AOT 范围）**排除**，不建臂 |

⇒ 落地形态三处同动：① `:11947-11953` 判定改 `implementsInterface("Countable")`（并保留调用其 `count()`）；② `:11956` 的非数组支由「返 0」改 `throwThrowable("TypeError", "count(): Argument #1 ($value) must be of type Countable|array, {s} given", …)`；③ `{s}` 的类型名走 C6/C7 实测口径。门臂在落地轮以 **v30–v33** 追加进门 V（V 的注册红集随之重定档），C3/spl 两支按上表剔除。

#### 28.7.2 ★①不能与②同批：实测的过度收紧风险（读码取得，未落地）

「把判定换成接口检查」今天会把三枚**内建类**打回 fatal，因为它们都注册了 `count()` 方法但 `interfaces` 字段是空的：

| 内建类 | 证据 |
|---|---|
| `SplFixedArray` | 方法注册 `:8942`（`splFixedArray_count`），meta 构造处 `:8932 .interfaces = &.{}` |
| `ArrayObject` | 方法注册 `:9406`（`arrayObject_count`），meta 构造 `ClassMeta.init(allocator, "ArrayObject")`，接口字段未填 |
| `WeakMap` | 方法注册 `:15172`，虽然 `:15151 meta.interfaces = ifaces` 会赋值，但 `ifaces` 内容未证 ⇒ 待实测 |

⇒ 若①先于「内建类接口表」落地，`count(new ArrayObject)` 之类由「能数」变「TypeError」＝**用 fail-open 换 over-fatal**（规则 37 的同一形态，且正是 F-26/F-27 两次的自造回归模式）。⇒ 更正后的排期：**F-33 拆两半**——第 1 批只做②＋③（非数组且无 `count()` 可调用 ⇒ 抛 TypeError，纯加严到 PHP 真值、零过度收紧）；第 2 批与 **F-3 的「内建接口表」同一轮**做①（`interfaces` 数据补齐后才能切判定）。C1（有 `count()` 未实现 `Countable`）作为**注册红留在门上**，等第 2 批收。

#### 28.7.3 ★第 1 批还有一条隐藏前置：**`php_count` 从不解引用**（R-154 备料轮实测）

| 实测 | 值 |
|---|---|
| PHP `count($r)`，`$r = &$a`、`$a=[1,2,3]` | **3**（`/tmp/f31truth/r2.php` R1） |
| PHP `count($rc)`，`$rc = &$countableObj` | **11**（R3） |
| PHP `function takesRef(array &$x) { return count($x); }` | **2**（R5） |
| AOT `php_count:11945-11967` 体内 `isRef` 出现次数 | **0**（grep 实数） |

⇒ 若第 1 批直接「非数组且无 count 可调 ⇒ TypeError」，而 AOT 的 `count(&$array)` 真把 `.ref` 值传进来，就会**把合法 PHP 打成 fatal**（规则 37 的过度收紧）。⇒ 第 1 批必须**三处同动**：`actual = if (arr.isRef()) arr.asRef().* else arr`（先例：`php_cast_array:20211`）＋ ②非 Countable 抛 TypeError ＋ ③消息类型名口径。⚠️ AOT 侧 `count($ref)` 的**当前读数未测**（本批链路在跑、禁并发编译）⇒ 落地轮第一件事是建臂 **v34**（引用→数组 / 引用→Countable / by-ref 形参三种形态）量出真值，再决定第 1 批的最小形态；不得凭「发射器大概会 deref」下笔。
（模板内解引用惯用法 `const x = if (v.isRef()) v.asRef().* else v;` 共 **52** 处，先例含 `php_cast_array:20211` ⇒ 写法有既有口径，不新造。）

#### 28.7.4 消息里的类型名表（PHP 8.5.8 实测，`/tmp/f31truth/m.php`，取 `…, X given` 的 X）

| 实参 | PHP 打印 | 说明 |
|---|---|---|
| `false` / `true` | **`false` / `true`** | ★不是 `bool`（同脚本里 `get_debug_type(true)` 给 `bool`）⇒ 这条消息用另一套格式化，**禁套 `phpGetValueTypeName:6355`**（它返回 `bool`） |
| `7` / `1.5` / `"x"` / `null` | `int` / `float` / `string` / `null` | 与现有表一致 |
| `new stdClass()` | **类名**（`stdClass given`） | 与 `phpGetValueTypeName` 的对象支（返回 `meta.name`）一致 |
| `fopen("php://memory","r")` | `resource` | 现有 `phpGetValueTypeName` **无 resource 格** ⇒ 需补 |
| 闭包 | `Closure` | 与本批 `:21765` 的 `.function` 口径一致 |

⇒ F-33 第一批需新增一枚**专用** helper（暂名 `countArgTypeName`），不复用现有类型名表；否则 `count(false)` 的消息会印成 `bool given` 而与真值不符 —— 消息面也是面，门 X 的 x9 与门 V 的 v15 就是量它。

### 28.8 新立 F-34：`spl_object_id()` 对闭包返回 0

v18：PHP 给正整数（闭包就是对象），AOT 走 `Value_isObject` 早退得 0 ⇒ 与 §28.2 的「读侧」同类，但涉及对象身份证分配器，未定价。

**实文核对后的定价（本批补，未落地）**：`php_spl_object_id:11494` 的实现是 `@intFromPtr(Value_asObject(obj)) & 0x7FFFFFFF`，非对象早退 0；同族第二枚 `php_spl_object_hash`（紧随其后）同样早退成 `"0000000000000000"`。闭包侧存在稳定指针来源 `Value.asFunction(): *PHPClosure`（`:2618`）⇒ F-34 = **两处各加一枚 `.function` 支**，取 `@intFromPtr(val.asFunction())` 的同一掩码口径。⚠️ 注意 AOT 的 id 本来就是**地址掩码**而非 PHP 的递增序号 ⇒ v18 的判据只能是 `> 0` 与「同一闭包两次调用相等」，禁把 id 绝对值当等值判据（同 [[feedback-aot-regression-rules]] 规则 19 的「非等值面」口径）。

### 28.9 新立 F-35：**返回值类型位完全不校验**

v26：`function rb(): object { return 5; }` ⇒ PHP `TypeError: rb(): Return value must be of type object, int returned`（可捕获），AOT 静默返回 `int`。⇒ v24/v25「闭包从 `: object` 返回」的绿**不是**闭合正确性，而是「这里根本没检查」。工单 010 §8 的 `n_void` 臂早已记录「未知返回类型名不参与校验」，本批把它从「未知类名」扩成「整条返回位无校验」，属独立一张门。

### 28.10 F-3 / F-30 的**静态根**（本批读码取得，未修）

内建可抛出层级在模板里是**两处自己写下的「简化」注释**，正好是三门（P 的 i1/i2、T 的 t2/t12/t13、V 的 v19/v20/v22）注册红的共同上游，且直接违反宪法 §四.1「禁止简化实现」：

| 位点 | 现码（注释为原文） | 后果 |
|---|---|---|
| `runtime_lib_template.zig:14781-14787` | `// Error extends Exception in our implementation for simplicity` + `error_meta.parent = meta`（`meta` = Exception） | ⇒ v19 `is_subclass_of('TypeError','Exception')` AOT `true`（PHP 8.5.8 `false`）、v20 `catch (Exception)` 过度捕获引擎错误 ⇒ **F-30 的根就在这里**，改法是 `error_meta.parent = null` + 让 `Error` 走 Throwable 伪接口支；风险＝把「现在被 Exception 臂接住」的站点改到下一臂或变成 uncaught，需语料普查 |
| `:14758-14779` | `// Register standard PHP exception subclasses (flat: extends Exception)`，12 枚名字一律 `child.parent = meta` | PHP 的 SPL 层级是**两级**（`LogicException`/`RuntimeException` 为中间层）⇒ `get_parent_class('UnderflowException')` 之类读数与 `catch (RuntimeException)` 的命中面都会错；具体父子表**须实测**（本批未测，禁凭记忆写） |
| `:14803-14808` | `oob_meta.parent = meta; // simplified: parent = Exception` | 又一处自认简化（PHP：`OutOfBoundsException` 另有其父） |
| 接口表 | 内建类注册时**不填** `interfaces` ⇒ v22 `class_implements('Exception')` 为空（PHP `Stringable,Throwable`） | 连带门 T 的 t2/t13（内建类 ↔ 内建接口格） |

⇒ 定档结论：F-3 与 F-30 不是「缺函数」而是**登记表数据不全 + 一处刻意的扁平化**；修法是把层级/接口做成数据表，属可测、可回归的中等改动，但会动到 catch 派发命中面 ⇒ 按 §六先请老铁定调，再按「一张父子表 + 接口表 + 语料 catch 面普查」开工（建议 R-155 归因轮先把真值表测穿：单进程 PHP 一次取全部 `get_parent_class`/`class_implements`，规则 38 口径）。

#### 28.10.1 PHP 8.5.8 真值表已取（单进程，32 名，`/tmp/f3truth/t.php`）

| 类 | `get_parent_class` | `class_implements` | 类 | `get_parent_class` | `class_implements` |
|---|---|---|---|---|---|
| `Throwable` | **—（无父）** | **`Stringable`** | `RuntimeException` | `Exception` | `Throwable,Stringable` |
| `Exception` | — | `Stringable,Throwable` | `LogicException` | `Exception` | `Throwable,Stringable` |
| **`Error`** | **—（无父）** | `Stringable,Throwable` | `BadFunctionCallException` | `LogicException` | `Stringable,Throwable` |
| `TypeError` | `Error` | `Throwable,Stringable` | `BadMethodCallException` | **`BadFunctionCallException`** | `Throwable,Stringable` |
| `ValueError` | `Error` | `Throwable,Stringable` | `DomainException` | `LogicException` | `Stringable,Throwable` |
| `ArithmeticError` | `Error` | `Throwable,Stringable` | `InvalidArgumentException` | `LogicException` | `Stringable,Throwable` |
| `DivisionByZeroError` | `ArithmeticError` | `Stringable,Throwable` | `LengthException` | `LogicException` | `Stringable,Throwable` |
| `UnhandledMatchError` | `Error` | `Throwable,Stringable` | `OutOfRangeException` | `LogicException` | `Stringable,Throwable` |
| `ErrorException` | `Exception` | `Throwable,Stringable` | `OverflowException` | `RuntimeException` | `Stringable,Throwable` |
| `ReflectionException` | `Exception` | `Throwable,Stringable` | `RangeException` | `RuntimeException` | `Stringable,Throwable` |
| `JsonException` | `Exception` | `Throwable,Stringable` | `UnderflowException` | `RuntimeException` | `Stringable,Throwable` |
| `Closure` | — | **空** | `UnexpectedValueException` | `RuntimeException` | `Stringable,Throwable` |
| `stdClass` | — | 空 | `Countable`/`JsonSerializable`/`Traversable`/`ArrayAccess` | — | 空；`Iterator`/`IteratorAggregate` 实现 `Traversable` |

三条可直接引用的实测结论：① **`Error` 无父类** ⇒ F-30 铁证（`catch (Exception)` 不得接引擎错误）；② `Throwable` **自己实现 `Stringable`** ⇒ 伪接口特判不能只考虑 `Exception`/`Error` 两支；③ SPL 异常是**两级**树（`LogicException`/`RuntimeException` 为中间层，`BadMethodCallException` 还是三级）⇒ `:14758` 的扁平表把 12 枚全挂到 `Exception`，父子读数与 `catch (LogicException)`/`catch (RuntimeException)` 的命中面都错。

★**取表形态的坑（R-155 前置）**：AOT 的 `php_get_parent_class` 首行 `if (!Value_isObject) return false` ⇒ **不接受类名字符串**，因此上表在 AOT 侧无法用同一形态复刻；要么改用对象实参（`get_parent_class(new TypeError)`），要么先补「内省函数接受类名字符串」这一子面（属 F-26 族的实参形态，非命名归一）。

### 28.11 语料面普查（为什么基线对这一族全盲）

| 普查 | 实测 |
|---|---|
| `is_object(` / `get_class(` / `gettype(` 调用点 | **12 处**，分布于 f006 f009 f044 f048 f067 f072 f151 |
| 逐点回溯实参是否可能是闭包 | **0 处**：f048 全文无闭包；f151 `Container::add()` 实参只有 `1..5` 与 `'hello'…`；f072/f044/f067 的 `gettype` 臂表里没有 `object` 格（闭包走 default 前后同值）；**f006:73** 的 `$listener` 来自 `subscribe(string $eventName, EventListener $listener)`（类类型形参，闭包进不来，全文唯一闭包是 `usort(fn…)`）；**f009:71-79** 的 `$this->wrapped` 是 `protected Command $wrapped` 类型化属性 ⇒ 同样不可能装闭包 |
| `object` 类型标注位点 | **2 处**：f010 `make(): object`（返回位＝不校验，F-35）、f104 `addComponent(string $type, object $comp)` ⇒ 15 个调用点实参**全是 `new X(...)`**，闭包 0 |
| `instanceof Closure` | **0 处** |
⇒ 主回归与影子对本族零暴露 ⇒ 门 V 是这一族唯一的常驻证据，禁以「链全绿」代替。

### 28.12 本批落地的风险面

| 项 | 评估 |
|---|---|
| 破坏性 | 非破坏：五枚都是**读侧加宽**（`.function` 值多态），`Value_isObject` 本体与发射侧零改动 ⇒ 二进制 md5 不变 |
| 类型双关 | 不可能引入：`asObject()` 的调用点谓词未变；实测闭包属性读/写（`@$f->prop` / `$f->dynProp = 7`）在修前就不崩（f2 探针得 NULL） |
| catch 派发 | `php_instanceof` 被 catch  dispatcher 复用（`ir_generator:3442`），但异常值只会是对象或（F-31 的）字符串，**永不**是 `.function` ⇒ 新增分支对派发面零影响 |
| 需盯的自造回归点 | 若 v11 金丝雀在链上转红 ⇒ 说明加宽溢出到非对象，必须立刻回滚（规则 30 第三次） |
| 残红 11 枚 | 全部属「新立未裁决」项，本批一律不碰 |

#### 28.12.1 待裁决六项的落地面与**影子漂移属性**（决定成本的唯一变量，实测/静态普查取得）

| 项 | 落点 | 落地面 | 是否动 `main.zig` ⇒ 是否需重冻影子 | 语料暴露面（规则 41 推断） |
|---|---|---|---|---|
| F-30 | 模板内建层级注册 `:14781` | **两半同动**：摘 `Error.parent` + 把方法集/接口表搬到 Error 根（`findMethod:13475` 沿 parent 上溯 ⇒ 只摘会砍掉 `getMessage` 整族） | **否**（纯模板 ⇒ 二进制不变、`main.zig` 中性） | 0（8 枚真实 catch 子句位点无一接引擎错误） |
| F-3 | 同上 + 内建方法表/接口表数据化 | SPL **两级**树（真值表 §28.10.1 已取全）+ `getTrace`/`getTraceAsString` 两枚方法缺失 | **否** | 0 |
| F-31 | 模板 17 枚 `throwException` 站点 | 按族分：4 类真值（Error/TypeError/带参消息/编译期 fatal）⇒ 见 §28.5.1，**非机械替换** | **否** | 0（这些站点今天都「不可捕获」，PHP 侧同为 fatal） |
| F-32 | 模板 `PHPObject.toString:19437` | **★本批把成本说小了，此处按实测更正**：fail-open 那行确实只有一处（`:19437`），但 `Value.toString` 在模板内被 **52 个调用点**使用（`grep -c "\.toString("` 实测），其中既有用户可见转换入口（`php_cast_string:20205`、`php_strval:24526`、`php_concat:7022`、插值），也有**诊断/消息构造**用途 ⇒ 直接在 `toString` 里抛 ⇒ 会把「构造错误消息」这类路径变成 fatal，甚至自递归。正确形态是「在**用户可见入口**抛 `Error`，`toString` 保留内部兜底」⇒ 需先在 `native_linker` 侧穷举发射到 `toString` 的入口清单 | **否**（纯模板） | 0 |
| F-33 | 模板 `php_count` | 非 Countable ⇒ `TypeError`；`count(` 在 pass/ 内 **184 处 / 47 文件**，面大但同为 fail-open。**★本批更正：不能一次做完**，接口判定会打红 `SplFixedArray`/`ArrayObject`（见 §28.7.2）⇒ 拆两批 | **否** | 0 |
| F-34 | 模板 `php_spl_object_id:11494` + `php_spl_object_hash` | 两处各加一枚 `.function` 支，指针源 `Value.asFunction(): *PHPClosure`（`:2618`）；判据只能 `>0` 与自等（AOT 的 id 是地址掩码，PHP 是递增序号 ⇒ 绝对值禁比） | **否** | 0 |
| F-35 | **发射侧**（`native_linker` 返回位） | 语料内带返回类型声明的函数/方法 **1064 处 / 68 文件全部命中** ⇒ 每个 return 出口都要插检查 ⇒ **必然全量影子漂移 = 一次重冻事件**（同 R-145 量级） | **是** ⇒ 需重冻 68 行 md5 | 0 |

⇒ 排期建议（按「成本 ÷ 风险」从优到劣，已按上表实测更正）：**F-33 第 1 批（只做②③，见 §28.7.2）→ F-30+F-3（合并一轮：内建层级/接口数据表 + 门 W 金丝雀）→ F-32 → F-31（按族分批）→ F-35（唯一需要重冻基线的，放最后单独一轮）**。理由：前三项都是纯模板改动 ⇒ 影子 `delta_rows=0` 天然成立、验收只花门链的钱；F-35 单独占一轮重冻，不与其它项混批（规则 31 同理，混批会让漂移无法归因）。

#### 28.10.2 F-30 落地前的影响面穷举（全部实测/实文，非推测）

| 问 | 取证方法 | 结果 |
|---|---|---|
| 有没有代码假定「可抛出 == Exception 后代」？ | grep 模板 `isSubclassOf("Exception")` / `class_name == "Exception"` 全部命中位 | **仅 1 处**：`php_instanceof` 的 Throwable 伪接口特判 `:20926-20927`，且它**已经**分 Exception/Error 两支各查 ⇒ 摘掉 `Error.parent` 后两支都仍成立 |
| 发射侧有没有硬编码这些类名？ | `grep '"Exception"|"Throwable"|"Error"' src/aot/native_linker.zig` | **0 命中** ⇒ F-30 的影响面完全收在模板内 ⇒ 影子中性（`main.zig` 不动） |
| 方法集从哪来？ | `findMethod:13475` / `findMethodLookup:13449` | 均沿 `self.parent` 上溯 ⇒ **`getMessage`/`getCode`/`getFile`/`getLine`/`getPrevious`/`__toString` 六枚今天全在 Exception 的 meta 上**，Error 支靠错链继承 ⇒ 摘 parent 必须同时把方法集搬到 Error 根 |
| 搬法（保序） | `putMethodOrdered:13415`（同名不重复入 `method_order`） | 按 `meta.method_order.items` 逐个 `error_meta.putMethodOrdered(m)`，再 `error_meta.magic_toString = error_meta.methods.get("__toString").?.func` ⇒ 门 P 的内部类 method_order 登记面不受扰动 |
| 属性读是否依赖 meta 声明？ | 读 `getMessage`/`getCode` 闭包体（`:14643-14674`） | 用 `this.getProperty("message")` 实例属性，非 meta 声明 ⇒ 摘 parent 不影响属性读 |

⇒ 结论：F-30 的**最小正确形态**＝「`error_meta.parent = null`」＋「方法集按 `method_order` 搬到 Error 根」＋「`Error`/`Exception` 各设 `interfaces = &.{ "Stringable", "Throwable" }`」三件同批，门 W 的 w13/w14（方法继承金丝雀）与 w15（`class_exists("Throwable")=false` 伪接口守卫）为硬验收项。

### 28.13 验收链（R-154，15 腿，`c021_r154_acceptance_chain_tmp.log`）

| 腿 | 读数 | 与注册值比对 |
|---|---|---|
| 链首 / 链尾二进制 md5 | `f1ff7a0d868410b8b2d111f325e0d368` / 见下 | 纯模板改动 ⇒ 首尾必须同值 |
| `zig build test` | rc=0 @3s，但输出末行 `failed command: …/test` | **不采信**，链后无并发复跑 `zig build test` + `test-aot` 另取 |
| 门 V | `shapes=29 same=18 diff=11 compile_fail=0 bad_probe=0` @121s | 等值（本批新建门） |
| 门 T | `shapes=22 same=16 diff=5 compile_fail=1 bad_probe=0` @89s | **注册红集下调一枚**（`t23` 转绿）⇒ 现行红 `t2 t9 t11 t12 t13`，`t17` 仍注册 compile_fail |
| 门 P | `shapes=76 same=71 diff=5 compile_fail=0` @302s | **恰等注册红、零新红** |
| 门 S | `shapes=47 same=47 diff=0` @195s | 等值（判据即 `diff=0`） |
| 门 M / N / O | `19 red=0 green=19` @72s ／ `7/7` @25s ／ `6/6` @21s | 等值 |
| 门 D8 | `defect_red=0 guard_same=14` @52s | 等值 |
| 门 Q / R | `same=5 unexpected_fail=0` @22s ／ `same=8 diff=1 terminate_lost=0` @40s | 等值 |
| 门 U | TSV 聚合 `75 行 = SAME 51 / COMPILE_FAIL 22 / BAD_PROBE_PHP 2` @213s | 等值（§26.2 注册值） |
| 普查门 B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` @2s | 等值（`diff_impl=3` 是 F-4 待裁决的现役证据） |
| 主回归 | 见 §28.13.1 | — |
| 影子 | 见 §28.13.1 | — |

★取证方式缺陷（已记，非回归）：链脚本以 `tail -1 <leg stdout>` 取 DONE 行，而门 U 根本不打印 `*_DONE` ⇒ 那腿链内行拿到的是普查表尾行。改进项：`grep -E "[A-Z0-9]+_DONE$"` 取，取不到则按列聚合回退。

★`repo_build_residue` 在本链不可当「泄漏」读：影子腿用 `ZIGPHP_AOT_KEEP_TEMP=1`，它自己在仓库根留 `.zigphp_aot_build_<pid>/` 直到该腿结束 ⇒ 影子跑动期间任何门的 `repo_build_residue=1` 都是**影子腿的正常状态**（本轮 18:11 实测目录 `.zigphp_aot_build_68626` 与影子行数同步增长）。⇒ 判泄漏要在影子腿结束后单跑一次门，或在链日志里对齐 mtime。**禁止在影子腿进行期间删除该目录**（属他人进程的在制品）。

### 28.13.1 主回归与影子（R-154 收尾实测）

| 腿 | 读数 | 判定 |
|---|---|---|
| 主回归（18:03:25 报表，@756s） | **`Total 68 / Pass 67 / Fail(Compile) 0 / Fail(Runtime) 0 / Fail(Diff) 0 / Skip 1`**；`## 失败明细` 仅 1 行 `f004_oop_deep_inheritance_magic.php SKIP（PHP_error_exit=255）` | **零回归**；回收枚 = 0（按规则 27 取明细行存在性，不看汇总 PASS）⇒ 与「语料对本族零暴露」的普查结论一致 |
| 影子 | `C010_SHADOW_DONE total=68 same=0 diff=68 miss=0 invalid=0` @1114s（18:21:59 收尾，**链总时长 3106s**）；new-side 整列已落盘 `c010_shadow_newside_r154_tmp.txt`（68 行，表身 md5 **`f19fb070ba1b86c34f02b3883de8e4dd`**） | 与 R-151b 基线列比对：**`changed_rows=0` / `col_identical=yes`**（由永久脚本 `c010_shadow_col_extract_tmp.sh` 取，内置「两侧必须各 68 行」硬断言）⇒ 纯模板发射中性复证；链尾二进制 md5 仍 `f1ff7a0d…` 与链首同值 |

**门 V 按注册字节复跑（链后、无并发）**：`c021_closure_obj_face_tmp.sh` md5 = **`e58681e5c4500bff85cf14ddbf8c82d5`** ⇒ `shapes=29 same=18 diff=11 compile_fail=0 bad_probe=0 repo_build_residue=0` @129s（与登记值同，仅时长差）。门 W 脚本 md5 `e41a00515b68d22ae32af19fe656f726`、门 X 脚本 md5 `173d8567cfd371b347e9c7168f173dcf`。

### 28.13.2 ★`zig build test` / `test-aot` 的真相（链内读数不采信，链后无并发复跑取得）

| 步 | 无并发复跑读数 | 结论 |
|---|---|---|
| `zig build test` | **rc=0**，16 行输出（两次 `✅ All performance tests passed`，末行仍打 `failed command: ./.zig-cache/o/7438e08b…/test`） | 该步整体成功；`failed command` 行由 perf/CI 包装器打印后继续 ⇒ **不能据此判红**，但也**不能**据 `rc=0` 宣称它验证了运行期模板 |
| `zig build test-aot` | **失败：6 compilation errors**（`dependency_resolver.zig:692/706/723/738/789` 五处在 `test` 块内用 2 实参调用 4 形的 `init`；`linker.zig:162` 缺 `items`/`capacity`） | ★**长期失编译，与本批无关**：这两个文件不在 `72cdaca`/`948c0c2` 的改动清单内，且错误全在 `test {}` 块里 ⇒ 主构建 `zig build` rc=0、产物 md5 不变。新立 **F-38「AOT 单测步骤长期失编译」** |
| 那本批模板正确性由什么证？ | 门 V/W/X 三轮共 **58 形**逐形 `--compile` 全部成功（`compile_fail=0`）⇒ 模板展开出的 `runtime_lib.zig` 真编译通过 | ★**更正旧口径**：模板的编译验证 = **AOT 产品编译**，不是 `zig build test`；此前记忆里「`zig build test` 21/21 & 326/326 覆盖模板」的说法不成立（`test_runtime_*.zig` 属 `test-aot`，而那一步早已编不过） |

### 28.14 本批纪律

- 先建门登记红（`same=10 diff=19`）再落地，链上再复跑；门脚本定档后 md5 见 §28.13。
- 纯模板改动 ⇒ 不重建二进制，链首尾各取一次 md5 自证（两者必须相同）。
- 链路运行期间零手工 `--compile`（规则 35，上一批刚踩过假红）。
- 所有真值实测，未用计算/推测；§25.5 那句「未测」在本批被明确改写为实测结论（`get_debug_type` 绿、`instanceof` 红）。
- ★两处**读数级别的自我否证**（写进门注释，防后来者误引）：v21 的 `get_parent_class('Error')` 两侧同值实为「AOT 不接受类名字符串」的巧合 ⇒ 不得作为父链证据（§28.4）；v24/v25 的绿来自返回位根本不校验 ⇒ 不得作为 F-27 收敛证据（§28.9）。
- 探针产物全部落在 `mktemp -d`，链尾统一清理；`.php` 原始脚本零删除。

## 29. R-155 备料轮（2026-10-13）：门 W / 门 X 登记轮 ⇒ **否证我自己提的引用前置**，并新立 F-36 / F-37 / F-38

### 29.1 门 X 登记轮（9 形，修前基线）

| 项 | 值 |
|---|---|
| 读数 | **`shapes=9 same=6 diff=3 compile_fail=0 bad_probe=0 repo_build_residue=0` @42s**（4.7 s/形）；脚本 md5 `173d8567cfd371b347e9c7168f173dcf` |
| 注册红（3 枚） | `x4`＝有 `count()` 但未实现 `Countable` ⇒ AOT 得 7、PHP 抛 TypeError（**第 2 批才收，按 §28.7.2 必须留红**）；`x6`＝`count(resource)` ⇒ AOT `ok:0`、PHP TypeError；`x9`＝`count(1.5)`／`count(true)` ⇒ AOT 双 `ok:0`、PHP TypeError（消息 `float given` / **`true given`**） |
| 守卫绿（6 枚） | `x5` Countable 对象=11、`x7` `COUNT_RECURSIVE` 嵌套=5、`x8` 空递归=0 与普通=2、**`x1`/`x2`/`x3` 引用三形全部 SAME** |
| ★对 §28.7.3 的否证 | 我在 §28.7.3 写「`php_count` 体内 `isRef`=0 ⇒ 第一批必须同补解引用，否则 `count(&$array)` 会变 fatal」——**实测否证**：`x1 count(&$array)=3`、`x2 count(&$countableObj)=11`、`x3 by-ref 形参内 count=2` 三形**已经等值** ⇒ 引用在**载入侧**已被解引用，`php_count` 收到的从来不是 `.ref` 值。⇒ 第 1 批**不需要**动解引用；那条「雷区」降级为「已验证不存在」，但 §28.7.3 的取证方式（先量再写）值得保留 |

⇒ F-33 第 1 批的真实形态收窄为**两处**：`:11956` 非数组支由「返 0」改 `throwThrowable("TypeError", …)`，加一枚专用类型名 helper（§28.7.4 表）。预期读数：`x6`、`x9` 转绿、`x4` 留红 ⇒ 门 X 定档 **`same=7 diff=2`，注册红 = `x4`**；门 V 的 `v15`（int/string/null/closure）应同时转绿 ⇒ V 定档从 `18/11` 变 `19/10`。

### 29.2 门 W 登记轮（20 形，修前基线）

| 项 | 值 |
|---|---|
| 读数 | **`shapes=20 same=7 diff=13 compile_fail=0 bad_probe=0 repo_build_residue=0` @78s**（3.9 s/形）；脚本 md5 `e41a00515b68d22ae32af19fe656f726` |
| 注册红（13 枚）与分组 | **F-30（3 枚）**：`w1 get_parent_class(new Error)` AOT=`'Exception'` vs PHP=`false`（★这条才是真正量父链的臂，`v21` 的字符串形态是盲的）、`w9 is_subclass_of('Error','Exception')` AOT=true、`w10` catch 派发 `EXC-MATCH` vs PHP `ERR-MATCH`；**F-3 层级（4 枚）**：`w4` BadMethodCallException 父名、`w5` UnderflowException 父名、`w6` **`class_parents()` 整个函数未实现**（AOT 报 `Call to undefined function class_parents()`）、`w17 get_class_methods("Exception")` 计数 AOT=7 vs PHP=10；**F-3 接口表（3 枚）**：`w7`/`w8` `class_implements` 对内建类返空、`w15 interface_exists("Throwable")` AOT=false；**F-3 catch 语义（2 枚）**：`w11 catch (RuntimeException)` 接不到 `UnexpectedValueException`、`w12 catch (LogicException)` 接不到 `BadMethodCallException`（都掉到 Exception 臂）⇒ **扁平树不只是读数错，还会让具体臂永不命中**；**F-36（1 枚）**：`w14`（见 §29.3） |
| 守卫绿（7 枚） | `w2 TypeError→Error`、`w3 DivisionByZeroError→ArithmeticError` 两枚父链正确（⇒ 注册表并非全错，是按名个别登记）；`w13 TypeError->getMessage/getCode/getPrevious` 全对 ⇒ **方法继承金丝雀已 armed**，摘 parent 后必须仍绿；`w16 instanceof Stringable`；`w18` 用户类 `extends Exception` 的 catch 与父名；`w19 catch (\Throwable)`；`w20 throw new Error` + `catch (Error)` |

### 29.3 新立 F-36 / F-37（本轮实测，均未修）

| 项 | 实测证据 | 状态 |
|---|---|---|
| **F-36** | `w14`：`new Error("em")->getMessage()` 正常，但 **`getFile()` 为空**（`file_gt0=false`）。~~而 `new Exception("x")->getFile()` 非空~~ ★**该对比已被 R-156 实测否证**：当时用的 `new Exception` 形是**被 `throw` 过的**（`/tmp/f31truth/fl.php` F2 在 try 内抛出），而 R-156 的 `/tmp/f36/p.php` 证明「构造但从未抛出」的 `Exception` 与 `Error` **两侧都空**（`file=[]`、`line=0`）⇒ 与 Error 支无关，见 §30.3 | 改判后待修：`file`/`line` 由 `setException` 惰性注入 ⇒ 未抛出的异常对象取不到位置（F-30 的「搬根」清单已据此删掉「属性初始化」一项） | | 待归因 ⇒ **Error 根与 Exception 根不等价**：构造期写入的默认属性（file/line/code）没跟着搬 ⇒ 直接补进 F-30 的落地清单（原来只写「搬方法集 + 接口」，现扩为**三件 + 属性初始化**） |
| **F-37** | `intdiv(1,0)`：PHP 抛可捕获 `DivisionByZeroError`（`getFile()` 非空）；AOT 打印 **`error: DivisionByZero`** 且 **rc=1**（Zig error 外逸到进程出口，既不是 PHP fatal 文本也没有 rc=255） | 新立，属 F-9／R-145「未捕获异常必须以 PHP 风格 fatal + rc=255 终止」这族的**漏网站点**：模板 `:5962/:5976/:6003` 三处 `_ = try throwThrowable("DivisionByZeroError"/"Modulo by zero")` 之后调用链把 Zig error 冒到了 `main`。待归因（门 R 现在抓不到它，因为门 R 的臂用的是 `throw` 语句而非算术错误） |
| **F-38** | `zig build test-aot` **6 compilation errors**，全在 `test {}` 块内（`dependency_resolver.zig:692/706/723/738/789` 用 2 实参调 4 形 `init`；`linker.zig:162` 缺 `items`/`capacity`）；本批与上一批的提交都未含这两个文件 ⇒ 长期失编译 | 新立；后果见 §28.13.2：**AOT 模块的单测步骤实际没有在保护任何回归**，宪法 §三.2 的「必须通过 `zig build test` 验证」对 AOT 侧是空转。修法＝修这 6 处陈旧测试调用（零生产码风险），或把该步从验收口径里显式摘掉并改用门链 |

### 29.4 本批纪律

零 `src/` 改动；门 X/W 各跑一次登记轮并在**链结束后**（无并发）取数；引用前置被自己的臂否证 ⇒ 按规则 34 带证据更正而非悄悄删结论；`zig build test` 的链内可疑读数用链后无并发复跑定案（并因此挖出 F-38）；F-36/F-37 只做实测登记、未动代码。

### 29.5 F-33 第一批落地（R-155，纯模板两处）

| 项 | 值 |
|---|---|
| 落地 | ① 新增专用 helper `countArgTypeName`（bool ⇒ `true`/`false`、resource ⇒ `resource`，其余复用 `phpGetValueTypeName`，DRY）；② `php_count` 的 `if (!arr.isArray()) return Value.initInt(0);` 改为 `return throwThrowable("TypeError", "count(): Argument #1 ($value) must be of type Countable|array, {s} given", runtime_allocator);` |
| 未做（按 §28.7.2 设计） | 接口判定 `implementsInterface("Countable")` **不换** ⇒ `x4`（有 `count()` 未实现接口）留注册红；否则 `SplFixedArray`/`ArrayObject` 由能数变 fatal |
| 未做（被本批否证） | 解引用**不加** —— 门 X 的 `x1/x2/x3`（引用→数组=3／引用→Countable=11／by-ref 形参内 count=2）登记轮已 SAME ⇒ 引用在载入侧已解 |
| 复证读数 | 门 X **`shapes=9 same=8 diff=1 compile_fail=0 bad_probe=0` @39s**（残红恰 `x4`）；门 V **`shapes=29 same=19 diff=10` @120s**（`v15` 转绿，其余 10 枚原样）⇒ 零守卫被打红 |
| 验收链 | 17 腿 `c023_r155_acceptance_chain_tmp.sh`（门 X/V/W 新入常备腿）；读数见 §29.5.1 |

### 29.5.1 R-155 验收链读数（17 腿，`c023_r155_acceptance_chain_tmp.log`，18:54:58→19:46:07，**3069s**）

| 腿 | 读数 | 判定 |
|---|---|---|
| 链首/链尾二进制 md5 | `f1ff7a0d868410b8b2d111f325e0d368` ／ 同值 | 纯模板改动自证（不重建） |
| `zig build test` | rc=0 @4s | 同 R-154 口径（见 §28.13.2：该步不覆盖模板；模板由门链的产品编译证） |
| 门 X | `shapes=9 same=8 diff=1 compile_fail=0 bad_probe=0` @39s | **本批判据**：残红恰 `x4`（设计留红），`x6`/`x9` 随 F-33 转绿 |
| 门 V | `shapes=29 same=19 diff=10` @121s | `v15` 转绿；其余 10 枚原样 ⇒ 零新红 |
| 门 W | `shapes=20 same=7 diff=13` @75s | 与登记轮**逐枚同值** ⇒ 本批未碰 F-3/F-30 |
| 门 T | `shapes=22 same=16 diff=5 compile_fail=1` @89s | 等值（红 `t2 t9 t11 t12 t13`，失败 `t17`） |
| 门 P | `shapes=76 same=71 diff=5 compile_fail=0` @302s | **恰等注册红、零新红** |
| 门 S | `shapes=47 same=47 diff=0` @187s | 等值 |
| 门 M / N / O | `19 red=0 green=19` @68s ／ `7/7` @24s ／ `6/6` @21s | 等值 |
| 门 D8 | `defect_red=0 guard_same=14` @49s | 等值 |
| 门 Q / R | `same=5 unexpected_fail=0` @22s ／ `same=8 diff=1 terminate_lost=0` @38s | 等值（门 R 关键：新增的 TypeError 抛出**没有**破坏 fatal 终止语义） |
| 门 U | 按列聚合 `75 行 = SAME 51 / COMPILE_FAIL 22 / BAD_PROBE_PHP 2` @203s | 等值（链脚本对无 `*_DONE` 的门已改为回退提示，见 §29.10.2 同批改进） |
| 普查门 B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` @2s | 等值（F-4 决策就绪，见 §29.9） |
| 主回归 | 19:28:47 报表 @785s：**`Total 68 / Pass 67 / Fail(Compile) 0 / Fail(Runtime) 0 / Fail(Diff) 0 / Skip 1`**，`## 失败明细` 仅 `f004 … SKIP` | **零回归、回收 0 枚**（规则 27 取明细行存在性）⇒ 与「语料 `count(` 站点无一是非 Countable 实参」的规则 41 推断一致 |
| 影子 | `C010_SHADOW_DONE total=68 same=0 diff=68 miss=0 invalid=0` @1040s；列落盘 `c010_shadow_newside_r155_tmp.txt`（68 行，md5 `f19fb070…`） | **`changed_rows=0` / `col_identical=yes`**（vs r154 列，且与 r148b~r151b 六列同值） |
| 残留 / 语料 | `.zigphp_aot_build_*` = 0、`aot_compile_*` = 0、`pass/*.php` = 68、`fuzzy_scripts_720` 内 `.php` = **403**（未变）、全仓 `.php` = 601 | 宪法 §三.7/§七.9 合规：**新口径**「403」的统计范围 = `find fuzzy_scripts_720 -name '*.php'`，跨轮比较须用同一范围 |

### 29.6 F-37 归因到位（本批只读，未修）：一处站点 + 一条外逸通道

| 环 | 证据 |
|---|---|
| 站点 | `php_intdiv:12799`，`:12802 if (b == 0) return error.DivisionByZero;` —— 用的是 **Zig error**，不是 `throwThrowable` |
| 通道 | 发射的入口是 `native_linker:2161` 的 `pub fn main(init_arg: std.process.Init.Minimal) !void`，**外层没有 catch** ⇒ Zig 默认处理器打印 `error: DivisionByZero` 并 **exit 1** |
| AOT 实测 | `intdiv(1,0)` ⇒ 输出 `error: DivisionByZero`、`rc=1`、且该错误**不可被 `try/catch` 捕获**（探针 `/tmp/f31truth/fl.php`） |
| PHP 真值（5 形实测，`/tmp/f31truth/ac4.php`） | `intdiv(1,0)`/`intdiv(0,0)` ⇒ **`DivisionByZeroError: Division by zero`**；`intdiv(PHP_INT_MIN,-1)` ⇒ **`ArithmeticError: Division of PHP_INT_MIN by -1 is not an integer`**；`intdiv("abc",2)` ⇒ `TypeError` 参数消息；`intdiv(5)` ⇒ **`ArgumentCountError: intdiv() expects exactly 2 arguments, 1 given`**；未捕获时 PHP **rc=255** + fatal 文本 |
| ⚠️ 未证的连带风险 | AOT 用 `@divTrunc(a, b)`：i64 `MIN / -1` 在 Zig 里是**整数溢出 panic**（ReleaseFast 下无检查 ⇒ 未定义结果）⇒ 第 2 形必须实测后再定，禁凭「大概会溢出」下结论 |

### 29.7 新立 F-39（整族普查，本批只读）：模板内 **304 处 `return error.X`** 全部绕过 PHP 异常语义

| 错误名 | 站点数 | 对应 PHP 真值（实测样例） |
|---|---|---|
| `InvalidArgumentCount` | **132** | `strlen()` ⇒ `ArgumentCountError: strlen() expects exactly 1 argument, 0 given`；`json_decode()` ⇒ `… expects at least 1 argument, 0 given`（措辞随函数变：exactly / at least） |
| `InvalidArgument` | 58 | `array_pop("x")` ⇒ **`Error: array_pop(): Argument #1 ($array) could not be passed by reference`** |
| `MissingArgument` | 32 | 同上族（按函数不同） |
| `ClassNotFound` | 21 | `Error: Class "X" not found`（与 §27 F-24d 相邻但不同位点） |
| 其余（`InvalidChannel` 10／`OutOfMemory` 9／`ReflectionClassNotFound` 6／`ReflectionMethodNotFound` 3／`MethodNotFound` 3／`InvalidJson` 3／`InvalidCallback` 3／其余各 1–2） | 62 | 各自待实测 |
| **合计** | **304** | — |

后果（统一）：这些站点在 AOT 里都成为**不可捕获**的 Zig error ⇒ 文本 `error: <Name>`、**rc=1**；PHP 侧全是**可捕获**的 `ArgumentCountError`/`TypeError`/`Error`，未捕获时 rc=255 ⇒ 属 F-9/R-145「未捕获 fatal」族在**内置函数边界**的漏网，且门 R 现有臂只测 `throw` 语句路径 ⇒ **抓不到这一族**（需扩臂）。语料暴露面按规则 41 = 0。

| 修法 | 收益 | 代价与后果 | 我的建议 |
|---|---|---|---|
| **甲：入口 `catch`** | 单点改动即覆盖 304 站的「未捕获」结局（PHP 风格 fatal 文本 + rc=255） | **仍然不可捕获**（`catch (ArgumentCountError)` 接不到）；属发射侧 ⇒ **影子全量漂移、需重冻 68 行** | 先做甲：它是 F-9 族的补完，且把最坏症状（rc/文本错）一次性收掉 |
| **乙：逐站改 `throwThrowable`** | 真·可捕获 + 消息与 PHP 一致 | 132 枚实参计数消息必须**逐函数实测**（`exactly` vs `at least`、参数名、个数），禁套模板硬编 ⇒ 按函数族分批，约 4–6 轮 | 与 F-31（`throwException` 17 站）合流成「抛出形态」工作流，乙排后 |

### 29.7.1 门 Y 已建成（`c024_zig_error_escape_tmp.sh`，12 形）+ PHP 真值已全部取（无并发轮 `AOT_BIN=/bin/false` 预验 ⇒ `bad_probe=0`）

| 臂 | 调用 | PHP 8.5.8 实测（catch 到的类 + 消息） | AOT 预期（本族机制） |
|---|---|---|---|
| y1 | `strlen()` | **`ArgumentCountError`**：`strlen() expects exactly 1 argument, 0 given` | `error: InvalidArgumentCount` + rc=1 + 不可捕获 |
| y2 | `json_decode()` | **`ArgumentCountError`**：`json_decode() expects **at least** 1 argument, 0 given` | 同上（措辞 exactly/at least 随函数变 ⇒ 乙案不能套模板） |
| y3 | `intdiv(5)` | `ArgumentCountError`：`intdiv() expects exactly 2 arguments, 1 given` | 同上 |
| y4 | `$s="x"; array_pop($s)` | **`TypeError`**：`array_pop(): Argument #1 ($array) must be of type array, string given` | 对应 `InvalidArgument` 族 |
| **y10** | `array_pop("x")`（临时表达式实参） | **`Error`**：`array_pop(): Argument #1 ($array) **could not be passed by reference**` | 与 y4 **不同类**（一个是 TypeError）⇒ 已单列一臂，对应 `InvalidArgument` 族的两种结局 |
| y5 | `intdiv(1, 0)` | `DivisionByZeroError`：`Division by zero` | **F-37 那一枚**（`:12802`） |
| y6 | `intdiv(PHP_INT_MIN, -1)` | **`ArithmeticError`**：`Division of PHP_INT_MIN by -1 is not an integer` | AOT 走 `@divTrunc` ⇒ 读数待测（Zig 溢出行为未知） |
| y7 | `1 % 0` | （待登记轮复述，PHP 侧 `DivisionByZeroError`） | 模板 `:6003` 已用 `throwThrowable` ⇒ 预期**绿**，作「同族正确先例」守卫 |
| y8/y9 | `new NoSuchClassX("a")` / `NonexistentClassX::staticM()` | **`Error`**：`Class "…" not found` | 对应 `ClassNotFound` 21 枚；与 §27 F-24d（父类缺失 fail-open）**不同位点** |
| g1/g2 | 正常调用 / 用户 `throw` + `catch` | `G1=3`、`G2=CAUGHT|RuntimeException|plain` | 守卫臂（必须恒绿；g2 证明「用户 throw 路径」仍可捕获，问题只在内置边界） |

⇒ 门 Y 的**建臂纪律**与本族特殊性已写进脚本头：外逸会终止进程 ⇒ **一枚外逸站点一臂**，禁合臂；合法性的 `bad_probe=0` 已在无并发轮（`AOT_BIN=/bin/false`）预验，AOT 侧读数与注册红集待 R-155 链结束后跑登记轮取。

### 29.8 ★探针设计缺陷（本轮新坑，待链后修门）：观测器必须**先绑定结果再 echo 前缀**

`echo $tag, "=ok:", var_export(count($v), true), "\n"` 在 PHP 里是**逐实参求值、顺序写出**：若 `count($v)` 抛错，前缀 `X4=ok:` 已落 stdout，随后 catch 分支又打一遍 ⇒ 读数出现 `X4=ok:X4=ERR|TypeError|…` 的半行伪迹（门 X 的 `x4/x6/x9` 与门 V 的 `v15` 全中）。等值判定仍成立（两侧都带同一前缀，且 AOT 返 7 时没有 ERR 段），但**「两侧都有 ok 段」极易被误读成「行为差不多」**。正确写法：`try { $r = count($v); echo $tag,"=ok:",var_export($r,true),"\n"; }`。⇒ 修门须在链结束后做（链进行中改脚本会污染正在执行的腿），并按「先修门后引用」重跑一轮。

### 29.9 F-4（`builtin_map` 重复键）机制取证完成 ⇒ **决策就绪**（本批只读，未动代码）

普查门 B 现行读数 `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30`。三枚实现不同的重复键与两套实现全部对上：

| 键 | 新版条目（R-144 落的支持 flags/offset + 第三实参 by-ref） | legacy 条目 | 模板两套实现 |
|---|---|---|---|
| `preg_match` | `native_linker.zig:4108` → `runtime_name = "preg_match"` | `:4146` → `"php_preg_match"` | `:10746` vs `:26983` |
| `preg_match_all` | `:4110` → `"preg_match_all"` | `:4147` → `"php_preg_match_all"` | `:10871` vs `:27117` |
| `preg_split` | `:4114` → `"preg_split"` | `:4150` → `"php_preg_split"` | `:11259` vs `:27386` |

★**真正的风险不是「哪条写在前面」**：`builtin_map` 是 `std.StaticStringMap(BuiltinInfo).initComptime(…)`（`native_linker:4001`），而 `std/static_string_map.zig` 的 `initComptime`（`:71`）把**全部条目（含重复键）按 key 排序**后存放，`getIndex`（`:198`）从长度索引线性扫描并返回**排序后第一个**相等键 ⇒ **胜者由编译期排序决定，与源码书写顺序无关、也不保证稳定**。当前实测胜者是新版（门 S 47 形 `diff=0` 就是证据：只有新版带 flags/offset 语义），但任何别处的地图改动都可能**无声翻面**，把 R-144 已收口的 PCRE 族整体退回 legacy 行为。

| 待你点头的形态 | 内容 | 风险与代价 |
|---|---|---|
| **甲（建议）** | 删三条 legacy 条目（`:4146/:4147/:4150`）保留新版；30 枚 `DUP_IDENTICAL` 同批去重（`field_diff=0` 已证两侧字段一致 ⇒ 无行为差） | 宪法 §六.3「涉及删除代码必须先问」⇒ 本批未动；删后复跑门 S（判据 `diff=0`）+ 门 B（判据由 `diff_impl=3` 改 **`=0`** ⇒ 属**判据变更**，须在工单登记新旧两版判据）+ 一链 |
| 乙 | 只删重复条目，不动 legacy 函数本体 | `php_preg_match`/`php_preg_match_all`/`php_preg_split` 成无引用死桩（先例：010 的 D-4「死桩维持」）⇒ 维持即可，不额外删函数 |
| 丙（否） | 保留重复、仅加注释 | 编译期排序的翻面风险常在，门 B 的 `diff_impl` 须永久挂着 ⇒ 不推荐 |

### 29.10 门 Y 登记轮（12 形，修前基线）⇒ F-39 分出**三个子面**，并新立 F-40 / F-41

| 项 | 值 |
|---|---|
| 读数 | **`shapes=12 same=3 diff=7 zig_escape=2 compile_fail=2 bad_probe=0 repo_build_residue=0` @43s**（3.6 s/形）；脚本 md5 见 §29.12（观测器与 rc 判据修过两次，取终稿值） |
| 守卫绿（3 枚） | `y7 1 % 0`（模板 `:6003` 走 `throwThrowable` ⇒ **同族正确先例**，与 `intdiv` 形成干净对照）、`g1` 正常调用、`g2` 用户 `throw` + `catch (Throwable)` ⇒ 证明「用户抛出路径可捕获」未被本族污染 |
| ★真 rc 才看得出的分级 | 见下表；`y2`/`y5` 的 rc=1 与 `y4`/`y8`/`y9`/`y10` 的 rc=255 在旧 rc 判据下**完全无法区分** |

| 臂 | PHP（可捕获） | AOT 真读数 | 子面归类 |
|---|---|---|---|
| `y2 json_decode()` | `ArgumentCountError` | `error: InvalidArgumentCount`、**rc=1**、不可捕获 | **F-39-i 裸外逸**（走动态分发 ⇒ 模板 `return error.X` 冒到 `main`） |
| `y5 intdiv(1,0)` | `DivisionByZeroError` | `error: DivisionByZero`、**rc=1** | **F-39-i**（同 F-37 那一枚站点） |
| `y4 array_pop($s)`／`y10 array_pop("x")` | `TypeError`／`Error` | `Uncaught TypeError: …`、**rc=255**，但 **catch 没接住** | **F-39-ii 入口守卫已把 Zig error 印成 PHP 风格 fatal，可捕获性仍然丧失**（Zig error 越过块级 handler 直接外逸到 `main`） |
| `y8 new NoSuchClassX("a")` | `Error: Class … not found` | 同上（rc=255、`Uncaught Error: Class …`、未被 catch） | **F-39-ii** |
| `y9 NonexistentClassX::staticM()` | `Error: Class … not found` | `Uncaught **Exception**: Class … not found`（rc=255、未被 catch） | **F-39-ii + F-31 叠加**（类名也错，静态调用支仍用 `throwException`） |
| `y6 intdiv(PHP_INT_MIN,-1)` | `ArithmeticError: Division of PHP_INT_MIN by -1 is not an integer` | **`Y6=RET` 静默返回、rc=0** | **F-37 第 2 形坐实**：`@divTrunc` 在 ReleaseFast 下不检查溢出 ⇒ 得到一个错值而不报错 |
| `y1 strlen()`／`y3 intdiv(5)` | 运行时 `ArgumentCountError` | **编译失败**：Zig 自身报 `error: expected 1 argument(s)` / `expected 2 argument(s)` ⇒ 无产物 | **新立 F-41** |

#### 29.10.1 新立 F-41：实参不足的内置调用在**编译期**就被拒（PHP 是运行时 `ArgumentCountError`）

| 证据 | 结论 |
|---|---|
| 失败信息 `expected N argument(s)` **不在本仓库任何 `.zig` 源里**（grep `argument(s)` 于 `src/` ⇒ 0 命中） | ⇒ 它是 **Zig 编译器**对生成码的报错，即发射出的 `runtime.php_strlen()` 调用**实参数与签名不符** |
| `strlen`(`:4084`)、`intdiv`(`:4311`) 走**直调快路径**（按位置发射实参）；`json_decode`(`:4042`) 走**动态分发**（`wrapBuiltin_*` 收 `args: []const Value`） | ⇒ 同一「实参不足」在不同发射形态下长出**两种**结局：直调＝编译不过；动态＝运行时裸外逸（F-39-i） |
| `fn bi()`（`native_linker` 内）实测是**恒等函数**（`return info`） | ⇒ 我之前把 `bi(...)` 当成「包一层可变参」的推测**是错的**，两形态的差别在别处（快路径 vs 动态表），不可再据 `bi` 判断 |
| 语料面 | 按规则 41 = 0（pass/ 内所有内置调用实参正确 ⇒ 否则早就是编译失败） | 

#### 29.10.2 新立 F-40（**取证件缺陷**，已修，读数未受影响）：五枚门的 rc 判据此前从未生效

| 项 | 内容 |
|---|---|
| 缺陷 | 门 **T / V / W / X / Y** 的判定段此前写成 `ao=$(timeout 10 "$bin" 2>&1 \| norm); arc=$?` ⇒ `arc` 取的是**管道末端 `norm` 的返回值（恒 0）**，而非可执行文件的退出码；同时 PHP 侧 rc 靠**再跑一次**取（正确但浪费一发） |
| 修法 | 统一改成门 R 已有的正确写法：`timeout 10 "$bin" >"$T/${s}.aot.out" 2>&1; arc=$?` + `ao=$(norm <…)`，PHP 侧同形合并成单次运行；五份脚本 `bash -n` 全过 |
| ★修复后复跑读数 | T `22 形 same=16 diff=5 compile_fail=1`、V `29 same=19 diff=10`、W `20 same=7 diff=13`、X `9 same=8 diff=1`、Y `12 same=3 diff=7 zig_escape=2 cf=2` ⇒ **与修复前逐枚同值** ⇒ 既往判读（含「零新红」结论）**未被该缺陷扭曲**，无需重登记红集；但今后 rc 才是真判据（本轮门 Y 的三个子面正是靠真 rc 才分得开） |
| 推广口径 | 「管道末端 `$?`」是 shell 侧的系统性坑：任何 `x=$(cmd \| filter); rc=$?` 都拿不到 `cmd` 的退出码 ⇒ 新脚本一律「先重定向到文件取 rc，再过滤文件」 |

### 29.11 资产登记表（R-154 / R-155 两批的门与脚本终稿）

| 资产 | 用途 | md5（终稿） | 现行判读 |
|---|---|---|---|
| `c021_closure_obj_face_tmp.sh` | 门 V（29 形，闭包=对象面） | **`9d3ff5efa345a8008bc5da7f729e21d4`** | `same=19 diff=10`，残红 `v13 v14 v16 v17 v18 v19 v20 v21 v22 v26` |
| `c022_internal_throwable_tmp.sh` | 门 W（20 形，内建可抛出层级/接口表） | **`d7c2fa82cefa989bacf1aa3bc559eda3`** | `same=7 diff=13`，红分组见 §29.2；w13/w14 为 F-30 方法继承金丝雀 |
| `c023_count_countable_tmp.sh` | 门 X（9 形，count/Countable） | **`c6769b77cc7b53bcc908e1d6857dfce6`**（中途值 `173d8567…`/`c751a307…`/`b7d90ff3…` 作废） | `same=8 diff=1`，注册红 = **`x4`（按 §28.7.2 设计留红）** |
| `c024_zig_error_escape_tmp.sh` | 门 Y（12 形，F-39/F-41） | **`fe5b75869e80c5bafe045c3ec8f47293`**（中途值 `ad7764b5…`/`736599f5…` 作废） | `same=3 diff=7 zig_escape=2 compile_fail=2` |
| `c021_r154_acceptance_chain_tmp.sh` / `c023_r155_acceptance_chain_tmp.sh` | 两批验收链（15 腿 / 17 腿） | `2911fb3f42ae2dc09a17932e2997d17f` ／ `35f5eb70729f9c15586030834e75eca8` | R-154 `3106s`、R-155 `3069s`，末腿均 `*_DONE` + 报表 mtime 双判 |
| `c010_shadow_col_extract_tmp.sh` | 影子 new-side 整列抽取 + 跨代差值（内置 68 行硬断言） | `4fdcf6995336c416e42e71558b989bfd` | r154/r155 两列 `changed_rows=0`、整列 md5 `f19fb070…` 与 r148b~r151b 六列同值 |
| 门 T（**代次更新**） | `c019_fq_typepos_gate_tmp.sh` | **`c4e94c68c52ed6005e6330c8473f7600`**（旧登记值 `a40c45b6…`/`056badda…` 作废；★门内**不再自指 md5**——改一行注释就失效，统一由本表登记） | `22 形 same=16 diff=5 compile_fail=1`，注册红 `t2 t9 t11 t12 t13` + 失败 `t17` |
| 运行期模板 | `src/aot/runtime_lib_template.zig` | **`c0e722b18d25821323b0ed1b183c7f5d`**（R-154 的 `980a3a8d…`、R-151b 的 `13203065…` 作废） | 二进制仍 `f1ff7a0d…`（两批都是纯模板 ⇒ 不重建、`main.zig` 中性） |

## 30. R-156（2026-10-13）：F-22 落地 ⇒ 回收门 P 注册红 `f26`；顺带钉出**既存编译器 panic**（F-42）与两条说法更正

### 30.1 F-22 落地形态（三处，按 §21.5.1 预置方案，实测回收）

| # | 位点 | 内容 |
|---|---|---|
| 1 | 模板 `php_restoreException(saved: Value) !void`（紧接 `clearException` 之后） | 三分支：`saved` 为 null ⇒ 无操作（此时调用后检查为假、寄存器不被清理，故它不持引用）；已有 pending ⇒ **不碰引用**（体内新抛优先，寄存器那份交给发射器的清理路径 release）；否则 ⇒ `retain()` 一份交全局再 `setException`（此后调用后检查为真，发射器清掉寄存器那份）⇒ **两侧各一份，不泄漏也不双释放** |
| 2 | `ir_generator` `generateTryStmt` 的 finally 段（原 `:3551-3561`） | 入口 `saved = peek_exception`（自带 retain）+ `clear_exception`；块尾（仅 `!isBlockTerminated()` 时）发一次 `.call php_restoreException(saved)`，`.return_type = .void` |
| 3 | `native_linker` `builtin_map`（`:4397` 附近） | **刻意不登记条目**：登记＝把名字发射进 `aot_registered_functions`（`function_exists` 的数据源）⇒ 每个 `main.zig` 都漂移、还凭空多一个 PHP 可见函数名；未登记的 `php_*` 名默认即所需语义（`functionMayRaise` 默认 `true` ⇒ 调用后走异常路由；`functionNeedsAllocator` 默认 `false`） |

关键取舍（都是实测，不是推测）：`setException` 收走所有权但不 retain（`current_exception = ex`）；`peekException` 命中时 retain；发射器在 `may_raise` 调用后生成「`hasException()` ⇒ 清理并 `reg.release()`」块 ⇒ 若 helper 自己再 release 就是**双释放**，若不放回就是**泄漏**。三分支逐一配平见上表。
`finally_dup_*`（`redirectThroughFinally`）**不加**同一段：入口时异常尚未置（`.throw` 终结符在复制体之后才发），无 pending 可摘。

### 30.2 新立 F-42：`try/finally` 两种形态令**编译器 panic**（合法 PHP 完全无法编译）——已证**非 R-156 引入**

| 形 | 构造 | PHP | AOT |
|---|---|---|---|
| `f34` | finally 体内 `throw`（新异常替换 pending） | `Uncaught LogicException: second`（`Next …` 链）+ rc=255 | **panic: `index out of bounds: index 2, len 2`** @`native_linker:18024` ⇒ 无产物 |
| `f35` | `try { … return } finally { 两条 echo }` | `try` → `FIN A` → `FIN B` → 返回 `ret` | 同样 panic ⇒ 无产物 |
| 对照 | —— | —— | ★把 `ir_generator.zig` **回退到 HEAD 重建**后两形**仍然同样 panic**（q3 嵌套 finally 双臂正常）⇒ 既存缺陷，不是本批引入 |

根（读码所得，未修）：`generateControlFlowStateMachine` 预计算 catch 块用表时用 `blk.exception_handler` 记录的 `handler.index` 去索引 `func.blocks.items`，该 index 在两形下越界（len=2 而 index=2）。⇒ 登记为门 P 常驻 `compile_fail` 臂 `f34/f35`（新门 P 定档 `78 形 same=72 diff=4 compile_fail=2`），修复属发射侧块索引记账问题，与 F-29/F-25 一样落在「块/索引生命周期」这一族。

### 30.3 ★更正两条本轮说法（规则 34：更正与主张同等取证）

| 原说法（§28.10.2 / §29.3 / R-155 变更文档） | 实测否证 | 改判 |
|---|---|---|
| 「F-36 = **Error 根与 Exception 根不等价**（`new Error()->getFile()` 空）」 | `/tmp/f22p`+`/tmp/f36/p.php`：`new Exception("ax")` 与 `new Error("bo")` **两侧都**空（`file=[]`、`line=0`），而 `throw` 过的两支都有值 | 与 Error 支无关。真机制＝**`file`/`line` 是在 `setException` 里惰性注入**（见其 `getProperty("file")` 判空后补 `src_file`），故「构造但从未抛出」的异常对象取不到位置。F-36 改述为「未抛出异常对象 file/line 为空」，且**从 F-30「搬根」清单里移除「属性初始化」一项**（搬根仍需的只有：方法集按 `method_order` 复制 + `interfaces` 表） |
| 「给 `php_restoreException` 登记 `builtin_map` 条目（may_raise=true）」 | 登记会把名字写进 `aot_registered_functions`；实测 `function_exists("php_bool_or")` **AOT=true / PHP=false**（⇒ 新立 **F-43**：既有 helper 登记泄漏成 PHP 可见函数名，非本批引入） | 不登记，改走默认路径（见 §30.1 第 3 行）；F-43 与 F-4 同族（键空间卫生），待裁决 |

### 30.4 R-156 验收链读数（17 腿，`c023_r156_acceptance_chain_tmp.log`，08:05:16→08:57:28，**3132s**）

★本代次**动了 `ir_generator` ⇒ 二进制换为 `4e048f47861cc841856a0c1dabacba62`**（R-144~R-155 的 `f1ff7a0d…` 作废）⇒ 所有门腿都必须按新代次复跑，本轮为**全量**而非抽查。

| 腿 | 读数 | 判定 |
|---|---|---|
| 链首 / 链尾二进制 md5 | `4e048f47…` / `4e048f47…` | 同值 ⇒ 链期间无重建 |
| `zig build test` | rc=0 @5s | 口径同 §28.13.2（不覆盖模板；`test-aot` 见 F-38） |
| 门 X | `shapes=9 same=8 diff=1 compile_fail=0 bad_probe=0` @42s | 等值（注册红仅 `x4`） |
| 门 V | `shapes=29 same=19 diff=10` @126s | 等值 |
| 门 W | `shapes=20 same=7 diff=13` @78s | 等值 |
| 门 T | `shapes=22 same=16 diff=5 compile_fail=1` @92s | 等值 |
| **门 P** | `shapes=78 same=72 diff=4 compile_fail=2 bad_probe=0` @316s | **本批判据**：`diff` 恰等四枚 `v2 i1 i2 f12` ⇒ **`f26` 已回收**；`cf` 恰等两枚 `f34/f35`（F-42 登记）。与链前无并发单跑（@313s）读数逐枚一致 ⇒ 非并发假象 |
| 门 S | `shapes=47 same=47 diff=0` @193s | 等值 |
| 门 M / N / O | `19 red=0 green=19` ／ `7/7` ／ `6/6` | 等值 |
| 门 D8 | `defect_red=0 guard_same=14` | 等值 |
| 门 Q / R | `same=5 unexpected_fail=0` ／ `same=8 diff=1 terminate_lost=0` | 等值 |
| 门 U | 无 `*_DONE` ⇒ 按列聚合（`75 行 = SAME 51 / COMPILE_FAIL 22 / BAD_PROBE_PHP 2`）@212s | 等值 |
| 普查门 B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` @2s | **`entries` 未变** ⇒ §30.1 第 3 行「刻意不登记 `php_restoreException`」做到零地图漂移（同时避免 F-43 再添一例） |
| 主回归 | 08:40:08 报表 @794s：`Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 全 0 / Skip 1`，明细仅 `f004 … SKIP` | **零回归**；回收判据取门 P 明细（`f26` 消失），不以汇总数代替 |
| 影子 | `C010_SHADOW_DONE total=68 same=0 diff=68 miss=0 invalid=0` @1040s；`SHADOWCOL_DONE gen=r156 rows=68 col_md5=f19fb070ba1b86c34f02b3883de8e4dd`（base r155 同值） | **`changed_rows=0`** ⇒ 新二进制下 `main.zig` 逐字节不变（语料 0 枚 `finally` ⇒ 新增两条指令从未被发射，符合预期且已实测而非推断） |
| 残留 / 语料 | 链内各腿 `repo_build_residue=0`；`.php` 原件零删除；`pass/` 68 | 影子腿期间的 `residue=1` 是其 KEEP_TEMP 在制品（§28.13 注），非泄漏 |

### 30.5 本批纪律

先按 §21.5.1 预置方案落地（不即兴改设计）；panic 用「回退 HEAD 重建」而非推断来定既存性；所有权三分支逐一对照发射器清理路径写注释；回收判据取门 P `## 明细` 里 `f26` 逐枚消失（规则 27），不看汇总 same 数；两处旧说法被实测否证后**当场改文档并撤销被否证的前置项**（规则 34）；`aot_compile_*` 产物随手删、`.php` 原件零删除。

### 30.6 ★F-42 归因到机制（R-156 只读轮完成，未动代码）：`optimizer` 删不可达块不回写 `.index`，且留下悬垂引用

| 环 | 实文证据 | 后果 |
|---|---|---|
| 索引怎么来的 | `ir.zig:392 Function.createBlock` ⇒ `BasicBlock.init(..., @intCast(self.blocks.items.len))`，即 **`.index` = 创建时的数组长度** | 只要块数组从不删元素，`.index` 才等于数组下标 |
| 谁破坏它 | `optimizer.zig:3355-3366`「Remove unreachable blocks」：`_ = func.blocks.orderedRemove(i); block.deinit(); self.allocator.destroy(block);` —— 释放块而**不修任何指向它的引用** | ★**本行旧措辞「既不回写后续块的 `.index`」已被 R-158c 实测否证**：`analysis.zig:273-275 rebuildCFG` 开头就统一重编号 `block.index = i`，且 `removeUnreachableBlocks:3371` 在 `changed` 时必调它 ⇒ `.index` 永远是紧的。真缺陷只剩**悬垂指针**（读已释放块的 `.index` ⇒ 拿到它被释放前的旧号） |
| 谁把 `.index` 当下标用 | `native_linker:18020-18026` `catch_idx = handler.index` ⇒ `func.blocks.items[catch_idx]` | **本次 panic**：`index out of bounds: index 2, len 2`（Debug 版编译器带边界检查才抓得到） |
| 还有哪些消费者 | `:18033` `current_exception_handler = handler.index`；`:18046` 打印；`:17709` `br_t.index < merge_block.index`（**顺序比较**）；`:25172/25173`、`:25237/25238`（`cond_br` 的 then/else 块号 ⇒ 生成 `current_block = N`）；`:25332/25341`（phi incoming 块号） | 越界只是最幸运的一种；★措辞更正（R-158c）：**不是「陈旧下标仍在范围内」**（下标被 `rebuildCFG` 重编过），而是**读已释放块的 `.index`** ⇒ 值是那块生前的旧下标（本例恰为 2），只要它数值上落在界内就是**静默跳错块**；ReleaseFast 下连越界 panic 都没有 |

⇒ 结论：**F-42 不是「给 18020 加个边界检查」能收口的**。★R-158c 更正后的正解只有**一半**：删块前把所有指向它的引用（各块 `exception_handler`、终结符 `then/else/br` 目标、phi `incoming.block`）**改道或证明不存在**。旧「② 删完统一回写 `.index`」**作废** —— `rebuildCFG` 已经在做这件事（`analysis.zig:273-275`），再加一遍是重复实现（违 DRY 与宪法「禁止不考虑后果的实现」）。
⇒ 排期建议：单独一轮（P0 级），因为它是**静默错控制流**的候选上游——本工单里 F-20（handler 倒灌，R-147 已用守卫挡住）与若干「块级路由」症状都可能与同一陈旧索引域相关；该轮先做「谁引用被删块」的穷举 + 一枚**能复现静默跳错块**（不是 panic）的门臂，再动刀。门 P 的 `f34/f35` 是现成的复现件。

#### 30.6.1 两条补强证据（R-156 同轮只读取得）

1. **默认档确实会跑到删块代码**：`removeUnreachableBlocks`（`:3307`）有两个调用者——`eliminateDeadCodeInFunction:2748/2809` 与 `runSCCPInFunction:3440/3653`（后者在 `changed` 时触发）；而 `Optimizer` 配置里 `cfg_cleanup: bool = true`（`:98`，`:161/:189/:217` 三档均 true，只有 `:140` 那一档关）⇒ 不是「只有非常规旗标才碰得到」的路径，默认编译即适用。
2. ★**同一 bug 类别本仓已经踩过一次，并留下可复用的修法**：`optimizer.zig:4144 fixupDanglingPhiReferences`（行号由 R-158c 复测更正，旧写作 `:4143`）的注释原文就是「优化 pass（如 cfg_cleanup、DCE）**可能释放 block 但未更新所有 PHI incoming.block**」，其做法是用 `rebuildCFG` 维护的 `block.predecessors` 重建 incoming。⇒ F-42 的正解不是新造机制，而是**把这个 fixup 的覆盖面从 PHI 扩到 `exception_handler`**（`valid_blocks` 指针→下标映射的骨架已经在那儿）；「补 `.index` 回写」那半已在 `rebuildCFG` 里，不需要重复。这也解释为什么 φ 侧多年不红、而 catch 路由侧偶发跳错。
3. 顺带：这条证据同时是 F-20（R-147 的 `try_body` handler 倒灌守卫）的上游候选——R-147 是在消费端（合并规则）挡，根源在 Produce 端引用失效。⇒ R-158b 落地后应回看 `optimizer:4367-4371` 那枚守卫是否仍必要（能删则删，但删守卫属删代码，需先问）。
4. ~~★**R-158b 的可达性量法已备好（不需新工具）**：`compiler.zig:1040-1048` 在 `options.verbose` 下打印 `Dead blocks removed`…~~ ⇒ **本项口径被 R-158c 实测否证**：统计旗标 `dead_blocks_removed` 全仓**只有 `:3364` 一处递增**（grep 实测：声明 `:235`、打印 `:272`、递增 `:3364`、测试 `:6504/:6518`），而 `cleanupCFGInFunction` 的两枚删块站点（`:4336` trampoline、`:4397` merge）**不计入统计** ⇒ 用「`Dead blocks removed`」量分母只覆盖三枚站点里的那一枚，且恰好**漏掉真正的肇事面孔**。实测读数与替代量法见 §31。

### 30.7 ★按宪法 §五「只报不改」：F-22 这一族在**另外两种模式**上的现状（静态取证，未动代码，等老铁明示）

| 模式 | 证据 | 判读 |
|---|---|---|
| **字节码模式** | `finally_begin = 0xA4` / `finally_end` 只在 `bytecode/instruction.zig`（定义）与 `bytecode/generator.zig:1895-1899`（**发射**）出现；`bytecode/vm.zig` 里 `finally` 出现次数 = **0**，而同一文件的 `try_begin` 有 3 处 ⇒ **执行侧没有任何 finally opcode 的 case** | 发射了却无人执行。⚠️ 不等同于「finally 体完全不跑」：体内指令是作为普通节点被发射的，正常路径的 dispatch 循环大概照样跑；**异常路径**（未捕获/被 catch 后）走 catch 表，不会经过体 ⇒ 具体差哪几格**必须实测**（链后） |
| 树遍历解释器 | `runtime/vm.zig:12326-12333` 顺序 `_ = try self.eval(finally_data.body)`；`exceptions.zig:405` 另有 `finally_executed` 字段 | 写法是「try/catch 求值完成后顺序执行 finally」。若 pending 异常以 Zig error 形式先向上冒（`try` 直接返回错误），则这一行**可能根本到不了** ⇒ finally 是否在该模式里被跳过**未测**，不下结论 |
| 关联既有记录 | 工单 §21.5 与本批都只针对 AOT；`ir_generator`/`native_linker`/`runtime_lib_template` 三处改动**不会**影响上面两个模式 | ⇒ 若要一并修，需老铁明示；建议先各建 1 形实测（`try{throw}finally{echo}` 与 `try{throw}finally{echo A; echo B}`）在两模式下的真值，再决定范围 |

⚠️ 本节全部是**静态**证据（计数 + 行号），没有任何一条是运行时读数 ⇒ 只作为「要不要开这一摊」的依据，不作为缺陷结论。

### 30.8 F-41 归因（R-156 只读轮，未动代码）：直调快路径不看「必填参数数」⇒ 少传实参＝Zig 编译错

| 环 | 实文证据 | 结论 |
|---|---|---|
| 报错来源 | `error: expected 1 argument(s)` 在本仓 `src/` 内 **0 命中**（grep 已证） | ⇒ 它是 **Zig 对生成码**的报错：发射出的 `runtime.php_strlen()` 少一个实参 |
| 发射形态 | `native_linker:22278 try self.writeValueArgs(writer, op.args)` 按调用点实参数**逐位**发射（另有 `:22138/22214/22259` 硬切片 `op.args[0..2]`） | 直调快路径**没有任何 arity 校验** |
| 为什么只有部分内置函数炸 | `strlen`(`:4084`)、`intdiv`(`:4311`) 走直调；`json_decode`(`:4042`) 走动态分发（收 `args: []const Value` ⇒ 运行时 `return error.InvalidArgumentCount` ⇒ F-39-i） | 同一缺陷在两条路径上长出**两种**结局：编译不过 / 运行时裸外逸 |
| 修法骨架**已在仓里** | `ir.zig:226-227` `Method = { param_count, required_params }`、`:1203-1204` `ClosureNewOp = { param_count, required_params }` ⇒ 「必填参数数」这套数据模型已存在并被闭包/方法动态调用使用；解释器侧另有 `src/runtime/fn_table.zig`（`min_args`/`max_args`，含 `get_class` 的 `0..1` 这类可变/可选信息） | ⇒ F-41 不需要新造机制：①给内置函数一份 arity 真值（复用 `fn_table` 或新建 AOT 表，**跨目录导入走 build.zig 模块**）②在 ir_generator 的直调发射前比较实参数，不足则改发**运行时** `ArgumentCountError`（消息要区分 `exactly` / `at least`，门 Y y1/y2 已实测两种措辞） |
| 语料暴露 | 规则 41 = 0（pass/ 内内置调用实参都正确，否则早就是 `compile_fail`） | 修复对基线零风险，属「合法 PHP 编译不过」类，与 F-42 同批优先级候选 |



---

## 31. R-158c（2026-10-14）：F-42 归因**改到行**——旧结论两条被实测否证，正解只剩「改道 `exception_handler`」一半（零 src 改动轮）

### 31.1 六枚 CLI 臂把「肇事 pass」钉死，并顺手暴露一枚脚本缺陷

| 形 | 臂 | rc | 首行读数 |
|---|---|---|---|
| f34 | default | 134 | `thread … panic: index out of bounds: index 2, len 2` |
| f34 | `--aot-disable-pass=dce` | **0** | `Success: Compiled to …` |
| f34 | `--aot-disable-pass=cfg-cleanup` | **0** | 同上 |
| f34 | 两旗标同关 | **0** | 同上 |
| f35 | default | 134 | `index out of bounds: index 2, len 2` |
| f35 | `--aot-disable-pass=dce` | 134 | **仍 panic** ⇒ 肇事不在 DCE |
| f35 | `--aot-disable-pass=cfg-cleanup` | **0** | ⇒ **f35 的肇事面唯一 = cfg_cleanup** |
| f35 | 两旗标同关 | **0** | 同上 |
| f34/f35 | `--verify-ir --no-opt-fallback` | 1 | `error: IR optimization failed: InvalidIR` |
| f34/f35 | `--verify-ir`（带兜底） | 1 | `IR optimization failed (fallback also failed): InvalidIR` |

★**脚本缺陷自纠（新 trap 入记忆）**：第一轮把两枚旗标塞进同一个变量 `extra="--aot-disable-pass=dce --aot-disable-pass=cfg-cleanup"` 再 `… $extra …`，被当成**一枚**旗标值 ⇒ 读数 `Error: Unknown AOT pass 'dce --aot-disable-pass=cfg-cleanup'`、`rc=0`，`none`/`verify` 两臂首跑全废。⇒ 多旗标臂必须 `set --` 或数组展开，且 `rc=0 + 首行是 Error` 这种组合要一眼识破（本表为重跑后的真实读数）。
★`--verify-ir` 是**常驻可用探针**（`optimizer.zig:776 verifyFunction` 逐块查 `exception_handler:785`/`predecessors:789`/`successors:793`/`终结符目标:801-813` 是否仍在块集内），`--no-opt-fallback`（`main.zig:303`）关掉 `compiler.zig:1013-1038` 的保守退路，否则 `InvalidIR` 会被兜底掩盖成 warning。⇒ 建**永久门 Z**（§31.5）。

### 31.2 ★否证一：`.index` **从不陈旧**——`rebuildCFG` 开头就统一重编号

`analysis.zig:270-275`：
```zig
pub fn rebuildCFG(func: *Function) !void {
    // Reassign indices to ensure they are compact and match array order
    for (func.blocks.items, 0..) |block, i| {
        block.index = @intCast(i);
    }
```
而三枚删块站点**全部**随后调用它：`removeUnreachableBlocks:3371-3373`（`changed` 必真，因 `:3365`）、`cleanupCFGInFunction:4251`（trampoline 逐次）、`:4265`（merge 逐次）。
⇒ §30.6 的「既不回写后续块 `.index`」与「修法要两半同动（② 统一回写 `.index`）」**作废**；再写一遍 `b.index = k` 属重复实现（违 DRY 与宪法 §四.3）。真缺陷只剩**悬垂指针**：读已释放块的 `.index` 拿到的是它**生前的旧号**（本例 2），不是任何"漂移"。

### 31.3 机制定案：`try{…}finally{…}`（无 catch 子句）的空 catch 块被 trampoline pass 释放

| 环 | 实文 | 后果 |
|---|---|---|
| 谁建 handler | `ir_generator.zig:3327-3349`：`catch_block = createBlock("catch")`，随后 `try_block.exception_handler = catch_block` | handler 边存在 |
| try_body 正常路径**不**经 catch | `:3359-3364`：`.br = finally_block`（有 finally）或 `exit_block` | ⇒ `catch_block.predecessors` 只由 **handler 边**贡献（`analysis.zig:314-320`），只有 `try_block` 一枚 |
| 无 catch 子句 ⇒ catch 块是**空块 + 一跳** | `:3544-3548`：`setCurrentBlock(catch_block); if (!terminated) setTerminator(.br = target_after_catch)`，`target_after_catch = finally_block orelse exit_block`（`:3370`） | 命中 trampoline 三前置：`:4319` 指令数为 0、`:4320` 自身无 handler、`:4323` 终结符是 `.br` |
| 删除时只改道**终结符** | `:4328-4332` 对 `block.predecessors` 逐个 `replaceBlockInTerminator(pt, block, target)`；而 `try_block` 的终结符根本不引用 catch_block ⇒ **零改道**；随后 `:4336 orderedRemove` + `:4337 deinit` + `:4338 destroy` | **`try_block.exception_handler` 悬垂** |
| 消费端读到什么 | `native_linker.zig:18018-18026`：`catch_idx = handler.index`（`:18020`，读已释放内存，ReleaseSafe 不报）⇒ `:18024 func.blocks.items[catch_idx]` **这枚数组下标才是 panic 行**（旧 §30.6 记成 `:18020` 不精确）；`:18033` 又把 `handler.index` 当路由号发成 `current_block = N` | 越界＝幸运面（本仓 `build.zig:10` 把默认 `zig build` 的 exe 映射成 **ReleaseSafe** ⇒ 有边界检查，所以 f34/f35 表现为 `compile_fail`）；**ReleaseFast 下无任何报警** |

★**比 panic 更重的面孔（新立，决定定级）**：`catch_idx` 若数值落在界内，`:18024 collectBlockUsedRegs(func.blocks.items[catch_idx], …)` 会从**另一个块**收集「catch 臂仍要用的寄存器集」，`:18035-18036` 把它装进 `self.current_catch_used_regs` ⇒ 发射的异常清理路径会 **release 掉 catch/finally 臂仍在用的寄存器** ⇒ **生成程序运行期 use-after-free**，编译器侧零报警、主回归侧也可能只是偶发错值。⇒ **F-42 的定级应按这条静默面，不按 panic 面**（panic 只是当前档位恰好把它变成了 `compile_fail`）。

★**面比「try/finally」更宽（R-158c 实文核）**：`ir_generator.zig:535-539 createBlock` 给**处于 try 上下文里的每一枚新建块**都继承 `context.catch_block` 作 handler ⇒ 一个空快转块只要落在 try 作用域内（`finally_block`、`catch_dispatch`、各类 merge/if 汇合块都算），它就可能同时是若干块的 handler。⇒ 修法的改道必须**扫全函数块表**（本 helper 正是这么做），不能只处理 `block.predecessors`（trampoline 旧写法只在这里改终结符，这正是漏 handler 的原因）。



### 31.4 三枚删块站点逐一判定 ⇒ 只补 Face A（其余两面**不**加防御，改由门 Z 常驻兜住）

| 面 | 站点 | 是否可留悬垂 handler | 判据 |
|---|---|---|---|
| **A trampoline** | `:4336`（`tryRemoveTrampolineBlock`） | ★**可以，且 f34/f35 实测即此面** | 它**不检查**自己是否正被别的块当 handler；`:4320` 只保证它**自身**没有 handler |
| **B merge** | `:4397`（`tryMergeBlockWithSingleSuccessor` 释放 `succ`） | **机械不可达**（推导） | 若 `L.handler == succ`，handler 边使 `L ∈ succ.predecessors`；`addPredecessor`（`ir.zig:536-538`）**不去重** ⇒ `L == block` 时还有终结符边、`len ≥ 2`；`L ≠ block` 时 `len ≥ 2` 亦成立；而 `:4349` 硬要求 `succ.predecessors == {block}` ⇒ 拒。且 `cleanupCFG` 在进 merge 循环前 `:4258`、每次合并后 `:4265` 都 `rebuildCFG` ⇒ 前驱表必新鲜 |
| **C unreachable** | `:3361` | **按定义安全** | `markReachableBlocks:3383-3386` 沿 handler 边标可达 ⇒ 活块的 handler 必在 reachable 集内，不可能被删 |

⇒ 按宪法「禁止为不可能发生的场景加防御」，B/C **不写**改道代码；正确性由门 Z 的 `--verify-ir` 常驻实测兜住（若推导有错，校验器必红，届时再补）。

### 31.5 分母：统计旗标读数 vs 校验器读数

| 量法 | 读数 | 有效性 |
|---|---|---|
| `--compile --no-debug-info --verbose` 抓 `Dead blocks removed`（全 68 逐形，产物 `aot_compile_*` 逐枚删） | **`scripts_total=68 删块脚本数=4`**：`f009_oop_decorator_chain_command=1`／`f037_adapter_unified_cache=1`／`f048_match_pattern_dispatch=2`／`f177_graph_traversal_dfs_bfs=1` | ★**只是下界且是错的面孔**：旗标 `dead_blocks_removed` 全仓仅 `optimizer.zig:3364` 一处递增（声明 `:235`、打印 `:272/:1045`、递增 `:3364`、测试 `:6504/:6518`），**恰好只统计 Face C**，而肇事面是 Face A ⇒ §30.6.1 第 4 项的口径作废 |
| **门 Z**＝`fuzzy_scripts_720/tmp/c026_dangling_ref_census_tmp.sh`（`--verify-ir --no-opt-fallback`，全 68 逐形单文件编译，桶 `DANGLING_REF/OK/OTHER_rc`） | 读数 **（待填：本轮跑动中，表身 61/68 已全 `OK`）** | ★这才是 F-42 的**有效分母**，且覆盖 A/B/C 三面的所有引用类型。**探针覆盖面已核**：`verifyModule` 在 pass 主循环里**每枚 pass 之后都调**，其中 cfg_cleanup 处有两枚 ⇒ `optimizer.zig:600-605`（模块级 `runCFGCleanup` 后）与 `:736-741`（超大函数的逐函数快路 `cleanupCFGInFunction` 后）⇒ Face A 的释放动作**一定被校验器看过**，不是「碰巧没跑到」 |
| 规则 41 口径（语料暴露） | 语料 `} finally {` 计数 = **0**（R-156 实测）⇒ Face A 的入口条件（空 catch 块）在语料内**不可达** | ⇒ 修复对基线**零暴露**，属「合法 PHP 编译不过」类；主回归与影子预期逐字节不变（`optimizer` 只改「删块前多改道一次」，语料无该形态 ⇒ 生成码不变）⇒ **影子不得漂移**是本轮硬验收项 |

### 31.6 修法（R-158b 待落地）与成本

| 项 | 内容 |
|---|---|
| 改动 | ① 新增 helper `redirectExceptionHandlerRef(func, removed, replacement)`：遍历 `func.blocks.items`，把 `b.exception_handler == removed` 改成 `replacement`（跳过 `removed` 自身）。② 在 `tryRemoveTrampolineBlock` 的 `:4336 orderedRemove` **之前**调用它，`replacement = target`（即 `term.br`） |
| 为何改道到 `target` 是**等价**而非近似 | 被改道的块**指令数为 0**（`:4319` 硬前置）且**自身无 handler**（`:4320`），只剩一条无条件 `.br` ⇒ 「进入它再落出去」与「直接进入 target」在块级路由模型里逐位相同；发射侧 `.try_begin/.try_end` 只输出注释不改状态（`:4361` 注释已记），空块里连这两枚都没有 ⇒ 无副作用 |
| 不选「拒绝合并」的理由 | 拒绝＝留块＝**编译器优化损失**（宪法 §六.7 要先问），而改道零性能损失且语义等价 ⇒ 本批无需裁决 |
| 验收（顺序即判据） | ① 门 P `f34/f35` 由 `compile_fail` 变**可比对** ⇒ 若输出与 PHP 真值不一致则**新立红**（`cf` 桶掉数不等于成功，须按规则 27 看明细行存在性并重定档）② 门 Z 全 68 仍 `dangling=0`（且新增 f34/f35 两形的探针臂必须绿）③ 主回归 `Pass 67 / Skip 1` 保持 ④ 影子 `changed_rows=0`（语料无 Face A 形态 ⇒ 生成码应逐字节不变）⑤ 门 B `entries=497` 不变 |
| 成本 | 改 `optimizer.zig` ⇒ **必须重建**二进制（上轮 `zig build` 68 s）+ 全链 17 腿 ≈ 3100 s；helper ≈10 行、调用 1 行 |

### 31.7 本轮新增/更正的记忆级教训（已同步 `feedback-aot-regression-rules`）

1. **「有统计旗标」≠「覆盖该机制」**：`Dead blocks removed` 只由三枚站点中的一枚递增 ⇒ 拿它当分母会把结论指向错误的 pass。任何「用计数器量可达性」的口径，落地前必须先 grep **该计数器的全部递增点**与被量机制的全部站点，逐一对照（规则 44 的加强版）。
2. **多旗标臂禁用单个变量塞两枚参数**（`$extra` 未数组化 ⇒ `Unknown AOT pass '… …'` 且 `rc=0`）。
3. **panic 面 ≠ 缺陷的全部面**：同一悬垂指针在 ReleaseSafe 是越界、在 ReleaseFast 是静默错值/错清理 ⇒ 定级要看最坏面，不能看当前档位恰好暴露的那面。

### 31.8 门 Z 建成读数（修前登记 → 落地重定档）

| 资产 | 形态 | 修前（bin `4e048f47861cc841856a0c1dabacba62`） | 修后（bin `b71f9f41f182161df7ebab04a0b64879`） |
|---|---|---|---|
| **门 Z 面孔门** `c026_dangling_ref_face_tmp.sh`（修前定档 md5 `1be8b8eb6ccd22dc0cfde2ed49493f4d`） | 8 形登记；落地轮补 z9/z10 ⇒ 10 形 | `shapes=8 same=2 diff=0 dangling=6 compile_fail=0 bad_probe=0`；dangling = z1 z2 z3 z4 z7 z8，**其中 5 枚 PANIC + z4 SILENT**；恒绿守卫 z5 z6 | `shapes=10 same=9 diff=1 dangling=0 compile_fail=0 bad_probe=0`（唯一残红 = **z2**，新立 **F-44**，§31.9） |
| **门 Z 全语料普查** `c026_dangling_ref_census_tmp.sh`（md5 `b5e5b1b889f100220d5fdbaa2d4cafe9`） | 68 语料 | `Z_DONE total=68 dangling=0 ok=68 other=0` | 链内复测 |

★**z4 才是本族最重的取证**：`try{echo "Z4 try"}finally{echo "Z4 FIN"}; echo tail` —— **全程零异常**，`--verify-ir` 报 `InvalidIR`，而不开校验器时 `rc=0`、产物存在、**输出与 PHP 逐字节相等**。⇒ 「编译过 + 跑对」对这类缺陷**完全失明**：门 P/T/V/W/X/Y 的输出面判据结构性抓不到它，只有 IR 校验器抓得到 ⇒ **门 Z 的判据必须是 `dangling` 桶，禁改成 `diff`**（规则 41 的又一种形态：fail-open 面在*通过*的语料里暴露恒 0，且这里连"探针跑对"都不能证合法）。
★z5/z6 为守卫臂：同层有 `catch` ⇒ `catch` 块是**非空派发块**（peek+instanceof+cond_br）⇒ 不满足快转块前置 ⇒ Face A 不触发 ⇒ 两臂修前后都 SAME ⇒ 证明本批改动的作用域恰为「无 catch 子句的 try」。
★z9/z10（落地轮补）验改道的**嵌套面**：z9 = 内层 `try/finally`（无 catch，内层 catch 是快转块）嵌在外层 `try/catch` 里，判据「外层臂必须仍能接住」⇒ 实测 `Z9 OUTER CAUGHT z9` 出现且 SAME ⇒ **否证**我落地前的担心「改道后置 `null` 会让异常逃到函数外、丢掉外层 catch」；z10 = 派发块与快转块同函数共存 ⇒ SAME。

### 31.9 ★F-44 新立（R-158b 落地轮实测，**属暴露非引入**）：`finally` 体内 `throw` 令 finally 体被**重发第二份**

门 Z 修后唯一残红 z2（＝门 P 的 `f34`）：两边都 `rc=255`，但 AOT 多打一行 `F34 FIN`，且 fatal 文本只有 `Uncaught LogicException: second`，PHP 给 `Uncaught RuntimeException: first` + `Next LogicException: second`。

| 环 | 实文/取证 | 结论 |
|---|---|---|
| 第一次归因**被自证否证** | 我先猜「改道后的 handler 路由回 finally」，又猜「自环 handler」；用 `ZIGPHP_AOT_KEEP_TEMP=1` 取 z2 的 `main.zig` 实文：函数只剩 2 块（`0 => entry (handler: 1)`、`1 => finally_2`），而块 1 内 **`php_echo(reg_3)` 与 `new LogicException` 各自顺序出现两次、中间无任何分支** | ⇒ 重复不是路由，是 **IR 里真的有两份 finally 体** |
| 根 | `ir_generator.zig:3735-3764 redirectThroughFinally`：为 throw/return 复制一份 `finally_dup_N` 块；其豁免条件写作 `:3744 if (is_throw and self.try_stack.items.len > 0) return false;` | 而 `throw` 位于 **finally 体自身**时，`generateTryStmt` 已在 `:3367` 弹掉 `try_stack`、`finally_stack` 到 `:3582` 才弹 ⇒ `is_throw ∧ try_stack 空` ⇒ **复制支被点亮** ⇒ 体被重发 |
| 既存性 | **A/B 实测（本轮补）**：`--aot-disable-pass=cfg-cleanup`（完全不做快转块删除，与 F-42 改动正交）重编 z2 ⇒ `KEEP_TEMP` 里 `main.zig` 有 **5 枚发射块**，其中 `4 => { // finally_dup_4_4` 独立成块、体内再次完整生成 `php_echo(reg_3)`；跑该产物照样**双打 "F34 FIN"** | ⇒ 双打**不依赖 cfg_cleanup、不依赖本批改道**，纯 `ir_generator` 侧既存缺陷；本批只是把 panic 移开、让它第一次显形（**属暴露非引入**，与 F-22 同判据） |
| 语料暴露 | `} finally {` 在 pass/ 内计数 = **0**（R-156 实测）⇒ 基线零保护 | 修复需动 `ir_generator` 的 finally 复制支 ⇒ 覆盖面含 `return in finally`（门 Z z7 现 SAME）⇒ **不得与本批顺手改**（规则 31：一臂一缺陷；F-42 与 F-44 不同层不同文件） |
| 定级建议 | P1（合法 PHP 能编译、能跑，但输出重发 + 异常链丢失；非崩、非内存不安全） | 修法候选：甲 在 `Self` 加「正在生成 finally 体」标志并在 `:3744` 短路／乙 弹栈顺序改成「先弹 finally_stack 再生成 throw 目标」——两者都要先给 z7/z3 建守卫臂再动 |

★**自纠一条本批推断**：`redirectExceptionHandlerRef` 里的「目标 == 自身 ⇒ 置 `null`」守卫**不是** z2 双打的原因（去掉它读数逐枚不变）。保留它的理由换成不变量本身：`rebuildCFG` 建 handler 边时硬写 `handler != block`（`analysis.zig:316`）⇒ 自环 handler 是本套 IR **自己声明不接受**的形态，而它是本改道唯一可能的来源，故不得造出。当前**无任何门臂能区分「带此守卫 / 不带此守卫」**（效果实测为零）⇒ 如实登记，不冒充成修复。
★**再自纠一条（同一轮内）**：我先把双打归因给「`exit_block` 也继承了本层 catch」——**已否证**：`generateTryStmt:3327-3333` 的 `try_block/catch_block/finally_block/exit_block` 四枚块全部建在 `try_stack.append`（`:3336`）**之前** ⇒ 它们继承的是**外层** try 的 catch（顶层则无 handler），只有 `:3349` 显式给 `try_block` 挂了本层 catch。双打的真来源就是上表的 `redirectThroughFinally` 复制支（`finally_dup_N` 整份体被再生成一次，再被 cfg_cleanup 并进同一发射块 ⇒ KEEP_TEMP 里看不到独立 dup 标签，只看到两份体顺序排列）。

### 31.10 optimizer.zig 锚点漂移表（R-158b 落地后；本工单 §31.1–§31.4 引用的均为**修前代次**行号）

| 符号 | 修前 | 修后 | 漂移 |
|---|---|---|---|
| `removeUnreachableBlocks` / 其 `orderedRemove` | `:3307` / `:3361` | 同 | 0（插入点在其后） |
| `fixupDanglingPhiReferences` | `:4144` | 同 | 0 |
| `cleanupCFGInFunction` | `:4236` | 同 | 0 |
| `tryRemoveTrampolineBlock` | `:4318` | 同 | 0 |
| ├ 其 `orderedRemove`（Face A 释放点） | `:4336` | **`:4342`** | +6 |
| ★新增 `redirectExceptionHandlerRef` | — | **`:4354`** | 新 |
| `tryMergeBlockWithSingleSuccessor` | `:4342` | **`:4371`** | +29 |
| ├ `succ.predecessors` 单前驱门 | `:4349` | **`:4378`** | +29 |
| ├ 「禁止合并 handler 不同块」守卫 | `:4354` | **`:4383`** | +29 |
| ├ R-147「handler 倒灌」守卫 | `:4367-4371` | **`:4396-4400`** | +29 |
| ├ successor handler 继承 | `:4385-4386` | **`:4414-4415`** | +29 |
| └ 其 `orderedRemove(idx)`（Face B 释放点） | `:4397` | **`:4426`** | +29 |

⇒ `:4354` 之后一律 **+29**；本工单其他章节（§30.6.1、§20.x 等）若引用 `optimizer.zig` 的 `:4340` 以后行号，须按此表换算。

### 31.11 资产登记表（R-158c / R-158b 两批终稿；★md5 全部在门头注释冻结后取，且正是本链各腿所跑的那份字节）

| 资产 | 用途 | md5（终稿） | 现行判读 |
|---|---|---|---|
| `c026_dangling_ref_face_tmp.sh` | **门 Z 面孔门**（10 形，悬垂 handler / 快转块族） | **`3bc9f759f52a2161f7a0021afcc525b0`**（修前登记版 `1be8b8eb6ccd22dc0cfde2ed49493f4d` 作废为「修前 8 形」快照） | 修前（8 形）`same=2 dangling=6`（5 PANIC + **z4 SILENT**）；修后（10 形）`same=9 diff=1(z2=F-44) dangling=0` ⇒ **判据取 `dangling` 桶，禁取 `diff`** |
| `c026_dangling_ref_census_tmp.sh` | **门 Z 全语料普查**（68 语料 × `--verify-ir --no-opt-fallback`） | **`b5e5b1b889f100220d5fdbaa2d4cafe9`** | `Z_DONE total=68 dangling=0 ok=68 other=0`（修前测得；链内 ZCENSUS 腿复测须同值） |
| `c012_reflection_gate_tmp.sh` | 门 P（78 形，内省族） | **`0d31ebf943c78b8426666a10acf28538`**（R-156 版 `e173c487079ef62e454293e8965a6570` 作废） | **改档**：`same=73 diff=5 compile_fail=0`，注册红 `v2 i1 i2 f12 f34`（★`f35` 转绿、`f34` 由 cf 转语义红 = F-44） |
| `c027_r158b_acceptance_chain_tmp.sh` | R-158b 验收链（**19 腿**，新增 ZFACES/ZCENSUS 两腿） | `40deafd3263fe04ea12f5611334fc787` | 读数见 §31.12 |
| 运行期模板 | `src/aot/runtime_lib_template.zig` | **`998aa7f6cb73d07050b5e7063eec0fe5`**（R-155 值 `c0e722b1…` 作废） | 本批**未动**模板 |
| IR 生成 / 发射 | `ir_generator.zig` / `native_linker.zig` | `f3f11deff95fce0adfd0758aab32fac3` / `31f9433d7e6fd3b130cca60f0d8fc80a` | 本批**未动**（F-44 待裁决 ⇒ 留待下一批） |
| ★优化器 | `src/aot/optimizer.zig` | **`e720145e5da407335bc301fbdfb0c909`**（R-147 值 `6cffa137…` 作废） | `+29/−0`：新增 `redirectExceptionHandlerRef` + trampoline 站点一行调用 |
| 二进制 | `zig-out/bin/php-interpreter` | **`b71f9f41f182161df7ebab04a0b64879`**（R-156 值 `4e048f47…` 作废） | ★本批改 `optimizer` ⇒ **必须重建**；中间代 `e5a6522d…`（无自环守卫）/`df1feb36…`（守卫但注释未更正）均作废 |
| 影子基线列 | `c010_shadow_newside_r156_tmp.txt`（表身 md5 `f19fb070ba1b86c34f02b3883de8e4dd`） | — | R-158b 列须与之 `changed_rows=0`（语料无 Face A 形态） |
