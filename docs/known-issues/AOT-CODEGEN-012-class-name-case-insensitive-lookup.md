# AOT-CODEGEN-012 · PHP 类名不区分大小写查找缺失：运行期类表精确匹配 ⇒ 跨大小写类使用全灭（new / instanceof / 静态调用 / class_exists / ::常量）；`extends` 与 `::class`/`get_class` 拼写保真已绿

**问题 ID**: AOT-CODEGEN-012
**优先级**: **P1**（合法 PHP 跨大小写类使用即命中；同族缺陷 = AOT-CODEGEN-010 §8 #6 函数名 CI，R-124/R-127 已修）
**性质**: 运行期类表查名（`runtime_lib_template.zig findClass` 精确匹配 + `php_instanceof` 直接名比较）⇒ **仅 AOT**（解释器/字节码的类表为独立实现，本单不涉）
**状态**: **R-1/R-2/R-3/R-131/R-132/R-136/R-137a/R-138/R-141/R-142/R-143/R-144/R-145/R-146/R-147/R-148/R-148b/R-149/R-150/R-151/R-151b/R-154/R-155/R-156/R-158b/R-159/R-160/R-161/R-163/R-165/R-166/R-167/R-169/R-170/R-171/R-172 已落地并验收；★R-167（F-56 **改定**＋新立并落地 **F-58**，老铁裁「甲型」＋「位运算族本轮一并修」）主门 MSR 建门即 **74 臂**、修前注册红 **48**（F-56 的 14 ＝面 A 类型旁路 6／面 B 负数静默错值 6／面 C float Deprecated 丢失 2；F-58 的 34 ＝操作数检查旁路 9／string×string 合法逐字节 5／诊断与移位计数 7／语句位 DCE 3／对象 3／一元 `~` 7），落地后 **`same=74 diff=0 aot_caught 0→28`**；★**§39.3/§40.4 的「常量折叠绕过检查」是被实测否证的旧归因**——`foldMod` 只在 `.int ∧ .int` 折，真凶是 `optimizer.zig:5903` 强度削减 `.mod` 臂**只查 rhs 不查 lhs**，把 `% 2^n` 改写成 `& (2^n-1)` ⇒ 发射成裸 Zig 运算、整条 php_mod（含 R-165 的检查＋路由）被绕开；因果对照臂 c1（`$a % $m`，m=2）绿 vs m7（`$a % 2`）红 把肇因锁死，c4（`-3 % 2` 两侧皆字面量）绿 反证折叠无辜；★**面 B「`-3 % 2` AOT=1／PHP=-1」是连异常都没有的纯静默错值**（截断取余 vs 向下取模），故守卫比 `.mul/.div` 多一条 `lhs >= 0`；F-58 侧另收 6 枚发射站点（`.shl/.shr/.bit_and/.bit_or/.bit_xor/.bit_not`）＋`foldShift` 的 C 风格 `@mod(rhs,64)` 掩码（`1 << 64` 应 0、负计数应抛 ArithmeticError，且旧写的 `@intCast` 到 u6 是越界转换）＋`isRaisableArithmetic` 补 `.neg`（**R-166 漏项**，b47 实测）与位运算六枚；★PHP 实测口径三条照抄不改：string × string **合法**（`&`/`^` 取较短者、`|` 取较长者补 NUL，`'5' & '3'` 是字符串 "1" 而非 int）、对象操作数**恒排前且用类名**（`1 & new Foo()` ⇒ `Foo & int`，故新增 `operandTypeName` 而**不动** `valueTypeName`）、一元 `~` 自成一支（`Cannot perform bitwise not on <X>`，bool 用值文本 "true"/"false"、**null/bool 也拒**）；★`1 & (array)1` 与 `1 & [1]` 的 PHP 自身措辞不一致**不复刻**，按字面数组自然顺序；★语料暴露普查＝位运算 ∪ `% 2^n` **35 枚**（bit_only 24／modpow_only 2／both 9／neither 33，桶和 68 自证）⇒ 本批改了发射器，影子 `changed_rows` **预期非 0**，归因判据「变化集 ⊆ 这 35 枚」；★性能实测：甲型成本＝A(`$i%2` 走 `&`) vs C(`$i%6` 走 php_mod＋内联常量) 中位 456/461 ms（ReleaseFast ≈1%）、1554/1588 ms（ReleaseSmall ≈2.2%），B(`$i%$m`) 的 +12% 来自 `getGlobalVar` 不是 php_mod；位运算热点修前基准 2119 ms 由链内 PERF 腿复测；★新立 **F-59**（算术族对**对象**完全放行＝`checkArithmeticOperand` 只拒无数字前缀串与 array，对象直接通过 ⇒ `$o + 1` 既不抛也无类名）与 **F-58-b**（`&=` 等复合赋值的结果寄存器被 `ir_generator:5083` 声明为 `.i64`，而 F-58 后 string×string 返回 string ⇒ 下游按 `.asInt()` 消费是潜在类型误读，**尚无运行期红证**）；★自我更正五条留字（§41.7）：门 DIFF 行 printf 少传 `$arc`；臂表表达式参数用双引号 ⇒ `set -u` 下整条门在第 45 臂崩掉；为改表头写的 python 用非唯一短语定位行区间，**删掉门脚本 153 行**（三个探针函数＋m/c/g＋b1..b35），靠「重建后同一子集 26 行逐字节 diff 为空」复证复建成功；`rm` 与 `md5` 并写一条（违规则 47，目标均为本会话 /tmp 草稿）；语句位取负此前无臂覆盖。资产：`optimizer.zig` `0eca28756912214892675ba8c4232d07`／`constant_folder.zig` `14c9fe6b958c98a21a057efea9625807`／`native_linker.zig` `1b70d7ad9fa6187a4b5d2c4a291a0dc4`／模板 `85747609374d54581ea9b46914e318fd`／二进制 `c514f194f274857bae241184e0fa2c9c`（`1ebb5a8b…` 作废）／门 MSR 脚本 `68a3cfb4d2fe1f91dc91ac89014504af`、修前表身 `acac0cf19bbbd6f87892a8c830945616`、修后表身 `27d013deffc0a9976bf9bc0e26268a1d`；★OPS 门**改档**：`same=23 diff=3`（红 o5/o14/g4）⇒ 期望 `same=25 diff=1`（残红只剩 g4＝F-55），按纪律不改已入库门头注释，改档登记于 §41.8；详见 §41）；★R-172（**F-62 落地＝乙型「模板内集中 helper」＋全数值族＋c／d 两段一并修**，§46）：老铁三裁＝「乙／全数值族／c＋d 全修」。
只读核查先把甲型否掉——`BuiltinInfo` 只有 `runtime_name/needs_allocator/may_raise/ref_params` 四字段（`native_linker.zig:3976`），且 **AOT 根本没有动态内置分发**（发射期静态解析，未知名直接 `undefined function`）
⇒ 中央发射校验与「在被调函数体内校验」**覆盖面等价**，而甲型要改 664KB 发射器并造新代次；模板里虽已有同措辞的 `php_check_param_type:6519`，但它对对象印 `object` ⇒ 新建 `rejectParamType` 走 `operandTypeName` 印**类名**，**不动**那 9 处本来正确的措辞。
主门 BLT 由 28 臂扩到 **129 臂**，修前 **same=44 diff=85**（A 段 **39/39 全红**＝数值内置根本没有参数类型校验；B 段 5/5＝Passing-null Deprecated 整条缺失；C 段 23 枚合法强转守卫里只红 3；D 段 11/19；E 段 12/15）
⇒ 终档 **same=126 diff=3**（关闭 **82** 枚；残红 b5＝F-62b、b27/b28＝F-63，全是先前已登记面；`aot_caught=53 compile_fail=0 zig_escape=0 bad_probe=0 residue=0` @577s）。
★PHP 口径照抄不改三条：**内置形参拒前导数值串**（`abs('5abc')`、`abs('0x1A')` ⇒ `string given`，与 R-171 的二元算术宽松口径**刻意相反** ⇒ `tryAsIntLoose` 不可复用）、
**对象恒拒且用类名**（带 `__toString` 的也拒：`abs($b)` ⇒ `Bar given`，而 `bcadd($b,"1")`='6' 静默转换 ⇒ bc／`?string` 族另立 F-62b）、
`int` 形参吃非整值 ⇒ **Deprecated 后向零截断**（`intdiv(-5.9,2)`=int -2）且 float-string 版措辞带引号（`float-string "5.5"`），NAN/INF/越界 ⇒ `float given`／`string given`。
D 段是**元素级 Warning 三分类**（object/array ⇒ 跳过；非数值串 ⇒ 计入 0；前导数值串 ⇒ `A non-numeric value encountered` 后计入前缀；禁 over-fatal），
E 段 object vs int ⇒ Notice 后按 **1**、vs float ⇒ 同句式 `to float` 后按 **1.0**、vs string/array ⇒ **无 Notice 且对象恒大于**（必须排在旧 Rule 7「array 恒大于非 array」之前）。
★本批经另两裁进入**新二进制代次 `bdd3af32…`**（前代 `c514f194…`，连续三代模板轮后的第一次重编译）：`native_linker.zig:4312` 的 `fdiv` ⇒ `.may_raise = true`（`php_fdiv` 改 `!Value` 的硬前置，四条发射路径与两处路由块据此自动对齐，门 b39/b40/b88 实测可编译可捕获），
`optimizer.zig:935` 的 LICM 纯函数名单摘除 `count`／`array_sum`／`array_product`（提升会把「每迭代一次诊断」变成「整循环一次」）
⇒ 影子判据由「纯模板轮必须 0」改为「**实测预期 0，若非 0 必须逐枚归因到这两张表**」（语料 `fdiv` 0 枚；`array_sum` 16／`min` 9／`max` 8／`number_format` 9 枚文件里无一是循环内不变量调用）。
四条自我更正**全部由门内实测抓回**（① `?Value` helper 当语句用 ⇒ 生成码 `value ignored`，`_ =` 补 4 站点；② **省略的可选形参在本运行时同样是 null** ⇒ 新增 `requireOptionalNumParam`，代价是显式 `round(1.5,null)` 的 `#2` Deprecated 不发，留字 F-62b；③ `min`/`max` 同值并列**取法不对称**（并列时 min 取后者、max 取前者，八臂矩阵实测）⇒ `php_min` 两支 `< 0`→`<= 0`；④ `php_spaceship` 自成一套实现 ⇒ object 落末路 `toFloat()`，交回 `phpCompare`——★「同一语义存在第二／第三套实现」已是**第三次**撞上）；
新登记 F-62b／F-62d／F-62e／F-65／F-61c 扩，性能成本（25 处入口各加一次校验）**本批未测** ⇒ 留字不报估算值。
★R-171（**F-55 落地＝算术结果的 int／float 分叉按 PHP「字面语法」收口**，§45）：实测钉死规则——结果类型由**字面语法**而非「数值是否为整」决定：`'5'+1`=int 6 但 `'5.0'+1`=**double 6.0**；`6/2`=int 3、`5/2`=double 2.5、`'6'/2`=int 3、`5/2.5`=double 2.0；`'5abc' + 2`=**int 7**（配非数字串 Warning）、`'5e2'+1`=double、`'0x10'+1`=int 1、越界串⇒float。★同时实测到**两套口径不能合并**：二元算术看**数字前缀**（尾随垃圾/首尾空白都容忍并打 Warning），而内置形参是**严格 `is_numeric`**（`abs('5abc')`、`abs('0x10')` 在 PHP 直接 TypeError）⇒ 新增 `tryAsIntLoose`、**保留** `tryAsInt` 给 abs，两者并存。四处缺口逐一坐实：R1 `php_pow`/`php_abs`/`php_div` 根本没用整数字面量判据（⇒ `'6'/2`、`'5'**2`、`abs('5')` 全落 float）；R2 `tryAsInt` 判据偏窄＝**门 OPS 唯一残红 g4 的真身**；R3 `abs(PHP_INT_MIN)` 在 i64 上 `-i` **回绕** ⇒ AOT 返回 `integer -9223372036854775808`（值与符号皆错，PHP 是 float）；R4 附带揪出 `php_pow` 整条**漏发** `A non-numeric value encountered`（值对警告缺，NST n15）。★`php_pow` 改 int 路径时**必须改用判据解析出的值**——旧写法对字符串寄存器调 `asInt()` 会被 NaN-boxing 兜底读成 0。门 NST（新建 32 臂，`a728ed98…`）：修前 `same=14 diff=18` ⇒ 落地后 **`same=30 diff=2`**，残红恰是两枚**已登记的交叉面**（n9＝F-62、n31＝F-63 记法，类型本身已修对 ⇒ 我为此另加只报 `gettype` 的 n32 作真验收臂）。★**改档达成：门 OPS 自本批起 `same=26 diff=0`＝零注册红**，是本工单第一道完全全绿的操作数门；BLT 同步 `11/17 → 13/15`。28 腿链 6805 s 全 rc=0：OBJ/ABS/MSR/F45FACE/PD/S/AC/AB/CENSUS/U/B/ZCENSUS 与 R-170 **逐字等值**（守卫未被改宽），主回归 Pass 67/Skip 1 零回归，影子 **`changed_rows=0`**＝连续第三个发射中性的纯模板轮。；★R-170（**F-59 的漏网面＝`pow()` 与 `**` 是两条实现**，§44）：R-169 我写过「`pow($o,2)` 与 PHP 逐字节同」——那是一句**只测了 PHP 侧＋只读了一行 `wrapBuiltin_pow`** 的未验证断言，被新门 BLT 的同源对照臂打回（`2 ** [1]` b26 绿／`pow($o,2)` b17 红）。真因＝内置名表 `native_linker.zig:4288` 把 `pow` 映射到 **另一个函数 `php_pow_func`**，该体**无操作数检查**（对象/数组/非数字串静默给 float）且整数幂**无溢出检测**⇒ 实测 `pow(2,63)` 得 **integer −9223372036854775808**、`pow(10,19)` 得 −8446744073709551616（PHP 两者皆 float）＝P0 级静默错值。修法＝`php_pow_func` **委托 `php_pow`**（同一语义只留一份，`@mulWithOverflow` 溢出转 float）；★委托前必须先补 `b == ±1` 早退——`php_pow` 的逐次乘法只靠溢出退出而 `|b|==1` 永不溢出 ⇒ `1 ** 10^12` 无界，不补就是**把挂死从 `**` 扩到 `pow()`**（修后四形瞬时返回且与 PHP 逐字同）。门 BLT 28 臂：修前 `same=7 diff=21`（快照 `903f50a7…`）⇒ 落地后 `same=11 diff=17`（`626bd9d7…`），关掉的恰是 pow 族 6 枚（b17/b21/b22/b23 措辞＋b27/b28 回绕），残红 17 枚**全部先前已登记**（F-62 13／F-55 2／★新立 **F-63** 2＝大浮点**记法**不合 PHP：`9.223372036854776E+18` vs `9223372036854776000.0`，值对写法错，**不属** §七.7 的末位精度豁免）。26 腿链 7102 s 全 rc=0：三族门等值、主回归 Pass 67/Skip 1、**影子 `changed_rows=0`**（连续第二个纯模板轮达标）；R-169 产出的三重自保首次全链生效。★可复用普查结论：**收口任何「既是运算符又是内置函数」的面之前，必须查 `native_linker` 的内置名表**（`abs/min/max/intdiv/sqrt/fdiv/array_sum/array_product` 目标函数体内检查命中数全为 0），但 `array_sum/array_product/max/min/比较` 在 PHP 侧是 **Warning/Notice ＋返回值**、**绝不可加抛**（同 R-155 `count()` 的 over-fatal 陷阱）；★R-169（F-59 落地，老铁裁「本轮直接修」＝**纯模板轮**，§43）：算术族**拒绝对象操作数**（`checkArithmeticOperand` 旧写只拒「无数字前缀串」与 array ⇒ **对象直接通过**，被 NaN-boxing 兜底成 `0.0`，`$o + 1` 静默得 **float 1.0**、`$o / 0` 还抢先报 `DivisionByZeroError`）＋操作数消息改用 **类名**（新增走 `operandTypeName`，算术族保**自然顺序** `int + Foo`，与位运算族「对象恒排前」**不合并**；`valueTypeName` 其余 9 处调用点逐字不动）＋增量族**第三套措辞**（`php_increment/php_decrement` 末路拦对象 ⇒ `Cannot increment|decrement <类名>`）。★两条先验判断被实测否证：① 我担心 `DateTime - DateTime` 是 DateInterval 合法差、blanket 拒绝会 over-fatal ⇒ 实测 **PHP 自己就抛** `Unsupported operand types: DateTime - DateTime`；② 只改算术检查会让 `$o++` 抛成 `Foo + int`＝**把一种错换成另一种错**，该中间态被**单独量出来**（门 OBJ 11 臂档 `same=4 diff=7`）后才补增量守卫（R-165 半修教训的正面执行）。门 OBJ 建门 24 臂修前红 **17**（对象算术 15＋语句位 2）⇒ 落地后 35 臂 **`same=33 diff=2`**，残红**恰好只有**登记的 F-61 两枚（i8 bool 增量缺 Warning、i11 数组增量措辞）；守卫臂 o18..o24 含「拼接 `$s . "x"` 仍合法」「`null+1`/`true+1` 仍不抛」「`$o & 1` 措辞未被改坏」全绿。★波及面**穷举核实**：全模板内 `php_add/php_sub/...` 的调用者只有 `php_increment/php_decrement` 末路与 `pow()` 内置（`array_sum/array_product` 是内联累加、不经 `php_add/php_mul`）⇒ 不会把它们从「返回值」推成「抛异常」。★验收**分两段**（环境事故）：`c045` 前 12 腿达标后在 ZCENSUS 被 **ENOSPC** 打断，其后 13 腿 `rc=1 wall=0s`、regression 未跑、shadowcol 自行 `ASSERT_FAIL`（规则 29 的断言正确地拒绝出假差值）；`c046` 补跑 17 腿（10:08:46→11:13:42，3896 s）全 rc=0 ⇒ 合并读数为ABS 26/26、MSR 74/74、F45FACE 12/7、OPS 25/1、PD 18/2、S 47/47、AB/U/B/ZCENSUS 与 R-167 逐字同、**主回归 Pass 67/Skip 1 零回归**、**影子 `changed_rows=0 col_identical=yes`**（纯模板轮预言达成 ⇒ 不重冻、不归因）。★纪律产出两条：链必须做**磁盘前置断言**（ENOSPC 下失败腿长得跟真失败一样：`rc=1 wall=0s`），且**任一腿非 0 立即停链**；仓库根 `.zig-cache` 在同一点整目录消失，**非我删除、原因不做无据归因**，代次一致性改由 md5 断言承担。★新立 **F-61**（增量族数组措辞＋bool 增量 Warning）与 **F-62**（内置数值形参的**第四套措辞** `<fn>(): Argument #N ($name) must be of type <T>, Foo given`；`array_sum/array_product` 对对象**只 Warning 不抛**并返回 0/1；`max/min/比较` 走 Notice），门已建 `c047_builtin_numeric_object_gate_tmp.sh`（20 臂）待跑。；★R-168（**零 `src/` 改动的取证轮**，§42）：新建永久侧门 **ABS**（`c043_bit_assign_gate_tmp.sh`，26 臂）把 §41.9 挂出的 **F-58-b 打到证伪**⇒ 实测 **26/26 全绿**（复合赋值 `&= |= ^= <<= >>=` 的 string 写回、string 结果被 `> 0`／`strlen`／`(int)`／拼接／`+1`／`===`／真值判定／数组键／循环内 共 20 枚消费位、int×int 五枚守卫、`~` 三枚，以及 a21..a26 六枚**复合赋值抛出面**＝`CAUGHT` 且 `RET` 缺席且 `tail` 照打 ⇒ 站点＋路由＋「抛出后写回不执行」三件事同证）。机制两条读实：① `Value.asInt()` 是**全函数**（NaN-boxing 三级试完最后 `return 0`，`asBool` 直接读 `(val & 0x1)`）⇒ 本仓「声明类型 vs 实装值」的风险**探不到 panic，只能靠逐字节差分**；② 位运算结果寄存器**没有任何消费点插 `.asInt()`**（落地时保留 Value 形态赋值，`writePhpValueExpr` 对任何标签都只打印 `reg_N`）⇒ `.i64` 声明在此只是元数据 ⇒ **F-58-b 撤销**，门留作永久守卫。★F-60 定价补齐关键一块：同代同档同调用数实测 `php_bit_and ≈ php_add`（1583 vs 1597 ms）⇒ **R-167 的位运算 +32% 不是「位运算比算术贵」，而是位运算第一次付了算术在 R-165/166 已经付过的钱**⇒ 直接推论＝**快路不能只对位运算开**，否则等于重审已批准的算术代价；★唯一仍缺的数＝语料级稀释比，且**拒绝用估算代替**：主回归报表**无耗时列**、影子 old 侧 `be305cfa…` 是 R-145 代（隔四代发射变更，非同一代对照）⇒ 同代修前二进制需 `git worktree add --detach df31715` 独立构建（会写 `.git/worktrees`）⇒ **已请示，未擅动**）；★**F-60 已由老铁裁定为「乙：接受现状，不做快路」**（依据 §42.3 实测 `php_bit_and ≈ php_add` ⇒ 快路只会造成算术/位运算口径分裂），该项**关闭**，不再占用裁决队列；★R-166（F-45-ii 收口＝DCE 守卫由 `.div/.mod` 扩到 `.add/.sub/.mul/.pow`）已闭合（门 F45FACE 扩到 19 臂 ⇒ `raise_lost 4→0`、p11/p12/p15/p19 与 PHP 逐字节同、原 12 臂逐字不变；★新增门 AB 语料分母腿实测 `diff=0` ⇒ 语料行为暴露 0；影子 `changed_rows=0` 比预留的"允许合法非 0"更强；★副产物＝修掉 `test_loop_unroll.zig:286` 那枚"Temporarily expect .add to allow build"占位断言，本批一改它就红，实测 `inst1` 现在真的是 `.nop`＝该测试原本期望的行为；教训＝**改优化器必须前置跑 `zig build test` 再开链**，本批首开链就在 buildtest 腿 rc=1 才撞上，已停链重开）；★R-165（F-46 甲型＝抛出站点改可捕获 TypeError **＋** 给 `.add/.sub/.mul/.pow/.neg` 补异常路由，两处缺一不可）已落地、25 腿链进行中（门 OPS 修前 `same=9 diff=17 aot_caught=0 aot_exit255=12` ⇒ 修后 `same=23 diff=3 aot_caught=14 aot_exit255=0`，3 枚残红身份逐枚可归因＝o5/o14 属 **F-56** 字面量 `%` 常量折叠绕过、g4 属 **F-55** 结果类型；★原登记「缺数组检查」是**误诊**——`checkArithmeticOperand:6076` 早已拒数组，真因是 `emitUnsupportedOperandError:6181` 的 `noreturn`+`exit(255)` 绕过路由；★半修态（只改抛出、不补路由）实测会多打 `RET|` 且未捕获形从"立即终止"变"继续跑"＝自造回归 ⇒ 已还原复验后再按甲型重落；★本批**改了发射器** ⇒ 影子 `changed_rows` 允许合法非 0，与 R-158b…R-163 那串"第 N 代同值"批不同）；★R-163（F-50 `preg_*` 分隔符/修饰符校验，**纯模板**）**已落地并 21 腿验收闭合**（链 `17:54:22→19:07:46` 4404 s、影子 `changed_rows=0`＝第 **11** 代发射同值、★门 S 47 臂仍 `diff=0`（本批改的就是它下游解析器）、主回归 Pass 67/Skip 1＝F-50 语料暴露 0；门 PD 修前 17 臂 `same=7 diff=10` ⇒ 修后 20 臂 `same=18 diff=2`，旧 17 臂全绿、红恰为新登记的 **F-53** 两枚；★建门轮两条预估被实测否证——成对分隔符 `(a)`/`{a}` 从未支持、缺校验面覆盖整个 preg 家族而非只 `preg_match`；合法修饰符集合＝**实测 13 枚** `imsxnurADJSUX`（第一版用 `error_get_last()` 得出"全部 UNKNOWN"的假结论，必须 `set_error_handler` 逐轮清零才测得准）；落地当场因 `_ = matches_ref;` 变成 pointless discard 导致 20 臂全 `compile_fail`，是「模板改动只有 AOT 产物编译才验得住」（F-38）的现形）；★R-160（F-41 丙型「arity 金丝雀」）**验收闭合**（§36：链 `16:16:30→17:26:23` 共 4193 s、影子 `changed_rows=0`＝自 R-148b 起**第 10 代发射同值**、门 AC `canary 0→7` 而 `compile_fail`/`zig_raw` 逐枚未动；★丙型**不解决**切片形参面（`json_decode()` 编译通过、运行期才炸）与用户函数/方法面，那三面属甲型）；★R-160b/R-160c（§37）＝甲型前置测量**已闭环**：`stdlib.zig:24-47` 早已用 `fn_table` 的 min/max 做中央校验（tree/fast 走、AOT 与 bytecode 不走）⇒ 表的 10 枚错值**今天就是 tree/fast 的活缺陷**（5 枚过度拒绝＋3 枚该拒不拒），而 **AOT 列补测否证了「把 AOT 接上表」的可行性顺序**——那 5 枚里 AOT 只对 `implode($a)` 失败，另 4 枚（`array_merge()`/`array_push($a)`/`array_diff($a)`/`array_unshift($a)`）AOT 与 PHP 逐字节等值（切片形参）⇒ **先修表再谈消费**，否则当场造 4 枚新红（违规则 30）；新立 **F-47/F-48/F-49**（全属非 AOT，待明示）＋ **F-50**（`preg_match("b",$s)` 缺分隔符校验且**返回错值 1 而非 false**，门 S 无臂可抓 ⇒ R-163 自办））（链 `16:16:30→17:26:23` 4193s，影子 `changed_rows=0`＝自 R-148b 起**第 10 代发射同值**；门 AC 13 臂 `compile_fail=8 canary=7 zig_raw=7`，12 臂口径与修前仅 `canary 0→7` 之差；门 F45FACE/Y 复证 R-161 档全等值；主回归 Pass 67/Skip 1；helper 签名登记率 **539/539**、`comptime/anytype/...` 排除 0 枚；★建门轮两条预估被实测否证——a12 `implode(",")` 其实是第 7 枚定长形参站点、`residue=7` 是我自己 KEEP_TEMP 留下的而非编译器泄漏；★丙型**不解决**切片形参面（a7 `json_decode()` 编译通过、运行期才炸）与用户函数/方法面（a10/a11），那三面属甲型＋运行期守卫）（★R-161=F-45（乙型）：DCE Phase 3 守卫追加「可抛出算术指令结果被丢弃也不删」+ 新谓词 `isRaisableArithmetic`（★按实测**只含 `.div`/`.mod`**）⇒ 门 F45FACE `on_eq_off=no` **9→2**（剩 p11/p12＝故意不收的 `.add/.mul`＝**F-45-ii**，其 TypeError 今天不可捕获⇒属 F-39 族）、p09/p10 **与 PHP 逐字节等值**；门 Y `y7` 回收 ⇒ 改档 `same=5 diff=5 zig_escape=1 cf=2`，红集降为 `y2 y4 y8 y9 y10`；★语料暴露实测 **0**（门 AB 折叠 `DATETIME` 后 `equal=67 diff=0`；首轮 f119/f175 系时间戳**假红**）；★新立 **F-46**（数组操作数的算术 TypeError **两臂都不抛**＝操作数类型检查缺数组，与 DCE 正交）；新资产＝门 AB＋门 F45FACE（14 臂，判据 `on_eq_off`）＋21 腿链；★R-160（F-41 丙型）方案已定：失败后自解析生成码报可读 arity 诊断（不碰子进程管道、不建 arity 表），甲型随后／★R-159=F-37：`php_intdiv` 两枚站点由「Zig error 外逸 / `@divTrunc` 静默回绕」改为可捕获 `DivisionByZeroError`/`ArithmeticError`（**纯模板**、不重建二进制、`builtin_map` 不动）⇒ 门 Y `y5 y6` 转绿、改档 **12 形 `same=4 diff=6 zig_escape=1 compile_fail=2`**，★门 Y **首次入链**（R-155/156/158b 三链均无 Y）；★修门轮否证旧口径「y7=`1 % 0` 是同族已正确先例」——`printf` 里裸 `%` 把探针静默截成 `1`，该臂从未测过取模 ⇒ 改转义口径后 y7 转真红并**新立 F-45**（结果被丢弃的 `%`/`/` 语句被 DCE 整条消除，A/B `--aot-disable-pass=dce`/`--aot-max-iterations=0` 两支复现 CAUGHT，待裁决）；★另登记一次资产事故：误写 `rm` 删掉未入库的门 Y 脚本，靠删除前 TSV 快照**逐臂字段比对**复验重建（除 ELAPSED 外全等）；模板锚点自 `:12811` 起 **+10**（§32.6 换算表）／★R-158b=F-42：`tryRemoveTrampolineBlock` 释放快转块前改道 `exception_handler`（`optimizer.zig` +29/−0）⇒ **门 Z** 面孔门 `dangling 6→0`、门 P `compile_fail 2→0`（`f35` 转绿、`f34` 转为语义红 ⇒ **新立 F-44**：`ir_generator.zig:3744 redirectThroughFinally` 在 finally 体内 throw 时把整个 finally 体重发一份；A/B 关 cfg_cleanup 实测仍双打 ⇒ 属暴露非引入，待裁决）；同时**否证 §30.6 两条口径**——「`.index` 陈旧」（`analysis.zig:273-275 rebuildCFG` 一直统一重编号）与「用 `Dead blocks removed` 当分母」（旗标只由三枚删块站点之一 `:3364` 递增，恰好漏掉肇事的 trampoline 面）；门 Z 全语料普查 `total=68 dangling=0 ok=68` ⇒ 语料对本族零暴露）／★R-156=F-22：门 P 注册红 `f26` 已回收，现行门 P = **78 形 `same=72 diff=4 compile_fail=2`**，四枚红 `v2 i1 i2 f12` + 两枚既存 panic 臂 `f34 f35`=新立 F-42；同时改判 F-36（与 Error 支无关，真机制＝file/line 在 setException 惰性注入 ⇒ 未抛出的异常对象取不到位置）并新立 F-43（`function_exists("php_bool_or")` AOT=true ⇒ helper 登记泄漏成 PHP 可见函数名，与 F-4 同族））**（R-138 = 内省枚举族八项落地 + 永久侧门 P 建成，2026-10-12，详见 §12；R-141/142/143 = F-8a 参数默认值面、F-12/F-12b 参数名面，详见 §14–§16；**R-144 = F-5/F-7 PCRE flags/offset 全族收口 + 新立并修复 F-13（`preg_match` 实参 ≥4 时引用装填丢失），详见 §17**）。⚠️ **§10 的 R-137b/R-137c 记录为假阳性**（抛出支从未入库，已由 R-138 重落，更正见 §10 内联与 §12.0）。**门 P 现行读数（R-149 定档）= **76 形 `same=71 diff=5`**，5 枚恰为注册红 `v2/i1/i2/f12/f26`（F-8b／F-3×2／F-18 漏报／**F-22 多语句 finally**）；**f33（原 F-23）已由 R-149 的 F-24c 转绿**——它不是独立缺陷，而是「`extends`/`implements` 父名被解析两次」的症状（工单 §22）；新建**门 T**（R-150 定档 **19 形**，F-24 族：7 枚注册红 `t2 t8 t9 t11 t12 t13 t19` + 1 枚注册 compile_fail `t17`；F-24a/t1·t4·t5·t14 与 F-24b/t6 已转绿，另新立 F-24e 与 F-25）；**F-21 六枚臂（f15 f17 f19 f20 f21 f23）已由 R-148 全部转绿**，catch 类型名解析六枚臂（f27–f32）同批转绿；其「嵌套外溢」旧措辞作废（真根因＝单臂 catch 不建派发块，见 §21.1）；**r10 与 n15 已分别由 R-146／R-145 转绿，f14（F-20 handler 倒灌）由 R-147 转绿**；**n15 = F-1 已于 R-145 转绿**，其守卫移交 F 组 f1…f13（合法性矩阵，全部 PHP 8.5.8 实测）。R-144 轮为 39 形 `same=34 diff=5`（历史快照）；R-138 建成代次为 35 形 `same=31 diff=4`（见 §12.7，仅作历史快照）。**门 S 现行读数（R-144 建成轮）= 47 形 `same=47 diff=0`，判据即 `diff=0`（本门无注册红）**，修复前 30 形 `same=9 diff=21`（§17.1/§17.5）。门 M 19 形 `red=0 green=19`、门 D8 14/14、门 N 7/7、门 O 6/6、门 Q `same=5`、门 R `same=8 diff=1`、普查门 B `diff_impl=3`；`zig build test` 21/21 & 326/326；主回归 **13:38:37（R-149 代）Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 0 / Skip 1**，且影子 vs R-148b 列 **`changed_rows=0`**（F-24c 与 F-24a/b 均语料发射中性实测：影子 vs R-148b、vs R-149 两次 `changed_rows=0`）（★R-148a 代曾掉到 Pass 66：本批自造的 `f006 catch (\Throwable)` 回归，已由 `resolveClassName` 收口复证，见 §21.9/§21.10）（失败明细仅 1 行 `f004 SKIP` ⇒ 回收枚 0；判据取明细行存在性而非汇总数，见 [[feedback-aot-regression-rules]] 规则 27）；影子 `total=68 same=0 diff=68 miss=0 invalid=0` @1037s，且 **new-side 列相对 R-144 代 `changed_rows=68 / unchanged=0`** ⇒ R-145 因入口守卫进入每个 `main.zig`，**是一次彻底的影子重冻事件**（前缀 `be305cfa` 须在「提交」时按当代次重冻）。**当前代次（R-149 定档）**：`ir_generator.zig` **`f3d13cb82395d945d2a246b2158589ea`**（R-149 F-24c；R-148b 值 `81dffec5…` 作废）／`optimizer.zig` `6cffa137…`（R-147）／二进制 **`1abad89e2166d15e32fc304e2d071c28`**／门 P 脚本 **`cb1a622797cc7b0519f38dc1f8ca3bb1`**（76 形）／影子基线列 `c010_shadow_newside_r148b_tmp.txt`（表身 `f19fb070…`，R-147/R-148a 两列并存）；旧值 `8b5c65a1…`／`bbff3b4a…`／`001bc245…`／`8dae7b2b…`／`eab47607…`／`37a86a66…` 作废。原「R-147 定档」：`runtime_lib_template.zig` `4ff0befc7c5b50d4fcfb8b1fd1f057e7`（R-147 未变）／`native_linker.zig` `49a3da31660fef4963b8eb50d7587987`（未变）／`ir_generator.zig` `0242d8b5a960a8b8e06b063494f6ec23`（未变）／**`optimizer.zig` `6cffa137f766bdd2a13769c7ba3314b5`（本轮新增守卫）**／二进制 `8b5c65a1f34af70977e73e6c4dea2bd7`（**R-147 改优化器 ⇒ 已重建**，`fec549b26ab4d58f77bfa5316f61445e` 作废）／门 P 脚本 `eab47607d8d4d02979ed17dcdc76bb3b`／门 S 脚本 `f3c2c9e6b1a319cd76a297217212fb54`（未变）；影子 new-side 整列已落盘 `fuzzy_scripts_720/tmp/c010_shadow_newside_r147_tmp.txt`（68 行，表身 md5 `628aa13b3778359d1210c6800901f687`）；原 `3d5c0c8aa86954d389f533c1b1c184e9`（门 P 39/57 形代）；本批中途代次 `0b9cf3a7…`/`d40ee9a9…` 与 R-144 轮 `5c0ecf42…`/`86174723…`、R-145 中途轮 `67a60675…`（模板）与门 P `5904939b…`、R-144 轮 `5c0ecf42…`/`86174723…`、R-138 轮 `b356e19e…` 均作废（见规则 25）。**待裁决**：F-3（门 P 注册红 i1/i2）；F-1 已落地（R-145，§18）、F-2 已落地（R-146，§19）；**待裁决 F-25 修法（甲 改模板捕获名⇒全 68 枚漂移需重冻／乙 只给撞名用户函数改 Zig 符号⇒零漂移、建议／丙 甲+乙）**；**新增 F-29「类声明提前登记」（R-153 归因）＝F-24d 的硬前置：AOT 启动期一次性登记所有类，PHP 在声明语句执行处登记（d8/d9 实测 `class_exists` PHP=n／AOT=y）⇒ 直接在登记处加「父类缺失即 fatal」会把 PHP 不报错的场景变成 over-fatal，两者必须一起排；语料面：未解析父/接口引用 0 枚、作用域内类声明 0 枚 ⇒ 双双看不见**；F-27 第 1 层（属性位）已落地（R-151b，§25.3）⇒ **R-154 更正：类型检查实为三条互不复用的链，R-151b 只收了属性位**（形参位 v9/v27/v28、`instanceof` 位 v5/v6 由 R-154 落地；返回值位的「绿」被证伪为新立 F-35，见 §28.2/§28.9）；F-28 已随 R-154 落地，并新建永久侧门 **门 V**（定档 **29 形 `same=18 diff=11 compile_fail=0 bad_probe=0`** @122s，登记轮修前 `same=10 diff=19`）；F-24d（t9/t11）待修；**★R-154 新立六张面孔（全部未修、待裁决，§28.4–§28.9）＝F-30：PHP 8.5.8 实测 `Error` **不再继承** `Exception`（`is_subclass_of('TypeError','Exception')=false`、`get_parent_class('Error')=false`），AOT 仍按旧层级过度捕获 ⇒ 跨切面／F-31：`throwException:21822` 把异常置成**字符串**伪值 ⇒ `catch` 永不命中且 fatal 文本类名错，调用点实测 **17 枚**，逐枚须先测真值异常类别／F-32：`PHPObject.toString:19437` 无 `__toString` 时 fail-open 返类名／F-33：`count()` 对非 Countable 返 0（语料高频，改前必须普查）／F-34：`spl_object_id()` 对闭包返 0／F-35：返回值类型位**完全不校验**（`: object` 返回 `int` 静默放行）；**★R-155（§29）＝门 W（20 形 `same=7 diff=13`）与门 X（9 形）建成 ⇒ 实测否证我自己提的「`php_count` 需补解引用」前置（x1/x2/x3 引用三形本就与真值等值 ⇒ 引用在载入侧已解）；F-33 第一批已落地（`php_count` 非 Countable ⇒ `throwThrowable("TypeError", …)` + 专用 helper `countArgTypeName`）⇒ 门 X `x6`/`x9` 转绿且 `x4` 按 §28.7.2 **设计留红**（接口判定须与 F-3 内建接口表同批，否则打红 `SplFixedArray`/`ArrayObject`）、门 V `v15` 转绿（`18/11`→`19/10`）；另新立 F-36（`new Error(...)->getFile()` 为空而 `new Exception(...)` 非空 ⇒ **Error 根与 Exception 根不等价**，「搬根」必须含构造期属性初始化）／F-37（`intdiv(1,0)` 打印 `error: DivisionByZero` 且 **rc=1** ⇒ Zig error 外逸，属 F-9/R-145「未捕获必须 PHP 风格 fatal + rc=255」族的漏网站点，门 R 现有臂抓不到）／F-38（`zig build test-aot` **6 处编译错误**全在 `test {}` 块内 ⇒ AOT 单测步骤长期失编译；运行期模板的编译验证实际由 AOT 产品编译承担，旧「`zig build test` 覆盖模板」口径作废，见 §28.13.2）**；**F-20（f14，P1，try 前语句异常被无关 catch 吞）已落地（R-147，§20.2–§20.3）＋**F-21（六枚臂 f15 f17 f19 f20 f21 f23）已落地（R-148/R-148b，§21：根因＝单臂 catch 不建派发块 + 末臂 else 落点；含本批自造的 `\Throwable` 回归收口）**＋**新立 F-22（f26，多语句 finally 与 pending 异常共存，属暴露非引入）与 F-23（f33，命名空间用户类 `extends \Exception` 后内建方法整族丢失，前缀 `be305cfa` 证非本批引入）待归因****＋F-4 去重（删代码，§17.7 记「裸侧未动」的理由）／F-6（`debug_backtrace`）／F-8b（设计分叉，§14.4）／F-10（删功能，登于 013）／**F-13b、F-14、F-15（§17.7）**／**F-16（入口未捕获异常上报，R-145 已修，§18.3）、F-17（trait 名限定的 Deprecated 文本，§18.7）**；F-5/F-7/F-12/F-12b 已落地；**F-11 未登记（编号保留，勿误读为存在该项）**。门 M 终态 **17 形 `red=0 green=17`**（链 XI 同口径全绿：影子 68/68、主回归 Pass 67/Skip 1、门 D8/H/H2/I/E/F/G 注册值保持，2026-10-11 07:05:35 报表）：门 M `red=5→0 green=3→8 compile_fail=0 bad_probe=0 residue=0`（链 VIII 同口径全绿：影子 68/68 零漂移、主回归 Pass 67/Skip 1、门 D8/H/H2/I/E/F/G 与 R-127 代注册值一致；二进制随链 VIII 代 `5c436e9e…` 后续树，runtime 模板不改变解释器二进制 md5）；落地含两处自纠（php_instanceof 重写误删 Throwable 块 ⇒ 补回；伪接口比较 eqlIgnoreCase ⇒ `instanceof stringable` 双拼写 ✅）；变更文档 `docs/changes/2026-10-11/AOT-CODEGEN-012_类名族CI_R128_2026-10-11_fbe6382a.md`
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
| **门 Z**＝`fuzzy_scripts_720/tmp/c026_dangling_ref_census_tmp.sh`（`--verify-ir --no-opt-fallback`，全 68 逐形单文件编译，桶 `DANGLING_REF/OK/OTHER_rc`） | 读数 **`Z_DONE total=68 dangling=0 ok=68 other=0`**（767 s；R-158b 链内 ZCENSUS 腿复测同值，见 §31.12） | ★这才是 F-42 的**有效分母**，且覆盖 A/B/C 三面的所有引用类型。**探针覆盖面已核**：`verifyModule` 在 pass 主循环里**每枚 pass 之后都调**，其中 cfg_cleanup 处有两枚 ⇒ `optimizer.zig:600-605`（模块级 `runCFGCleanup` 后）与 `:736-741`（超大函数的逐函数快路 `cleanupCFGInFunction` 后）⇒ Face A 的释放动作**一定被校验器看过**，不是「碰巧没跑到」 |
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
| 运行期模板 | `src/aot/runtime_lib_template.zig` | **`6d520849c9a7eab50082c62e924662dd`**（R-159 终稿；R-156 的 `998aa7f6…` 作废；本表原记的 `998aa7f6…` 属 R-158b 代） | ★R-159 改 `php_intdiv` 两枚站点 ⇒ 纯模板、**不重建二进制**（`bin_md5` 仍 `b71f9f41…`） |
| **门 Y（首次入链）** | `c024_zig_error_escape_tmp.sh` | **`89cd0ef91e1ad7a3348c9579e07b476a`**（★旧值随误删事故不可核对，见 §32.5） | 12 形 `same=4 diff=6 zig_escape=1 compile_fail=2`，注册红 `y2 y4 y7 y8 y9 y10` + `cf` `y1 y3`；★`zig_escape` 是正交旗标，非互斥桶 |
| IR 生成 / 发射 | `ir_generator.zig` / `native_linker.zig` | `f3f11deff95fce0adfd0758aab32fac3` / `31f9433d7e6fd3b130cca60f0d8fc80a` | 本批**未动**（F-44 待裁决 ⇒ 留待下一批） |
| ★优化器 | `src/aot/optimizer.zig` | **`e720145e5da407335bc301fbdfb0c909`**（R-147 值 `6cffa137…` 作废） | `+29/−0`：新增 `redirectExceptionHandlerRef` + trampoline 站点一行调用 |
| 二进制 | `zig-out/bin/php-interpreter` | **`b71f9f41f182161df7ebab04a0b64879`**（R-156 值 `4e048f47…` 作废） | ★本批改 `optimizer` ⇒ **必须重建**；中间代 `e5a6522d…`（无自环守卫）/`df1feb36…`（守卫但注释未更正）均作废 |
| 影子基线列 | `c010_shadow_newside_r156_tmp.txt`（表身 md5 `f19fb070ba1b86c34f02b3883de8e4dd`） | — | R-158b 列须与之 `changed_rows=0`（语料无 Face A 形态） |

