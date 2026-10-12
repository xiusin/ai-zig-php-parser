# AOT-CODEGEN-012 · PHP 类名不区分大小写查找缺失：运行期类表精确匹配 ⇒ 跨大小写类使用全灭（new / instanceof / 静态调用 / class_exists / ::常量）；`extends` 与 `::class`/`get_class` 拼写保真已绿

**问题 ID**: AOT-CODEGEN-012
**优先级**: **P1**（合法 PHP 跨大小写类使用即命中；同族缺陷 = AOT-CODEGEN-010 §8 #6 函数名 CI，R-124/R-127 已修）
**性质**: 运行期类表查名（`runtime_lib_template.zig findClass` 精确匹配 + `php_instanceof` 直接名比较）⇒ **仅 AOT**（解释器/字节码的类表为独立实现，本单不涉）
**状态**: **R-1/R-2/R-3/R-131/R-132/R-136/R-137a/R-138 已落地并验收**（R-138 = 内省枚举族八项落地 + 永久侧门 P 建成，2026-10-12，详见 §12）。⚠️ **§10 的 R-137b/R-137c 记录为假阳性**（抛出支从未入库，已由 R-138 重落，更正见 §10 内联与 §12.0）。门 P 终态 **35 形 `same=31 diff=4`**（4 枚为注册红 `n15/r10/i1/i2`，属 F-1/F-2/F-3 三族新立面孔）；门 M 19 形 `red=0 green=19`、门 D8 14/14、门 N 7/7、门 O 6/6；`zig build test` 21/21 & 326/326；主回归 **Pass 67 / Skip 1**；影子 `diff=68` 已定性为发射面预期漂移（§12.6）。二进制 `b356e19e769af014c8cddc9fce9b54c9`。**待裁决**：F-1~F-6（§12.5）；门 M 终态 **17 形 `red=0 green=17`**（链 XI 同口径全绿：影子 68/68、主回归 Pass 67/Skip 1、门 D8/H/H2/I/E/F/G 注册值保持，2026-10-11 07:05:35 报表）：门 M `red=5→0 green=3→8 compile_fail=0 bad_probe=0 residue=0`（链 VIII 同口径全绿：影子 68/68 零漂移、主回归 Pass 67/Skip 1、门 D8/H/H2/I/E/F/G 与 R-127 代注册值一致；二进制随链 VIII 代 `5c436e9e…` 后续树，runtime 模板不改变解释器二进制 md5）；落地含两处自纠（php_instanceof 重写误删 Throwable 块 ⇒ 补回；伪接口比较 eqlIgnoreCase ⇒ `instanceof stringable` 双拼写 ✅）；变更文档 `docs/changes/2026-10-11/AOT-CODEGEN-012_类名族CI_R128_2026-10-11_fbe6382a.md`
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
**✅ R-138 已收口（2026-10-12）**：另立**永久侧门 P**（`fuzzy_scripts_720/tmp/c012_reflection_gate_tmp.sh`，35 形，读数 `c012_reflection_tmp.tsv`），详见 §12。

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