### 31.12 R-158b 验收链 19 腿读数（`R158B_CHAIN_START 2026-10-14 09:51:06 bin_md5=b71f9f41…`）

| 腿 | DONE 行读数 | wall | 判读 |
|---|---|---|---|
| buildtest | `zig build test` rc=0 | 8 s | 与 R-156 代同为缓存命中档（R-156 腿 5 s） |
| **ZFACES** | `ZFACE_DONE shapes=10 same=9 diff=1 dangling=0 compile_fail=0 bad_probe=0` | 36 s | ★**本批主判据**：`dangling=0` ⇒ Face A 悬垂引用清零；唯一残红 `z2`＝F-44 |
| **ZCENSUS** | `Z_DONE total=68 dangling=0 ok=68 other=0` | 767 s | ★68 语料逐形 `--verify-ir --no-opt-fallback` 全通过 ⇒ 语料零暴露，且**无需保守退路**即可过全量 IR 校验 |
| X | `shapes=9 same=8 diff=1 cf=0` | 39 s | 等值注册档（残红 `x4` 设计留红） |
| V | `shapes=29 same=19 diff=10 cf=0` | 122 s | 等值注册档 |
| W | `shapes=20 same=7 diff=13 cf=0` | 75 s | 等值注册档（F-3/F-30 未动） |
| T | `shapes=22 same=16 diff=5 cf=1` | 88 s | 等值注册档（红 `t2 t9 t11 t12 t13` + 失败 `t17`） |
| **P** | `shapes=78 same=73 diff=5 cf=0` | 310 s | ★**改档确认**：`cf 2→0`、注册红 4→5（`f35` 转绿、`f34` 转 F-44 语义红）⇒ 与链前单跑（@306 s）**逐枚同值** |
| S | `shapes=47 same=47 diff=0 cf=0` | 187 s | 等值注册档（本门无注册红，判据即 `diff=0`） |
| M | `shapes=19 red=0 green=19` | 68 s | 等值 |
| N | `shapes=7 red=0 green=7` | 24 s | 等值 |
| O | `shapes=6 red=0 green=6` | 21 s | 等值 |
| D8 | `shapes=14 defect_red=0 guard_same=14` | 49 s | 等值 |
| Q | `shapes=5 same=5 expect_fail=0 unexpected_fail=0` | 22 s | 等值 |
| R | `shapes=9 same=8 diff=1 terminate_lost=0` | 38 s | 等值 |
| U | 列聚合（无 DONE 行）与 R-156 代**逐字节相同**（`diff /tmp/r156_U.out /tmp/r158b_U.out` = 空） | 203 s | 等值（F-25 冲突普查面未动） |
| B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` | 2 s | ★`entries=497` 未变 ⇒ 本批零地图漂移（未新增登记项） |
| regression | `Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 全 0 / Skip 1`，`## 失败明细` 仅 `f004 … SKIP` 一行 | 785 s | 回收枚 0、新增红 0（规则 27 取明细行存在性） |
| shadow | `C010_SHADOW_DONE total=68 same=0 diff=68 miss=0 invalid=0` | 1119 s | `diff=68` 是**对照冻结前缀**（`be305cfa`，pre-72cdaca）的常态 ⇒ 无 miss/invalid 即合格 |
| shadowcol | `SHADOWCOL_DONE gen=r158b rows=68 col_md5=f19fb070ba1b86c34f02b3883de8e4dd base=…r156_tmp.txt base_md5=同值 changed_rows=0 col_identical=yes` | — | ★**发射中性实证**：换了二进制代次，68 语料的 `main.zig` 整列仍逐字节不变 ⇒ F-42 改道在语料内零触发（自 r148b 起第 7 代同值） |
| 链尾 | `R158B_CHAIN_END 2026-10-14 10:57:09 bin_md5=b71f9f41… ELAPSED=3963s` + `R158B_CHAIN_DONE` | — | 首尾二进制同值 ⇒ 链内无代次漂移；规则 28 双判满足 |

★链内读数与链前单跑**逐枚同值**（门 P `same=73 diff=5 cf=0`、红集 `v2 i1 i2 f12 f34`、`f35 SAME`；门 Z `dangling=0`）⇒ 非并发假象。各腿 `repo_build_residue=0`；`.php` 原件零删除。

## 32. R-159（2026-10-14）：F-37 落地（`intdiv` 两枚 Zig 外逸）⇒ 门 Y 改档；★一枚 printf 转义缺陷揪出「假绿守卫」⇒ 新立 F-45

### 32.1 落地内容（纯模板 ⇒ 零 `zig build`、`main.zig` 中性）

站点 = `src/aot/runtime_lib_template.zig:12798-12816 php_intdiv`。★`intdiv` 在 `builtin_map` 里是 `.needs_allocator = false`（`native_linker.zig:4311`）⇒ 沿用模板全局 `runtime_allocator`，**签名与地图都不动**（门 B `entries` 须仍 497）。

| 面孔 | 修前实测（bin `b71f9f41…`） | PHP 8.5.8 真值（实测） | 落地形态 |
|---|---|---|---|
| `intdiv(1, 0)` | 打印 `error: DivisionByZero`、**rc=1**，后续语句不执行 | `DivisionByZeroError: Division by zero`，可捕获、rc=0 | `_ = try throwThrowable("DivisionByZeroError", "Division by zero", runtime_allocator); return Value.initNull();`（形态照搬同文件 `/`、`%` 三支 `:5962`/`:5976`/`:6003`） |
| `intdiv(PHP_INT_MIN, -1)` | **静默回绕**：`@divTrunc` 结果仍是 `-9223372036854775808`、`rc=0` | `ArithmeticError: Division of PHP_INT_MIN by -1 is not an integer` | `if (b == -1 and a == std.math.minInt(i64))` ⇒ `throwThrowable("ArithmeticError", …)`；★不硬编码字面量（`std.math.minInt(i64)` 正是 `:494` 登记 `PHP_INT_MIN` 用的同一表达式） |
| 正常位（对照） | `intdiv(PHP_INT_MAX,1)`／`intdiv(-9223372036854775807,3)`／`intdiv(±10,3)` | 与 AOT **逐字节全等** | 未触碰（⇒ 回绕守卫没有误伤正常商） |
| `PHP_INT_MIN/MAX/SIZE` 本身 | 与 PHP 全等（`-9223372036854775808`／`9223372036854775807`／`8`） | 同 | ⇒ AOT 的 PHP 可见 int 面是 **i64**（虽然 `Value` 装箱是 int48，`:2391-2392`），故守卫基准取 i64 min 正确 |

### 32.2 ★否证：门 Y 的「y7 = 同族已正确的先例」是 **printf 转义**造成的假绿

| 环 | 证据 |
|---|---|
| 噪音 | 门 Y 修前首跑 stderr 就有一行 `line 48: printf: \`% 0': missing format character`——我先前把它当无害噪音，读数照收 |
| 生成物实文 | 复现该臂的 printf 序列 ⇒ 探针主体是 `<?php\ntry { 1 ; echo "Y7=RET\n"; }`：**`% 0` 整段被吞**，取模从未执行 |
| 后果 | 该臂永远 SAME ⇒ 「`%` 零除已是正确先例」这条写进门头与工单 §29.10 的结论**从未被实测支撑** |
| 修法 | 表达式发射统一走单一转义口径 `printf '%s' '<expr>'`（本门 10 枚表达式臂全改），并在门头写下禁混用两种口径 |
| 修后读数 | 仅修转义、未动模板时 = `same=2 diff=8 zig_escape=2 compile_fail=2` ⇒ 与 R-155 档的**唯一差值就是 y7 由假绿转真红**，其余逐臂同值（规则 34：带证据更正，不悄悄改档） |

★**F-40 的同一家族再添一枚**：`printf` 的格式串里出现裸 `%` ⇒ bash 报错并**静默截断**，产物仍合法（PHP 语法没错）⇒ `php -l` 预检与「输出非空」预检都抓不到。**How to apply**：任何由 shell 生成的探针，建门轮必须回读一枚生成物实文核对预期表达式在不在；门脚本自身 stderr 的非零噪音行一律当缺陷查。

### 32.3 ★F-45 新立（实测，未修）：**结果被丢弃**的可抛出算术语句被 DCE 整条消除

四格探针（`/tmp/f45p/st.php`，同一文件内顺序四句）实测：

| 语句 | PHP | AOT 默认档 | AOT `--aot-disable-pass=dce` | AOT `--aot-max-iterations=0` |
|---|---|---|---|---|
| `1 % 0;`（结果弃用） | `CAUGHT DivisionByZeroError` | **`RET`（无异常）** | `CAUGHT DivisionByZeroError` | `CAUGHT DivisionByZeroError` |
| `1 / 0;`（结果弃用） | `CAUGHT DivisionByZeroError` | **`RET`（无异常）** | `CAUGHT` | `CAUGHT` |
| `intdiv(1, 0);`（结果弃用） | `CAUGHT DivisionByZeroError` | `CAUGHT`（★本批 R-159 修好后） | `CAUGHT` | `CAUGHT` |
| `$x = 1 % 0;`（结果使用） | `CAUGHT DivisionByZeroError` | `CAUGHT` | `CAUGHT` | `CAUGHT` |

⇒ 归因（A/B 双支独立复证）：**DCE 的「无副作用」谓词不看「该运算能否抛出」**，于是把 `.mod`/`.div` 这类结果寄存器为死的指令整条删掉 ⇒ 应抛的可捕获异常消失。四格矩阵同时给出边界：**只有「结果弃用」+「运算在模板里以纯 binop 发射」的交集才中招**（`intdiv` 是 call、被保留；赋值形结果活、被保留）。

| 项 | 内容 |
|---|---|
| 定级 | P1（静默错语义、非崩、非内存不安全；但属「合法 PHP 的行为被消除」） |
| 语料面 | ★**不给正则分母**：我试的「结果被丢弃的除法/取模语句」粗正则命中 1075 行，属**过匹配**（把数组下标、跨行表达式、字符串内斜杠全算进去）⇒ 该数字作废、禁引用。正确口径需 IR 侧计数（死寄存器 ∧ `.div`/`.mod`）或逐形实测，留待 F-45 归因轮 |
| 修法候选 | 甲 DCE 的 purity 判定加「可抛出性」（`.div`/`.mod`/`intdiv` 等一律视为有副作用）⇒ 少删指令＝**编译器优化损失**，按宪法 §六.7 须老铁点头；乙 仅在语句位（结果弃用）保留这类指令 ⇒ 面更小、非语句位仍可删 |
| 本批不动的理由 | 规则 31（一臂一缺陷、一批一层）＋本批是纯模板收口，F-45 在 `optimizer` 侧需重建与全链 ⇒ 分开排 |

### 32.4 门 Y 改档与链缺口

- 门 Y 现行判读（R-159 定档）：**12 形 `same=4 diff=6 zig_escape=1 compile_fail=2 bad_probe=0`** @44s；注册红 = `y2 y4 y7 y8 y9 y10`，`cf` = `y1 y3`；`zig_escape` 是与 same/diff **正交的旗标**（数输出含 `error: ` 的臂 ⇒ 桶和须等于 12 才是自洽读数）。
- ★**链缺口修补**：门 Y 自 R-155 建成后**从未进过验收链**（R-155/R-156/R-158b 三条链的腿表里都没有 Y）⇒ 本批起把 Y 作为永久腿并入链（R-159 链 20 腿）。
- 落地复跑的逐臂变化：`y5 DIFF→SAME`、`y6 DIFF→SAME`（本批目标），其余 9 臂逐枚同值；守卫 `g1 g2` 恒绿。

### 32.5 ★资产事故与复原（必须留档，不作静默修补）

| 环 | 事实 |
|---|---|
| 事故 | 我在追加 §32 之后执行了一条**误写的命令** `rm -f <fragment> md5 -q <脚本>` ⇒ `rm` 把门 Y 脚本路径当参数吃掉 ⇒ `fuzzy_scripts_720/tmp/c024_zig_error_escape_tmp.sh` **被删除**。该脚本未入库（`?? ` 未跟踪），无 git 副本 |
| 未受损 | 门 Y 的 TSV 表身 `c024_zig_error_escape_tmp.tsv`（11:05 那次真跑的输出）与所有已入工单的读数都还在 ⇒ 有**复验基准** |
| 复原方式 | 按本会话内逐段读到的原文（`sed -n` 的 10-22 / 30-48 / 48-60 / 60-95 行区间）+ 同名旧代次脚本模板重建；**未凭记忆新写判据** |
| 复验 | 先 `cp -p` 快照旧 TSV ⇒ 重跑重建门 ⇒ 用 python 逐臂解析记录做字段比对 ⇒ **`diff` 结果除 `ELAPSED` 外完全为空（TSV_IDENTICAL_EXCEPT_ELAPSED）**，12 臂桶值与表身文本逐一等值 |
| 重建期发现的两处口径漂移（已当场更正并留证） | ① `zig_escape` 旗标：重建首跑给到 **5**，因为子串匹配 `"error: "` 把 PHP 自己的 `PHP Fatal error:  Uncaught …` 也算成外逸 ⇒ 改成**行首锚定** `^error: [A-Za-z]`（Zig 默认处理器的形态），复验回 **1**。② `norm`：重建首版用了 `/^Stack trace:/,$d`（从首个 Stack trace 删到**文件末尾**），把第二份回显与 `#0 {main}` 帧一并删掉 ⇒ 桶值虽同、表身文本与工单 §29.10 引用的读数**不可逐字节比对** ⇒ 改回「剥 `PHP Fatal error:`/`Fatal error:` 前缀、只删 `Stack trace:` 单行与 `thrown in …` 行、保留帧行与空行」 |
| 终稿 | 门 Y 脚本 md5 **`89cd0ef91e1ad7a3348c9579e07b476a`**（旧值随脚本删除一并作废，无法再核对；★从此脚本必须入库，见下） |
| 教训（入记忆） | ① `rm -f` 的**参数列表**里绝不能混进「本不想删的路径」——组合命令里 `md5 -q` 这类词被 `rm` 吞成文件名是典型形态；删除类命令前置 `ls`/`echo` 打印将要删除的参数，或分两条命令。② 永久门脚本长期 `?? 未跟踪` 是**资产流失风险面**（本仓已有 `AOT-PROC-001` 记 gitignore `test_*` 的同类事故）⇒ 所有 `fuzzy_scripts_720/tmp/c0*_tmp.sh` 门脚本应在首次定档后即入库。③ 重建后的门必须用**旧表身**做逐臂字段比对，而不是只看汇总 DONE 行数字（数字同值 ≠ 表身同值）。 |

### 32.6 ★锚点漂移登记（本批在 `runtime_lib_template.zig` 内插入 10 行所致）

本批于 `:12802-12811`（`php_intdiv` 两枚守卫的注释与语句）插入 10 行 ⇒ **模板文件内 `:12811` 之后的所有锚点一律 +10**。工单内**历史读数所记的行号按当轮代次保留、不改写**，换算表如下（★行号已按 R-159 代次逐枚 grep 复测，非推算）：

| 符号 / 锚点文本 | R-156 代（旧记） | R-159 代（现值） | 用途 |
|---|---|---|---|
| `php_intdiv` 函数体 | `:12799`（旧 §30.8 记 `:12802` 为 `return error.DivisionByZero` 行） | `:12799`（守卫后函数体扩到 `:12816`） | F-37 站点 |
| `// Register standard PHP exception subclasses (flat: extends Exception)` | `:14758` | **`:14784`** | F-30「Exception 平铺」证据 |
| `// Error extends Exception in our implementation for simplicity` | `:14781` | **`:14808`** | ★F-30 根行 |
| `oob_meta.parent = meta; // simplified: parent = Exception` | `:14803` | **`:14831`** | F-30 第三处 |
| `DivisionByZeroError` 的 ClassMeta 登记注释 | `:14843` | **`:14853`** | 本批 F-37 依赖（异常类已存在 ⇒ 无需新登记） |
| `pub fn toString(self: *PHPObject, …)` | `:19437` | **`:19449`** | ★F-32 根行（fail-open 返类名） |
| `pub fn throwThrowable(class_name, message, allocator) !Value` | `:20827`（★该值记于**更早代次**（RUNTIME-002 轮），其间的累计漂移**不由本批 +10 解释**） | **`:21871`**（R-159 代实测） | F-37 使用的抛出入口；⇒ 旧跨代换算表不可复用，引用它须重 grep |

⇒ 换算规则：**凡引用 `runtime_lib_template.zig` 的 `:12811` 之后行号，R-159 代一律 +10**；`native_linker.zig`（`:18020`/`:18033`/`:4311` 等）与 `optimizer.zig`/`ir_generator.zig` 的锚点**不受本批影响**（本批未动这三个文件；`optimizer.zig` 的 +29 漂移见 §31.10）。

## 33. R-160 备料轮（2026-10-14，只读，零 `src/` 改动）：F-41「内置函数必填参数数」的三表对照 ⇒ **两张候选真值表都不可直接使用**

### 33.1 新建永久普查门 **ARITY**（`c029_arity_census_tmp.sh`，md5 **`a85c9e1ff07fe319a45fa2cb3f707652`**，表身 `c029_arity_census_tmp.tsv`）

★抽查行（表身实测，供后续复算）：`array_merge REFL min=0 total=1 variadic fn_table=Y`／`implode REFL min=1 total=2 fixed fn_table=Y`／`parse_str REFL min=2 total=2 fixed fn_table=Y`／`echo NO_PHP fn_table=Y`（★`fn_table` 连 `echo`/`print` 这类**语言构造**也当函数登记 ⇒ 它并非纯函数表）／`php_deref NO_PHP fn_table=N`。

★与其余门不同：**本门不调 AOT**（纯静态抽取 + 纯 PHP 反射）⇒ 允许在验收链跑动期间执行（规则 35/46 的例外面）。

建门轮读数（2026-10-14，`reflect_rc=0`）：

```
ARITY_DONE builtin_map_names=464 in_fn_table=299 missing_from_fn_table=165 php_reflected=412
           php_no_such_func=52 php_minargs_ge1=354 ge2=112 variadic=21 sample_msg=10
```

| 计数 | 值 | 含义 |
|---|---|---|
| `builtin_map_names` | **464** | 与门 B 的 `distinct=464` 互证 ⇒ 抽取口径正确 |
| `in_fn_table` / `missing_from_fn_table` | **299 / 165** | ★`src/runtime/fn_table.zig`（自称 SSOT）**覆盖不到 36% 的 AOT 内置名** |
| `php_reflected` | **412** | 464 枚里 PHP 侧确有此函数并可反射的枚数 |
| `php_no_such_func` | **52** | ★**F-43 的族谱定量**：AOT 登记成「可调用内置」而 PHP 无此名 ⇒ 含语言构造 `echo`/`print` 与内部 helper `php_deref`/`php_ref_assign`/`php_ref_assign_ptr`/`php_new_object_dynamic`/`preg_match_with_matches`/`php_array_get_ref` 等 |
| `php_minargs_ge1` / `ge2` / `variadic` | **354 / 112 / 21** | arity 守卫的**理论覆盖面**（≥1 必填的枚数）⇒ F-41 不是冷门面 |

### 33.2 消息文本公式（抽样 10 枚真调用实测，非推算）

| 样本 | 反射 min | PHP 消息 |
|---|---|---|
| `strlen()` | 1 | `ArgumentCountError: strlen() expects exactly 1 argument, 0 given` |
| `intdiv()` | 2 | `…intdiv() expects exactly 2 arguments, 0 given` |
| `array_pop()` | 1 | `…array_pop() expects exactly 1 argument, 0 given` |
| `json_decode()` | 1 | `…json_decode() expects at least 1 argument, 0 given` |
| `substr()` | 2 | `…substr() expects at least 2 arguments, 0 given` |
| `str_replace()` | 3 | `…str_replace() expects at least 3 arguments, 0 given` |

⇒ **公式（全部由实测归纳，禁写死单函数消息）**：`ArgumentCountError: <name>() expects <exactly|at least> <min> argument(s), <given> given`
- `exactly` ⇔ `min == total ∧ !variadic`；`at least` ⇔ 其余
- 单复数随 `min`（`1 argument` / `2 arguments`）
- ★反例校核：`array_merge()`（反射 min=0）真调用 **不报错** ⇒ min=0 的函数不得进守卫名单，否则造出 over-reject（与 010 门 H2「过度宽容」同类，方向相反）

### 33.3 ★否证「复用 `fn_table` 就行」：它既不全也不准

同表对照（`fn_table` 的 `min_args` vs PHP 反射必填数，可对照 292 枚）⇒ **10 枚不一致**，其中 4 枚已用**真调用**复证（反射与运行时消息同向）：

| 函数 | `fn_table` | PHP 反射 | 真调用实测 |
|---|---|---|---|
| `array_merge` | min=1 max=255 | min=0 variadic | `array_merge()` ⇒ **无错**（fn_table 高估） |
| `array_push` | min=2 max=255 | min=1 variadic | — |
| `array_diff` | min=2 max=255 | min=1 variadic | `array_diff()` ⇒ `expects at least 1 argument, 0 given` |
| `implode` / `join` | min=2 max=2 | min=1 total=2 | `implode()` ⇒ `expects at least 1 argument, 0 given` |
| `parse_str` | min=1 max=2 | min=2 | `parse_str("a=1")` ⇒ `expects exactly 2 arguments, 1 given`（fn_table **低估**） |
| `mktime` | min=0 max=6 | min=1 | `mktime()` ⇒ `expects at least 1 argument, 0 given` |
| `get_class_methods` | min=0 max=1 | min=1 | `get_class_methods()` ⇒ `expects exactly 1 argument, 0 given` |

⇒ 结论（决定 R-160 形态）：**两张候选表都不能直接当 AOT arity 真值** —— `fn_table` 缺 165 枚且 10 枚与 PHP 冲突；`builtin_map` 本身不带 arity 字段。而 AOT 侧已有 arity 数据模型（`ir.zig:226-227` `Method = { param_count, required_params }`、`:1203-1204` `ClosureNewOp` 同）⇒ **缺的只是内置函数那一份真值**。

### 33.4 待老铁裁决的三型（我不动代码）

| 型 | 内容 | 影响面 | 落地成本 |
|---|---|---|---|
| **甲** | **就地修 `src/runtime/fn_table.zig`**：补齐 165 枚缺失 + 更正 10 枚冲突，AOT 侧 `@import("runtime")` 复用（★可行性已核：`src/main.zig:12 const aot = @import("aot/root.zig")` ⇒ `src/aot/*.zig` 编在 **exe 根模块**内，而 `build.zig:84` 已给根模块 `addImport("runtime", runtime_mod)` ⇒ **不需要改 build.zig**；但 `src/aot/` 现有 @import 集合里从未出现过 `"runtime"`，首次引入需实测） | 单一真值源，最干净 | ★**跨模式**：`fn_table` 同时服务解释器/字节码/JIT ⇒ 按宪法 §五/§六 **必须老铁明示**；成本＝补 165 枚（可由反射脚本生成候选，仍需逐枚核） |
| **乙** | **AOT 侧新建 arity 表**（由 PHP 反射生成、入库为 AOT 专用），只给直调快路径用 | 零跨模式风险 | 低-中：两张表并存 = 违 DRY，且 36% 覆盖差会**永久分叉**；需在建表注释里写明「真值来源＝PHP 反射实测 + 生成命令」 |
| **丙** | 先只做 **arity 金丝雀**（编译期把「实参数 < 已知 min」报成显式警告/错误，名单取已反射确认的 354 枚里语料实际用到的枚数） | 语料面 0（pass/ 内内置调用实参都正确，R-156 已测） | 最低：不改任何真值表，先把「静默 Zig 编译错」变「可读诊断」；但**不解决**运行时 `ArgumentCountError` 语义（门 Y y1/y3 仍红） |

⇒ 我的推荐：**丙 → 甲**（丙先把红面显性化，甲再一次性收真值源），但甲跨模式，**等老铁明示后才动**。

### 33.5 本轮另两枚顺手实测（只登记，未修）

1. ★`fn_table` 有 79 枚名字不在 AOT `builtin_map`（如 `array_change_key_case`、`array_first`、`array_last`、`bit_and`/`bit_or`/`bit_shift_*`）⇒ 与 `php_no_such_func=52` 合起来说明**两张名单的方向性缺失**：AOT 有表没有 × PHP 有表没接。
2. ★`debug_zval_dump` 的 variadic 口径与反射不一致（`fn_table` 记 `max=255`，反射非 variadic）⇒ 若走甲型，这一枚要单独核。

### 32.7 R-159 验收链读数（20 腿，11:15:25→12:22:32，**4027 s**；链首尾 `bin_md5=b71f9f41…`、`tpl_md5=6d520849…` **双双同值** ⇒ 纯模板批未换代次）

| 腿 | 读数 | wall | 判定 |
|---|---|---|---|
| buildtest | rc=0 | 4 s | 缓存档（与 R-156/158b 的 5s/8s 同量级） |
| **Y（首次入链）** | `shapes=12 same=4 diff=6 zig_escape=1 compile_fail=2 bad_probe=0` | 43 s | ★本批主门，与改档值等值；红集 `y2 y4 y7 y8 y9 y10` + `cf` `y1 y3` |
| ZFACES | `shapes=10 same=9 diff=1 dangling=0 compile_fail=0 bad_probe=0` | 38 s | 等值 R-158b 档（本批零触碰） |
| ZCENSUS | `total=68 dangling=0 ok=68 other=0` | 814 s | 等值（★跨 run 自证：与修前普查同值，且模板批不影响 IR 合法性） |
| X / V / W / T | `9→8/1` @42s ／ `29→19/10` @126s ／ `20→7/13` @76s ／ `22→16/5 cf=1` @91s | — | 全部等值注册档 |
| P | `78 same=73 diff=5 cf=0` | 320 s | 等值 R-158b 改档（红 `v2 i1 i2 f12 f34`） |
| S / M / N / O / D8 / Q / R | `47 diff=0` ／ `19 red=0` ／ `7/7` ／ `6/6` ／ `defect_red=0 guard_same=14` ／ `same=5` ／ `same=8 diff=1 terminate_lost=0` | — | 全等值 |
| U | 列聚合（无 DONE 行） | 210 s | 与 R-158b 代同值 |
| B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` | 2 s | ★`entries`/`distinct` 未变 ⇒ 「改函数体不动签名」确实零地图漂移；`distinct=464` 同时**互证 ARITY 普查的门 B 口径** |
| regression | `Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 全 0 / Skip 1`；`## 失败明细` 仅 `f004 … SKIP` | 794 s（报表 mtime 12:05:09） | 零回归、回收 0 枚（语料 `intdiv(` = 0） |
| shadow | `total=68 same=0 diff=68 miss=0 invalid=0` | 1043 s | 对照冻结前缀，无 miss/invalid |
| shadowcol | `gen=r159 rows=68 col_md5=f19fb070ba1b86c34f02b3883de8e4dd`＝r158b 列同值 ⇒ `changed_rows=0 col_identical=yes` | — | ★自 r148b 起**第 8 代同值**；★但按规则 29，影子不哈希 `runtime_lib.zig` ⇒ 本批运行面证据是 **门 Y + 语料计数 0**，不是影子 |
| 残留 | 各腿 `repo_build_residue=0`；`.php` 原件零删除 | — | 合规 |

### 32.8 ★老铁裁决（2026-10-14，同轮记录，后续各批以此为前提）

| 项 | 裁决 | 排期含义 |
|---|---|---|
| **F-41 arity 真值来源** | **丙 → 甲 两步走** | R-160 ＝ 丙（编译期 arity 金丝雀，把静默 Zig 编译错变可读诊断，不改真值表）；后续一轮 ＝ 甲（就地补齐/更正 `src/runtime/fn_table.zig` 的 165 缺失 + 10 冲突并让 AOT `@import("runtime")` 复用）。★甲跨解释器/字节码/JIT 三模式 ⇒ 甲开工前先把「改表对其他模式的行为影响」量出来再动，不擅改运行面 |
| **F-45 DCE 消除可抛出语句** | **乙：仅语句位保留** | 只对「结果未被使用（语句位）」的 `.div`/`.mod` 等保留指令，非语句位仍可正常删除 ⇒ 性能损失面最小；先决条件＝IR 侧「死寄存器 ∧ 可抛 binop」分母实测（原粗正则 1075 行过匹配已作废） |
| **门脚本入库** | **暂不提交，保持现状** | 我**不执行任何 `git add`/`commit`**（源码、门资产、文档均不提交），等老铁明说「提交」；误删风险期继续靠「改判据前先 `cp -p` 快照 TSV」自保 |

### 33.6 ★F-45 分母的三次尝试：前两枚**静态启发式全部作废**，改用端到端差分（永久门 AB）

| # | 量法 | 读数 | 判定 |
|---|---|---|---|
| ① | 粗正则 `^[^=;]*[/%][^=;]*;$` | 命中 **1075** 行 | **作废（过匹配）**：数组下标 `$a[1/2]`、跨行表达式、字符串里的斜杠（`sprintf('%4d')`）、注释全算进来 |
| ② | 门 STMT（`c030_stmt_raise_census_tmp.sh`，PHP `token_get_all` 切语句 + 深度 0 判 `/`/`%`） | 命中 **2** 行（f045、f135） | **作废（假阳性）**：实为 `return (int)(($doy - 1) / 7) + 1;`／`return $x % $M;` 这类 **return 形（结果被使用）**，切分器把整个 `class …{…}` 当一条语句 ⇒ 深度跟踪错。⇒ 门 STMT 保留作**反面教材**，其读数禁引用 |
| ③ | **门 AB**（`c031_dce_ab_gate_tmp.sh`）：同一份 PHP 分别用默认档与 `--aot-disable-pass=dce` 编译并运行，比对**输出与 rc** | 建门轮读数＝**待本门跑完后追加到 §33.6 末**（跑动中，禁预估） | ★**不依赖任何静态启发式**，直接量「DCE 有没有改变可观察行为」⇒ 这才是 F-45 的语料暴露面 |

★**门 AB 的自检（先证门能探测到，再谈它的 0）**：合成三形跑同一门 ⇒
| 探针 | 形态 | 门读数 | 手工对照 |
|---|---|---|---|
| `pos0` | `$a = 6; $a / 0; echo "TAIL\n";`（结果弃用 ∧ 除数 0） | **`on_eq_off=no`** ⇒ `DIFF_BOTH_WRONG` | `--dump` 两侧实文：默认档只打 `TAIL`（异常消失）；关 DCE 打 `PHP Fatal error: Uncaught DivisionByZeroError: Division by zero` ⇒ **门确实抓得到本族** |
| `posmod` | `$a % 0;` 同位 | `on_eq_off=no` | 同上（`Modulo by zero`） |
| `neg` | `$c = $a / $b;`（结果被使用） | `on_eq_off=yes EQUAL_BOTH_MATCH_PHP` | ⇒ 不假报 |
| `pos`（除数非 0 的语句位） | `$a / $b;` | `on_eq_off=yes` | ⇒ 门的差分只在**真的抛**时才亮，符合预期 |

★`DIFF_BOTH_WRONG` 的两枚**同时**计入「两侧都不等于 PHP」是**已知且可解释**的：off 侧文本属门 Y `y4/y8/y9/y10` 那族「未捕获上报格式与 PHP 不逐字节等值」（F-39-ii），与本族无关 ⇒ 读数解读时禁把它当第二枚独立缺陷。

### 33.7 ★F-45 根因已由实文钉死（与门 AB 无关的独立证据，落地前取证）

| 环 | 实文 | 结论 |
|---|---|---|
| DCE 删除点 | `optimizer.zig:2790-2801`：`inst.result` 未被 `used_registers` 命中 ⇒ `if (!self.hasSideEffects(inst))` 就 `orderedRemove` | 语句位（结果弃用）正是这个条件的目标集 |
| **纯度谓词** | `:3239 hasSideEffects` 第 `:3243` 行**白纸黑字**：`.add, .sub, .mul, .div, .mod, .pow => false` | ★**除/取模/幂被声明为无副作用** ⇒ F-45 的根就在这枚枚举行，不在别处 |
| `hasSideEffects` 的**消费者共 4 枚** | 实测 grep：`:996`（可删/可提升判定）、`:2793`（DCE Phase 3）、`:4594`（内联器）、`:5278`（LICM 提升） | ★甲型（直接改谓词）会**同时**改变 LICM 与内联器的行为 ⇒ 红面与影子漂移风险远大于本族收益；乙型只在 `:2793` 加局部守卫 ⇒ 谓词与其 4 枚消费者不动 |
| 仓内已有的「可抛出」谓词 | `:3294 mayRaiseException` 列了 call/数组/属性/`cast`/`type_check`/`unbox` 等，**但不含 `.div`/`.mod`/`.pow`**；且全仓只被 `:4598`（内联器）**一枚**站点使用 | ⇒ 不复用/不扩它：改它会连带动内联器（更大红面 + 影子漂移）；本批另立局部谓词只在 DCE 站点用 |
| 发射侧是否本来就对 | 关 DCE 后 `main.zig` 的除零调用带 `hasException()` 路由并正确抛 ⇒ **发射侧无需改** | ⇒ 修复面 = DCE 一处「别删会抛的算术指令」 |

⇒ 采**乙型**（老铁已裁）的落地形状：在 `:2793` 的守卫上追加「该指令是可抛出算术（`.div`/`.mod`/`.pow`）则不删」。★语义上「结果弃用」＝「语句位」，所以乙型天然不需要新的 IR 标记；而甲型（改 `hasSideEffects`）会波及该谓词的其它消费者 ⇒ 二者在本仓的实际差集就是「改哪一枚谓词」。
★成本与风险：改 `optimizer.zig` ⇒ 重建 + 全链；**影子可能漂移**（语料里若有被删的 dead `.div`，保留后会多生成一次调用与路由 ⇒ `main.zig` 变）⇒ 落地后须先看影子 `changed_rows`，非 0 则按当代次重冻并逐枚归因（禁默认放行，规则 30）。

## 34. R-162 备料轮（2026-10-14）：F-31「`throwException` 置字符串伪异常」17 枚站点的 **PHP 真值全表**（纯只读，零 `src/` 改动，零 AOT 调用）

### 34.1 站点清单与真值（消息文本与异常类名逐枚实测，PHP 8.5.8 `/opt/homebrew/bin/php`）

| 站点（`runtime_lib_template.zig`） | AOT 现文本 | PHP 真值（类名 + 消息） | 差在哪 | 触发面实测 |
|---|---|---|---|---|
| `:2909` | `Object of class Closure could not be converted to string` | **`Error`**：`Object of class Closure could not be converted to string` | ★**文本全等**，只错在「伪异常字符串 ⇒ catch 永不命中」＋未捕获时类名打不出 | `(string)$closure` |
| `:5405`、`:5425`、`:5531`、`:5560` | `Only arrays can be unpacked` | **`TypeError`**：`Only arrays and Traversables can be unpacked, int given`（`...$"abc"` ⇒ `…, string given`；`...$null` ⇒ `…, null given`） | ★**类名与文本都错**，且缺「实际类型」尾巴 | `function f(...$a){}` 以 `f(...$x)`（`x` 为 int / string / null） |
| `:5554`、`:5585` | `Call to a member function on null` | **`Error`**：`Call to a member function go() on null` | ★缺**方法名**；且 `$b=false; $b->go()` 的尾巴是 `on false` 不是 `on null` ⇒ 类型词也得跟着算 | `null->go()` / `false->go()` |
| `:5557`、`:5588` | `Method name must be a string` | **`Error`**：`Method name must be a string` | ★**文本全等**（同 `:2909`，只差伪异常本身） | `$o->{7}()` |
| `:5591` | `Arguments must be an array` | 同 unpack 族：`TypeError: Only arrays and Traversables can be unpacked, <type> given` | ★AOT 用的是 **PHP 5 时代的旧文本**，PHP 8 已换措辞与类名 | 变参展开路径的第二枚站点 |
| `:5599` | `Cannot find class metadata` | PHP **无此文本**（内部态） | ⇒ 落地时应换成 `Error` 的真实措辞或直接归入 undef 族 | 元数据缺失（AOT 内部条件） |
| `:5600` | `Call to undefined method` | **`Error`**：`Call to undefined method stdClass::nope()` | ★缺 `类名::方法名` | `$o->nope()`（`stdClass`） |
| `:21242` | `Cannot access self:: when no class scope is active` | **`Error`**：`Cannot access "self" when no class scope is active` | ★AOT 写 `self::`、PHP 写 `"self"`（带引号无冒号） | `self::VAL` 在类外 |
| `:21247` | `Cannot access parent:: when no class scope is active` | **`Error`**：`Cannot access "parent" when no class scope is active`（★实测） | 同 `:21242`（只差引号形态与 `::`） | `$x = parent::Y;` 在类外 |
| `:21250` | `Cannot access parent:: when current class has no parent` | **`PHP Fatal error: Cannot use "parent" when current class scope has no parent`** | ★动词错（`Cannot access` → **`Cannot use`**）+ 名词形态错（`parent::` → `"parent"`）+ `current class has no parent` → `current class scope has no parent` | `class A { static function f(){ return parent::f(); } } A::f();` |
| `:21256` | `Cannot access static:: when no class scope is active` | **`Error`**：`Cannot access "static" when no class scope is active`（★实测） | 同上；⇒ 三枚合成一条规则：**`Cannot access "<kw>" when no class scope is active`**，AOT 系统性多写了 `::`、少了一对引号 | `$y = static::Y;` 在类外 |
| `:21262` | 变量消息 | 逐枚决定 | — | 转发点 |
| `:5599`/`:21262` 之外的回调族 | — | `call_user_func(7)` ⇒ **`TypeError`**：`call_user_func(): Argument #1 ($callback) must be a valid callback, no array or string given`；`array_map("nope_fn",[1])` ⇒ **`TypeError`**：`array_map(): Argument #1 ($callback) must be a valid callback or null, function "nope_fn" not found or invalid function name` | ⇒ 这两族的消息**带函数名与参数名**，`throwException` 的静态字符串根本装不下 ⇒ 属 F-31 的「需要新参数」子集 | 实测 |

### 34.2 落地前必须先定的两件事（我这轮**没有**动代码）

1. ★**伪异常 → 真对象的改造面**：`throwException:21864` 现在做 `Value.initString(msg)` + `setException` ⇒ `catch` 永不命中、未捕获时类名固定错。改成 `throwThrowable(class, msg, allocator)`（该函数已在 `:21871` 存在且被大量使用）即可，但**每枚站点的类名不同**（`Error` vs `TypeError`），且若干站点需要**运行时上下文**（方法名、类名::方法名、实际类型名、参数名）⇒ 需要给这些站点传参，改造面是「17 枚站点 + 其调用者签名」，不是单点。
2. ★**与 F-30 的耦合**（禁混判，规则 31）：`TypeError`/`Error` 在 PHP 8.5 **不再**是 `Exception` 子类，而本仓 `:14808`（★R-159 后行号，旧 `:14781`）仍写作 `Error extends Exception in our implementation for simplicity` ⇒ 若先修 F-31，探针会从「catch 不到」变成「`catch (Exception)` 误接」⇒ **两类红都可能出现**。⇒ 排期上 **F-30 必须先于或同批于 F-31**，否则 F-31 的验收判据无法固定（这条正是 R-151「必须先修 F-27 才允许 F-26 留在树上」的同构情形）。

### 34.3 语料暴露（规则 41）

`throwException` 的 17 枚站点全部位于**错误路径**（unpack／动态调用／无类作用域），pass/ 语料内这些形全绿 ⇒ 暴露 0；★但**这不代表无缺陷**——门 P/T/V/W/X/Y/Z 的输出面判据只能看见「语料里跑得对的」，看不见这些错误路径 ⇒ 需要为 F-31 单独建永久门（拟名**门 FB**：break/dynamic-call/unpack/backtrace 错误路径族），且**先建门取修前红集，再动代码**。

## 35. R-161（2026-10-14）：F-45 落地轮 —— 守卫集**按实测收窄到 `.div/.mod`**，`.add/.sub/.mul` 另立 F-45-ii

### 35.1 门 F45FACE 修前登记（bin `b71f9f41…`，13 形，`c032_f45_face_tmp.tsv`）

★判据是 **`on_eq_off`**（DCE 有没有改变行为），不是「与 PHP 等值」——后者另有独立缺陷面。

| 形 | 面 | 修前读数 | on_eq_off | 与 PHP | 归因 |
|---|---|---|---|---|---|
| p01 `$a=1; $a / 0;` | 未捕获除零 | `DIFF_BOTH_WRONG` | **no** | no | F-45 |
| p02 `$a=1; $a % 0;` | 未捕获取模零 | `DIFF_BOTH_WRONG` | **no** | no | F-45 |
| p03 `$a=1.0; $a / 0.0;` | ★float 也抛（否证我「浮点除零返 INF」预设） | `DIFF_BOTH_WRONG` | **no** | no | F-45 |
| p04 `$x=0; $a=7; $a / $x;` | 变量实参版 | `DIFF_BOTH_WRONG` | **no** | no | F-45 |
| p05 `try{$c = 1/0;}catch` | 控制臂（结果被使用） | `EQUAL_BOTH_MATCH_PHP` | yes | **yes** | ⇒ 修复不扩大行为面 |
| p06 `$a=0; $a ** -1;` | PHP 只给 **Deprecated** | `EQUAL_BOTH_RED` | yes | no | 独立型（诊断未实现），★不入本面 |
| p07 `$b=strlen("xy")-2; $a / $b;` | ★零由**运行时算出**（排除常量折叠说） | `DIFF_BOTH_WRONG` | **no** | no | F-45 |
| p08 零次循环内 `$a / 0;` | ★**LICM 对偶风险守卫臂** | `EQUAL_BOTH_MATCH_PHP` | yes | **yes** | 保住指令不会被提升到循环外造出假异常 |
| p09 `try{1 % 0;}catch` | 可捕获取模 | `DIFF_DCE_SIDE_WRONG` | **no** | no(on)/**yes(off)** | ★off 侧与 PHP **逐字节等值** ⇒ 落地即完全收敛 |
| p10 `try{1 / 0;}catch` | 可捕获除法 | `DIFF_DCE_SIDE_WRONG` | **no** | no/**yes** | 同上 |
| p11 `try{$a + 1;}catch`（`$a="abc"`） | 算术 TypeError | `DIFF_BOTH_WRONG` | **no** | no/**no** | ★**F-45-ii**：AOT 消息文本对但 **try/catch 接不住**（Zig error 外逸 ⇒ F-39 族） |
| p12 `try{$a * 1;}catch` | 同上 | `DIFF_BOTH_WRONG` | **no** | no/no | F-45-ii |
| p13 `$a=[]; $a % 1;` | 数组操作数 | `EQUAL_BOTH_RED` | yes | no | ★**F-46**（两臂都不抛 ⇒ 与 DCE 无关，是操作数类型检查缺数组） |

计数（由 13 行明细逐行数得）：**`on_eq_off=no` 共 9 枚**＝p01 p02 p03 p04 p07 p09 p10 p11 p12；**`on_eq_off=yes` 共 4 枚**＝p05 p06 p08 p13。
★**本门自己的 `F45FACE_DONE` 行没有打印** —— 我在该门跑动期间又去改它的头部注释（第 14 臂与 p11/p12 语义），bash 按字节偏移惰性读脚本 ⇒ 汇总块被截成 `syntax error near unexpected token )`（规则 48(a) 的现形）。⇒ 明细可信（崩溃前已写盘），汇总行不可信，本表按明细重算。
★p14（加宽集的 LICM 守卫臂）是登记之后补的，其修前态已用 `--aot-disable-pass=dce` 单独实测：只打 `TAIL`，与 p08 同结论。
★**落地后的预测判据（本批守卫集只含 `.div/.mod`）**：9 枚 lost 应剩 **2 枚**（p11/p12，按 §35.2 属 F-45-ii 不计收口），preserved 由 4 → **11**；p09/p10 还要额外满足「与 PHP 逐字节等值」。对不上即为落地不彻底，禁按「大部分转绿」放行。

### 35.2 ★由 p11/p12 得出的**收窄决定**（这条是本批真正的判断，不是照单全收）

- 我一度把守卫集加宽到 `.add/.sub/.mul`（因为它们遇非法操作数也抛 `TypeError: Unsupported operand types: string + int`，实测三形一致）。
- 但 c1/c2 对照实测：**同样的语句在 AOT 里接不住** —— AOT 打 `Fatal error: Uncaught TypeError …`（消息文本与 PHP 全等，却没进 `catch (TypeError)`），而 `.div/.mod` 的 `DivisionByZeroError` **能**被 `catch` 正确接住（`CAUGHT-DBZE|Modulo by zero` == PHP）。
- ⇒ 保住 `.add/.sub/.mul` 的效果只是「静默 ⇒ 不可捕获的 Fatal」：**不算收敛**，且给「本来靠 DCE 删掉才通过的语料脚本」新增死亡风险（违规则 30「修复不得自造回归」）。
- ⇒ 本批守卫集＝`.div, .mod`（保住即逐字节收敛，p09/p10 为证）；`.add/.sub/.mul` 立为 **F-45-ii**，排在 F-39（304 处 `return error.X` 外逸族）之后收口。p11/p12 因此只要求 `on_eq_off=yes`，**不要求等于 PHP**。
- ★同一轮排除的还有：`.pow`（PHP 8.5.8 只给 Deprecated＋INF）、位运算/移位/取负（数组操作数两臂都不抛 ⇒ 属 **F-46**，另立）。

### 35.3 落地内容与门 AB 的语料分母（★已复跑完毕，读数见 §35.6 末行与 §35.8）

- 代码改动：`optimizer.zig` DCE Phase 3 守卫 `:2793` 追加 `and !self.isRaisableArithmetic(inst)` + 新增该谓词（★**不改** `hasSideEffects` 本体 ⇒ LICM `:996`、内联器 `:4594`、CSE `:5278` 三枚消费者行为不动）。
- ★门 AB 首轮把 f119/f175 报成 `on_eq_off=no` ⇒ 逐行看差异**只有时间戳**（`05:22:51` vs `05:23:05`）⇒ 归一加 `DATETIME`/`UNIXTS` 折叠后两枚转 `equal` ⇒ **F-45 语料暴露实测为 0**；同轮 f124 的 `COMPILE_FAIL` 属**关 DCE 那侧** `error: unreachable code`（默认档正常），非基线缺陷。
- ★我自己 11 分钟前刚写下「两个门不得共用输出路径」，转头就因内层门还没接 `TSV_OUT` 而把 68 行语料表截成 2 行 ⇒ 已补内层 `TSV_OUT` 支持并整表重跑（本表读数以重跑为准，见下）。
- 语料分母（归一修复后重跑，实测）：**`AB_DONE equal=67 diff=0 dce_only_red=0 both_red=1 compile_fail=1 bad_probe=0`** ⇒ F-45 语料暴露 **0**（详表 §35.6 末行）。

### 35.4 ★修后实测（新二进制 `d824ad999d10ec232255999d8edddfad`）

**门 F45FACE（14 臂，`c032_f45_face_tmp.tsv`）**：`on_eq_off=no` 由修前 **9 → 2**，且剩下的 2 枚正是按定义**不计收口**的 p11/p12（`.add/.mul`＝F-45-ii）。逐枚：

| 臂 | 修前 | 修后 | 判定 |
|---|---|---|---|
| p01 / p02 / p03 / p04 / p07（语句位除零、未捕获） | `DIFF_BOTH_WRONG`（`on_eq_off=no`） | `EQUAL_BOTH_RED`（**`on_eq_off=yes`**，≠PHP） | ★F-45 收口（异常回来了）；≠PHP 的残余属**未捕获上报文本**面（F-39-ii，门 Y 的 y4/y8/y9/y10 同族），禁算进本面也禁当成新红 |
| **p09 / p10（可捕获形）** | `DIFF_DCE_SIDE_WRONG`（`no`） | **`EQUAL_BOTH_MATCH_PHP`**（`yes` ∧ **=PHP**） | ★**逐字节收敛**——落地前写死的硬判据，没让"只做到两侧相等"蒙混 |
| p05（控制臂：结果被使用） | `EQUAL_BOTH_MATCH_PHP` | 不变 | ⇒ 修复没扩大行为面 |
| p08 / p14（LICM 对偶风险守卫臂：零次循环内 `$a / 0;`、`$a + 1;`） | `EQUAL_BOTH_MATCH_PHP` | **不变** | ★保住指令未被提升到循环外造出 PHP 没有的异常（加宽前后各测一枚） |
| p06（`0 ** -1`） | `EQUAL_BOTH_RED` | 不变 | 「诊断未实现」独立型，未纳集（有意的） |
| p13（`[] % 1`） | `EQUAL_BOTH_RED` | 不变 | **F-46** 未被本批掩盖也没被误收（反面臂起作用） |

**门 Y**：`12 形 same=5 diff=5 zig_escape=1 compile_fail=2 bad_probe=0` @44s ⇒ ★注册红由六枚降为五枚 **`y2 y4 y8 y9 y10`**（**`y7` 转 SAME**），`cf` 仍 `y1 y3`。与落地前写在 §35.3 的预测逐项一致（不是事后对齐）。

### 35.5 ★本轮又抓到并修掉的三枚自造工具错（都要留档，不许静默改）

| # | 错 | 症状 | 修法 |
|---|---|---|---|
| 1 | **在门跑动期间编辑该门脚本**（规则 48(a) 现形） | bash 按字节偏移惰性读文件 ⇒ 汇总块被截成 `syntax error near unexpected token )`，`F45FACE_DONE` 整块没打印（13 行明细在崩溃前已写盘 ⇒ 明细可用，汇总行不可用） | 明细手算计数代替；此后：改判据/加臂一律在门**未跑**时做，或在链外单独重跑 |
| 2 | 汇总 awk **列取错 + `NR>1` 吃首行** | `lost` 恒 0（用 `$4` 而 `on_eq_off=` 在 `$3`）、`both_red` 少 1（`NR>1` 跳表身第一枚；本门 TSV **无表头**） | 改 `$3=="on_eq_off=no"` 等精确列匹配并去掉 `NR` 条件；表头存在与否在注释里写清 |
| 3 | 归一不折叠**时间戳**（规则 49） | 门 AB 首轮把 f119/f175 报成语料暴露，实际两臂差异**只有 `date()` 输出**（相差 14 秒） | 加 `DATETIME`/`UNIXTS` 折叠 ⇒ 两枚转 equal；⇒ 差分门的归一必须先覆盖宪法 §七.5/6/7 的「不算差异」清单 |

### 35.6 资产登记（R-161 代次）

| 资产 | md5 | 说明 |
|---|---|---|
| `src/aot/optimizer.zig` | **`ba0e0f579518908e030fc09ca994147f`** | R-161 增量 `+19/−1`（谓词 + DCE 守卫）；R-158b 的 `e720145e…` 作废 |
| `zig-out/bin/php-interpreter` | **`d824ad999d10ec232255999d8edddfad`** | 改 optimizer ⇒ 必须重建；R-158b/R-159 的 `b71f9f41…` 作废 |
| 门 AB `c031_dce_ab_gate_tmp.sh` | `17d3cbe3dd9150ccee99e2f936486c53` | 归一加时间戳折叠 + 接 `TSV_OUT`；表身 `c031_dce_ab_tmp.tsv` |
| 门 F45FACE `c032_f45_face_gate_tmp.sh` | `5eb4c077eb524764f885eddaa12f6524` | 14 臂；汇总列已修正；表身 `c032_f45_face_tmp.tsv` |
| 门 Y `c024_zig_error_escape_tmp.sh` | `1b23d3e81dc5a85b10990dc7643891b6` | R-161 改档（y7 回收 ⇒ 红集 `y2 y4 y8 y9 y10`） |
| 链 `c033_r161_acceptance_chain_tmp.sh` | `5a7471ec67a07a370c263629aa4f5bd6` | 21 腿（新增 F45FACE 腿） |
| 语料分母（门 AB 重跑，归一修复后） | 门自己打的 DONE：**`AB_DONE equal=67 diff=0 dce_only_red=0 both_red=1 compile_fail=1 bad_probe=0`**；表身 68 行 = `66 EQUAL_BOTH_MATCH_PHP + 1 EQUAL_BOTH_RED(f004) + 1 COMPILE_FAIL(f124，失败在**关 DCE 那侧**的 `unreachable code`)` | ★**F-45 语料暴露 = 0**（`on_eq_off=no` 计数 0；`diff=0`）。★两枚旁支都不是 F-45：f004 是主回归里唯一 SKIP（PHP 自身 exit=255），f124 只在关掉 DCE 时编不过 ⇒ 属"关优化"侧的既存现象 |

### 35.7 ★指令级删除站点的逐条审计（规则 39：共享谓词必须**逐链**声明入口函数 + 实测臂）

F-45 的根在 `hasSideEffects`，而这枚谓词被 4 处消费、全仓共有 **6 处** `block.instructions.orderedRemove` ⇒ 只补 DCE 一处是否够？逐条读实文 + 用门 F45FACE 的臂复证（行号为 R-161 代次实测）：

| 站点 | 所在 pass | 会不会二次犯 F-45 | 证据 |
|---|---|---|---|
| `:2798` | `eliminateDeadCodeInFunction` Phase 3 | ★**会，且就是本面** | 已加守卫 `and !self.isRaisableArithmetic(inst)`；门 F45FACE `on_eq_off=no` 由 9 → 2（剩 2 枚＝故意不收的 F-45-ii） |
| `:1095` | `optimizeLoop`（LICM）经 `removeInstructionFromBlock` | **不会**——它是**搬移**：先 `orderedRemove` 再 `pre_header.instructions.append(inst)` | 实测 p08（零次循环内 `$a / 0;`）与 p14（同形 `$a + 1;`）：默认档与 `--aot-disable-pass=dce`（＝保住指令的代理）**两侧都只打 TAIL** ⇒ 没造出 PHP 没有的异常。★但 LICM 的可提升判定 `:996` 同样走 `hasSideEffects` ⇒ 「把可抛运算提升到零次循环外」理论上是风险面，本批不改该谓词（甲型才改）⇒ 留作观察项，两枚臂常驻可抓 |
| `:2917`–`:2971`（6 枚） | `eliminateRCEllisionInFunction` | **不会**——删的是 `retain`/`release` 配对，不是运算 | 站点上下文全是 `.retain/.release`；且 `hasSideEffects` 把它们标 **true**（`:3298` 实测）⇒ 本就不进"纯"集 |
| `:4137` | `eliminateBoxUnboxInFunction` | **不会（有条件）**——只在 `box.from_type.eql(unbox.to_type)` 时消除 ⇒ 类型已匹配该 `unbox` 不抛 | 实文 `if (b.from_type.eql(op.to_type))` 后才 `replaceRegisterUsage` + 删。★记一处**谓词不一致**：`mayRaiseException:3316`（★行号已按 R-161 代复测，旧记 `:3294` 因本批插行下移） 把 `.cast/.type_check/.unbox` 列为可抛，而 `hasSideEffects` 判 false ⇒ 类型相等时不可抛，本批不动，列为观察项 |
| `:4467` | `simplifySinglePredecessorPhiNodes` | **不会**——化简单前驱 PHI（转发），不删运算 | 站点仅处理 `.phi` |
| `:4812` | `inlineFunction` | **不会**——删的是 `.call` 本身，紧接 `block.instructions.insert` 把克隆体插回 | 实文 `orderedRemove(inst_index); destroy(call_inst); … insert(…)`；★默认档 `function_inlining=false`（`:82/:132/:209`，仅 `:153` 等档 true）⇒ 语料走不到这条链（AOT-CODEGEN-007 已记） |

⇒ 结论：**本批只补 DCE 一处即闭合 F-45**（实测支持：9 枚红收 7 枚，剩 2 枚是刻意排除的 F-45-ii）。同时留下两枚**如实登记的观察项**：① LICM 提升可抛运算；② `mayRaiseException:3316` 与 `hasSideEffects:3261` 对 `.cast/.type_check/.unbox` 的口径互相矛盾。二者各自需要自己的实测臂 ⇒ 不在本批顺手改（规则 31/39）。

### 35.8 ★R-161 验收链 21 腿读数（`R161_CHAIN_START 2026-10-14 14:02:04 bin_md5=d824ad99… tpl_md5=6d520849…` → `CHAIN_END 15:09:59`，**4075 s**；首尾**二进制与模板 md5 各同值** ⇒ 链内零代次漂移）

| 腿 | DONE 行读数（实测，非预估） | wall | 判读 |
|---|---|---|---|
| buildtest | rc=0 | 6 s | 缓存档（R-156/158b/159 为 5/8/4 s 同量级） |
| **F45FACE** | `F45FACE_DONE shapes=14 raise_lost(on_eq_off=no)=2 preserved(on_eq_off=yes)=12 both_match_php=5 both_red_not_match_php=7` | 108 s | ★本批主门：`raise_lost` 与链前单跑（§35.4）**逐枚同值**＝p11/p12；`preserved=12` 且 `both_match_php=5` ⇒ p09/p10 收敛保持。★链日志该行取到的是内层 `AB_DONE`（见下方取证更正） |
| **Y** | `shapes=12 same=5 diff=5 zig_escape=1 compile_fail=2 bad_probe=0 residue=0` | 44 s | ★等值 R-161 改档：红集 `y2 y4 y8 y9 y10`（`y7` 保持 SAME）、`cf=y1 y3`、桶和 5+5+2=12 核对通过 |
| ZFACES | `shapes=10 same=9 diff=1 dangling=0 compile_fail=0 bad_probe=0` | 38 s | 等值（残红 `z2`＝F-44，未触碰） |
| ZCENSUS | `total=68 dangling=0 ok=68 other=0` | 787 s | 等值 ⇒ 保住死指令未破坏任何语料的 IR 合法性 |
| X / V / W / T | `9→8/1` @40s ／ `29→19/10` @122s ／ `20→7/13` @75s ／ `22→16/5 cf=1` @89s | — | 全部等值注册档 |
| P | `shapes=78 same=73 diff=5 cf=0 bad_probe=0` | 314 s | 等值 R-158b 档（红 `v2 i1 i2 f12 f34`）⇒ ★F-45 未把任何内省臂打红 |
| S | `shapes=47 same=47 diff=0` | 189 s | 等值（判据即 `diff=0`） |
| M / N / O | `19 red=0 green=19` @70s ／ `7 red=0` @24s ／ `6 red=0` @21s | — | 等值 |
| D8 | `shapes=14 defect_red=0 guard_same=14` | 50 s | 等值 |
| Q / R | `same=5 expect_fail=0 unexpected_fail=0` @22s ／ `same=8 diff=1 terminate_lost=0` @38s | — | 等值 |
| U | 无 `*_DONE` ⇒ 按列聚合 **75 行 = `SAME 51 / COMPILE_FAIL 22 / BAD_PROBE_PHP 2`** | 206 s | ★等值 §26.2 注册档（`51/22/2` 逐桶同） |
| B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` | 2 s | 等值 ⇒ 零地图漂移（本批不动 `builtin_map`） |
| regression | `Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 全 0 / Skip 1`；`## 失败明细` 仅 `f004 … SKIP` 一行 | 787 s（报表 mtime `14:52:37`） | 回收 0 枚、新增红 0 枚（规则 27 取明细行存在性） |
| shadow | `C010_SHADOW_DONE total=68 same=0 diff=68 miss=0 invalid=0` | 1042 s | 对照冻结前缀的常态，无 miss/invalid |
| shadowcol | `SHADOWCOL_DONE gen=r161 rows=68 col_md5=f19fb070ba1b86c34f02b3883de8e4dd` ＝ r159/r158b 列**同值** ⇒ **`changed_rows=0 col_identical=yes`** | — | ★自 r148b 起**第 9 代同值**：落地前我预留的「合法漂移」出口**没有触发**——保住 dead `.div/.mod` 在 68 语料内一次都没改变 `main.zig` ⇒ 与门 AB 的 `equal=67 diff=0`（暴露 0）互相印证，不需要逐枚归因 |
| 残留 | 各腿 `repo_build_residue=0` / `bad_probe=0`；`.php` 原件零删除 | — | 合规 |

★**规则 28 双判**：① 末腿 `R161_CHAIN_DONE`（日志第 28 行）；② 主回归报表 mtime `14:52:37` 落在该腿窗口内且晚于其开跑时刻（链首 14:02:04 + 前 19 腿 Σ2245 s = 14:39:29）。两判同时成立 ⇒ 读数可用，不是轮询假象。

★**取证方式缺陷（本轮抓到并当场修，登记不静默改）**：链脚本 `run_gate` 用 `grep … | head -1` 取 DONE 行（`c028` 起引入、`c033` 照抄），凡**门内部再套一层门**的腿（F45FACE 内嵌门 AB）就会把**内层**的 `AB_DONE` 当成该腿读数写进链日志。⇒ 已把 `c033`/`c028` 两处统一改为 `tail -1`，脚本 md5 随之作废重登（下表）；本批 F45FACE 腿的真实读数是从腿文件 `/tmp/r161_F45FACE.out` 第 2 行取回并逐枚核对的，链日志那一行只是显示层缺陷，不影响判定。

### 35.9 资产 md5 刷新（§35.6 的两行作废）

| 资产 | 旧 md5（作废） | 新 md5 |
|---|---|---|
| 链 `c033_r161_acceptance_chain_tmp.sh` | `5a7471ec67a07a370c263629aa4f5bd6` | **`f6fedf6db9d739b999048df0ba62df42`** |
| 链 `c028_r159_acceptance_chain_tmp.sh` | （未单登） | **`6fa76c2af4cfd0c19a059d4238d4e8af`** |

⇒ `src/` 侧资产未变：`optimizer.zig` 仍 `ba0e0f579518908e030fc09ca994147f`、二进制仍 `d824ad999d10ec232255999d8edddfad`、模板仍 `6d520849c9a7eab50082c62e924662dd`。R-161 至此**验收闭合**。

## 36. R-160（2026-10-14）：F-41 **丙型**落地 —— 编译失败后自解析生成码，把裸 Zig arity 错翻译成可读诊断

### 36.1 先取证：生成码到底长什么样（本轮实测，非推算）

| 形 | PHP 源 | 生成码调用点 | Zig 原始报错 | helper 签名（运行时库实文） |
|---|---|---|---|---|
| a1 | `strlen()` | `reg_0 = try runtime.php_strlen();` | `main.zig:57:24: error: expected 1 argument(s), found 0` | `php_strlen(str: Value)`＝1 |
| a2 | `intdiv(1)` | `runtime.php_intdiv(reg_0)` | `expected 2 argument(s), found 1` | `php_intdiv(dividend, divisor)`＝2 |
| a3 | `array_pop()` | `runtime.php_array_pop(runtime.runtime_allocator)` | `expected 2, found 1` | `php_array_pop(arr: Value, allocator)`＝2 |
| a4 | `substr("abc")` | `runtime.php_substr(reg_0, runtime.runtime_allocator)` | `expected 4, found 2` | `php_substr(str, start, length, allocator)`＝4 |
| a5 | `strpos("ab")` | `runtime.php_strpos(reg_0)` | `expected 3, found 1` | `php_strpos(haystack, needle, offset)`＝3 |
| a6 | `str_replace("a","b")` | `runtime.php_str_replace(reg_0, reg_1, alloc)` | `expected 5, found 3` | `php_str_replace(search, replace, subject, count_out, allocator)`＝5 |
| a12 | `implode(",")` | `runtime.php_implode(reg_0, alloc)` | `expected 3, found 2` | `php_implode(...)`＝3 |
| **a7** | `json_decode()` | `runtime.php_json_decode(&[_]runtime.Value{}, alloc)` | ★**无报错，编译通过** | 切片形参 `args: []const Value` ⇒  arity 面在**运行期**才现形 |

⇒ 发射器把 PHP 实参**按位**填进固定形参（末尾自动补 `allocator`，`count_out` 这类输出槽由发射器决定），少填就是 **Zig 硬错** ⇒ 编译产物不存在、rc=1、且报错只指生成码。

### 36.2 门 AC 修前登记（永久侧门 `c034_arity_canary_gate_tmp.sh`，12 臂 ⇒ 建门轮）

`C034AC_DONE arms=12 compile_fail=7 ran=5 same=2 diff=3 canary=0 bare_symbol=7 zig_raw_arity_err=7 bad_probe=0 repo_build_residue=0` @23 s（表身 `c034_arity_canary_tmp.tsv`，快照 `/tmp/c034_prefix_baseline_snapshot.tsv`）。
七枚 `compile_fail` ＝ **a1 a2 a3 a4 a5 a6 a12**（逐臂 `canary=no zig_raw=yes bare=yes`）；`ran=5` ＝ a7/a10/a11 三枚 `RUN_DIFF` + a8/a9 两枚 `RUN_SAME`。

★**判据是 `canary`（我们自己的诊断行），不是「与 PHP 等值」**——丙型不改变 `compile_fail` 这一事实：改变它需要 arity 真值表＝甲型。

### 36.3 ★建门轮否证了我自己的两条预估（都要留档）

1. **a12 `implode(",")` 预估为反面臂 ⇒ 实测是第七枚定长形参站点**（`php_implode` 3 形参 vs 生成码 2 实参 ⇒ `expected 3, found 2`）。
   我原先按「PHP 侧它 arity 够、只是类型不符（`TypeError`）」推它不该进本面——**发射侧的形参数与 PHP 的必填数是两回事**，
   前者才是 Zig 报错的依据。⇒ 金丝雀覆盖面由预估 6 枚升为**实测 7 枚**。
2. **「`repo_build_residue=7` ⇒ 失败编译泄漏临时目录」的怀疑被证伪**：那 7 枚全是我自己前面用 `ZIGPHP_AOT_KEEP_TEMP=1` 手工取证留下的目录
   （`deinit:1523-1531` 只在 `KEEP_TEMP` 未设时才 `deleteTree`）。清理后重跑 ⇒ `residue=0`。
   ⇒ 教训：**residue 旗标报警时先数自己留了几个**，别急着给编译器立新缺陷（本轮如果我直接登记「失败泄漏目录」就是假缺陷工单）。

### 36.4 落地内容（只动 `native_linker.zig` 的**失败分支**，`+246/−0`，不改任何生成码文本）

| 件 | 位置 | 作用 |
|---|---|---|
| 调用钩子 | `invokeZigCompilerSingleStep` 的 `.exited code != 0` 分支，`deleteStaleProduct` 之前（`:32993`） | 只在**终局编译失败**时跑；成功路径零成本（不新增读盘、不新增分支） |
| `reportBuiltinArityCanary` | `:33182` 起 | 读临时目录里的 `main.zig` + `runtime_lib.zig`，扫出「调用实参数 ≠ helper 形参数」的站点并打印诊断 |
| `collectRuntimeHelperArity` | 同段 | 从运行时库扫 `pub fn php_*(` ⇒ **形参数直接来自 Zig 的判据同源**，不建第二份真值表 |
| `scanTopLevelList` | 同段 | 括号/方括号/花括号平衡 + 字符串与注释感知的顶层条目计数；**不可靠即返回 null ⇒ 放弃这条诊断** |
| `parseEmittedSourceLocation` | 同段 | 从生成码的 `setSourceLocation("<php 路径>", N)` 游标取**用户 PHP 源码位置** |
| 反面自证 |  hits==0 时打 `AOT: 未发现…`（★**故意不带** `AOT-ARITY:` 前缀） | 门 AC 的 a13 靠这条不被 grep 命中来证明「非 arity 失败不会被误报」 |

★三条已裁口径落进代码注释（§32.8/§33.4）：① 不建 arity 表；② 不碰子进程管道（Zig 诊断照旧 inherit 透传）；③ 宁可沉默也不骗人。

### 36.5 实测输出（修后，二进制 `fe5d70d4…`）

```
main.zig:57:24: error: expected 1 argument(s), found 0
AOT-ARITY: [1] PHP 内置函数 strlen() 的调用在生成码里传了 0 个实参（已含自动补上的 allocator/输出槽），
           而运行时实现 php_strlen 声明 1 个形参 ⇒ 实参数与该实现不符，AOT 在生成码阶段就编不过
           （PHP 侧同形为 ArgumentCountError；精确必填参数数属甲型工作）｜源码 /private/tmp/r160_probe/a1.php:2
```
★措辞刻意写成「生成码里传了 N 个实参（含自动补的 allocator/输出槽）」而非「PHP 少写 N 个」——
`substr("abc")` 的诊断里 N=2 而 PHP 只写了 1 个实参，措辞若不区分就会误导用户（第一版就是这样，已改）。

### 36.6 ★覆盖面与诚实边界（丙型**不解决**的部分要写清）

| 面 | 实测 | 丙型后仍在？ |
|---|---|---|
| 直调定长形参 helper（a1..a6/a12） | 7 枚编译失败 ⇒ 现全带可读诊断 | ✅ 收口（诊断面） |
| **切片形参 helper**（a7 `json_decode()`） | 编译通过、运行期才炸 ⇒ `RUN_DIFF` | ❌ **不解决**（无 Zig 失败可挂诊断）⇒ 属甲型＋运行期守卫 |
| 用户函数/方法少传参（a10 `u()`／a11 `C13AC::m()`） | 走运行时 args 数组，`RUN_DIFF` | ❌ 不在此面（机制不同，且 PHP 消息是 `Too few arguments to function`） |
| min=0 的合法形（a8 `array_merge()`） | `RUN_SAME` | ✅ 恒绿＝过度拒绝守卫臂（若它变红即说明我把扫描写宽了） |
helper 签名登记率实测 **539/539**（`grep -c "^pub fn php_"` ＝ 539；因 `comptime/anytype/type/...` 被排除 **0** 枚）⇒ 覆盖面没有隐性折损。

### 36.7 本轮三枚工具自纠（登记，不静默改）

1. **marker 前缀会被自己的"未发现"行假亮**：负向说明行若也带 `AOT-ARITY:`，门 AC 的 `canary` 就会在任何一次无关编译失败上都计数 ⇒ 改成 `AOT:`。
2. **注释里的同名文本**：生成码每条指令前有 `// <php 文件>:<行>` 注释，扫描器若不排除注释就可能把注释片段读成调用点 ⇒ 现回退到行首，途中见 `//` 即放弃该处（只跳一字节继续扫，不漏后续真调用）。
3. **链脚本传多环境变量的坑**：`run_gate` 的第 4 参是 `env $4`（不加引号），`ONLY=a1 a2 …` 会被拆成「ONLY=a1」＋命令「a2」⇒ 直接取消 AC12 腿，改由 AC 的 13 臂 TSV **去掉 a13 行**推 12 臂口径（a13 只贡献 `compile_fail+1`、`bare_symbol+1`）。

### 36.8 R-160 验收链读数（21 腿，`16:16:30 → 17:26:23`，**4193 s**；首尾 `bin_md5=fe5d70d4…`／`tpl_md5=6d520849…` 各同值）

| 腿 | DONE 行／聚合读数 | wall | 判读 |
|---|---|---|---|
| buildtest | rc=0 | 1 s | 缓存档 |
| **AC** | `C034AC_DONE arms=13 compile_fail=8 ran=5 same=2 diff=3 canary=7 bare_symbol=8 zig_raw_arity_err=7 bad_probe=0 residue=0` | 25 s | ★**本批主判据**：`canary=7` ＝ 七枚定长形参站点（a1–a6+a12）；`compile_fail=8`＝那七枚 + a13（a13 按设计就该失败）；`zig_raw=7` 未变 ⇒ 子进程管道没被我动过 |
| F45FACE | `F45FACE_DONE shapes=14 raise_lost(on_eq_off=no)=2 preserved=12 both_match_php=5 both_red_not_match_php=7` | 106 s | ★**R-161 复证**：残红恰 2（p11/p12＝故意不收的 F-45-ii）；★本腿 DONE 行第一次直接显示外层（`tail -1` 生效） |
| Y | `shapes=12 same=5 diff=5 zig_escape=1 compile_fail=2 bad_probe=0` | 44 s | 等值注册档（红 `y2 y4 y8 y9 y10`、`cf=y1 y3`）⇒ ★丙型**不该**让 y1/y3 转绿，实测确实没转 |
| ZFACES | 链日志只打 `tsv=` ⇒ 表身聚合 `10 行 = SAME 9 / DIFF 1`（唯一红 `z2`＝F-44） | 38 s | 等值（★见下方取证更正：**`tail -1` 也不通用**） |
| ZCENSUS | 表身聚合 `68 行 = OK 68`（`dangling` 命中 0） | 824 s | 等值 ⇒ 语料 IR 合法性未受本批影响 |
| X / V / W / T | `9→8/1` @42s ／ `29→19/10` @128s ／ `20→7/13` @79s ／ `22→16/5 cf=1` @93s | — | 全部等值注册档 |
| P | `shapes=78 same=73 diff=5 cf=0 bad_probe=0` | 327 s | 等值（红 `v2 i1 i2 f12 f34`） |
| S | `shapes=47 same=47 diff=0` | 198 s | 等值 |
| M / N / O / D8 | `19 red=0 green=19` ／ `7 red=0` ／ `6 red=0` ／ `defect_red=0 guard_same=14` | 73/25/22/52 s | 等值 |
| Q / R | `same=5 unexpected_fail=0` ／ `same=8 diff=1 terminate_lost=0` | 23/41 s | 等值 |
| U | 无 `*_DONE` ⇒ 按列聚合 **75 行 = `SAME 51 / COMPILE_FAIL 22 / BAD_PROBE_PHP 2`**（★桶和=行数已核对） | 214 s | 等值 §26.2 注册档 |
| B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` | 2 s | 等值 ⇒ 零地图漂移（本批不动 `builtin_map`） |
| regression | `Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 全 0 / Skip 1`；`## 失败明细` 仅 `f004 … SKIP` 一行 | 794 s（报表 mtime `17:09:01`） | 回收 0、新增红 0（规则 27） |
| shadow | `C010_SHADOW_DONE total=68 same=0 diff=68 miss=0 invalid=0` | 1042 s | 对照冻结前缀常态，无 miss/invalid |
| shadowcol | `SHADOWCOL_DONE gen=r160 rows=68 col_md5=f19fb070ba1b86c34f02b3883de8e4dd` ＝ r161 列同值 ⇒ **`changed_rows=0 col_identical=yes`** | — | ★**落地前写死的硬判据达成**：自 R-148b 起**第 10 代同值** ⇒ 本批确实零发射改动（诊断只在失败分支）；若非 0 就说明我把守卫写进了发射路径 |
| 链尾 | `R160_CHAIN_END 17:26:23 ELAPSED=4193s` + `R160_CHAIN_DONE` | — | 规则 28 双判：DONE 行 ∧ 报表 mtime `17:09:01` 晚于该腿开跑（前 19 腿 Σ≈2331s→16:55:01）；首尾二进制同值 ⇒ 链内零代次漂移 |

★**取证更正（第 2 版，覆盖 §35.8 的口径）**：链日志的 DONE 选取 `head -1` 与 `tail -1` **都不通用**——
门 ZFACES 先打 `ZFACE_DONE shapes=…`、后打 `ZFACE_DONE tsv=…`，所以 `tail -1`（我在 §35.8 建议的修法）反而把这腿的数字吃掉了。
⇒ 正确口径＝**按内容取**：`grep -E '_DONE (shapes|arms|total)='`，取不到再回退表身列聚合。
本轮已实测：ZFACES/ZCENSUS 两腿的表身聚合与注册档逐枚同值（`10=9/1`、`68 OK`），显示层缺陷不影响判定。


链前（链外单跑）已登记的判据，与上表逐项对照：
- 门 AC 13 臂 `compile_fail=8 ran=5 same=2 diff=3 canary=7 bare_symbol=8 zig_raw_arity_err=7 residue=0` @25 s；
  链内首跑（腿 AC）**同值**；12 臂口径由 TSV 去 a13 推得＝`cf=7 canary=7 bare=7 zig_raw=7` ⇒ 与修前仅 `canary 0→7` 之差。
- 影子判据：**必须 `changed_rows=0`**（本批不改发射文本）；非 0 即说明我把改动写进了发射路径 ⇒ 回看并停止。
- 门 F45FACE / 门 Y 须复证 R-161 档（`raise_lost=2`；`same=5 diff=5 zig_escape=1 cf=2`——y1/y3 仍只是 `cf`，因丙型不改 rc）。

## 37. R-160b 备料轮（2026-10-14，只读，零 `src/` 改动）：★甲型的**前置测量**做完 —— 结论是 `fn_table` 的错值**今天就是 tree/fast 模式的活缺陷**

老铁裁「丙 → 甲」时附带条件：**甲开工前先把「改表对其他模式的行为影响」量出来**（§32.8）。本轮就是那枚测量，
并且它改写了甲型的形态：不是「再建一份 AOT arity 真值」，而是「**`fn_table` 已经被一枚中央守卫消费了**」。

### 37.1 现有机制（实文，非推测）

`src/runtime/stdlib.zig:24-47 callBuiltinFast` ⇒ `fn_dispatch.lookup(name)` → **`fn_dispatch.validateArgs(id, args.len)`** →
`TooFewArguments/TooManyArguments` 时取 `fn_dispatch.getMeta(id).?` 的 `meta.min_args / max_args` 造 `ArgumentCountError`；
`meta` 即 `src/runtime/fn_table.zig`（该文件 `:8` 自述「min_args/max_args 与 stdlib.zig 中注册的值一致」，`:46 min_args: u8`）。
⇒ **AOT 完全不经过这条链**（发射器直调 `runtime.php_X(...)` ⇒ Zig 编译期硬错）；**tree/fast 经过**；**bytecode 未经**（§37.2 证）。

### 37.2 十形跨模式矩阵（PHP 8.5.8 为真值；tree/bytecode/fast 实测；★AOT 侧本轮**未测**——链跑动中禁并发编译，规则 35）

| # | 探针 | PHP 8.5.8 | tree | bytecode | fast |
|---|---|---|---|---|---|
| 1 | `array_merge()` | ✅ 返回 `[]` | ★**ArgumentCountError**（过度拒绝） | ✅ `[]` | ★**ArgumentCountError** |
| 2 | `array_push($a)` | ✅ 返回 2 | ★ArgumentCountError | `NULL` | ★ArgumentCountError |
| 3 | `array_diff($a)` | ✅ 合法 | ★ArgumentCountError | `NULL` | ★ArgumentCountError |
| 4 | `implode($a)` | ✅ `'12'` | ★ArgumentCountError | `NULL` | ★ArgumentCountError |
| 5 | `array_unshift($a)` | ✅ | ★ArgumentCountError | `NULL` | ★ArgumentCountError |
| 6 | `parse_str("a=1")` | ★Fatal ArgumentCountError（min=2） | **放行** `true`（该拒不拒） | `NULL` | **放行** `true` |
| 7 | `mktime()` | ★Fatal ArgumentCountError（min=1） | **放行**时间戳 | `NULL` | **放行**时间戳 |
| 8 | `get_class_methods()` | ★Fatal ArgumentCountError | **放行** `false` | `NULL` | **放行** `false` |
| 9 | `str_replace("a","b")` | ★Fatal ArgumentCountError | ArgumentCountError ✅ | `NULL` | ArgumentCountError ✅ |
| 10 | `preg_match("x",$s)` | ✅（另有分隔符告警面，属门 S 族） | ✅ | ✅ | ✅ |

★**两参对照臂**（证明这些函数在三模式都**已实现**，`NULL` 不等于"未实现"）：
`implode(",",$a)`／`array_merge([1],[2])`／`array_push($a,9)`／`array_diff([1,2],[1])` ⇒ 三模式与 PHP **逐枚相同**（`1,2 / 2 / 3 / 1`）。
★附带一枚**非 arity** 的另一模式崩溃（只登记不修，属 §五.3 需明示的范围）：`fast` 模式跑该对照臂时
`panic: integer overflow  src/runtime/fast_vm.zig:763 printValue` ⇒ 新立 **F-49**。

### 37.3 结论（四条，全部由上表实测支撑）

1. **`fn_table` 的 10 枚错值不是「AOT 的远端问题」，而是 tree/fast 当前的活缺陷**：
   **5 枚过度拒绝**（#1–#5，PHP 合法的调用在 tree/fast 抛 `ArgumentCountError`）＋**3 枚该拒不拒**（#6–#8，PHP fatal 而 tree/fast 静默放行）。
   ⇒ 我原先隐含的「改表只影响 AOT」**被实测否证**。
2. **bytecode 模式完全不查 arity**：10 枚里 8 枚直接 `NULL`（两参对照臂却全对）⇒ 既不拒绝也不报错，是**第三枚独立面孔**（新立 **F-48**）。
3. **守卫的消息文本本身不合 PHP**（新立 **F-47**）：tree 打
   `Uncaught ArgumentCountError: array_merge() expects 1 arguments, 0 given in builtin:0`
   ——缺 `at least/exactly` 区分、缺单复数（`1 arguments`）、位置写死 `builtin:0`（丢源码行号）。
   ⇒ 甲型只补表不修消息，tree/fast 就从「拒错」变成「拒错但换个说法」。
4. **甲型的成本结构因此重排**：便宜路径是**让 AOT 也走同一枚中央守卫**（发射期用 `fn_table` 的 `min_args` 校验并补 `ArgumentCountError`），
   而不是再建一张表；但前置是先把表修对（§33.3 的 165 缺失 + 10 冲突），而**修表必然改动 tree/fast 行为**
   ⇒ 需老铁明示「是否一并修解释器/字节码模式」（宪法 §五.3/§六.6），我不擅改。

### 37.4 待老铁裁决的甲型三态（本轮零推进）

| 选项 | 内容 | 跨模式影响 |
|---|---|---|
| 甲‑1 | 只修表 + **只让 AOT 消费**新表（tree/fast 仍读旧值） | 零跨模式行为变化，但双表并存违 DRY，且 tree/fast 的 8 枚缺陷原地保留 |
| 甲‑2（推荐） | 修表 + tree/fast/bytecode/AOT **全走同一枚守卫** | ★一次性消 8 枚跨模式缺陷＋面 2/面 3，但**必须重冻解释器侧基线**并新开跨模式差分门 |
| 甲‑3 | 先只修 F-47 消息文本（不动 min/max） | 最小，但把「错的拒绝」留着 |

### 37.5 ★AOT 列补测完成（R-160c，资产 `r160c_aot_arity_matrix_tmp.sh`，表身 `r160c_aot_arity_matrix_tmp.tsv`）

`R160C_DONE shapes=10 compile_fail_canary=5 compile_fail_quiet=0 same=4 diff=1 bad_probe=0` @24 s。全五列矩阵：

| 形 | 探针 | PHP 8.5.8 | tree | bytecode | fast | **AOT（当代 `fe5d70d4…`）** |
|---|---|---|---|---|---|---|
| m1 | `array_merge()` | ✅ `[]` | ✗ 过度拒绝 | ✅ | ✗ 过度拒绝 | ★**与 PHP 等值**（切片形参 ⇒ 编译通过） |
| m2 | `array_push($a)` | ✅ 2 | ✗ | ✗ NULL | ✗ | ★**与 PHP 等值** |
| m3 | `array_diff($a)` | ✅ | ✗ | ✗ NULL | ✗ | ★**与 PHP 等值** |
| m4 | `implode($a)` | ✅ `'12'` | ✗ | ✗ NULL | ✗ | ✗ **编译失败**（带金丝雀，`expected 3, found 2`） |
| m5 | `array_unshift($a)` | ✅ | ✗ | ✗ NULL | ✗ | ★**与 PHP 等值** |
| m6 | `parse_str("a=1")` | ✦Fatal ACError | ✗ 放行 | ✗ NULL | ✗ 放行 | ✗ **编译失败**（带金丝雀） |
| m7 | `mktime()` | ✦Fatal ACError | ✗ 放行 | ✗ NULL | ✗ 放行 | ✗ **编译失败**（带金丝雀，`expected 6, found 0`） |
| m8 | `get_class_methods()` | ✦Fatal ACError | ✗ 放行 | ✗ NULL | ✗ 放行 | ✗ **编译失败**（带金丝雀） |
| m9 | `str_replace("a","b")` | ✦Fatal ACError | ✅ 拒绝 | ✗ NULL | ✅ 拒绝 | ✗ **编译失败**（方向对、形态错：不可捕获） |
| m10 | `preg_match("x",$s)` | ✅ `false`＋分隔符 Warning | ✅ | ✅ | ✅ | ✗ **AOT_DIFF**（见 §37.7，非 arity） |

### 37.6 ★这列数据把甲型的**顺序**钉死了（不是口径，是顺序）

1. **AOT 的拒绝面与 tree/fast 的拒绝面几乎不相交**：tree/fast 过度拒绝的 5 枚里，AOT 只对 `implode($a)` 一枚失败，
   另 **4 枚（m1/m2/m3/m5）AOT 今天与 PHP 逐字节等值**——因为那几个 helper 是**切片形参**（`[]const Value`），发射器不会少填。
2. ⇒ **「先把 AOT 接到 `fn_table` 上」会当场把 4 枚绿形变成红**（违规则 30「修复不得自造回归」）。
   所以甲型的**唯一安全顺序**是：**先修表的 165 缺失 + 10 冲突，再谈让谁消费它**；§37.3-4 那句「前置是先把表修对」由推断升为**实测**。
3. AOT 该拒而拒得不对的 4 枚（m6–m9）＝「PHP 是可捕获 `ArgumentCountError`，AOT 是无产物编译失败」⇒ 甲型真正的**收敛证据**必须是这四枚从 `COMPILE_FAIL` 变成 `CAUGHT|ArgumentCountError|<message>`，**不能**拿「诊断变可读」当收敛（丙型已把诊断面做掉，两回事）。
4. `compile_fail_quiet=0` ⇒ 本批十形里没有「编译失败但金丝雀沉默」的 ⇒ 丙型的覆盖面在这组样本内不缺（★不代表普遍成立，切片面与用户函数面另论）。

### 37.7 顺手实测的新面孔（非 arity，登记待裁决）：**F-50** `preg_match` 缺**分隔符校验**且返回**错值**

| 臂 | PHP 8.5.8 | AOT |
|---|---|---|
| `preg_match("/b/", "abc")`（控制臂，合法模式） | `1` | `1` ✅ |
| `preg_match("b", "abc")`（无分隔符） | `Warning: preg_match(): Delimiter must not be alphanumeric, backslash, or NUL byte` ＋ **`false`** | **`1`**，且**零告警** |

⇒ 不只是缺 Warning，**返回值也是错的**（PHP 判定模式非法 ⇒ `false`；AOT 当成匹配成功 ⇒ `1`）⇒ 静默错值面。
门 S（PCRE flags/offset，47 臂 `diff=0`）**抓不到这一形**（它没有无分隔符臂）⇒ 修法＝门 S 扩臂后按 PHP 口径补校验；属 AOT 面，可自办，待排。

★本轮零 `src/` 改动；探针与产物已删（`/tmp/r160c*`）。


### 36.9 资产登记（R-160 代次）

| 资产 | md5 | 说明 |
|---|---|---|
| `src/aot/native_linker.zig` | **`9eb19280e01eea3740dea1ffa00bddbb`** | ＋246/−0（金丝雀 6 枚私有函数 + 失败分支一行调用） |
| `src/aot/optimizer.zig` | `ba0e0f579518908e030fc09ca994147f` | ★未变（R-161 值保持） |
| `src/aot/runtime_lib_template.zig` | `6d520849c9a7eab50082c62e924662dd` | ★未变（只被**读**取签名） |
| `zig-out/bin/php-interpreter` | **`fe5d70d42745ab8e3fddc8a66139d6b6`** | 改 `native_linker` ⇒ 必须重建；R-161 的 `d824ad99…` 作废 |
| 门 AC `c034_arity_canary_gate_tmp.sh` | **`87d4c39b37811aaf2fa70901a097cbd9`** | 13 臂永久侧门；表身 `c034_arity_canary_tmp.tsv`（**无表头**）；★建门轮中途曾以 `f2146a28…` 登记 12 臂修前档，其后加 a13＋改归一折叠 ⇒ 该值作废，修前读数已在 §36.2 逐枚落表 |
| 链 `c035_r160_acceptance_chain_tmp.sh` | **`9151aeca615c1a5475a13a0d2cb3bb6e`** | ★链后按 §36.8 取证更正改为**按内容取 DONE**（旧值 `78a9755b…` 作废；作废前的读数已逐腿用表身/腿文件复核，判定不受影响） |
| 影子 new-side 列 | `c010_shadow_newside_r160_tmp.txt`（表身 md5 `f19fb070…`） | ★第 10 代同值，作 R-161 后续代的 BASE |




## 38. R-163（2026-10-14）：F-50 落地 —— `preg_*` 补齐 PHP 的分隔符/修饰符校验（纯模板改动）

### 38.1 ★先测口径再动手：PHP 8.5.8 的完整校验规则（资产 `c036_preg_delimiter_gate_tmp.sh` 的注释即本表）

| 形态 | PHP 的告警文本 | PHP 的返回值 | `$matches` 出参 |
|---|---|---|---|
| `""`／`" "`（空或仅空白） | `{fn}(): Empty regular expression` | false | **不写**（保留调用者预置值） |
| 首字符是字母/数字/`\`/NUL（`"b"`、`"abc"`、`"\a\"`） | `{fn}(): Delimiter must not be alphanumeric, backslash, or NUL byte` | false | 不写 |
| 开括号 `(`/`[`/`{`/`<` 作分隔符 ⇒ 找**配对**闭括号，同名可嵌套 | 正常匹配（`(a)`→1、`(a(b))`→`ab`、`((a))`→`a`） | 1 | 正常填 |
| 开括号找不到配对闭括号（`"(a]"`） | `{fn}(): No ending matching delimiter ')' found` | false | 不写 |
| 非括号分隔符找不到结束符（`"/a"`、`"/"`、`"#a|"`） | `{fn}(): No ending delimiter '/' found` | false | 不写 |
| **闭括号单独作分隔符**（`)a)`） | ★**合法**（⇒ 配对规则只对开括号生效） | 1 | 正常填 |
| 结束符后有空白（`"/a/ "`） | ★**合法**（空白即终止修饰符扫描） | 1 | 正常填 |
| 非法修饰符（`"/a/g"`、`"/a/i/"`） | `{fn}(): Unknown modifier 'g'` | false | 不写 |

★**合法修饰符集合＝实测 13 枚**：`i m s x n u r A D J S U X`（逐字符扫 a–zA–Z 实测，`error_get_last()` 会残留 ⇒ 必须用 `set_error_handler` 逐轮清零才测得准；第一版用 `error_get_last` 得出「全部 UNKNOWN」的**假结论**，已作废重测）。
★**家族返回值**（非法模式下实测）：`preg_match`/`preg_match_all`/`preg_split`/`preg_grep` ⇒ **false**；`preg_replace`/`preg_filter`/`preg_replace_callback` ⇒ **null**。
★**数组实参** ⇒ PHP **逐元素告警**（2 元素 ⇒ 2 条 Warning）且 `preg_replace/preg_filter` 返回**空数组**（不是 null）。

### 38.2 门 PD 修前登记（17 臂，md5 `f2d1ec987a096d52b90d55de898e7b2c`）

`C036PD_DONE arms=17 same=7 diff=10 compile_fail=0 bad_probe=0 repo_build_residue=0` @66 s（表身 `c036_preg_delimiter_tmp.tsv`）。
红 10 枚 ＝ pd1–pd8（四告警形 × 函数族）＋ ★**pd11 `(a)`／pd12 `{a}`**。

### 38.3 ★建门轮否证了我自己的两条预估（都要留档）

1. **预估「pd11/pd12 是恒绿守卫臂」⇒ 实测是红**：`(a)`/`{a}` 两侧都无告警但值不同（PHP `1`，AOT `0`）
   ⇒ 旧解析器把 `([{` 一律当"深度"、只按**同名字符**找结束符，于是 `(a)` 扫到末尾找不到 `(` ⇒ body 变成 `a)` ⇒ 编译失败静默降级。
   ⇒ 本批覆盖面因此多出**「成对分隔符从未支持」**一枚（我原本只打算补校验）。
2. **预估「缺校验只在 `preg_match`」⇒ 实测全族都缺**：`preg_split`（`'b'`→按空模式逐位切出 5 段）、`preg_match_all`（→4 次空匹配）、`preg_replace`/`preg_filter`（→返回原串）都静默放行。
   ⇒ 修复面必须是共享解析器 `parsePHPRegexPattern` ＋ **11 枚调用站点**，不是单点。
3. ★另登记一枚**死码**：`php_preg_replace`（`:27284`，手写非 PCRE 实现，`pat.len < 3` 就直接原样返回）**全仓零引用**
   （`grep -n "php_preg_replace\b"` 只命中定义行；`builtin_map` 的 `preg_replace` 两枚条目都指向 legacy `preg_replace`）
   ⇒ 按宪法 §六.3 **不删**，登记为「已知无引用实现，勿误当活路径修」。

### 38.4 落地内容（纯 `runtime_lib_template.zig`，二进制不重建）

| 件 | 位置 | 内容 |
|---|---|---|
| 口径注释块 | `:10681` 前 | 把 §38.1 的实测规则写进代码注释（禁凭 PCRE 文档推测） |
| `PatternIssue` 枚举 | `:10694` | `none/empty/bad_delimiter/no_end_delimiter/no_end_matching_delimiter/unknown_modifier` |
| `ParsedPattern` 扩字段 | `:10701` | `issue` + `issue_char`（告警文本要回显那个字符） |
| `php_regex_valid_modifiers` | `:10712` | ★实测 13 枚集合 |
| `pairedCloseDelimiter` | `:10723` | `(`→`)`、`[`→`]`、`{`→`}`、`<`→`>`，其它 ⇒ 0 |
| `emitRegexPatternWarning` | `:10732` | 用 `[256]u8` 固定缓冲 `bufPrint` 拼 PHP 口径文本后 `emitWarning`（★不分配、热路径零成本） |
| `parsePHPRegexPattern` 重写 | `:10750` 起 | 前导空白→空判定；首字符合法性；**只对开括号做配对扫描**（含同名嵌套深度）；转义跳过；修饰符逐个校验后空白终止 |
| 11 枚调用站点 | `preg_match`/`preg_match_with_matches`/`preg_match_all`/`preg_replace`/`preg_filter`×2/`preg_split`/`preg_grep`/`php_preg_match`/`php_preg_match_all`/`php_preg_replace_callback` | `if (parsed.issue != .none) { emit…; return false|null; }`；数组循环内那枚按 PHP 的逐元素语义 `continue` |

★**自纠一枚（落地当场）**：删掉 `_ = matches_ref;` 之前先加了写盘，`zig build-exe` 报
`runtime_lib.zig:10840:9: error: pointless discard of function parameter` ⇒ 20 臂全部 `compile_fail`、门跑飞（9 s 就"跑完"是**假信号**）。
⇒ 教训：**模板改动的编译验证只发生在 AOT 产物编译**（F-38 已记 `zig build test` 不覆盖模板），所以**落地后必须先单跑一枚门**再谈验收链；本轮门 PD 的 `compile_fail=20` 就是那枚探针。

### 38.5 ★修后实测（模板 `7bfee93178e59bd83c405e4775a80673`，二进制仍 `fe5d70d4…`）

`C036PD_DONE arms=20 same=18 diff=2 compile_fail=0 bad_probe=0 repo_build_residue=0` @79 s。
原 17 臂**全绿**（`same=15 diff=0` 于旧臂集；`pd11`/`pd12` 成对分隔符转绿、`pd1`–`pd8` 四告警形逐字节收敛含消息文本与 `false`/`null` 之分）；
新增 3 臂里的 `pd19`（合法模式覆盖预置值）绿，`pd18`/`pd20` 红 ⇒ 见 §38.6。

### 38.6 新立 **F-53**（本批落地才现形，登记不掩盖）

`$m = array('pre'); preg_match("b", $s, $m);` ⇒ PHP **保留** `['pre']`（实测），AOT 给**空数组** ⇒ `count($m)` 由 1 变 0。
★根因不在本批改动：AOT 的**按引用实参槽位不从调用者变量初始化**（REF-004/F-13 同族），所以早退支要么留 null（`count(null)` ⇒ 直接 `TypeError` rc=255，比 PHP 更糟）要么装空数组。
⇒ 本批取**装空数组**（与本文件既有早退支一致，且对最常见形态 `[]`/`null` 预置与 PHP 同值），并把「保留非空预置值」这一残差单列 F-53。
★同族观察项（不在本批修）：合法但**语义未实现**的修饰符 `n u r A D J S U X` 仍按"接受但不映射选项"处理 ⇒ 需要一枚 PHP-vs-AOT 的修饰符语义门才能定级（本批未测 ⇒ 不作"已支持"声明）。

### 38.7 ★R-163 验收链读数（21 腿，`17:54:22 → 19:07:46`，**4404 s**；首尾 `bin_md5=fe5d70d4…` 同值＝纯模板未换代次，`tpl_md5=7bfee931…`）

| 腿 | 读数 | wall | 判读 |
|---|---|---|---|
| buildtest | rc=0 | 4 s | ★**不证模板可编译**（F-38）；模板证据在下面每一腿的 AOT 产物编译里 |
| **PD** | `arms=20 same=18 diff=2 compile_fail=0 bad_probe=0 residue=0` | 80 s | ★**本批主判据达成**：修前 17 臂 `same=7 diff=10` ⇒ 现 17 旧臂全绿，红恰为 **pd18/pd20**＝新登记的 F-53（不是本批目标） |
| **S** | `shapes=47 same=47 diff=0 cf=0` | 186 s | ★**首要回归守卫仍 `diff=0`**：改的就是它下游的解析器 ⇒ 合法模式/flags/offset 面零扰动 |
| AC | `arms=13 cf=8 canary=7 bare=8 zig_raw=7` | 24 s | 等值 R-160 档 |
| F45FACE | `shapes=14 raise_lost=2 preserved=12 both_match_php=5` | 103 s | 等值 R-161 档 |
| Y | `shapes=12 same=5 diff=5 zig_escape=1 cf=2` | 42 s | 等值 R-161 档 |
| ZFACES | `shapes=10 same=9 diff=1 dangling=0` | 40 s | 等值（残红 `z2`＝F-44） |
| ZCENSUS | `total=68 dangling=0 ok=68 other=0` | 834 s | 等值 |
| X / V / W / T | `9→8/1` ／ `29→19/10` ／ `20→7/13` ／ `22→16/5 cf=1` | 42/130/80/94 s | 全等值注册档 |
| P | `shapes=78 same=73 diff=5 cf=0` | 330 s | 等值 |
| M / N / O / D8 | `19 red=0` ／ `7 red=0` ／ `6 red=0` ／ `defect_red=0 guard_same=14` | 73/26/22/53 s | 等值 |
| Q / R | `same=5` ／ `same=8 diff=1 terminate_lost=0` | 23/41 s | 等值 |
| U | 无 DONE ⇒ 列聚合 **75 行 = `SAME 51 / COMPILE_FAIL 22 / BAD_PROBE_PHP 2`**（★桶和＝行数已核对） | 216 s | 等值 §26.2 档 |
| B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` | 2 s | 等值 ⇒ 零地图漂移 |
| regression | `Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 全 0 / Skip 1`；`## 失败明细` 仅 `f004 … SKIP` | 852 s（mtime `18:49:19`） | 零回归、回收 0 枚 ⇒ ★语料内**没有**非法模式形（F-50 语料暴露 0） |
| shadow | `total=68 same=0 diff=68 miss=0 invalid=0` | 1107 s | 对照冻结前缀常态 |
| shadowcol | `gen=r163 rows=68 col_md5=f19fb070…` ＝ r160 列同值 ⇒ **`changed_rows=0 col_identical=yes`** | — | ★第 **11** 代发射同值；★规则 29：本批运行面证据是门 PD＋门 S＋主回归，**影子只能证发射器未动**（模板进的是 `runtime_lib.zig`） |
| 链尾 | `R163_CHAIN_END 19:07:46 ELAPSED=4404s` + `R163_CHAIN_DONE` | — | 规则 28 双判成立；各腿 `residue=0`、`bad_probe=0`；`.php` 原件零删除 |

★**链脚本口径升级首验**：本链的 `run_gate` 改为**按内容**取 DONE（`grep -E "_DONE (shapes|arms|total|entries)="`），
腿 ZFACES/ZCENSUS 因此**第一次在链日志里直接显出计数**（`shapes=10 same=9 diff=1 dangling=0`／`total=68 dangling=0 ok=68`），
不再需要回表身复核 ⇒ §35.8/§36.7 那两版 `head -1`/`tail -1` 的取证缺陷正式关闭。

### 38.8 资产登记（R-163 代次）

| 资产 | md5 | 说明 |
|---|---|---|
| `src/aot/runtime_lib_template.zig` | **`7bfee93178e59bd83c405e4775a80673`** | ★本批唯一 `src/` 改动；R-159 的 `6d520849…` 作废 |
| `zig-out/bin/php-interpreter` | `fe5d70d42745ab8e3fddc8a66139d6b6` | **未重建**（纯模板） |
| `src/aot/native_linker.zig` / `src/aot/optimizer.zig` | `9eb19280…` / `ba0e0f57…` | 未变 |
| 门 PD `c036_preg_delimiter_gate_tmp.sh` | **`2bdb246eaee92fb6dcbd2c667a006af9`** | 20 臂（修前登记时为 17 臂 `f2d1ec98…`，其后加 pd18–pd20 承 F-53）；表身 `c036_preg_delimiter_tmp.tsv`（**无表头**） |
| 链 `c037_r163_acceptance_chain_tmp.sh` | **`55cd8c9db28e650a64161fc7ee4793fe`** | 21 腿；★首条采用「按内容取 DONE」口径 |
| 影子 new-side 列 | `c010_shadow_newside_r163_tmp.txt`（表身 md5 `f19fb070…`） | 第 11 代同值，作后续代 BASE |


## 39. R-165（2026-10-14）：F-46 **归因轮 ⇒ 原诊断被实测否证**，拆成三枚独立面孔；半程修复已**回退**，等裁决

### 39.1 ★原登记（§35.1 p13「数组操作数的算术 TypeError 两臂都不抛 ⇒ 操作数类型检查缺数组」）是**误诊**

实文核对（`runtime_lib_template.zig`）：
- `checkArithmeticOperand:6076` **已经**拒绝数组（`:6083 return !v.isArray();`）与非数字字符串（`hasNumericPrefix`）；
- 肇因是 `emitUnsupportedOperandError:6181` —— 它是 **`noreturn` + `std.process.exit(255)`**，
  自己打印 `Fatal error: Uncaught TypeError: Unsupported operand types: …` 后**直接终止进程**，
  ⇒ 消息文本本来就对，但**绕过了整条异常路由** ⇒ `try/catch` 永远接不住。
⇒ ★所以 F-46 不是"缺检查"，而是**同一枚抛出站点的形态错**（不可捕获）。检查面还缺的只有 `php_pow`/`php_neg`（两函数**没有**调用该检查）。

### 39.2 永久侧门 **门 OPS**（`c038_operand_type_gate_tmp.sh`）——判据是「**有没有进 catch**」

★与门 F45FACE 的分工：那枚判 **DCE 有没有消除可抛指令**（`on_eq_off`）；本门判 **抛出来可不可捕获**。
探针把表达式放进 `try { … } catch (Throwable)`，同时打两枚旗标 `aot_caught` / `aot_exit255`。

| 轮 | 读数 | 说明 |
|---|---|---|
| 修前（＝当代 HEAD `df31715` 态，回退后**复跑逐桶同值**） | `arms=26 same=9 diff=17 cf=0 aot_caught=0 aot_exit255=12` @117 s | 16 枚抛出面全红；`aot_caught=0` ＝**没有一枚进过 catch** |
| 半程修复试验（throwThrowable 化，已回退） | `same=12 diff=14 aot_caught=14 aot_exit255=0` @115 s | 可捕获性达成，但★**路由延迟**（见 §39.4）⇒ 不是收敛，故回退 |

臂表（真值全部本轮实测，资产 `fuzzy_scripts_720/tmp/c038_operand_truth_tmp.php`、`fuzzy_scripts_720/tmp/c038_string_truth_tmp.php`、`fuzzy_scripts_720/tmp/c038_pow_neg_truth_tmp.php`）：
- **抛出面**：`array OP scalar`(×6)／`scalar OP array`(×4)／`array OP array`(×2，★`+` 是并集不抛)／`'abc' + 2`、`'abc' % 2`、`'' + 2`／一元 `-[1]`（★PHP 措辞是 `Unsupported operand types: array * int`，照抄）
- **守卫面**：`[1] + [2]` 并集、`'5' + 2`、`'5.5' + 2`、`true + 1`、`null + 1`、`1 + 2`、`1.5 + '2'`、`'abc' . 2`（★拼接位禁扩检查）、`[] + ['k'=>1]`

### 39.3 ★拆出的三枚独立面孔（禁再混为「F-46 缺数组检查」）

| 编号 | 面孔 | 实测证据 | 归属 |
|---|---|---|---|
| **F-46（改定）** | 抛出站点用 `exit(255)` 而非可捕获异常 | 门 OPS 修前 `aot_caught=0`、`aot_exit255=12` | AOT 面，模板单点可修 |
| **F-57** | **算术 binop 站点缺异常路由检查**：发射器只在 `.div`/`.mod` 分支里手写 `if (runtime.hasException())`（`native_linker.zig:20837` 起，`.div` 分支 `:20918` 附近那一条），`.add/.sub/.mul/.pow/.neg` 分支**没有** | 实文：`main.zig:109 reg_3 = try runtime.php_add(...)` 之后**无**检查，检查出现在 `:121` 的下一条 `php_echo` 之后 ⇒ 现象是 `O1=RET\|O1=CAUGHT\|…`（PHP 只打 CAUGHT） | AOT 面，**须改 native_linker ⇒ 重建 + 全链**，且每个 binop 加一枚分支＝**编译器性能代价**（§六.7 须明示） |
| **F-56** | **常量折叠绕过操作数检查**：字面量数组/非数字串参与的 `%`、`**`、`-` 根本不生成 `php_mod/php_pow/php_neg` 调用 ⇒ 静默算出错值 | 门 OPS 的 o5 `[1] % 2`⇒`RET\|1`、o6 `[1] ** 2`⇒`RET\|1.0`、o14 `"abc" % 2`⇒`RET\|0`、o16 `-([1])`⇒`RET\|-1.0`（★全为 `exit255=no`＝压根没抛）；改成**变量**操作数即走运行时检查（实测 `$a % $b` ⇒ Fatal） | AOT 面，IR/优化器侧 |
| **F-55** | 有数字前缀字符串的算术**结果类型**不符：`'5abc' + 2` PHP⇒`7`（int）＋Warning，AOT⇒`7.0`（float） | 门 OPS 守卫臂 g4（★建门轮就红，属预先存在，非本批引入） | AOT 面，`tryAsInt`/`toFloat` 口径 |

### 39.4 ★为什么半程修复必须回退（不是保守，是实测形态）

把 `emitUnsupportedOperandError` 改成 `throwThrowable("TypeError", …)` + 返回 null 后：
- ✅ 12 枚 `exit255` 消失，`aot_caught=0→14`（类名与消息文本与 PHP 逐字节同）；
- ❌ 但异常要等**下一条被检查的指令**才路由 ⇒ **错误之后的语句先被执行**了（`RET|` 也被打出来），
  对**未捕获**形更是把「立即终止」变成「继续跑到下一个检查点」——这比原形态更偏离 PHP（PHP 是就地终止/就地 catch）。
⇒ 单独落这一半会造出**新的错行为**（违规则 30），所以工作区已还原到 `7bfee931…`（＝HEAD `df31715` 态），
   补丁留存 `fuzzy_scripts_720/tmp/c038_half_fix_experiment_R165.patch`（146 行，含 `php_pow`/`php_neg` 补检查与措辞照抄），裁决后即可复用。

### 39.5 待老铁裁决的三型（我不自行推进）

| 型 | 内容 | 影响面 | 代价 |
|---|---|---|---|
| **甲（推荐）** | 抛站点 + 路由**同批落地**：`emitUnsupportedOperandError`→可捕获；`native_linker` 给 `.add/.sub/.mul/.pow/.neg` 补 `hasException()` 路由 | 一次性真收敛（门 OPS 26 臂应达 `same=22`，余 4 枚属 F-56、1 枚属 F-55） | ★改发射器 ⇒ 重建 + 全链 + 影子重估；**每个算术 binop 多一枚分支**＝编译器/产物性能代价（§六.7 必须明示） |
| **乙** | 只修抛站点（可捕获），接受路由延迟，把 F-57 单列下一批 | 收敛一半，★但**未捕获形会从"立即终止"变成"继续跑"** ⇒ 有自造回归风险 | 低（纯模板，不重建） |
| **丙** | 只修 F-56（折叠绕过）与 F-55（结果类型），抛出形态维持 `exit(255)` | 消除静默错值，可捕获性不动 | 中（IR/优化器侧，需新面探针） |

★本轮零 `src/` 净改动（半程修复已回退、逐桶复验与修前登记同值）；新资产＝门 OPS（26 臂，永久侧门）＋三枚真值脚本；
`.php` 原件零删除；`repo_build_residue` 最终 0（本轮 KEEP_TEMP 自查后清理）。

### 39.6 ★老铁裁决＝**甲型**（2026-10-14 22:00，同轮记录）：抛站点 + binop 路由**同批**落地，接受每枚算术 binop 多一枚分支

⇒ 落地形态（两处，缺一不可）：

| 件 | 文件 | 内容 |
|---|---|---|
| 抛出站点 | `runtime_lib_template.zig` | `emitUnsupportedOperandError`（`noreturn` + `exit(255)`）⇒ 改为 `throwUnsupportedOperandError(...) Value`：`throwThrowable("TypeError", "Unsupported operand types: {l} {op} {r}")` + 返回 null；`.add/.sub/.mul/.div/.mod` 五枚站点改成 `return throw…`；★补上 `php_pow`（`**`）与 `php_neg`（一元取负，PHP 措辞实测是 `{type} * int`）此前**没有**的操作数检查 |
| 异常路由 | `native_linker.zig` | `.add`(20541)／`.sub`(20646)／`.mul`(20741)／`.pow`(21023)／`.neg`(21978) 五枚发射分支，各补一段与 `.div`/`.mod` **同形**的路由块（`hasException()` → `@branchHint(.unlikely)` → `generateCleanupCode` → `current_block = handler` 或 `return error.RuntimeError`） |

★代次：`runtime_lib_template.zig` `a72ad897776fd520e322dce01005710c`／`native_linker.zig` `28f8271a6044ab8568fa5a1895d122b4`／二进制 **`b3b6c07d9c4a655871c0271a1ecf4cae`**（R-160/R-163 的 `fe5d70d4…` 作废）。

★落地即时验证（链外）：`$a % $b`／`$a ** $b`／`-$a`／`$s + 1` 四形 AOT 输出与 PHP **逐字节同**（只打 `CAUGHT|TypeError|Unsupported operand types: …`，不再多打 `RET|`）⇒ 路由延迟消失。

### 39.7 ★门 OPS 修后读数（链外单跑，资产 `c038_operand_type_gate_tmp.sh` md5 `620f69c338b450e398a880e99bafc034`，表身 `c038_operand_type_tmp.tsv`）

`C038OPS_DONE arms=26 same=23 diff=3 compile_fail=0 aot_caught=14 aot_exit255=0 bad_probe=0 repo_build_residue=0` @116 s。

| 项 | 修前（＝HEAD `df31715` 态，回退后复跑逐桶同值） | 修后 | 判读 |
|---|---|---|---|
| `same` | 9 | **23** | ＋14 枚收敛 |
| `diff` | 17 | **3** | ★残红身份**必须**逐枚核对（下表） |
| `aot_caught` | 0 | **14** | 抛出来的东西第一次真的能被 `catch` 接住 |
| `aot_exit255` | 12 | **0** | `exit(255)` 硬退形态在本面清零 |

3 枚残红逐枚归因（★一枚都不许算进本批收敛）：

| 臂 | 形 | 现象 | 归属 |
|---|---|---|---|
| o5 | `[1] % 2`（**字面量**数组） | AOT `RET\|1`＝压根没抛 | **F-56** 常量折叠绕过检查（★改变量操作数即正常抛 ⇒ 证据链闭合） |
| o14 | `"abc" % 2`（字面量非数字串） | AOT `RET\|0` | **F-56** 同一枚 |
| g4 | `'5abc' + 2` | AOT `7.0` vs PHP `7`（两侧都带同一条 Warning） | **F-55** 数字前缀串结果类型（★建门轮即红，预先存在） |

★**预估被实测更正**：我在 §39.3 把 o6 `[1] ** 2` 与 o16 `-([1])` 也归进「折叠绕过」，实测这两枚**本批已收敛**
⇒ F-56 的覆盖面比预估**窄**：目前只现形于 `%` 的字面量操作数形（`**`/一元 `-` 走运行时调用）。
⇒ 今后谈 F-56 只说 `%`（外加未测形式），禁把已收敛的两枚继续挂在它名下。

★语料暴露预检（链外抽查 5 形，含 f045/f135/f010/f124/f006）：五枚 AOT 与 PHP 归一后**逐字节同**且 rc=0/0。

### 39.8 ★R-165 验收链读数（25 腿，`22:04:51 → 23:18:54`，**4443 s**；首尾 `bin_md5=b3b6c07d…`／`tpl_md5=a72ad897…` 同值 ⇒ 链内零代次漂移）

| 腿 | 读数 | wall | 判读 |
|---|---|---|---|
| buildtest | rc=0 | 7 s | 缓存档（★不证模板可编译，模板证据在各腿 AOT 编译里） |
| **OPS** | `arms=26 same=23 diff=3 cf=0 aot_caught=14 aot_exit255=0 residue=0` | 116 s | ★**本批主判据达成**，且 3 枚残红身份逐枚核过＝o5/o14（F-56 字面量 `%` 折叠）＋g4（F-55 结果类型） |
| PD | `arms=20 same=18 diff=2 cf=0` | 84 s | 等值 R-163 档 ⇒ 本批未扰动 preg 面 |
| **S** | `shapes=47 same=47 diff=0` | 197 s | ★仍 `diff=0`（PCRE 面零扰动） |
| AC | `arms=13 cf=8 canary=7 zig_raw=7` | 24 s | 等值 R-160 档 |
| F45FACE | `shapes=14 raise_lost=2 preserved=12 both_match_php=5` | 107 s | 等值 R-161 档（★本批**没扩** DCE 守卫，故 p11/p12 仍 2 枚，扩守卫＝R-166） |
| Y | `shapes=12 same=5 diff=5 zig_escape=1 cf=2` | 44 s | 等值 R-161 档 |
| ZFACES / ZCENSUS | `shapes=10 same=9 diff=1 dangling=0` @38s ／ `total=68 dangling=0 ok=68 other=0` @823s | — | 等值（★按内容取 DONE 后这两腿终于直接显数） |
| X / V / W / T | `8/1` ／ `19/10` ／ `7/13` ／ `16/5 cf=1` | 42/128/79/93 s | 全等值注册档 |
| P | `78 same=73 diff=5 cf=0` | 327 s | 等值 |
| M / N / O / D8 / Q / R | `19 red=0` ／ `7 red=0` ／ `6 red=0` ／ `defect_red=0 guard_same=14` ／ `same=5` ／ `same=8 diff=1 terminate_lost=0` | 71/26/21/52/23/40 s | 全等值 |
| U | 无 DONE ⇒ 列聚合 **75 行 = `SAME 51 / COMPILE_FAIL 22 / BAD_PROBE_PHP 2`**（★桶和＝行数已核） | 215 s | 等值 §26.2 档 |
| B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 field_diff=0 identical=30` | 2 s | 等值 ⇒ 零地图漂移 |
| regression | `Total 68 / Pass 67 / Fail(Compile·Runtime·Diff) 全 0 / Skip 1`；`## 失败明细` 仅 `f004 … SKIP` | 837 s（mtime `23:01:27`） | ★**零回归**：路由块进场后 67 枚仍全绿 |
| shadow | `total=68 same=0 diff=68 miss=0 invalid=0` | 1047 s | 对照冻结前缀常态（无 miss/invalid） |
| shadowcol | `gen=r165 rows=68 col_md5=b4cbc4f5…` vs r163 列 `f19fb070…` ⇒ **`changed_rows=49 col_identical=no`** | — | ★**合法漂移**，且**逐枚机制归因完成**（见 §39.9）；R-148b 起连 11 代的 `changed_rows=0` 链在此**正当终结**（本批改的就是发射器） |
| 链尾 | `R165_CHAIN_END 23:18:54 ELAPSED=4443s` + `R165_CHAIN_DONE` | — | 规则 28 双判成立；各腿 `residue=0`、`bad_probe=0`；`.php` 原件零删除 |

### 39.9 ★`changed_rows=49` 的归因（不是"看起来合理"，是把 19 枚未变化行逐一验伪）

判据取反更容易证伪：**若某脚本生成码里没有任何算术 binop 调用，它就不该变**。⇒ 对 19 枚未变化脚本逐枚编译并计数
`runtime.php_(add|sub|mul|pow|neg)(` 出现次数：

| 集 | 枚数 | `arith_calls` | 结论 |
|---|---|---|---|
| 未变化（md5 与 r163 同值） | **19 / 19 全查** | **全为 0** | ⇒ 未变化是真中性（无路由块可插），不是漏检 |
| 变化（抽样 4 枚：f031/f006 属未变化侧、f045/f124 属变化侧） | — | f045＝**26**、f124＝**9** | ⇒ 变化量＝该脚本的算术 binop 站点数，机理对得上 |

⇒ 49 枚漂移**全部**由"算术 binop 后新增一段 `hasException()` 路由块"解释，无一枚需另立原因；主回归 Pass 未降。
★影子基线已按当代次重冻：后续代次的 BASE 改用 `c010_shadow_newside_r165_tmp.txt`（列 md5 `b4cbc4f563527fae1d0c7a473b9df97f`）。

### 39.10 资产登记（R-165 代次）

| 资产 | md5 | 说明 |
|---|---|---|
| `src/aot/runtime_lib_template.zig` | **`a72ad897776fd520e322dce01005710c`** | 抛站点改可捕获 + pow/neg 补检查（R-163 的 `7bfee931…` 作废） |
| `src/aot/native_linker.zig` | **`28f8271a6044ab8568fa5a1895d122b4`** | 五枚算术分支补路由块（R-160 的 `9eb19280…` 作废） |
| `zig-out/bin/php-interpreter` | **`b3b6c07d9c4a655871c0271a1ecf4cae`** | ★发射器改动 ⇒ 必须重建（`fe5d70d4…` 作废） |
| 门 OPS `c038_operand_type_gate_tmp.sh` | `620f69c338b450e398a880e99bafc034` | 26 臂永久侧门；表身 `c038_operand_type_tmp.tsv`（**无表头**，聚合勿加 `NR>1`） |
| 链 `c039_r165_acceptance_chain_tmp.sh` | `ddf651f561b13b7cbce8d38a15291337` | 25 腿；★首条**预注册"影子允许合法非 0 ＋ 逐枚归因规则"**的链 |
| 半修补丁留存 | `fuzzy_scripts_720/tmp/c038_half_fix_experiment_R165.patch` | 回退前的"只做①"实验件；★**不要单独 apply**（缺路由⇒自造回归，§39.6 已记） |


## 40. R-166（2026-10-14）：F-45-ii 收口 —— DCE 守卫由 `.div/.mod` 扩到 `.add/.sub/.mul/.pow`

### 40.1 前置与判据（为什么现在才敢扩）

R-161 裁乙型时把 `.add/.sub/.mul` 排除，理由是「它们的 TypeError 今天走 Zig error 外逸 ⇒ 保住只是把静默换成**不可捕获** Fatal」。
R-165 把这个前提抽掉了（抛站点改 `throwThrowable` ＋ 五枚算术分支补路由，门 OPS 实测 `aot_caught 0→14`）⇒ 保住指令现在等于**真收敛**，于是本批扩守卫。
★顺序不可颠倒的实证就是本批：同一份探针在 R-161/R-165 之间读数是 `DIFF_BOTH_WRONG`（两侧都不等于 PHP），R-165 之后变 `DIFF_DCE_SIDE_WRONG`（off 侧已＝PHP，只差删不删）。

### 40.2 ★门 F45FACE 扩到 19 臂并重新登记（新臂的修前档是在 R-165 代二进制上测的）

| 臂 | 形 | 修前（R-165 代） | 修后（R-166） | 判读 |
|---|---|---|---|---|
| p11 | `try { $a + 1; }`（`$a="abc"`） | `DIFF_DCE_SIDE_WRONG` `on_eq_off=no` | **`EQUAL_BOTH_MATCH_PHP`** | ★F-45-ii 收口 |
| p12 | `try { $a * 1; }` | 同上 | **`EQUAL_BOTH_MATCH_PHP`** | 同上 |
| **p15**（新） | `try { $a - 1; }` | 同上 | **`EQUAL_BOTH_MATCH_PHP`** | `.sub` 同机制 |
| **p19**（新） | `try { $a ** 2; }` | `on_eq_off=no`（手工双臂实测：on＝`RET`、off＝与 PHP 逐字节同） | **`EQUAL_BOTH_MATCH_PHP`** | ★`.pow` 纳入 ⇒ **更正 §35.2 对 `.pow` 的排除理由**（见 §40.4） |
| **p17**（新） | `$a + 1;` **未捕获**形 | `DIFF_BOTH_WRONG` `on_eq_off=no` | `EQUAL_BOTH_RED` `on_eq_off=yes`，≠PHP | ★只算"抛回来了"，**文本面属 F-39-ii，禁算进收敛** |
| **p16**（新） | `$r = $a + 1;`（结果被使用） | `EQUAL_BOTH_MATCH_PHP` | 逐字不变 | 守卫臂：扩守卫没动非语句位 |
| **p18**（新） | 零次循环内 `$a * 1;` | `EQUAL_BOTH_MATCH_PHP` | 逐字不变 | LICM 对偶风险守卫（mul 族） |
| p01–p10、p13、p14 | 原 12 臂 | — | **逐字不变**（快照 `fuzzy_scripts_720/tmp/c032_f45_face_14arm_R165_snapshot.tsv` 逐臂比对） | 无扰动 |

汇总：修前（19 臂口径）`raise_lost=4`／`both_match_php=7` ⇒ 修后 **`raise_lost=0`／`preserved=19`／`both_match_php=11`／`both_red=8`**（11+8=19＝桶和核对通过）。
资产：门 `c032_f45_face_gate_tmp.sh` md5 `2e6381008ec2492116cffb97383db451`（19 臂版；旧 14 臂值作废）。

### 40.3 ★落地当场被 `zig build test` 抓到的一枚**占位断言**（这是本轮最有价值的副产物）

`src/aot/test_loop_unroll.zig:286` 原为
```zig
// TODO: Test infrastructure issue - inst1 not replaced in second pass for some reason.
// Temporarily expect .add to allow build.
try std.testing.expect(inst1.op == .add);
```
本批一改，它就红（`325/326 tests passed, 1 failed`）。加临时打印实测 ⇒ **`inst1.op=nop`、`inst2.op=add`**
⇒ 该断言钉的正是"第二遍 CSE 没替换 inst1"这个**旧缺陷**，而 DCE 不再删这枚死 add 之后，CSE 如注释里所说把它换成了 `.nop`
⇒ 断言改成**期望行为** `expect(inst1.op == .nop)`，并保留 `inst2` 那半（Else 分支的替换仍未生效，未一并"顺手修"）。
★教训：**改优化器必先前置跑 `zig build test` 再开验收链**——本批第一次开链就是 buildtest 腿 rc=1 才看见它（链已白跑约 3 分钟，已停并重开）；
这枚占位断言在仓库里躺了很久，只有改变 IR 形状的申请才会踩到 ⇒ 它是**免费的回归探测器**，禁再往测试里塞"为过构建而放宽"的断言。

### 40.4 ★两条被实测更正的旧口径

1. §35.2 把 `.pow` 排除守卫的理由写的是「`0 ** -1` 在 PHP 8.5.8 只给 Deprecated」——那说的是**数值**形；
   **操作数类型**非法形（`"abc" ** 2`）实测抛可捕获 TypeError ⇒ `.pow` 已纳入守卫（p19 为证）。
   ★同时确认 `.pow` 的纳入不扰动 p06（`0 ** -1` 两臂仍 `EQUAL_BOTH_RED`，AOT 不发 Deprecated 那半是独立的"诊断丢失"型）。
2. §35.2/§35.1 说位运算/移位/取负「两臂都不抛 ⇒ 属 F-46」：R-165 归因后重述为——那些 op 在 AOT **不经运行时类型检查**
   （发射成裸 Zig 整数运算），所以"保住指令"换不回任何抛出 ⇒ 仍排除在守卫外，但归属改挂 **F-56**（静默错值族），不再叫 F-46。

### 40.5 ★R-166 验收链读数（26 腿，`2026-10-14 23:47:44 → 2026-10-15 01:25:31`，**5867 s**；首尾 `bin_md5=1ebb5a8b…`／`tpl_md5=a72ad897…` 同值 ⇒ 链内零代次漂移）

| 腿 | 读数 | wall | 判读 |
|---|---|---|---|
| **buildtest** | rc=0 | 1 s | ★**第二次开链才绿**：首开链 5 s 处 rc=1（`test_loop_unroll` 占位断言，§40.3）⇒ 停链、修断言、重开 |
| **F45FACE** | `shapes=19 raise_lost(on_eq_off=no)=0 preserved=19 both_match_php=11 both_red_not_match_php=8` | 139 s | ★**本批主判据达成**（19 臂口径 `raise_lost 4→0`；11+8=19 桶和核对通过） |
| OPS | `arms=26 same=23 diff=3 aot_caught=14 aot_exit255=0` | 110 s | 等值 R-165 档 ⇒ 未扰动运行时抛出面 |
| PD / S | `20 → 18/2` @80s ／ `47 diff=0` @187s | — | 等值（R-163/R-155 成果保持） |
| AC | `13 cf=8 canary=7 zig_raw=7` | 24 s | 等值 R-160 档 |
| **AB（本批新增语料分母腿）** | 表身聚合 `68 行 = on_eq_off=yes 67 / one_or_both_sides_missing 1` ⇒ **`diff=0`** | 1583 s | ★默认档与关 DCE 档在语料内 **0 枚行为差**（那 1 枚 missing＝f124 在**关 DCE 侧**的既存 `unreachable code`）⇒ 扩守卫的语料行为暴露实测 **0** |
| Y / ZFACES / ZCENSUS | `12 same=5 diff=5 cf=2` ／ `10 same=9 diff=1 dangling=0` ／ `total=68 dangling=0 ok=68` | 42/37/769 s | 全等值 |
| X / V / W / T / P | `8/1` ／ `19/10` ／ `7/13` ／ `16/5 cf=1` ／ `73/5 cf=0` | 40/122/74/88/309 s | 全等值注册档 |
| M / N / O / D8 / Q / R | `19 red=0` ／ `7 red=0` ／ `6 red=0` ／ `defect_red=0 guard_same=14` ／ `same=5` ／ `same=8 diff=1` | 69/24/21/49/22/38 s | 全等值 |
| U | 列聚合 `75 行 = SAME 51 / COMPILE_FAIL 22 / BAD_PROBE_PHP 2`（★桶和＝行数） | 203 s | 等值 |
| B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 identical=30` | 2 s | 等值 ⇒ 零地图漂移 |
| regression | `Total 68 / Pass 67 / Fail 全 0 / Skip 1`；`## 失败明细` 仅 `f004 … SKIP` | 789 s（mtime `01:08:06`） | 零回归、回收 0 枚 |
| shadow | `total=68 same=0 diff=68 miss=0 invalid=0` | 1045 s | 对照冻结前缀常态 |
| shadowcol | `gen=r166 col_md5=b4cbc4f563527fae1d0c7a473b9df97f` ＝ r165 列**同值** ⇒ **`changed_rows=0 col_identical=yes`** | — | ★**比预留判据更强的结果**：链头写的是"允许合法非 0 ＋ 反证归因"，实测 0 ⇒ 语料内**压根没有**"结果被弃的语句位 `.add/.sub/.mul/.pow`"可被保住 ⇒ 不需归因，BASE 仍用 r165 列 |
| 链尾 | `R166_CHAIN_END 01:25:31 ELAPSED=5867s` + `R166_CHAIN_DONE` | — | 规则 28 双判成立；各腿 `residue=0`、`bad_probe=0`；`.php` 原件零删除 |

★资产登记（R-166 代次）：`optimizer.zig` **`8ae9cdb9288da18897b91dd5297c291a`**、`test_loop_unroll.zig` **`6716a3171ae8c6fcf60b8bd0c2fef77f`**、二进制 **`1ebb5a8bbf583c74c7c2040d7da88e67`**（`b3b6c07d…` 作废）、门 F45FACE `2e6381008ec2492116cffb97383db451`（19 臂版）、链 `c040_r166_acceptance_chain_tmp.sh`；修前 14 臂快照存 `fuzzy_scripts_720/tmp/c032_f45_face_14arm_R165_snapshot.tsv`（表身已被 19 臂版覆盖，快照即修前档）。

## 41. R-167（2026-10-15）：F-56 **改定为强度削减**（不是常量折叠）＋ 新立并落地 F-58 位运算族 ＋ F-59 登记

老铁 2026-10-15 两项裁决：**F-56 取甲型**（`.mod` 臂补 lhs 守卫，接受 `% 2^n` 回退 `php_mod` 的性能代价）、
**F-58 本轮一并修**（位运算/移位/取反族）。本轮同时改了 `optimizer.zig`／`constant_folder.zig`／
`native_linker.zig`（发射器）／`runtime_lib_template.zig` ⇒ 新二进制代次 **＋ 影子列必然漂移**。

### 41.1 机制更正：推翻本单 §39.3/§40.4 的「常量折叠绕过算术操作数类型检查」

R-165/166 把门 OPS 的两枚残红 `o5 [1] % 2`／`o14 "abc" % 2` 归给"字面量 `%` 的常量折叠"。**该归因是错的**，
取证两条：

| 证据 | 读数 | 结论 |
|---|---|---|
| `constant_folder.zig:149 foldMod` | 入口条件 `lhs == .int and rhs == .int and rhs.int != 0`；`ConstantValue` 联合体**根本没有 array 分支** | 折叠**不可能**折 `[1] % 2`／`"abc" % 2` |
| `KEEP_TEMP` 生成码（`[1] % 2`） | `reg_0 = initArray(…)` → `reg_24 = initInt(1)` → **`reg_3 = initInt(reg_0.toInt() & reg_24.toInt())`**，全程**没有** `php_mod` 调用 | 真正肇因是把 `% 2` 改写成了 `& 1` |

真凶＝**强度削减** `optimizer.zig:5903-5927` 的 `.mod` 臂：只查 `rhs` 是常量 2 的幂，**完全不查 lhs**，
直接 `inst.op = .bit_and` ⇒ 发射成裸 Zig 整数运算，`php_mod`（连同 R-165 刚补好的
`checkArithmeticOperand` ＋ `hasException()` 路由）被整条绕开。
同族另两臂**实测免疫**，恰证守卫口径本就存在、只是 `.mod` 漏了：`.mul`(`:5840`) 与 `.div`(`:5872`)
都**额外要求 lhs 也是常量整数**（`.div` 还要求整除），所以门 OPS 的 `o3 [1] * 2` 才是 SAME。

### 41.2 同一臂的两面缺陷（面 B 比面 A 更危险）

| 面 | 机制 | 实测 |
|---|---|---|
| A 类型检查旁路 | lhs 是 array／非数字串 ⇒ 本应抛可捕获 TypeError | `[1] % 2` PHP 抛、AOT `RET\|1`；`"abc" % 2` PHP 抛、AOT `RET\|0` |
| **B 负数静默错值** | PHP `%` 是**截断取余**（符号随被除数），`x & mask` 是**向下取模**（恒非负） | `-3 % 2` PHP **-1**／AOT **1**；`-9 % 8` PHP **-1**／AOT **7**；`'-5' % 4` PHP **-1**／AOT **3** |
| C 诊断丢失 | float lhs 的 `Implicit conversion from float … loses precision` Deprecated 一并消失 | `3.7 % 2`／`-3.7 % 2` AOT 无 Deprecated |

★面 B **连异常都没有**，是对正确程序的纯静默错算 ⇒ 定级 P0；且 `.mul`/`.div` 两支不存在该面
（它们只在两侧皆常量时改写，而 `@rem(lhs,rhs)==0` 已把符号问题挡掉）。

### 41.3 因果对照臂（把肇因锁死在这一臂）

| 臂 | 表达式 | 修前 | 含义 |
|---|---|---|---|
| m7 | `$a = -3; $a % 2` | **红**（AOT 1） | 字面量模数 ⇒ 进改写支 |
| c1 | `$a = -3; $m = 2; $a % $m` | **绿**（-1） | ★同一表达式，只差 rhs 是否字面量 ⇒ 强度削减为唯一因 |
| c4 | `-3 % 2`（两侧皆字面量） | **绿**（-1） | 常量折叠**先**接走该指令 ⇒ 折叠不是肇事者（旧归因反证） |
| c2/c3 | `$a % 2.0`／`$a % 3` | **绿** | 非 int／非 2 的幂 ⇒ 不进改写支 |
| m13 | `$a = 0; $a = $a - 1; $a % 2` | **绿** | 经减法产生的负值走 `php_mod` ⇒ 证明"值来自非常量"这条链本就正确 |

### 41.4 门 MSR 建门与修前红集（永久侧门，`c041_mod_strength_gate_tmp.sh`）

**修前档（72 臂，表身 md5 `acac0cf19bbbd6f87892a8c830945616`，快照 `c041_msr_prefix_72arm_R167_snapshot_tmp.tsv`）：**
`arms=72 same=24 diff=48 compile_fail=0 bad_probe=0 repo_build_residue=0` @324s（4.5 s/形），桶和 24＋48＝72 自证。

| 组 | 修前红臂 | 枚数 |
|---|---|---|
| F-56 面 A（类型旁路） | m1 m2 m3 m4 m5 m6 | 6 |
| F-56 面 B（负数错值） | m7 m8 m9 m10 m11 m14 | 6 |
| F-56 面 C（float Deprecated） | m12 **g8** | 2 |
| F-58 面 A′（操作数检查旁路） | b1…b9 | 9 |
| F-58 面 B′（string × string 合法逐字节） | b10…b14 | 5 |
| F-58 面 C′（Warning/Deprecated/移位计数） | b15…b21 | 7 |
| F-58 面 D′（语句位被 DCE 删） | b23 b24 b25 | 3 |
| F-58 面 E′（对象操作数） | b26 b27 b28 | 3 |
| F-58 面 F′（一元 `~` 自成一支） | b29…b35 | 7 |
| **合计** | | **48** |

★**唯一"看着该红却绿"的臂是 b22**（`$a >> 64`）：发射侧的 `@min(63,…)` 钳位对 -1 恰好凑出 PHP 的 -1；
而字面量形 `1 << 64`（b20）走 `foldShift` 的 `@mod(rhs,64)` 掩码 ⇒ 同一件事**两条路径两套错法**，都收进本批。
★守卫臂恒绿 24 枚：`m13 c1 c2 c3 c4 g1…g7 b22 b36…b46`。
★b47/b48（语句位 `-([1]);`／控制臂 `2 ** [1];`）在链跑动前补入集合 ⇒ 现行 **74 臂**；
b47 的修前读数用同一支探针在修前二进制（`1ebb5a8bbf583c74c7c2040d7da88e67`）单独实测：
PHP `CAUGHT|TypeError|Unsupported operand types: array * int` ／ AOT `RET|1` ＝红，控制臂 b48 两侧逐字节同。

### 41.5 F-58 PHP 8.5.8 真值全表（本轮逐枚实测，资产 `c041_bit_truth_tmp.php`／`c041_bit_truth2_tmp.php`）

| 面 | 实测口径 |
|---|---|
| 二元位运算 array／非数字串／空串 | 可捕获 `TypeError: Unsupported operand types: <l> <op> <r>`（运算符按 `& \| ^ << >>` 原样） |
| **string × string** | **PHP 合法**逐字节运算，返回 **string**：`&`／`^` 结果长度取**较短者**、`\|` 取**较长者**并把短者右侧补 `\0`；`'5' & '3'` = 字符串 `"1"`（**不是** int 1） |
| 有数字前缀的非数字串 | 先 `Warning: A non-numeric value encountered`，再按前缀取整（`'5abc' & 3` = 1） |
| float | `Deprecated: Implicit conversion from float … loses precision` 后转整 |
| 移位负计数 | **`ArithmeticError: Bit shift by negative number`**（可捕获） |
| 移位计数 ≥64 | `1 << 64` = 0、`8 >> 65` = 0、`-1 >> 64` = -1（符号填充）；`PHP_INT_MAX << 1` = **-2**（位回绕） |
| 对象操作数 | 用**类名**且**恒排在前面**：`new Foo() & 1` 与 `1 & new Foo()` 都印 `Foo & int` |
| array 操作数顺序 | **自然顺序**：`[1] & 2` ⇒ `array & int`、`2 & [1]` ⇒ `int & array` |
| 一元 `~` | 消息族不同＝`Cannot perform bitwise not on <X>`；`<X>` 对 bool 用**值文本 "true"/"false"**、对象用类名；**null／bool 也拒**（二元族接受）；string **一律**逐字节取反返回 string（`~'5'` 也是 string） |
| ★PHP 自身不一致 | `1 & (array)1` 印 `array & int`（与 `1 & [1]` 的 `int & array` **相反**）⇒ 本实现按字面数组的自然顺序，**不复刻**该反常 |

### 41.6 落地清单（四文件）

| 层 | 文件·位置 | 变更 |
|---|---|---|
| 优化器 | `optimizer.zig:5903+` `.mod` 强度削减臂 | 补 lhs 守卫：要求 `lhs` 亦为常量整数**且 `>= 0`**（比 `.mul/.div` 多这一条，因为 `x & mask` 对负数不等价）＝**甲型** |
| 优化器 | `optimizer.zig:3256 isRaisableArithmetic` | 集合由 `.add/.sub/.mul/.div/.mod/.pow` 扩到 **＋`.neg`**（更正③，b47 实测）与 **＋`.bit_and/.bit_or/.bit_xor/.shl/.shr/.bit_not`**（更正④，F-58 后前提改变）；旧注释里"位运算不经运行时检查"的排除理由已随本批失效，留字防重犯 |
| 常量折叠 | `constant_folder.zig:167 foldShift` | 去掉 C 风格 `@mod(rhs,64)` 掩码：负计数**不折叠**（交运行时抛 ArithmeticError，同时消掉一处 `@intCast` 越界转换）、计数 ≥64 按 PHP 口径（shl 0／shr 符号填充）、shl 经 i128 截断复刻位回绕 |
| 运行时模板 | `runtime_lib_template.zig`（`php_mod` 之后新增一段） | 新 helper：`operandTypeName`（对象给**类名**，不动 `valueTypeName` ⇒ 规则 30）、`emitFloatToIntDeprecatedIfNeeded`（从 `php_mod` 两段内联形抽出，`php_mod` 就地改调，DRY 且形为不变）、`throwBitwiseOperandError`（对象排前）、`throwBitNotError`、`throwBitShiftNegativeError`、`bitwiseStringResult`、`php_bitwise` 核心＋`php_bit_and/or/xor/shl/shr` 五包装、`php_bit_not` |
| 发射器 | `native_linker.zig:21133/21138/21143/21152/21161`（`.shl/.shr/.bit_and/.bit_or/.bit_xor`）与 `:22067`（`.bit_not`） | 六枚站点由裸 Zig 整数运算改走 `try runtime.php_bit_*（…）`，统一 `writeRegAssignmentPrefix` ＋ `writePhpValueExpr`（顺带补上 `.shl/.shr` 原先**缺失的 alloca `.*` 解引用**，并去掉 `.bit_not` 那三段按 `operand.type_` 分档的同构死分支），每枚站点后追加路由 |
| 发射器 | `native_linker.zig`（`generatePostCallExceptionCheck` 之后） | 新增 `emitThrowSiteRouting`（块级 4 空格缩进的抛出站点路由，与既有七处内联形逐字节同构；既有七处**保持原样**，不把无关重排混进本轮） |

### 41.7 建门/落地轮的自我更正（五条，全部留字）

| # | 事件 | 教训 |
|---|---|---|
| 1 | 门 DIFF 行的 `printf` 少传一个参数（`$arc`）⇒ AOT 列丢了 rc、输出被挤到 rc 槽 | 差分门的格式串与参数个数必须逐支对齐；判据本身未受影响（比较发生在 printf 之前） |
| 2 | 臂表 b20 的表达式参数写成**双引号** `"$n << 1"` ⇒ bash 展开 `$n`，`set -u` 下**整条门在第 45 臂崩掉**（无 DONE 行） | 臂表表达式参数一律单引号；`bash -n` 抓不到这类运行时错，必须跑到出 DONE 行为止 |
| 3 | 为改表头注释写的 python 片段用"首个匹配短语"定位行区间，命中了 `expr_for` 里的同义注释 ⇒ **删掉门脚本 21–173 行**（三个探针函数与 m/c/g、b1..b35 全丢） | ① 未入库资产也要先快照再改；② python 行区间定位必须用**唯一**锚点或显式行号；③ 重建后用「同一子集逐字节复证」验收——本轮实测 m/c/g 26 行与毁损前快照 `diff` 为空，才算复建成功 |
| 4 | 一元取反的**语句位**（`-[1];`）此前无任何门覆盖 ⇒ `.neg` 自 R-165 就可抛，但不在 `isRaisableArithmetic` 集合里，属 R-166 的**漏项** | 扩"可抛集合"时必须同时问"语句位臂在哪"；本轮补 b47/b48 成对入集合 |
| 5 | 一条命令里把 `rm -rf /tmp/r167*` 与 `md5` 并写（违规则 47「`rm` 禁与其他命令同条」） | 目标全是本会话自建 /tmp 草稿、无仓库资产受损，但纪律违规本身要登记 |

### 41.8 修后读数与验收链

★门 MSR 落地后单跑（74 臂，表身 md5 `27d013deffc0a9976bf9bc0e26268a1d`，脚本 md5 `68a3cfb4d2fe1f91dc91ac89014504af`）：

```
C041MSR_DONE arms=74 same=74 diff=0 compile_fail=0 aot_caught=28 aot_exit255=0 bad_probe=0 repo_build_residue=0 ELAPSED=340s
```

⇒ **48 枚修前红全部转绿**、守卫臂一枚未被打红（规则 30 判据成立）、`aot_caught` 从 **0 → 28**
（抛出站点第一次全面可捕获）；抽查四条口径逐枚可读：`b1` 打出 `array & int`、`b10` 得 `string|616260`、
`b32` 得 `string|9e9d9c`、`b18` 进 `ArithmeticError`。

★语料暴露普查（`c042_bit_corpus_census_tmp.sh`，纯 grep，桶和 24＋2＋9＋33＝68 自证）：

```
C042CENSUS_DONE total=68 bit_only=24 modpow_only=2 both=9 neither=33
```

⇒ 位运算/`% 2^n` 语料面 **35 枚**（24＋2＋9）⇒ 本批**改了发射器**，影子列 `changed_rows` 必然非 0，
归因判据＝**变化集 ⊆ 这 35 枚**，其余 33 枚必须逐字节不变。

★性能实测（同一对 bench 文件、同一命令口径，修前基线）：

| bench | 修前（bin `1ebb5a8b…`） | 判读 |
|---|---|---|
| 模运算 A(`$i%2` 走 `&`)／C(`$i%6` 走 php_mod＋内联常量)／B(`$i%$m`) | ReleaseFast 中位 **456 / 461 / 512 ms** | ★甲型的成本代理是 **A vs C**＝**约 1%**（噪声级）；B 的 +12% 来自 `getGlobalVar` 而非 `php_mod` |
| 模运算（小产物 ReleaseSmall 档） | A 1554／C 1588 ms | 约 **+2.2%** |
| 位运算热点（`($i & 0xFF) \| (($i << 2) & 0xF0) ^ ($i >> 1)`，n=3M） | **2119 ms**（2092/2127/2119） | F-58 走带检查 helper 的代价基准，链内 PERF 腿复测同文件 |

★验收链 `c042_r167_acceptance_chain_tmp.sh`（腿序：buildtest → **MSR** → F45FACE → OPS → PD → S → AC → AB → CENSUS → PERF → Y/ZFACES/ZCENSUS/X/V/W/T/P/M/N/O/D8/Q/R/U/B → regression → shadow → shadowcol）：
链头/链尾与各腿读数见下表（★OPS 的期望由修前档 `same=23 diff=3`（红 o5/o14/g4）**改档为 `same=25 diff=1`**，
残红只剩 g4＝F-55；o5/o14 正是本批 F-56 面，转绿即闭环。按既有纪律**不改已入库的门头注释**，改档登记于此）。

| 腿 | 读数 | 判读 |
|---|---|---|
| 链头 | `R167_CHAIN_START 09:50:56 bin=c514f194… tpl=85747609… opt=0eca2875… nlk=1b70d7ad… cf=14c9fe6b…` | 代次四件套齐全（本批多了 `constant_folder.zig` 一枚） |
| buildtest | `rc=0 wall=1s` | ★**开链前先跑过**（R-166 的教训入规）；`zig build test` 主步骤不含 `src/aot/root.zig`，`test-aot` 的 F-38 六处编译错误逐字复现＝非本批引入 |
| **MSR（本批主门）** | `arms=74 same=74 diff=0 compile_fail=0 aot_caught=28 aot_exit255=0 bad_probe=0 residue=0` @337s | ★48 枚修前红**全收**、24 枚守卫臂一枚未被打红、可捕获性 0→28；与链外单跑**同值**（表身 md5 `27d013de…` 复现） |
| F45FACE | `shapes=19 raise_lost=0 preserved=19 both_match_php=11→**12** both_red=8→**7**` | ★`raise_lost=0` 保持＝守卫只扩不缩（规则 30 判据）；**多收的一枚是 p13**（`[] % 1`，`isPowerOfTwo(1)` 为真 ⇒ 旧臂走 `& 0` 静默 RET，本批守卫后落 `php_mod` ⇒ 与 PHP 逐字节等值）＝F-56 的第三枚侧面闭环；余 7 枚 RED 全是 p01/p02/p03/p04/p06/p07/p17＝**未捕获文本面 F-39-ii**，与本批无关 |
| **OPS** | `arms=26 same=23→**25** diff=3→**1** aot_caught=14→16` | ★按 §41.8 预告**改档成立**：红臂 `o5 [1] % 2`／`o14 "abc" % 2` 转绿，残红恰 1 枚＝`g4`（F-55 结果类型）；本批把 `php_mod` 的 float 段抽成 helper，`o4/o9/g8` 是这条 DRY 回边的守卫 ⇒ 全部未动 |
| PD | `arms=20 same=18 diff=2` | 等值（2 枚恒红＝已登记的 F-53 按引用出参面） |
| S | `shapes=47 same=47 diff=0` | 等值 |
| AC | `arms=13 compile_fail=8 ran=5 same=2 diff=3 canary=7 bare_symbol=8 zig_raw=7` | **逐字段与 R-166 全等** |
| AB（DCE A/B 语料分母） | 全行分桶 `68 行 = EQUAL_BOTH_MATCH_PHP 66 + EQUAL_BOTH_RED 1 + COMPILE_FAIL 1`；`on_eq_off` 列 `yes 67 / one_or_both_sides_missing 1` | ★与 R-166 档**分布逐字相同** ⇒ 守卫扩到 `.neg`＋位运算六枚后语料行为暴露仍为 **0**；`COMPILE_FAIL` 那行＝f124 在**关 DCE 侧**的既存 `unreachable code`（非本批）；★读数用**全行**分桶（首版误用 `NR>1` 吃掉 f004 一枚真数据行，违规则「桶和＝行数」当场自检出） |
| CENSUS（新） | `total=68 bit_only=24 modpow_only=2 both=9 neither=33 bucket_sum=68` | 语料面 35 枚 ⇒ 影子漂移的允许集 |
| **PERF（新）** | bit 热点 `2807/2803/2783` ms（修前 `2127/2092/2119`，ReleaseSmall，`s` 值逐字节同）＝**+32%**；mod bench A `503/486/473`、C `473/491/493`、B `521/621/620`（ReleaseFast）⇒ **A≡C**（甲型后 `% 2` 与 `% 6` 同价），A 修前 456 ⇒ **+2～4%** | ★**更正我在裁决前提的"位运算代价约在个位数"**：实测是 **+32%**（合成体每轮 5 次调用，折算约 45 ns/次）；模运算侧的 1～3% 预估**成立**。语料级稀释比**未测**（要 A/B 得重建修前二进制，`/tmp/c010_prefix_backup` 那枚是 R-145 代 `be305cfa…`，跨了 R-160/163/165/166 四代发射变更，不可用作同代对照）⇒ 见 §41.10 的 F-60 待裁决 |
| Y / ZFACES / ZCENSUS | `12 same=5 diff=5 zig_escape=1 cf=2` ／ `10 same=9 diff=1 dangling=0` ／ `total=68 dangling=0 ok=68` | 全等值 |
| X / V / W / T / P | `8/1` ／ `19/10` ／ `7/13` ／ `16/5 cf=1` ／ `73/5 cf=0` | 全等值注册档 |
| M / N / O / D8 / Q / R | `19 red=0` ／ `7 red=0` ／ `6 red=0` ／ `defect_red=0 guard_same=14` ／ `same=5` ／ `same=8 diff=1` | 全等值 |
| U | 列聚合 `75 行 = SAME 51 / COMPILE_FAIL 22 / BAD_PROBE_PHP 2`（★桶和＝行数） | **与 R-166 档全等** |
| B | `entries=497 distinct=464 dup_rows=33 diff_impl=3 identical=30` | 等值 ⇒ 零地图漂移 |
| regression | `Total 68 / Pass 67 / Fail 全 0 / Skip 1`；报表 mtime `11:18:12` | ★**零回归**：本批改了发射器＋优化器＋折叠器，主回归不掉一枚 |
| shadow | `total=68 same=0 diff=68 miss=0 invalid=0` @1051s | 常态（old 侧跨代前缀） |
| **shadowcol** | `gen=r167 rows=68 col_md5=f5f2bf5ef969dd091962a468bf3afcbb base_md5=b4cbc4f5… changed_rows=**13** col_identical=no` | ★本批是**受控重冻事件**（与 R-166 的 `changed_rows=0` 不同）；归因见下 |
| 链尾 | `R167_CHAIN_END 11:35:43 ELAPSED=6287s` + `R167_CHAIN_DONE` | 规则 28 双判成立；各腿 `residue=0`、`bad_probe=0`；`.php` 原件零删除 |

★**影子 13 枚漂移的逐枚归因**（判据方向＝变化集必须是 CENSUS 允许集的子集）：

| 检查 | 结果 |
|---|---|
| 变化集（13 枚） | `f007 f016 f025 f027 f043 f045 f047 f065 f066 f135 f151 f152 f178` |
| `OUT_OF_RANGE`（变化却不在 `bit ∪ modpow` 集内） | **空** ⇒ 无越界漂移 ✓ |
| 与 `% 2^n` 允许集（11 枚）的关系 | **11 枚全部在变化集内**（f007 f027 f043 f045 f047 f065 f066 f135 f151 f152 f178）⇒ 甲型守卫逐枚命中 |
| 余下 2 枚（f016 hash_bloom、f025 crc/rle/lzw） | 位运算热点文件 ⇒ F-58 命中 |
| 「在允许集却未变化」的 22 枚 | 逐枚严格复查：命中全部是**普查口径过宽**的假阳性（按引用 `array &$arr`、联合类型 `int|string`、逻辑 `&&`、字符串字面量里的 `&`/`^`/`~`（如 `"Insert & Search"`、`'/[^\p{L}]/u'`））⇒ 严格位运算符扫描在 22 枚中只剩这 2 类假阳性、**零真运算符** ⇒ 无遗漏解释 ✓ |

### 41.9 本轮**未修**、新登记的面孔

| 编号 | 面孔 | 实测证据 | 定级 |
|---|---|---|---|
| **F-59** | **算术**族对**对象操作数完全放行**：`checkArithmeticOperand:6078` 只拒 string（无数字前缀）与 array，对象直接通过 ⇒ `$o + 1` 既不抛也无类名消息；PHP 侧是自然顺序＋类名（`1 + new Foo()` ⇒ `int + Foo`） | `s4.php` 四臂实测（`add_obj`／`add_obj_r`／`and_obj`／`and_obj_r`）；二元位运算面**已随 F-58 收口**，算术面对象面**未收** | P1，待裁决：修法是给 `checkArithmeticOperand` 补"对象也拒"还是新增 `arithOperandTypeName`，两者都会波及 68 枚语料共用的运行时入口（规则 30）⇒ 必须单独一轮 |
| **F-58-b** | 位运算结果的 **IR 类型声明**与真值可能不一致：`ir_generator.zig:5083-5086` 把 `&=`/`|=`/`^=`/`<<=`/`>>=` 的结果寄存器声明为 `.i64`，而 F-58 之后 string × string 会返回 **string** Value ⇒ 若下游按 `.asInt()` 取用即类型误读 | 代码路径实测存在，**尚未取得运行期红证**（本轮门内 b10..b14 都是"结果直接输出"形，未构造 `.asInt()` 消费形） | P1，★下一轮先造"字符串位运算结果被按 int 消费"的臂（链跑动期间禁并发 AOT 编译，故本轮不测） |
| **F-55** | 数字前缀字符串算术结果的 int/float 分叉（`'5abc' + 2` AOT `RET\|7` vs PHP `RET\|7`＋Warning 已同值，但 g4 仍差末位类型） | 门 OPS 残红 g4（本批未触碰） | P2 待裁决 |
| F-38 | `zig build test-aot` 仍 6 处编译错误（`dependency_resolver.zig:692/706/723/738/789` 调 `init` 少两参、`linker.zig:162` 缺 `ArrayList` 字段） | 本轮复测逐字相同 ⇒ 非本批引入；`zig build test` 主步骤 rc=0 且**不含** root.zig 那批 ⇒ AOT 模块单测长期失编译 | 已知，登记于 §28.13.2 |

### 41.10 新立 **F-60**（性能回边，待裁决）与本批后续建议

★本批**唯一**没有落在语义面的后果：位运算热点实测 **+32%**（合成体每轮 `($i & 0xFF) | (($i << 2) & 0xF0) ^ ($i >> 1)`
共 5 次带检查调用＋5 段路由；折算约 45 ns/次）。老铁批的是「本轮一并修」，但**我在裁决前给的估算是"个位数百分比"，
实测否证了它**——按纪律以实测为准登记，不用估算交差。

| 编号 | 面孔 | 现状 | 可选路线 |
|---|---|---|---|
| **F-60** | 位运算/移位/取反在**两侧皆为整数**时也付带检查调用的代价 | 已闭合正确性，性能回边未做 | **甲**：发射期按 `getInferredRegType`/`current_register_types` 判"两侧皆 int"⇒ 保留旧的裸 `& ^ \|` 内联形（int×int 不可能抛 ⇒ 连路由一起省，速度全还原），其余形走 helper。★前提＝类型推断对 `Value` 寄存器**可靠**：`.mod` 现有实现只用它选 unwrap 形态、**从不用它跳过检查**，且 CODEGEN-007／REF-004 两次实测都证明"声明类型与实装值不符"是本仓的真实失效模式 ⇒ 必须先做一轮"被推断成 int 却实装 string/float"的证伪普查，否则就是拿正确性换性能（规则 30）。<br>**乙**：接受现状，仅在真实语料出现可测退化时再议。推荐先按乙走，同时把语料级稀释比补测出来（需重建修前二进制作同代对照）。 |
| F-59 | 算术族对**对象**放行（`$o + 1` 不抛不报） | 未修 | 需改 `checkArithmeticOperand`（68 枚共用入口）⇒ 单独一轮 |
| F-58-b | 复合赋值 `&= \|= ^= <<= >>=` 的结果寄存器在 `ir_generator:5083-5086` 声明为 `.i64`，而 string × string 现在返回 string Value | 未测出红证 | ★下一轮第一枚臂：构造"字符串位运算结果被按 int 消费"的形（`$a = "abc"; $a &= "abd"; if ($a > 0) …`），链跑动期间禁并发 AOT 编译，故本批未取数 |
| F-55 | `'5abc' + 2` 结果类型末位（门 OPS 唯一残红 g4） | 未修 | 待裁决 |

★复测路径（体验顺序）：`bash fuzzy_scripts_720/tmp/c041_mod_strength_gate_tmp.sh`（74 臂，约 340 s）⇒ 期望
`same=74 diff=0`；再 `bash fuzzy_scripts_720/tmp/c042_r167_acceptance_chain_tmp.sh`（26 腿，实测 6287 s）。
★资产登记（R-167 代次）：门 `c041_mod_strength_gate_tmp.sh` md5 `68a3cfb4d2fe1f91dc91ac89014504af`（74 臂）；
修前表身快照 `c010…/c041_msr_prefix_72arm_R167_snapshot_tmp.tsv`（md5 `acac0cf1…`，72 臂档）；修后表身 `27d013de…`；
真值资产 `c041_bit_truth_tmp.php`／`c041_bit_truth2_tmp.php`／`c041_mod_perf_tmp.php`／`c041_bit_perf_tmp.php`；
普查 `c042_bit_corpus_census_tmp.sh`＋表 `c042_bit_corpus_census_tmp.tsv`；链 `c042_r167_acceptance_chain_tmp.sh`＋日志
`c042_r167_acceptance_chain_tmp.log`；影子列 `c010_shadow_newside_r167_tmp.txt`（表身 md5 `f5f2bf5e…`，**新 BASE**）。
★**待裁决的收口项**：F-60 甲/乙、F-59、F-58-b、F-55；以及全部 R-167 资产与四文件变更**仍未提交**（老铁口径：只记录不提交）。

## 42. R-168（2026-10-15）：F-58-b **取证即证伪** ＋ F-60 定价补上关键一块（零 `src/` 改动轮）

本轮不做任何代码改动，只做两件事：把 §41.9 挂出的 **F-58-b** 打到"证伪"或"坐实"，以及把 F-60 的定价补齐。

### 42.1 新永久侧门 ABS（`c043_bit_assign_gate_tmp.sh`，26 臂）＝**26/26 全绿**

| 组 | 臂 | 覆盖位 |
|---|---|---|
| 复合赋值的写回类型 | a1 `&=`／a2 `|=`／a3 `^=`（string × string） | PHP 侧是 string ⇒ AOT 逐字节同（`string|616260`、`616267`、`000007`） |
| ★string 结果被按标量消费 | a4 `> 0`／a5 `strlen`／a6 `(int)`／a7 拼接／a8 `$x + 1`／a9 `===`／a10 真值判定 | 全部与 PHP 同：`a4=GT`（PHP 8 把 int 0 转成 `"0"` 再比串）、`a6=0`、`a8=CAUGHT\|string + int`、`a10=1\|string` |
| 数组键／循环／外提 | a11 位结果当数组键／a12 循环内三形 | `hit\|ab`、`stringstringstring` ⇒ LICM 与哈希键路径无错位 |
| int × int 守卫 | a13–a17 `&= \|= ^= <<= >>=` | 全部 `integer`（8／7／5／12／-4）⇒ **没有**把 int 形改宽成串形 |
| 一元 `~` 消费面 | a18 `~$s`／a19 再赋／a20 `strlen`＋比较 | `string|9e9d9c` ✓ |
| ★复合赋值的**抛出**面 | a21 `$a &= [1]`／a22 `$a &= 1`（串）／a23 `$a <<= -1`／a24 `$a %= 2`（-5）／a25 `$a %= 0`／a26 `$a ^= 1` | 全部 `CAUGHT` **且 `RET` 缺席、`tail` 照打** ⇒ 站点＋路由＋「抛出后写回不得执行」三件事同时成立；a24 `-1` 是甲型在 `%=` 形上的复证，a25 是 `Modulo by zero` |

`C043ABS_DONE arms=26 same=26 diff=0 compile_fail=0 zig_escape=0 bad_probe=0 repo_build_residue=0` @102 s。

### 42.2 F-58-b 判**证伪**，机制两条（都是读实不是推断）

1. **`Value.asInt()` 是全函数**：NaN-boxing 下依次试 `TAG_INT_MARKER` → `isBigInt()` → 「非 QNAN 则按 float 回整」，**全部落空时 `return 0`**，
   既不 panic 也不 trap ⇒ 即便真有"声明 int 实装 string"的错位，症状也是静默 0 而不是崩溃（这正是我担心的形态，但下一条把它排除了）。
2. **位运算结果寄存器没有任何消费点插 `.asInt()`**：R-167 落地时我保留的是 `reg_N = try runtime.php_bit_and(…)` 的 **Value 形态赋值**
   （与旧形 `Value.initInt(…)` 同形），而 `writePhpValueExpr` 对任何标签的分支**都只打印 `reg_N`**（源码注释原文「所有寄存器都是 Value 类型，直接使用」）
   ⇒ `.i64` 声明在这里只是**元数据**，不生成拆箱代码 ⇒ a1–a20 的 20 枚消费位实测全绿即闭合。

★结论：**F-58-b 撤销**（不建代码项，仅留本门为永久守卫）。同时留下一条可复用的判据：
**本仓"声明类型 vs 实装值"的风险不能用 panic 探到**（`asInt/asBool` 都是静默兜底：`asBool` 直接读 `(val & 0x1)`），
只能靠**逐字节差分**探 ⇒ 任何"类型推断可跳过检查"的方案都必须先有 ABS 这样的消费面门，否则错值不可见。

### 42.3 F-60 定价补齐：位运算**没有**引入新型代价（实测）

同代、同档、同调用数的对照（ReleaseSmall，n=3,000,000，三轮中位）：

| 臂 | 每轮调用构成 | 中位 |
|---|---|---|
| `$s += $i & 0xFF` | `php_bit_and` ＋ `php_add` | **1583 ms** |
| `$s += $i + 1` | `php_add` ＋ `php_add` | **1597 ms** |

⇒ **`php_bit_and ≈ php_add`**（差值在噪声内，且位运算侧还略快）。
所以 R-167 测到的位运算热点 **+32%** 不是"位运算比算术贵"，而是**位运算第一次付了算术在 R-165/R-166 已经付过的钱**
（改前位运算是零调用的内联形）。
★直接推论：**任何"快路"都不能只对位运算开**——同一守卫若只覆盖 `& | ^ << >>`、不覆盖 `+ - * / %`，
等于重审老铁已经批准的 R-165 代价，属口径不一致（这也是我不擅自做快路的理由）。

### 42.4 仍缺的一个数（且我拒绝用估算代替）

★**语料级稀释比未测**。两条不可用与一条待批：

| 途径 | 判定 |
|---|---|
| 主回归报表 `regression_report.md` | **无耗时列**（只有 Total/Pass/Fail/Skip 与失败明细）⇒ 拿不到逐枚 runtime |
| 影子门的 old 侧 `/tmp/c010_prefix_backup/php-interpreter.prefix` | md5 `be305cfa…` 是 **R-145 代**，与 r166 之间隔了 R-160/163/165/166 四代发射变更 ⇒ 用它 A/B 会把 R-165 的算术路由代价混进 F-58 的读数，**不是同代对照** |
| `git worktree add --detach /tmp/… df31715` ＋ 独立构建 | 唯一能得到**同代修前二进制**的办法；会写 `.git/worktrees`（可 `git worktree remove` 撤销）⇒ 属"动仓库状态"，**先请示**（§六） |
| 已有的同代微基准 | 修前 `1ebb5a8b…` vs 修后 `c514f194…` 跑**同一对 bench 文件**：bit 2119→2803 ms（+32%）、mod A 456→473 ms（+2～4%，且 A≡C）⇒ 微基准侧代价已闭合，缺的只是"这个代价在真实脚本总耗时里占多少" |

## 43. R-169（2026-10-15）：F-59 落地 —— 算术族拒绝对象操作数 ＋ 消息改用类名 ＋ 增量族第三套措辞

老铁两项裁定：**F-60 取乙（接受现状，不做快路）**、**F-59 本轮直接修**。
本轮是**纯模板轮**（没动 `optimizer.zig`／`native_linker.zig`／`ir_generator.zig`／`constant_folder.zig`）
⇒ 生成码应逐字节中性 ⇒ 影子判据比 R-167 更强：**`changed_rows` 必须为 0**。

### 43.1 肇因（读实）

```zig
// runtime_lib_template.zig: checkArithmeticOperand
if (v.isString()) { … return hasNumericPrefix(str); }
return !v.isArray();          // ★对象直接通过
```

⇒ `$o + 1` 既不抛也不报，对象被 NaN-boxing 兜底成 `0.0` ⇒ **静默得 float**（门 OBJ 修前实测 o1 `RET|1.0`、o3 `RET|-1.0`、o9 `RET|-0.0`）。
另两条同源缺陷：① 操作数消息用 `valueTypeName` ⇒ 对象打成 `"object"`；② `php_increment/php_decrement` 的末路
`return try php_add/sub(val, initInt(1))` ⇒ 一旦①修好，`$o++` 会被接成算术措辞而不是 PHP 的增量措辞。

### 43.2 PHP 8.5.8 真值矩阵（资产 `/tmp/r169/truth.php`＋`/tmp/r169/inc.php`，逐枚实测）

| 面 | 实测 |
|---|---|
| 二元算术对象面 | `Foo + int`／`int + Foo`／`Foo - int`／`int - Foo`／`Foo * int`／`Foo / int`／`Foo % int`／`Foo ** int`／`Foo + Foo` —— **自然顺序 ＋ 类名**（与位运算族「对象恒排前」**不同** ⇒ 两套消息函数不合并） |
| 一元取负 | `-$o` ⇒ **`Foo * int`**（与数组面同措辞） |
| ★检查次序 | `$o / 0` ⇒ `Foo / int`（**操作数类型检查先于除零**）⇒ o10 是次序臂，AOT 修前给 `DivisionByZeroError`（次序反了） |
| ★`__toString` 不豁免 | `Strable + 1` ⇒ `Unsupported operand types: Strable + int` ⇒ **不能**借隐式转串放行 |
| ★★我的顾虑被实测否证 | 我原本怕 `DateTime - DateTime` 是 DateInterval 合法差、 blanket 拒绝会引入 over-fatal。实测 **PHP 8.5.8 就是抛** `Unsupported operand types: DateTime - DateTime`（取差要靠 `diff()`）⇒ **「对象一律拒」就是 PHP 正确行为**，无需特例 |
| 增量族（第三套措辞） | `++$o`／`$o++` ⇒ `Cannot increment Foo`；`--$o`／`$o--` ⇒ `Cannot decrement Foo`（pre/post 同文本，可捕获） |
| 增量族其它 | `$arr++` ⇒ `Cannot increment array`；`$b++`（bool）⇒ `Warning: Increment on type bool has no effect, this will change in the next major version of PHP`；`"a"++` ⇒ Deprecated 提示改用 `str_increment()`；`$o > 0` ⇒ `Notice: Object of class Foo could not be converted to int` 后返回 true |

### 43.3 门 OBJ（`c044_arith_object_gate_tmp.sh` `367bd7564fd1e4f895711c65bf42a3af`）三段读数

| 档 | 读数 | 内容 |
|---|---|---|
| **修前（24 臂）** | `arms=24 same=7 diff=17 aot_caught=2 zig_escape=0 compile_fail=0 bad_probe=0` @118s（表身 md5 见下方更正①） | 红＝**o1..o17** 全枚（对象算术 15 ＋ 语句位 o16/o17）；绿＝守卫 **o18..o24**（拼接 `$s . "x"`、`null + 1`、`true + 1`、`$o & 1`（R-167 已收，复证「对象排前」未被改坏）、`1 + 2`、`'5' + 2`、`$d1->format("Y")`） |
| **中间态（11 臂）** | `arms=11 same=4 diff=7 aot_caught=6` @54s（快照 `c044_obj_increment_intermediate_R169_tmp.tsv` `cfc54f6d…`） | ★只改 `checkArithmeticOperand`、**未加增量守卫**时，`$o++`/`++$o`/`$o--`/`--$o`/语句位 五枚全部抛成 `Unsupported operand types: Foo + int` ⇒ **把一种错换成另一种错**。这就是 `throwCannotIncDecError` 必须同批落地的实测依据（R-165 半修教训的复发预防） |
| **落地后（35 臂）** | `arms=35 same=33 diff=2 aot_caught=24 zig_escape=0 compile_fail=0 bad_probe=0 repo_build_residue=0` @171s | 17＋5 枚转绿；★残红**恰好只有** i8（bool 增量缺 Warning）与 i11（数组增量措辞）＝下面 F-61 的两枚登记红，**没有第三枚** ⇒ 收口范围与裁定一致 |

抽查四枚关键口径（落地后 AOT 列）：`o9 → Foo * int`、`o10 → Foo / int`（次序对）、`o13 → DateTime - DateTime`、`i1 → Cannot increment Foo`、`o16`（语句位）`→ CAUGHT`（DCE＋路由都在）。

### 43.4 落地清单（**全部在模板**，4 处）

| # | 位置 | 变更 |
|---|---|---|
| 1 | `checkArithmeticOperand` | 新增 `if (Value_isObject(v)) return false;`（含「DateInterval 特例经实测不存在」的取证注释）⇒ 七处算术站点（add/sub/mul/div/mod/pow/neg）一次性收口，**不新造窄判据**（规则 30） |
| 2 | `throwUnsupportedOperandError` | `valueTypeName` → `operandTypeName`（自然顺序保留，只换类型名口径）⇒ 实测 `int + Foo` ✓ |
| 3 | `throwNegateOperandError` | 同上 ⇒ `-$o` ⇒ `Foo * int` ✓ |
| 4 | `php_increment`／`php_decrement` 末路 ＋ 新 helper `throwCannotIncDecError` | 对象走第三套措辞 `Cannot increment\|decrement <类名>`；`++` 的发射是 `.call` ⇒ 已有 `generatePostCallExceptionCheck` 路由（实测 o16/i5 语句位可捕获），**本批无需改发射器** |
| — | `php_bitwise` 的对象提前拦截 | **保留**（理由改为「位运算族要对象排前」，与算术族口径不同），并把旧注释里「`checkArithmeticOperand` 对对象放行 ⇒ 见 F-59」更新为已落地事实 |

★`valueTypeName` 的其余 9 处调用点（`count()` 的 `must be of type array, object given` 等）**逐字不动**——那里的 "object" 措辞本来就是对的。

★**波及面已实测穷举**（grep 全模板的内部调用者，只这三类）：`php_increment`／`php_decrement` 的末路（本批已加对象守卫）＋ `pow()` 内置（`return php_pow(args[0], args[1])`，`:31798`）⇒
`php_pow` 的符号串实测为 `"**"`。★★**该结论只测了 PHP 侧就断言 AOT 也同，属未验证断言——R-170 实测否证**：内置名表把 `pow` 映射到 **另一个函数** `php_pow_func`（`native_linker.zig:4288`），其函数体无操作数检查，故 `pow($o,2)` 落地后仍静默得 `double 0.0`（门 BLT b17 红），而 `2 ** [1]`（b26）是绿的 ⇒ 同面两条实现。更正与修法见 §44。
★**`array_sum`／`array_product` 不经 `php_add`/`php_mul`**（`php_array_sum:22822` 是内联 `sum_int += …` 累加，全模板内 `php_mul(` 无内部调用者）⇒ 本批改动**不会**把它们从「返回值」推成「抛异常」。
★顺带取到一组**新的未覆盖面**（登记为 **F-62**，本批不修、且待链跑完再补臂）：PHP 对**内置数值形参**用的是**第四套措辞**＝参数类型校验，而非操作数措辞——
`abs($o)` ⇒ `abs(): Argument #1 ($num) must be of type int|float, Foo given`；`intdiv($o, 2)` ⇒ `… must be of type int, Foo given`；`fdiv($o, 2)` ⇒ `… must be of type float, Foo given`；`bcadd($o, "1")` ⇒ `… must be of type string, Foo given`；
而 `array_sum([$o])` ⇒ **不抛**，只 `Warning: array_sum(): Addition is not supported on type Foo` 后返回 `0`；`max($o, 1)`／`min($o, 1)` ⇒ `Notice: Object of class Foo could not be converted to int` 后分别返回对象与 `1`（比较族）。

### 43.5 新立 **F-61**（增量/比较族，登记不修）

| 子面 | 实测 | 备注 |
|---|---|---|
| i11 `$arr++` | PHP `Cannot increment array` ／ AOT `Unsupported operand types: array + int` | 数组在 R-165 就被拒 ⇒ **本批未改其行为**，措辞差属存量 |
| i8 `$b++`（bool） | PHP 先打 `Warning: Increment on type bool has no effect…` 再返回 `true` ／ AOT 只返回 `true` ⇒ **本臂实测的差异只有一行 Warning** | ★另有一处**代码阅读观察（未取运行证据）**：`php_increment` 对 bool 的返回值写的是 `if (val.asBool()) 2 else 1`，而本臂走的是「先取旧值再回存」的 lowering ⇒ 两者不一致说明**「增量表达式结果被直接使用」的形**（如 `echo $b++;` 之外的 `$y = php_increment($b);` 类路径）尚未有臂覆盖 ⇒ 留给 F-61 一起测 |
| （未入门）`$o > 0` | PHP `Notice: Object of class Foo could not be converted to int` ＋ `true` | 比较族，非算术站点 ⇒ 留给 F-61c |

### 43.6 本轮自我更正（两条）

| # | 事件 | 更正动作 |
|---|---|---|
| ① | **修前档 TSV 被终档覆盖**：35 臂跑完后 `$OUT` 写回同一文件，而我在建门 24 臂档与落地 35 臂档之间**没有先快照**（中间态倒是有快照）⇒ 修前表身 md5 只能引本轮日志与逐臂打印，不能引文件 | 复测口径改为「门脚本 md5 ＋ DONE 行 ＋ 逐臂打印」三件；纪律补一条：**每次扩臂后立刻快照，再跑下一档** |
| ② | 两次误操作：一次把 Edit 的 `file_path` 写成占位路径（工具报错，未落盘）；一次锚点「获取 Value 的 PHP 类型名称」在文件里**出现两次** ⇒ 编辑被拒（未产生半改状态） | 锚点必须验唯一性；同轮内三次 Edit 全部一次成功才继续 |

### 43.7 验收链**分两段**（★环境事故：磁盘写满令腿静默失败）

#### 43.7.1 第一段 `c045_r169_acceptance_chain_tmp.sh`（2026-10-15 16:44:16 起，链头代次 `bin=c514f194… tpl=40f7802f…`）

**前 12 腿全部达标后，在 ZCENSUS 腿被 `no space left on device` 打断**，之后 13 腿 `rc=1 wall=0s`（根本没执行），
`regression` 未跑（报表 mtime 仍是 R-167 代 `11:18:12`），`shadow` 未跑，`shadowcol` 报
`SHADOWCOL_ASSERT_FAIL gen_rows= base_rows=`（规则 29 的断言正确地拒绝了不可引用的差值 ⇒ 没产出假绿）。

| 腿 | 读数 | 判读 |
|---|---|---|
| buildtest | `rc=0` | ★开链前先跑过（R-166 教训入规） |
| **OBJ（主门）** | `arms=35 same=33 diff=2 aot_caught=24 zig_escape=0 compile_fail=0 bad_probe=0 residue=0` @172s | 22 枚修前红全收，残红恰为登记的 F-61 两枚（i8/i11），**没有第三枚** |
| ABS | `arms=26 same=26 diff=0` @108s | ★本批改的是**共用的** `checkArithmeticOperand` 与消息 helper ⇒ 刚收口的位运算消费面零扰动（规则 30） |
| MSR | `arms=74 same=74 diff=0 aot_caught=28` @356s | 全绿保持 |
| F45FACE | `raise_lost=0 preserved=19 both_match_php=12 both_red=7` | 与 R-167 定档逐字同 ⇒ 守卫未被改宽/改窄 |
| OPS | `arms=26 same=25 diff=1 aot_caught=16` | 与 R-167 改档同值；★消息 helper 换名后**非对象形参的措辞一字未动**（12 枚数组/字符串臂全绿） |
| PD / S / AC | `20 18/2` ／ `47 same=47 diff=0` ／ `13 cf=8 canary=7 bare_symbol=8 zig_raw=7` | 逐字段与 R-167 全等 |
| AB（DCE A/B） | `total_rows=68 = MATCH_PHP 66 + BOTH_RED 1 + COMPILE_FAIL 1`（★全行分桶，禁 `NR>1`） | 与 R-167/R-166 分布逐字同 ⇒ 本批在语料内行为暴露 0 |
| Y / ZFACES | `12 same=5 diff=5 zig_escape=1 cf=2` ／ `10 same=9 diff=1 dangling=0` | 等值 |
| ZCENSUS 起 | **ENOSPC 打断**（`rc=1 wall=237s`，之后各腿 `wall=0s`） | ⇒ 交第二段补跑 |

#### 43.7.2 事故记录与纪律产出（两条，都是本轮新长出来的）

| # | 事实 | 产出 |
|---|---|---|
| ① | `df` 现在显示 Data 卷 `80 Gi` 可用（62% 已用），但链当时写不进 ⇒ **ENOSPC 是瞬时/回收态**，且仓库根 **`.zig-cache` 整目录在同一时点消失**。**原因我不做无据归因**（不是我删的，我也没跑过任何清理命令）；代次一致性因此**不依赖缓存目录**，改由 `bin/tpl md5` 断言证明 | 补跑链 `c046` 开头即做 md5 断言：`GENERATION_ASSERT_FAIL` 就直接拒收（规则 25） |
| ② | 腿被 ENOSPC 打死时表现为 **`rc=1 wall=0s` 的静默失败**，与"测试真的失败"在日志里长得一样 | **纪律产出：链必须做磁盘前置断言**。`c046` 每腿开始前查 `avail_gib`，`< 8 GiB` 即 `DISK_ABORT` 停链；且任一腿 `rc!=0` 立即 `LEG_FAIL` 停链，**禁止带着失败腿继续** |

#### 43.7.3 第二段补跑 `c046_r169_makeup_chain_tmp.sh`（2026-10-16 10:08:46 起，17 腿）

| 腿 | 读数 |
|---|---|
链头断言：`avail_gib=79`、`bin_md5=c514f194…`、`tpl_md5=40f7802f…` 与第一段**逐字同代**（`GENERATION_ASSERT_FAIL` 未触发）。
★全程未触发 `DISK_ABORT`，且每腿都带 `rc=0`（任一腿非 0 即停链），故本段读数可与第一段**合并为一次完整验收**。

| 腿 | 读数 | 判读 |
|---|---|---|
| ZCENSUS | `total=68 dangling=0 ok=68 other=0` | 等值 |
| X / V / W / T | `9 same=8 diff=1` ／ `29 19/10` ／ `20 7/13` ／ `22 16/5 cf=1` | 全等值注册档 |
| P / M / N / O / D8 | `78 73/5` ／ `19 red=0 green=19` ／ `7 red=0` ／ `6 red=0` ／ `defect_red=0 guard_same=14` | 全等值 |
| Q / R / U / B | `same=5` ／ `same=8 diff=1 terminate_lost=0` ／ 列聚合 `75 行 = SAME 51 + COMPILE_FAIL 22 + BAD_PROBE_PHP 2`（桶和＝75 ✓）／ `entries=497 distinct=464 dup_rows=33 diff_impl=3 identical=30` | 全等值（与 R-167/R-166 逐字同） |
| **regression** | `rc=0 wall=861s report_mtime=2026-10-16 10:55:41`；`Total 68 / Pass 67 / Skip 1`；`## 失败明细` 仅 `f004 … SKIP` | ★**零回归、回收 0 枚**（规则 27：判据取明细行存在性，不取汇总数） |
| shadow | `total=68 same=0 diff=68 miss=0 invalid=0` @1081s | 常态 |
| **shadowcol** | `gen=r169 rows=68 col_md5=f5f2bf5ef969dd091962a468bf3afcbb` ＝ base(r167) `base_md5` **同值** ⇒ **`changed_rows=0 col_identical=yes`** | ★**本批判据比 R-167 更强且达成**：纯模板轮 ⇒ 生成码逐字节中性 ⇒ 无需重冻、无需归因，`r169` 列与 `r167` 列同内容 ⇒ 下一代 BASE 仍用同一前缀 |
| 链尾 | `R169_MAKEUP_END 2026-10-16 11:13:42 ELAPSED=3896s` ＋ `R169_MAKEUP_DONE` | 规则 28 双判成立；各腿 `residue=0`、`bad_probe=0`；`.php` 原件零删除 |

★**R-169 验收结论（两段合并）＝闭合**：主门 OBJ `same=33 diff=2`（残红只能是 F-61 的 i8/i11）、ABS/MSR/F45FACE/OPS/PD/S/AC 与 AB/U/B/ZCENSUS 全部等值、
主回归 `Pass 67 / Skip 1` 零回归、影子 `changed_rows=0`。

## 44. R-170（2026-10-16）：F-59 的**漏网面**＝`pow()` 与 `**` 是两条实现 ＋ 新立 F-63

### 44.1 发现路径：门里的对照臂把 R-169 的未验证断言打回来

R-169 我在 §43.4 写了「`pow($o,2)` 与 PHP 逐字节同」，但**只测了 PHP 侧**、只读了 `wrapBuiltin_pow → php_pow` 这一行。
新门 BLT 的同源对照臂把它否证了：

| 臂 | 形 | PHP | AOT（R-170 修前） |
|---|---|---|---|
| b26 | `2 ** [1]` | `Unsupported operand types: int ** array` | **同**（绿） |
| b17 | `pow($o, 2)` | `Unsupported operand types: Foo ** int` | **`RET|double|0.0`（红）** |

根因：`native_linker.zig:4288` 的内置名表条目是 **`.{ "pow", .{ .runtime_name = "php_pow_func" … } }`** ⇒
函数调用形式**不经** `php_pow`，而 `php_pow_func`（模板 `:13123`）函数体里**一次检查都没有**，末路是
`std.math.pow(f64, base.toFloat(), exponent.toFloat())`。
★**可复用结论**：收口任何一个「既是运算符又是内置函数」的面（`pow`/`abs`/`min`/`max`/`intdiv`/`sqrt`/`fdiv`/…）
都必须**同时查这张内置名表**，否则运算符侧绿、函数侧红。普查已做：这 8 个数值内置的目标函数体
在开头 45 行内 `checkArithmeticOperand|throwUnsupportedOperandError` 命中数**全为 0**。

### 44.2 同一体内还藏着一条 **P0 级静默错值**：整数幂回绕

旧 `php_pow_func` 的整数路径是 `while (i < e) result *= b`（**无溢出检测**），且只在 `e < 64` 时走：

| 臂 | PHP | AOT（修前） |
|---|---|---|
| b27 `pow(2, 63)` | `double 9.223372036854776E+18` | **`integer -9223372036854775808`**（有符号回绕） |
| b28 `pow(10, 19)` | `double 1.0E+19` | **`integer -8446744073709551616`** |
| b24 `pow("5", 2)` | **`integer 25`** | `double 25.0` |

`php_pow` 用的是 `@mulWithOverflow`（溢出即转 float）⇒ 委托过去一并修好。b24 是**另一族**（整值数字串应得 int）⇒ 归 F-55。

### 44.3 落地（2 处，纯模板）

| # | 位置 | 变更 |
|---|---|---|
| 1 | `php_pow_func` | 整体**委托 `php_pow`**（同一语义只留一份实现，不重抄检查与溢出逻辑）。★不是"加两行检查"，因为旧体的溢出与 `e >= 64` 口径也独立错了一份 |
| 2 | `php_pow` | 补 `b == 1`／`b == -1` 早退——**下界的必要性**：下面的逐次乘法只靠溢出退出，而 `|b| == 1` 永不溢出 ⇒ `1 ** 10^12` 无界（`|b| >= 2` 至多 63 步即溢出，故其余有界）。委托后这条从 `**` 扩到了 `pow()`，故必须先补 |

★**验证读数**（同一对臂）：`1 ** 1000000000000`／`(-1) ** 999999999999`／`pow(1, 10^12)`／`pow(-1, 999999999999)` 四形 AOT 与 PHP 逐字同且**瞬时返回**（10 s 超时未触发）；`2 ** 62` 仍为 int 4611686018427387904（未误改有界整数路径）。
★「修前会挂死」这一条是**从循环结构直读**得出的（`while (i < e)` 仅有溢出出口），我**没有**在修前二进制上实测到超时；修后的瞬时返回是实测。

### 44.4 门 BLT 三段读数（`c047_builtin_numeric_object_gate_tmp.sh`，md5 `ccac79537b9a5a17e836b825694e1cf0`）

| 档 | 读数 | 快照 |
|---|---|---|
| 建门 20 臂（R-169 代模板） | `same=5 diff=15` @87s | 表身已被 28 臂档覆盖，逐臂打印见本会话记录 |
| 扩到 28 臂·**修前** | `same=7 diff=21` @122s | `c047_blt_prefix28_R170_snapshot_tmp.tsv`（`903f50a7…`） |
| **本批落地后** | `arms=28 same=11 diff=17 aot_caught=7 compile_fail=0 bad_probe=0 residue=0` @121s | `c047_blt_postfix28_R170_snapshot_tmp.tsv`（`626bd9d7…`） |

关掉的正好是 pow 族 6 枚：**b17 b21 b22 b23 转 SAME**（措辞逐字节对上，含 `int ** Foo` 的反向顺序），
**b27 b28 的负整数回绕消失**（现为 `9223372036854776000.0`／`10000000000000000000.0`）。
残红 17 枚全部**先前已登记**、本批有意不关：b1..b13＝F-62，b14/b24＝F-55，b27/b28＝**新立 F-63**。

### 44.5 新立 **F-63**：大浮点数的**记法**不合 PHP（值已对）

`9.223372036854776E+18`（PHP，科学计数）vs `9223372036854776000.0`（AOT，展开）；`1.0E+19` vs `10000000000000000000.0`。
★这**不属于**宪法 §七.7 豁免的「末位精度微差」——数值完全相同，差的是**表示法**（`var_export`／`echo` 都受影响），
且只在数量级跨过 `%g` 的指数阈值时出现。定级 P2：会改变任何涉及大浮点输出的语料逐字节对照，需先普查暴露面再动格式化。

### 44.6 验收链 `c048_r170_acceptance_chain_tmp.sh`（26 腿；判据＝影子 `changed_rows=0` ＋ Pass 67/Skip 1）

链头 11:42:33，`bin_md5=c514f194…`（与 R-169 **同代二进制**，本批纯模板 ⇒ 委托门断言「二进制不该变」已通过）、
`tpl_md5=5f86073c…`、`avail_gib=75`、buildtest `rc=0`。

| 腿 | 读数 | 判读 |
|---|---|---|
| buildtest | `rc=0 wall=13s` | 缓存重建后仍绿 |
| **BLT（主门）** | `arms=28 same=11 diff=17 aot_caught=7 zig_escape=0 compile_fail=0 bad_probe=0 residue=0` @123s | 与链外单跑**逐字段同**（表身 `626bd9d7…`）；17 枚残红全部先前已登记（F-62 13／F-55 2／F-63 2），**本批未新增任何一枚红** |
| OBJ / ABS / MSR | `35 33/2` ／ `26 26/0` ／ `74 74/0 aot_caught=28` | 三族全等值 ⇒ 委托 `php_pow` 未波及已收口面 |
| F45FACE / OPS / PD / S / AC | `raise_lost=0 preserved=19 both_match_php=12` ／ `26 25/1 caught=16` ／ `20 18/2` ／ `47 47/0` ／ `13 cf=8 canary=7 bare_symbol=8 zig_raw=7` | 与 R-169 定档逐字同 |
| AB / U / B / ZCENSUS | `68 行 = MATCH_PHP 66 + BOTH_RED 1 + COMPILE_FAIL 1`（★全行分桶）／ `75 行 = SAME 51 + CF 22 + BAD_PROBE 2` ／ `entries=497 distinct=464 dup_rows=33 diff_impl=3 identical=30` ／ `total=68 dangling=0 ok=68` | 全等值（桶和＝行数自证） |
| Y/ZFACES/X/V/W/T/P/M/N/O/D8/Q/R | 全部与注册档一致 | 零扰动 |
| **regression** | `rc=0 wall=862s report_mtime=2026-10-16 13:21:53`；`Total 68 / Pass 67 / Skip 1`；明细仅 `f004 SKIP` | ★**语料内 pow() 的三处调用点（f043/f048/f179）无一掉值** ⇒ 委托未改坏有界整数路径 |
| shadow / shadowcol | `68 same=0 diff=68` @1142s ／ **`gen=r170 col_md5=f5f2bf5e… = base(r169) 同值 ⇒ changed_rows=0 col_identical=yes`** | 纯模板轮的强判据达成 ⇒ 不重冻 |
| 链尾 | `R170_CHAIN_END 13:40:55 ELAPSED=7102s` ＋ `R170_CHAIN_DONE`；全程 `avail_gib` 从 75 缓降到 71、未触发 `DISK_ABORT`；各腿 `residue=0`、`bad_probe=0` | R-169 事故的三重自保（`GENERATION_ASSERT_FAIL`／`DISK_ABORT`／`LEG_FAIL`）**首次全链生效** |

## 45. R-171（2026-10-16）：F-55 落地 —— 算术结果的 int／float 分叉按 PHP 的「字面语法」规则收口

纯模板轮（未动任何 `.zig` 编译器文件 ⇒ 二进制仍是 `c514f194…`，链内断言）。

### 45.1 PHP 的规则被实测钉死：由**字面语法**决定，不是由「数值是否为整」决定

真值资产：`/tmp/r171/matrix.php`、`m2.php`、`abs.php`、`absmin.php`。

| 实测 | 结论 |
|---|---|
| `'5' + 1` = int 6，但 `'5.0' + 1` = **double 6.0**、`'0.0' + 1` = double 1.0 | 有 `.` 就是 float，即使值是整数 |
| `6 / 2` = **int 3**、`5 / 2` = double 2.5、`'6' / 2` = int 3、`'6.0' / 2` = double 3.0、`5 / 2.5` = double 2.0 | `/` 只在「两侧皆 int 语法 ∧ 整除」时给 int |
| `'5abc' + 2` = **int 7**、`'5abc' - 2` = int 3、`'5abc' * 2` = int 10、`'5abc' / 1` = int 5、`'5abc' ** 2` = int 25、`'5abc' + '6def'` = int 11（均配 `A non-numeric value encountered`） | 二元算术看**数字前缀**，尾随垃圾不影响类型判定 |
| `' 5' + 1` = `'5 ' + 1` = int 6、`'0x10' + 1` = int 1（前缀只吃到 `0`）、`'5e2' + 1` = double 501.0、`'5.5abc' + 2` = double 7.5 | 首尾空白允许；前缀里有 `.`／指数 ⇒ float |
| `'99999999999999999999' + 1` = **double 1.0E+20** | 越界 ⇒ float |
| `abs('5')` = int 5、`abs(' 5')` = int 5、`abs('-5.0')` = double、**`abs('5abc')`／`abs('0x10')` = TypeError** | ★内置形参是**严格 `is_numeric`** 口径 ⇒ 与二元算术的宽松前缀口径**刻意不能合并** |
| `abs(PHP_INT_MIN)` = **double 9.223372036854776E+18**；`-PHP_INT_MIN` 同 | 越界取绝对值 ⇒ float（`php_neg` 早就这么处理，`php_abs` 没有） |

### 45.2 四处缺口（门 NST 修前 18 枚红，逐处已定位到函数）

| # | 缺口 | 证据臂 |
|---|---|---|
| R1 | `php_pow`／`php_abs` 的整数路径要求 `.isInt()`；`php_div` 的整除判定只看 `isInt/isNull/isBool` ⇒ **整数字面量串一律落 float** | n2 n5 n7 n10 n29 n30（`'6' / 2`、`'5' ** 2`、`abs('5')`、`pow('5',2)`…） |
| R2 | `tryAsInt` 只收「整串 `^[+-]?\d+$`」⇒ **前缀数字串**落 float：`'5abc' + 2` 得 `7.0`（PHP `7`） | n11..n19，★其中 n11 就是门 OPS 唯一残红 **g4 的真身** |
| R3 | `php_abs` 对 `i64` 最小值直接 `-i` ⇒ **回绕**，AOT 返回 `integer -9223372036854775808`（值与符号皆错） | n31（该臂另叠 F-63 记法面） |
| R4 | `php_pow` 整条**漏发** `A non-numeric value encountered`（值对、警告缺） | n15 |

★`php_add/php_sub/php_mul` 本来就用 `tryAsInt` ⇒ 那三族的"整数字面量串"形一直是绿的（这也是为什么 R2 只在 n11..n19 这类**前缀串**上才现形）。

### 45.3 落地（5 处，纯模板）

| # | 位置 | 变更 |
|---|---|---|
| 1 | 新 `tryAsIntLoose` | 宽松前缀判据（跳首空白、可选符号、吃数字；后跟 `.`／`e`／`E` ⇒ null；`parseInt` 失败 ⇒ null；非串走 `tryAsInt`）。★与 `tryAsInt` **并存不合并**，理由见 45.1 的 abs 行 |
| 2 | `php_add`／`php_sub`／`php_mul` | 三处判据换 `tryAsIntLoose`（修 R2） |
| 3 | `php_div` | `lhs_is_int`／`rhs_is_int` 改走 `tryAsIntLoose`；**整除与 INT48 范围判断一字未动** |
| 4 | `php_pow` | int 路径改 `if (tryAsIntLoose(base)) \|b\| { if (tryAsIntLoose(exp)) \|e\| { …`，并**改用判据解析出的值**（旧写法对字符串寄存器调 `asInt()` 是 NaN-boxing 兜底，会读成 0）；补两行 `emitArithmeticStringWarningIfNeeded`（修 R4，次序＝先警告再类型检查） |
| 5 | `php_abs` | 走**严格** `tryAsInt`；并补 `i == minInt(i64)` ⇒ `initFloat`（修 R3，形与 `php_neg` 一致） |

### 45.4 门 NST（`c049_numeric_string_type_gate_tmp.sh`，32 臂，md5 `a728ed983f390bbd35445fbf5a420c42`）

| 档 | 读数 | 快照 |
|---|---|---|
| 修前（2026-10-16，R-170 代模板） | `arms=32 same=14 diff=18 aot_caught=1 compile_fail=0 bad_probe=0` @145s | `c049_nst_prefix32_R171_snapshot_tmp.tsv`（`7b0d5394…`） |
| 落地中途（R1..R3 之后、R4 之前） | `same=29 diff=3`（残 n9 n15 n31） | — |
| **全部落地后** | `arms=32 same=30 diff=2 aot_caught=1 compile_fail=0 bad_probe=0 residue=0` @147s | `c049_nst_postfix32_R171_snapshot_tmp.tsv`（`4766181…`） |

★18 枚修前红 → 2 枚残红，且这 2 枚**都不是本批承诺面**、先前已各自登记：
`n9 abs('5abc')`＝PHP 抛 `Argument #1 ($num) must be of type int|float, string given` 而 AOT 给 `5.0` ⇒ **F-62**；
`n31 abs(PHP_INT_MIN)` ⇒ 类型已修对（`double`），残差只是记法 `9223372036854776000.0` vs `9.223372036854776E+18` ⇒ **F-63**。
⇒ 我特意为这个交叉面加了 **n32**（只报 `gettype` 列表，与记法无关）作为真正的验收臂，它已转绿。

★**连带改档**：门 OPS 由 `same=25 diff=1`（残红 g4）⇒ 应为 **`same=26 diff=0`**，即 OPS 自本批起**无注册红**；
门 BLT 由 `same=11 diff=17` ⇒ 应为 `same=13 diff=15`（b14 `abs("5")`、b24 `pow("5",2)` 转绿）。两处均登记于此、不改已入库门头注释。

### 45.5 验收链 `c050_r171_acceptance_chain_tmp.sh`（28 腿，判据＝影子 `changed_rows=0` ＋ Pass 67/Skip 1）

| 腿 | 读数 | 判读 |
|---|---|---|
| 链头 | `14:08:57 bin_md5=c514f194…（未变，纯模板轮） tpl_md5=15b9d494… avail_gib=69` | 代次断言通过 |
| buildtest | `rc=0 wall=3s` | — |
| **NST（主门）** | `arms=32 same=30 diff=2 aot_caught=1 compile_fail=0 bad_probe=0 residue=0` @142s | ★18 枚修前红 → **只剩 2 枚登记交叉面**（n9＝F-62、n31＝F-63 记法），本批承诺面全关 |
| **OPS** | `arms=26 **same=26 diff=0** aot_caught=16` | ★**改档达成：门 OPS 自 R-171 起零注册红**（g4 由 F-55 收口）＝本工单第一道完全全绿的操作数门 |
| **BLT** | `arms=28 same=13 diff=15`（修前 11/17） | 恰如预告：b14 `abs("5")`、b24 `pow("5",2)` 转绿 ⇒ 结果类型面同时修好了内置函数侧 |
| OBJ / ABS / MSR | `35 33/2` ／ `26 26/0` ／ `74 74/0 aot_caught=28` | 三族零扰动（R-168～R-170 的成果未被本批改宽/改窄） |
| F45FACE / PD / S / AC | `raise_lost=0 preserved=19 both_match_php=12` ／ `20 18/2` ／ `47 47/0` ／ `13 cf=8 canary=7 bare_symbol=8 zig_raw=7` | 全等值（PD 的 2 枚＝F-53 恒红） |
| AB / CENSUS / U / B / ZCENSUS | `68 行 = MATCH_PHP 66 + BOTH_RED 1 + COMPILE_FAIL 1` ／ `68 = bit_only 24 + modpow_only 2 + both 9 + neither 33` ／ `75 行 = SAME 51 + CF 22 + BAD_PROBE 2` ／ `entries=497 distinct=464 dup_rows=33 identical=30` ／ `total=68 dangling=0 ok=68` | 与 R-170 档**逐字同**（全行分桶，桶和＝行数自证） |
| Y/ZFACES/X/V/W/T/P/M/N/O/D8/Q/R | 全部等值注册档 | 零扰动 |
| **regression** | `rc=0 wall=800s report_mtime=2026-10-16 15:44:43`；`Total 68 / Pass 67 / Skip 1` | ★本批改的是**共享的结果类型判定**，语料零回归（值级改动若错，Pass 会掉） |
| shadow / shadowcol | `68 same=0 diff=68` ／ **`gen=r171 col_md5=f5f2bf5e… = base(r170) 同值 ⇒ changed_rows=0 col_identical=yes`** | ★连续**第三个**纯模板轮达到发射中性（r169/r170/r171 三代同值） |
| 链尾 | `R171_CHAIN_END 16:02:22 ELAPSED=6805s` ＋ `R171_CHAIN_DONE`；31 腿 `rc=0`、`residue=0`、`bad_probe=0` | 三重自保全程未触发停链 |

★**资产**：门 NST 脚本 `a728ed983f390bbd35445fbf5a420c42`；修前表身 `7b0d53941509396faf7d83176ad56c91`、修后 `476618159cf60242e72e5394bb9f2262`；
模板 md5 `15b9d4941267ad099b85af1ed3867106`（`5f86073c…` 作废，二进制仍 `c514f194…`）；链 `c050_r171_acceptance_chain_tmp.sh`＋`.log`；
真值资产 `/tmp/r171/{matrix,m2,abs,absmin}.php`；影子列 `c010_shadow_newside_r171_tmp.txt`（表身 `f5f2bf5e…`，与 r169/r170 同值）。


---

## 46. R-172（2026-10-16）：F-62 落地＝乙型「模板内集中 helper」＋**全数值族**＋c／d 两段一并修

老铁三项裁定：落地形态＝**乙**（模板内集中 helper＋逐函数入口，不改发射器元数据）、覆盖范围＝**全数值族**、
F-62 里另外两套机制（array_sum/array_product 的元素级 Warning、max/min 的比较族 Notice）＝**c＋d 全修**。
主门 BLT（`c047`）由 28 臂扩到 **129 臂**，修前注册红 **85** ⇒ 修后 **3**（＝关闭 **82** 枚，剩 3 枚全是先前已登局面）。
★本批**不是纯模板轮**：另经老铁批准两项发射器/优化器**表位一行级**改动（`fdiv` 的 `may_raise`、LICM 纯函数名单摘三枚），
⇒ 二进制代次由 `c514f194…` 进到 `bdd3af32…`（连续三代模板轮之后的第一次重编译）。

### 46.1 只读核查先把「甲」否掉：发射器根本没有形参类型元数据，而且 AOT 没有动态内置分发

| 核查项 | 实测结论（文件∶行） | 对形态选择的意义 |
|---|---|---|
| `BuiltinInfo` 字段 | `native_linker.zig:3976-3981` 只有 `runtime_name`／`needs_allocator`／`may_raise`／`ref_params` **四枚** | 甲型要新增整张形参类型表，且必须逐名手写 ⇒ 与乙型的逐入口一字不差，却没换来任何覆盖面 |
| 动态内置分发 | 无。调用点在发射期静态解析（`mapToRuntimeFunction:3965`），未知名直接 `undefined function` | ⇒ 中央发射时校验与「在被调函数体内校验」**覆盖面完全等价**，而后者还顺带覆盖任何未来的动态路径 |
| `may_raise` 的消费点 | `functionMayRaise:3913` ＋ 四条发射路径（`:22904/:23196/:23384/:23432` 的 `try`／非 `try` 分支）＋ 路由块两处（`:23488/:23653`） | ⇒ `php_fdiv` 改 `!Value` 时**只需**翻表位，四条路径与路由块自动对齐（已由门 BLT b39/b40/b88 实测：可编译、可捕获） |
| 同措辞的既有实现 | 模板 `php_check_param_type:6519` 早已产出 `{fn}(): Argument #{d} (${p}) must be of type {t}, {g} given`，但它服务于**用户函数声明形参**，且 `given` 走 `phpGetValueTypeName` ⇒ 对象印 `object` | ★不复用、不改它（规则 30：改 `valueTypeName` 那一族会波及 `count()` 等 9 处本来正确的措辞）⇒ 新建 `rejectParamType`，用 `operandTypeName` 给**类名** |
| 语料暴露 | 数值内置 ∪ 命中 **30/68 枚、247 处调用**（`log` 28／`number_format` 25／`array_sum` 22／`abs` 19／`min` 15／`max` 13／`round` 12／`sqrt` 12…） | ⇒ 校验口径只要偏严一格（例如拒首尾空白串或 bool），主回归立刻红 ⇒ 本批为此专设 **C 段 23 枚合法强转守卫臂**，先于语料把口径钉住 |
| 常量折叠是否绕过 | `constant_folder.zig` 对这些内置**无折叠**；`optimizer.zig:935` 的 `pure_functions` 是 **LICM 提升**名单不是折叠 | ⇒ 字面量臂（`abs("5abc")`、`intdiv("5a",2)`…）确实走运行时校验，读数是有效的（R-167 的「折叠绕过」教训已排除） |

### 46.2 PHP 8.5.8 的口径（逐枚实测；真值资产 `/tmp/r172/f62_param_truth{,2,3,4}_tmp.php`、`f62_names_tmp.php`、`f62_names2_tmp.php`、`f62_edge_tmp.php`、`f62_tiebreak_tmp.php`）

| 传入 | `int` 形参（intdiv#1/#2、round#2、number_format#2） | `float` 形参（sqrt/exp/log/log10/fdiv/fmod/三角/atan2/hypot/deg2rad/rad2deg） | `int\|float`（abs/floor/ceil/round#1/number_format#1） |
|---|---|---|---|
| int／float | 整值且域内 ⇒ 静默；非整值 ⇒ `Deprecated: Implicit conversion from float 5.9 to int loses precision` 后**向零截断**（`intdiv(-5.9,2)`=**-2**）；NAN/INF/`1e19` ⇒ `TypeError …, float given` | 原样 | 原样 |
| bool | ⇒ 1／0 静默（`abs(true)`=**int 1**） | ⇒ 1.0（`sqrt(true)`） | ⇒ int |
| null | ⇒ `Deprecated: <fn>(): Passing null to parameter #N ($p) of type int is deprecated` 后按 0 继续 | 同（类型文本 `float`） | 同（类型文本 `int|float`；★`number_format` 的 `$num` 是**唯一**措辞分叉点：TypeError 印 `int\|float`、Passing-null 印 `float`） |
| 数值串 | `"5"`/`"+5"`/`" 5 "`/`"5 "` ⇒ int；`"5.0"` ⇒ 静默取整；`"5.5"` ⇒ `Deprecated: Implicit conversion from float-string "5.5" to int loses precision`（★带引号原文，与 float 版**不同句式**）；`"1e19"`/`"99999999999999999999"` ⇒ `string given` | ⇒ 值（`sqrt("4")`=2.0） | `"5"`⇒int、`"5.5"`⇒float、`"1e3"`⇒**float 1000.0**、`"1e19"`⇒float |
| **前导数值串** | `"5a"`/`"0x1A"`/`""`/`" "` ⇒ `TypeError …, string given` | 同 | 同（★与二元算术的**宽松**口径**刻意相反**，R-171 的 `tryAsIntLoose` 不可复用于此） |
| array | ⇒ `array given` | ⇒ `array given` | ⇒ `array given` |
| object | ⇒ **类名** `Foo given`；★带 `__toString` 的**照样拒**（实测 `abs($b)` ⇒ `Bar given`） | 同 | 同 |
| 次序 | 校验**先于**运算：`intdiv($o, 0)` ⇒ 参数类型错而非 DivisionByZeroError；`intdiv(5, null)` ⇒ 先 Deprecated 再 DivisionByZeroError | | |

**元素级（c 段，`array_sum`/`array_product`）＝只 Warning 不抛**：
`int/float` 计入；`bool/null` 静默计入 1/0；完整数值串按 int/float 语法计入；前导数值串 ⇒ `Warning: A non-numeric value encountered` 后计入前缀（`array_sum([1,"5a",2])`=8、`array_product([2,"5a"])`=10）；
非数值串 ⇒ `Warning: <fn>(): Addition|Multiplication is not supported on type string` 后**计入 0**（`array_product([2,"abc"])`=0）；
array／object ⇒ 同句式（`on type array`／`on type <类名>`）但**整枚跳过**（`array_product([2,[1]])`=2、`array_sum([1,$o,2])`=3）；
容器实参非数组 ⇒ `TypeError: <fn>(): Argument #1 ($array) must be of type array, <类名> given`。

**比较族（d 段）**：object vs int ⇒ `Notice: Object of class <X> could not be converted to int` 后按 **1**；vs float ⇒ 同句式 `to float` 后按 **1.0**；
vs string／vs array ⇒ **无 Notice 且对象恒大于**（`$o > "abc"`、`$o > [1]`、`$o <=> "a"`、`$o <=> [1]` 全 true/1，而 `[1] > $o`、`"abc" > $o` 全 false）；vs bool ⇒ 走 bool 比较无 Notice。
★同值并列的取法**两侧不对称**（`f62_tiebreak_tmp.php` 八臂矩阵实测）：`min($o,1)`=**int 1**、`min(1,$o)`=**Foo**（并列取**后者**），
`max($o,1)`=**Foo**、`max(1,$o)`=**int 1**（并列取**前者**）⇒ 旧 `php_min` 用 `< 0` 是与 max 对称的写法，本身错。

### 46.3 门 BLT 扩臂 28 ⇒ **129** 与三段读数（脚本 md5 `12ae49834c8426d5ec9a2868cd94835c`）

| 段 | 臂 | 内容 | 修前 | 首次落地 | 终档 |
|---|---|---|---|---|---|
| 旧 28 臂 | b1–b28 | R-170/R-171 档原样保留（**逐字未改**，用快照 `c047_gate_28arm_pre_R172_snapshot_tmp.sh` 对段 diff 自证） | 13 SAME ／ **15 DIFF** | 24 绿 | **25 SAME ／ 3 DIFF**（b5＝F-62b、b27/b28＝F-63） |
| A param-type | b29–b67 | 逐函数一枚对象面＋array／非数值串／前导数值串／越界 float／`Argument #2` 面 | **39／39 全红** | 39 绿 | 39 绿 |
| B null-Deprecated | b68–b72 | `intdiv/sqrt/floor/number_format/round` 的 Passing-null | **5／5 全红** | 4 绿／b72 红 | 5 绿 |
| C 合法强转守卫 | b73–b95 | `" 5 "`／`"+5"`／`"1e3"`／`"5.0"`／bool／整值 float／精度损失 Deprecated | 20 SAME ／ **3 DIFF**（b75,b80,b81） | 23 绿 | 23 绿 |
| D sum/product 元素 | b96–b114 | 跳过 vs 计入 0 vs 计入前缀 ＋ 结果类型 ＋ 容器 TypeError | 8 SAME ／ **11 DIFF** | 19 绿 | 19 绿 |
| E 比较族 | b115–b129 | Notice＋按 1／1.0、vs string/array 恒大于、`max(标量)`、同值并列取法 | 3 SAME ／ **12 DIFF** | 13 绿／b11+b119 红 | **15 绿** |
| **合计** | **129** | | **same=44 diff=85** | same=123 diff=6 | **same=126 diff=3** |

三档表身：修前 `c047_blt_prefix129_R172_snapshot_tmp.tsv`＝`398300fa013fbce51f82f11c20a9c901`；
首次落地（含 3 枚新暴露面）`c047_blt_6red_R172intermediate_snapshot_tmp.tsv`＝`0c63a1fc006b02985aeef9e975e00876`；
终档 `c047_blt_postfix129_R172_snapshot_tmp.tsv`＝`ef05fa3f9efba7aaee23effce8439bb5`。
★终档残红 3 枚**全是先前已登记**面：b5＝**F-62b**（bc 族 string 形参要 stringable 感知）、b27/b28＝**F-63**（大浮点记法）。
本批关闭 **82** 枚；`compile_fail=0 zig_escape=0 bad_probe=0 residue=0`，`aot_caught=53`（＝53 枚臂里 PHP 抛的异常在 AOT 侧同样**可捕获**）。

### 46.4 落地清单（模板 helper 12 枚 ＋ 入口 25 处 ＋ 元素族 2 处 ＋ 比较族 3 处 ＋ 表位 2 行）

| # | 位置 | 改动 |
|---|---|---|
| 1 | 模板新增 `NumParamKind`／`numParamExpectedText`／`rejectParamType`／`trimNumericWhitespace`／`strictIntFromTrimmed`／`numericPrefixValue`／`emitDeprecatedPassingNull`／`emitDeprecatedFloatStrToInt`／`intParamFromFloat`／`requireNumParamAs`／`requireNumParam`／`requireOptionalNumParam`／`requireArrayParam` | 单一实现承载第四套措辞（对象⇒类名走 `operandTypeName`），**不动** `php_check_param_type`／`valueTypeName` |
| 2 | 模板新增 `ArrayNumElem`／`classifyArrayNumElem`／`arrayElementNotSupported` | c 段元素级三分类（计入／计入 0／跳过），sum 与 product 共用 |
| 3 | 模板新增 `emitNotice`／`emitObjectToNumberNotice` | d 段：本模板第一处 `Notice:` 站点（此前只有 Warning／Deprecated，`Notice` 只出现在 `E_USER_NOTICE` 标签里） |
| 4 | 入口 ×25：`abs sqrt floor ceil round(×2) intdiv(×2) fdiv(×2) fmod(×2) exp log log10 log2 sin cos tan asin acos atan atan2(×2) sinh cosh tanh hypot(×2) deg2rad rad2deg number_format(×2)` | 每处一行 `const x = requireNumParam(...) orelse return Value.initNull();`，把校验后的 **int／float** 值喂回原逻辑 ⇒ 顺带把「字符串寄存器被 `asInt()` 读成 0」这类误读挡在入口 |
| 5 | `php_array_sum`／`php_array_product` | 容器形参 `requireArrayParam` ＋ 循环体改走 `classifyArrayNumElem`；★`array_sum` 的 `all_int` SIMD 快速路（`fastPackedIntSum`）**保留不动**（纯 int 无诊断可省） |
| 6 | `php_max`／`php_min` | 单参非数组 ⇒ TypeError；`php_min` 两支 `< 0` ⇒ **`<= 0`**（并列取后者） |
| 7 | `phpCompare` Rule 2b／2c | object vs 数值 ⇒ Notice＋按 1／1.0；object vs string／array ⇒ 恒大于且无 Notice（★必须排在旧 Rule 7「array 恒大于非 array」之前） |
| 8 | `php_spaceship` | 顶部 `if (Value_isObject(lhs) or Value_isObject(rhs))` ⇒ **交 `phpCompare`**，不再落末路 `toFloat()` |
| 9 | `native_linker.zig:4312` | `fdiv` 的 `.may_raise = false` ⇒ `true`（`php_fdiv` 签名 `Value` ⇒ `!Value` 的硬前置） |
| 10 | `optimizer.zig:935` | LICM 纯函数名单摘除 `count`／`array_sum`／`array_product`（提升会把「每迭代一次诊断」变成「整循环一次」） |
| 11 | **刻意不做** | `pow()` **不加**参数校验：实测其措辞是 `Unsupported operand types: Foo ** int`（操作数面），加校验反而造出第二套措辞；`log2()` PHP 根本不存在；`round` 的 `$mode` 走 **ValueError**；bc 族与 `?string` 形参走 stringable 语义 |

### 46.5 本轮四条自我更正（全部由**门内实测**抓回，不是读码推定）

| # | 事件 | 抓到方式 | 处置 |
|---|---|---|---|
| ① | `requireArrayParam(...) orelse return` 当语句用 ⇒ 生成码 `value of type 'Value' ignored`（4 站点） | **AOT 编译期**（冒烟编译，早于任何门跑） | 补 `_ =`；教训：模板里 `?Value` helper 作语句用时必须显式丢弃 |
| ② | **省略的可选形参在本运行时也是 null** ⇒ 给没写的 `$precision`/`$decimals` 也打了一行 Passing-null Deprecated | 门 BLT **b72** 实测（AOT 多两行、PHP 只一行） | 新增 `requireOptionalNumParam`：null/missing 当「未提供」透传，只做类型拒。★代价留字：显式 `round(1.5, null)` 的 `#2` Deprecated 本实现**不发**（PHP 发）＝登记进 F-62b 家族，不是静默错值。语料侧 `round` 12 处／`number_format` 25 处多为省略写法，不处理会整片多输出 |
| ③ | 旧 `php_min` 与 `php_max` 写成对称的 `< 0` ⇒ 同值并列的取法两边都当成「取前者」 | 门 BLT **b11** ＋ 专测八臂矩阵 `f62_tiebreak_tmp.php` | min 改 `<= 0`（并列取后者），max 保持 `< 0`（并列取前者）＝逐枚照抄实测，不自创统一规则 |
| ④ | `php_spaceship` **自成一套**实现（int/int、string/string、array/array、末路 toFloat），object 落末路 ⇒ 与 `<`/`>` 族漂移 | 门 BLT **b119**（AOT `-1` 且无 Notice，PHP `0`＋Notice） | object 操作数交 `phpCompare` 单点实现。★同型问题**已是第三次**（R-170 的 `pow` vs `**`、本批 `spaceship` vs `<`）⇒ 「同一语义存在第二／第三套实现」应做一次专项普查 |

### 46.6 本批新登记（**登记不修**）

| ID | 面 | 实测事实 | 为何不当批修 |
|---|---|---|---|
| **F-62b** | bc 族与 `?string` 形参需 **stringable 感知** | `bcadd($b,"1")`='6'（有 `__toString` ⇒ 静默转换）而 `bcadd($o,"2")` ⇒ `Foo given`；`number_format` 的 `#3/#4` 期望 `?string`（null 合法无 Deprecated） | 数值形参「对象一律拒」不需要探测方法，string 形参需要 ⇒ 且 AOT 的 `__toString` 调用链是否已通未测（门 b5 恒红即此面） |
| **F-62d** | `round` 的 `$mode` | 期望类型是 `RoundingMode\|int`，非法值走 **ValueError**：`round(): Argument #3 ($mode) must be a valid rounding mode (RoundingMode::*)`（`round(1.5,2,"9")`、`round(1.5,2,123)` 同句式） | 措辞族不同（ValueError 而非 TypeError），且 `RoundingMode` 常量表未落地 |
| **F-62e** | arity／多余内置 | `log($num, $base)` 的 `$base` AOT 未实现；`log2()` 在 PHP 8.5.8 **不存在**（`Call to undefined function log2()`）而 AOT 有 `php_log2`；`max()`／`min()` 零参数 PHP 抛 `ArgumentCountError`，AOT 返回 0 | 属 arity／内置名表，不属参数类型校验族 |
| **F-65** | 精度形参的溢出与 UB | PHP 实测 `round(1.5, PHP_INT_MAX)`=1.5、`round(1.5,-3000000000)`=0.0、`number_format(1,3000000000)` 直接**内存耗尽 Fatal**；AOT 侧 `@as(i32,@intCast(precision))` 对超出 i32 的 int 是越界转换，`for (0..dec) pow10 *= 10` 对大 dec 是长循环＋u64 回绕 | ★**存量**风险（旧写法同样存在，本批只是首次把它量出**未测运行证据**的定性观察 ⇒ 按纪律标注为读码结论），修它要先定 PHP 的短路口径，不夹带进本批 |
| **F-61c** 扩 | object vs object 的比较 | `$o <=> $b` 与 `$b <=> $o` 在 PHP **两个方向都印 1**（不稳定），`$o == $o` 恒 true、不同实例 `==` false；AOT 走末路 `toFloat()` ⇒ 恒相等 | 复刻需先确定 AOT 的对象身份序规则，且 PHP 侧本身不自洽 ⇒ 不复刻 |
| 性能 | 25 个入口各加一次校验 | ★**本批未测**（链内无 PERF 腿；R-167 的教训是「估算值不得当结论写」）⇒ 后续轮补 `abs`／`intdiv`／`array_sum` 热点基准，与 R-167 位运算族的 +32% 同档对照 | 不测就不写数，留字待测 |

★**F-62 覆盖面边界普查**（收尾只读核查，脚本内联于本节复测口径；结论＝本批「全数值族」只覆盖到**数学/三角/对数/幂/格式化**那 30 个入口，另有 **76 个内置**体内是 `toInt()/toFloat()` 而**无任何校验**）：
下表全部**实测**（`/tmp/r172/f62_family_tmp.php`），登记为 **F-62f**，措辞与参数名一并钉死，供下批纯机械补入口：

| 内置 | PHP 8.5.8 实测 | 归属 |
|---|---|---|
| `dechex($o)`／`decoct($o)` | `TypeError: dechex(): Argument #1 ($num) must be of type int, Foo given`（decoct 同句式） | ★数值族**漏网**（本批入口表按函数名列举时把「十进制转十六/八进制」当成字符串族，实际形参是 **int**） |
| `long2ip($o)`／`rand($o,5)`／`sleep($o)`／`array_fill($o,1,2)` | `…($ip)/($min)/($seconds)/($start_index) must be of type int, Foo given` | int 形参族（时间/网络/数组结构），与数值族同机制不同范围 |
| `base_convert($o,2,10)` | `base_convert(): Argument #1 ($num) must be of type string, Foo given`；而 `base_convert(1,2,10)`='1'、`base_convert("10","2",10)`='2' | ⇒ `string` 形参＋int 形参混合，属 F-62b 的 stringable 那一支 |
| `bindec($o)`／`hexdec($o)`／`octdec($o)` | `…($binary_string)/($hex_string)/($octal_string) must be of type string, Foo given` | F-62b |
| `range($o,5)` | `range(): Argument #1 ($start) must be of type string\|int\|float, Foo given` | 三元素 union 形参（本 helper 的 `expected` 文本是自由串 ⇒ 可直接承载） |
| `settype($a,$o)` | **ValueError**: `settype(): Argument #2 ($type) must be a valid type` | F-62d 那一支（ValueError 措辞族） |
| `substr($o,1)`／`str_repeat($o,1)` | `…($string) must be of type string, Foo given` | 字符串位置/长度大族（`strpos`/`sprintf`/`wordwrap`/`chunk_split`… 同族） |
| ★**负证据（禁加校验）** `intval($o)` | **int 1**（不抛） | `mixed` 形参 ⇒ 加校验就是 over-fatal |
| ★**负证据** `floatval($o)` | **float 1.0**（不抛） | 同上 |
| ★**负证据** `sprintf("%d",$o)` | 字符串 `'1'`（不抛） | 变参/格式串族不做参数类型校验 |
| `number_format(1.5,0,".",$o)` | `number_format(): Argument #4 ($thousands_separator) must be of type ?string, Foo given` | ★本批只补了 `#1/#2`；`#3/#4` 是 `?string`（null 合法）⇒ 留 F-62b |
| `abs("5.0")` | **double 5.0** | ★与本批实现一致（整值**语法**才算 int，`"5.0"` 是 float 语法）⇒ C 段 b74 已钉死 |

★三条负证据尤其要留字：`intval`／`floatval`／`sprintf` 在 PHP 里吃对象**照样返回**（对象按 1 参与，与 d 段同源），
⇒ 将来做 F-62f 时**不可**把它们当成「数值内置」一并加校验，否则就是把合法 PHP 打成 Fatal。
