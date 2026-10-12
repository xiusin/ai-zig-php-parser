# 交接文档（会话 10 终）· CODEGEN-010/011/012 全谱收口（R-125~R-137 + 门 D8/M/N/O）

> - **日期**：2026-10-12（会话跨 2026-10-07 ~ 10-12）
> - **会话标识**：R-125~R-137（任务号 #122 系列衍生；本会话与我并行还有一会话在跑 CODEGEN-010 R-3/R-5 与 CODEGEN-011 取证，见 §2.3）
> - **HEAD**：`9f3b0b9`（工作树**全净**，`git status --porcelain` = 0）
> - **二进制**：`be305cfab370f56e515d6e9cd63b10ea`（影子基线已重冻结至此）
> - **主回归**：**Pass 67 / Skip 1**（2026-10-11 15:12:25 稳定态报表，0 FAIL）

---

## 0. 状态标记图例

| 标记 | 含义 |
|---|---|
| ✅ **DONE** | 已闭环并入库（或已验收待随下次提交） |
| 🟡 **待裁决** | 取证完整，落地前需老铁点头 |
| 🔒 **门控中** | 修复路线未启动，禁止开工 |
| ❌ **已否证** | 本会话实测推翻的旧说法（禁止再引用） |
| ⚠️ **推断未取证** | 禁止在评审中当证据引用 |

---

## 1. TL;DR

1. **三张工单全谱收口**：CODEGEN-010（关键字大小写，59+15 红 → 门 H **face=0 / inverse=0 / confounded=0** 79+21 全绿）、CODEGEN-011（面 A/B/C 全落，门 N 7 形 / 门 O 6 形全绿）、CODEGEN-012（类名/方法名/属性诊断/重复声明/Reflection 族/is_a/class_alias/method_exists，门 M **19 形 red=0 green=19**）。
2. **本会话十二个修复批**（R-125~R-137）全部落地并经链 V~XVI 多代验收；主回归恒 **Pass 67 / Skip 1**；影子在 R-129 注册签名漂移重冻结后保持 68/68。
3. **七张门资产新建/扩形**：门 D8（14 形 defect_red=0）、门 M（19 形）、门 N（7 形）、门 O（6 形）+ 影子门重冻结。
4. **流程铁律新增六条**（撕裂读 / zsh glob / ctor throwThrowable 传播 / bufPrint 转义 / toString 类型 / 标签发射器无内建分发），全部由实测事故沉淀，见 §7。
5. **未决存量**：仅剩 P2 登记项（§4.3）与待 §五 明示项（R-C3/R-M1）；**无待裁决必答项**。

---

## 2. 交接链

### 2.1 会话级文档链

| 顺序 | 文档 | 状态 |
|---|---|---|
| 上一份交接 | `docs/changes/2026-10-07/交接文档_2026-10-07_session9_R118-R120关键字穷举面闭环.md` | ✅ 已入库（f9432e2 归档） |
| **本份** | `docs/changes/2026-10-12/交接文档_2026-10-12_session10_名字族CI与goto全谱_R137.md` | 📦 新增（随下次提交） |

### 2.2 提交链（**含并行会话 "1" 扫掠映射**——考古必读）

| 提交 | 说明 | 内容归属 |
|---|---|---|
| `b92f206` "11" (10-07) | R-2 批（8 文件 +268/−78） | CODEGEN-010 R-2/R-2b/R-4 + 名位容忍支 15 处 |
| `0652130` "11" (10-08) | R-123/R-128~R-131 前后批（4 文件） | 赋值优先级 / var / namespace 穿线 / 类名 CI 前身 |
| `ca3cd0e` / `73f4d6b` / `f9432e2` (10-11 早) | 工单 20 张 / 门资产 318 份 / 变更文档 52 份归档 | 并行会话 + 本会话的文档与门资产 |
| `64cce60` **R-3/R-5 parser 批** | 并行会话工作（我分票点名） | 替代语法严格闭合 + switch 臂表位严格化（45 文件 +2946） |
| `7a4cee9` **R-125~R-132 八批**（amend 自 c9d40ba "1"） | goto 三形态降级 + 名字族 CI（ir +227/linker +59/runtime +305） | 见 §3 |
| `95b7ed4` **R-128~R-132 补遗批**（amend 自 ccbd4c1 "1"） | runtime_lib_template +29/−3 | 静态 Error 形态 / AllowDynamicProperties / 枚举名词 |
| `18efc8b` **R-134 面 B/C 批**（amend 自 7671e8e "1"） | parser/ast/ir_generator（+91/−32） | CODEGEN-011 R-B1/R-C1/R-C2 |
| `5864516` **R-135 批** | root/parser/main | case 分号 PHP 风格 Deprecated |
| `1484ccf` **门 N/O 资产与读数基线** | 门 N/O 脚本读数 + 九门刷新 + 回归基线 | 链 XIII/XIV 两代 |
| `9f3b0b9` **工单 012 修订与门读数尾差** | 工单 012 §9/§10/§11 + 十一 TSV/报表 | R-136/R-137 验收 |
| `9713cff` / `aa8514b` "1" (10-11 14:42/14:57) | **并行会话扫掠**：R-136/R-137 src（ir 除外）+ 工单 012 §9/§10 + R136 文档 | 已含全部 R-136/R-137 内容（amend 缺失——两笔 "1" 未改名，考古按时间定位） |

**⚠️ 协同纪律**：并行会话以 "1" 式快扫持续吞工作树（本会话发生三次，其中两次由我 amend 点名补救）。**多会话并行时，修复批完成后立即提交点名**；验收链运行期间**禁止任何源码编辑**（见 §7 铁律 1）。

### 2.3 并行会话工作（本会话只读协同，未推进其路线）

| 批 | 内容 | 状态 |
|---|---|---|
| R-3/R-5（任务 #124/#127） | 替代语法严格闭合 / switch 臂表位严格化（旗标门控 AOT-only） | ✅ 64cce60 |
| CODEGEN-011 取证（任务 #126） | 门 K 花括号 switch 与 case 臂族（4 形扩口 + 面 B/C 新立） | ✅ 已入库 |
| CODEGEN-011 面 A 落地（任务 #127） | 门 L 建成 + 面 A 收口 | ✅ 已入库 |

---

## 3. 本会话实测结论汇总（R-125~R-137 十二批）

### 3.1 门资产全景（终态读数）

| 门 | 形态 | 终态读数 |
|---|---|---|
| **D8**（§8 家族） | 14 形 | `defect_red=0 guard_same=14`（七枚缺陷全关闭） |
| **M**（类名/方法/属性诊断族） | 19 形 | `red=0 green=19` |
| **N**（终止符位，011 面B） | 7 形 | `red=0 green=7` |
| **O**（面C default 位次） | 6 形 | `red=0 green=6` |
| **E/F/G/H/H2/I**（CODEGEN-010 主群） | 19/8/7/79+21/15/19 形 | 全部与注册值一致（H face=0 noface=79 confounded=0 inverse=0） |
| **影子** | 68 语料 | `same=68`（R-129 注册签名漂移重冻结后；diff=68 分解见 §8） |

### 3.2 十二批修复一览（详据见各变更文档 R125~R137）

| 批 | 内容 | 关键自纠 |
|---|---|---|
| R-125/R-126 | goto label→closer 配对降级 do-while（顶层+generateBlock 下沉） | 原生 ctor throwThrowable 返回值被吞 ⇒ Zig error 传播 |
| R-127 | closer 首语句放宽 + 命名参数 CI + 运行期查名 CI 七处 | hasMethod 锚点缩进误配 ⇒ 行级定位重做 |
| R-128/R-129 | 类名族 CI（findClass 104 调用者）+ 重复声明校验 + instanceof 规范名 | Throwable 伪接口块误删 ⇒ 补回；{main} 未转义 ⇒ 门 M 12 全红 |
| R-130 | else 位 closer + 枚举 redeclare 名词 | w1/w2/w3 三探针先行证 do-while 渲染族可行 |
| R-131 | 方法名族 CI（findMethodLookup/findMethod 28 调用者）+ is_a/class_alias 新内建 + method_exists 类名形态 | emitWarning 双通道形态经门 M c17 抓回补齐 |
| R-132 | 属性诊断对齐（Undefined property Warning + emitDeprecated 动态属性） | R-131「属性宽松」系误读 ⇒ 复测更正入工单 |
| R-133 | 静态属性未声明改可捕获 Error | — |
| R-134 | CODEGEN-011 面 B/C（分号终结符 + default_slot + 臂链源码序） | 门 N/O 注册修复前后两代读数 |
| R-135 | case 分号 PHP 风格 Deprecated（PHPContext 通道） | AOT 入口 fatal 检查误吞纯 Deprecated 脚本 ⇒ first-fatal 扫描 |
| R-136 | ReflectionClass 规范名 + hasMethod CI + class_uses 空实现 | toString 返回 *PHPString ⇒ .data |
| R-137 | trait 使用记录 + ReflectionException + invoke(null) 消息 | 原生 ctor throwThrowable 须接 Zig error；注册表按值拷贝丢指针 |

### 3.3 面孔消除总账（CODEGEN-010 家族）

| 面 | 开局 | 终态 |
|---|---|---|
| 门 H 主群 | face 59（语义 57） | **0** |
| 门 H 反例组 | inverse_face 15 | **0** |
| 门 H CONFOUNDED | 5 | **0** |
| 门 D8 §8 缺陷 | 7 枚 | **0 枚**（门 N/O 补 011 面 B/C 亦 0） |
| 门 M 类名/方法族 | —（新探） | 19 形全绿 |
| CODEGEN-011 面 A/B/C | 4+5+位次缺失 | **全落**（面 B/C 本会话） |

---

## 4. 状态总表

### 4.1 ✅ 本会话 DONE

R-125/R-126/R-127/R-128/R-129/R-130/R-131/R-132/R-133/R-134/R-135/R-136/R-137 十三批全部落地验收（见 §3.2）；门 D8/M/N/O 四座新建/扩形；分票七笔点名入库；工单 010/011/012 状态行与 §9/§10/§11 回填；变更文档 R125~R137 十三份落盘。

### 4.2 🟡 待裁决 / 登记项（无必答项）

| 项 | 工单 | 说明 |
|---|---|---|
| 非规范 goto（双 goto 连发已解，余多标签/跨位） | 010 §3.9 | 需发射器 goto 形状改造（#122d 定论），独立评审 |
| `class_uses` trait 适配与链记录 | 012 §9 | ClassMeta 增 trait 使用字段（R-C1 同款），登记 |
| `ReflectionClass("nonexistent")` 的 ReflectionException 已抛但**消息形状**细修 | 012 | t3 已一致；`get_class_methods` 需标签驱动发射器支持（R-136 回退登记） |
| ReflectionMethod `invoke(null)` 消息 | 012 §10 | 已对齐 ✅；`get_class_methods`/`Reflection*` 深探继续 |
| 内部占位类用户覆盖后的并发查名权衡 | 012 | 设计注记 |
| `#[AllowDynamicProperties]` 已实现；属性 Deprecated 双通道形态 | 012 | norm 已对齐 |
| R-C3（VM 面 B/C）/ R-M1（VM 静默吞解析失败） | 011 | §五 明示后启动 |
| 属性 Deprecated 双通道形态 | 012 | norm 已对齐 |

### 4.3 🔒 门控中（其他工单，未动）

RUNTIME-002 / CODEGEN-007/008/009 / OPT-001 / REF-001~004 / PERF-001 / PROC-001 / CODEGEN-006 #81/#84 —— 全部维持各工单登记的待裁决状态。

### 4.4 ❌ 本会话否证说法（禁止再引用）

| 旧说法 | 实测 |
|---|---|
| 「属性查名宽松（`->pr` 读到 `Pr` 值）」 | **误读**——值语义全部精确；真实缺口是诊断静默（R-132 已对齐） |
| 「R-137 原生 ctor `return throwThrowable` 可行」 | 返回值被 `php_object_new_with_constructor` 的 `catch initNull` 吞掉 ⇒ 须接 Zig error 传播（c1/c2 对照探针） |
| 「get_class_methods 补注册即可」 | 标签驱动发射器（:7450-10956 区）**无 mapToRuntimeFunction 内建分发** ⇒ 特判不生效，回退登记 |
| 「门 M 拟名可用（011 面 C）」 | 已被 012 类名 CI 门占用 ⇒ 011 面 C 门改名 **门 O** |

### 4.5 ⚠️ 推断未取证

- 链 XV 影子 diff=68 的分解（trait 记录发射 + 并行会话内建注册表增项）基于两文件抽样逐字 diff，未逐文件穷举。
- `case 1;;` 双分号在 PHP 8.5 为合法（门 N n_two_semi SAME）——与门 K 时代 `l_two_semi` rc=255 的差异未归因（臂位 vs 列表位）。

---

## 5. 会话关联文件清单

### 5.1 工单（终态）

| 工单 | 状态 |
|---|---|
| `docs/known-issues/AOT-CODEGEN-010-keyword-case-insensitive-lexer.md` | ✅ 全谱关闭（118→1197 行） |
| `docs/known-issues/AOT-CODEGEN-011-switch-case-...md` | ✅ 面 A/B/C 全落（244 行） |
| `docs/known-issues/AOT-CODEGEN-012-class-name-case-insensitive-lookup.md` | ✅ 全谱关闭（111 行） |

### 5.2 变更文档（本会话新增）

R125~R132（2026-10-07/11 八份）+ R134/R135（011）+ R136/R137（012）——见 `docs/changes/2026-10-11/` 与 `2026-10-12/`。

### 5.3 门资产（全部已入库，1484ccf/9f3b0b9）

| 门 | 脚本 | 读数 |
|---|---|---|
| D8 | `fuzzy_scripts_720/tmp/c010_indep_defects_gate_tmp.sh` | `c010_indep_defects_tmp.tsv` |
| M | `fuzzy_scripts_720/tmp/c010_class_ci_gate_tmp.sh` | `c010_class_ci_tmp.tsv` |
| N | `fuzzy_scripts_720/tmp/c011_terminator_gate_tmp.sh` | `c011_terminator_tmp.tsv` |
| O | `fuzzy_scripts_720/tmp/c011_default_slot_gate_tmp.sh` | `c011_default_slot_tmp.tsv` |
| 影子 | `fuzzy_scripts_720/tmp/c010_shadow_main_md5_tmp.sh` | `c010_shadow_main_md5_tmp.tsv`（基线已重冻结至 `be305cfa`） |

### 5.4 源码锚点（终态 md5）

| 文件 | md5 |
|---|---|
| `zig-out/bin/php-interpreter` | `be305cfab370f56e515d6e9cd63b10ea` |
| `src/compiler/parser.zig` | `dd07fb09c6ac41b2f5ff5fafe41792d6` |
| `src/compiler/ast.zig` | `aad0782e70c49b68b0f0cc16088205e6` |
| `src/compiler/root.zig` | `82d705af5ae8a30367cf04f669f73cc5` |
| `src/main.zig` | `59e759b69b70d7ff7f74308470b2d755` |
| `src/aot/ir_generator.zig` | `c4141ad155264aed1426926437d4fefc` |
| `src/aot/runtime_lib_template.zig` | `12c3943470c28a9b99c30c398f312ad2` |
| `src/aot/native_linker.zig` | `4ee044fdb03daa596f29069d89d73353` |

---

## 6. 复测路径与验收成本

```bash
cd /Users/wangjianjun/products/parser
# 四家族门（~3 分钟）
timeout 300 bash fuzzy_scripts_720/tmp/c010_class_ci_gate_tmp.sh          # M  19 形
timeout 300 bash fuzzy_scripts_720/tmp/c010_indep_defects_gate_tmp.sh     # D8 14 形
timeout 300 bash fuzzy_scripts_720/tmp/c011_terminator_gate_tmp.sh        # N  7 形
timeout 300 bash fuzzy_scripts_720/tmp/c011_default_slot_gate_tmp.sh      # O  6 形
# CODEGEN-010 主群六门（~14 分钟）
timeout 480 bash fuzzy_scripts_720/tmp/c010_keyword_case_gate_tmp.sh
timeout 300 bash fuzzy_scripts_720/tmp/c010_mechanism_gate_tmp.sh
timeout 300 bash fuzzy_scripts_720/tmp/c010_constant_case_gate_tmp.sh
timeout 900 bash fuzzy_scripts_720/tmp/c010_kw_full_table_gate_tmp.sh
timeout 300 bash fuzzy_scripts_720/tmp/c010_noface_tolerance_gate_tmp.sh
timeout 480 bash fuzzy_scripts_720/tmp/c010_crossmode_gate_tmp.sh
# 影子（~26 分钟）+ 主回归（~14 分钟）
timeout 2400 bash fuzzy_scripts_720/tmp/c010_shadow_main_md5_tmp.sh
timeout 1800 bash fuzzy_scripts_720/run_regression.sh
timeout 590 zig build test
```

**预期全绿**：M 19/19、D8 14/14、N 7/7、O 6/6、六门注册值、影子 68/68（prefix 已重冻结至 `be305cfa`）、主回归 Pass 67/Skip 1。

---

## 7. 流程铁律（本会话新增六条，全部事故沉淀）

1. **验收链运行期间禁止任何源码编辑**（含本会话自身的修复）——链 XV 主回归在源码编辑窗口运行 ⇒ **Pass 0 撕裂读**；稳定态重跑恢复 67。链必须对冻结树运行。
2. **zsh glob 无匹配即中止整条命令**——`rm -rf a* b*` 若 `a*` 无匹配，`b*` 的删除也不执行（两次掩盖残留）⇒ 用 `find -maxdepth 1 -name ... -exec rm -rf`。
3. **原生运行时函数抛 PHP 异常**：`return throwThrowable(...)` 返回值会被调用方的 `catch initNull` 吞掉 ⇒ 须 `_ = throwThrowable(...) catch {}` 后 `return error.X` 传播（仅构造器/经 helper 二次调用的路径；builtin 直发路径的值返回约定正常，因生成码有 hasException 后检）。
4. **bufPrint 格式串的字面花括号必须 `{{`/`}}` 转义**——`#0 {main}` 未转义 ⇒ 生成码编译 `too few arguments` ⇒ 门 M 5 秒 12 全红。
5. **`Value.toString` 返回 `*PHPString` 而非切片**——取 `.data`；发射器 fmt 字面 `{` 同铁律 4。
6. **标签驱动发射器（generateLabelDrivenBlockRange 区）无 mapToRuntimeFunction 内建分发**——新内建注册 builtin_map 后，在该路径调用的函数还需在该区补发射特判（get_class_methods 回退根因）；写前先 grep 该区是否已有同名分发。

**沿用铁律**：门先修后引用；探针 php -l 预检 + 输出非空预检；多会话并行时修复批完成即提交点名（防 "1" 式抢扫吞点名）。

---

## 8. 风险与完整性自证

| 维度 | 实测 |
|---|---|
| 主回归 | Pass 67 / Skip 1（15:12:25 稳定态；链 XIV/XVI 两代一致） |
| 四家族门 | M 19/19、D8 14/14、N 7/7、O 6/6 |
| 六门主群 | 与注册值一致（H face=0 noface=79 confounded=0 inverse=0） |
| 影子 | 基线已重冻结至 `be305cfa`；此前的 diff=68 已定性（R-129 注册签名 + trait 记录发射 + 并行会话内建注册表——全部为已入库代码的预期产物，逐字 diff 抽样证实） |
| .php 保护 | 601 完好（含并行会话新增 4 枚） |
| 残留 | 0 |

---

## 9. 后续建议（优先级 / 影响面 / 落地成本）

| 优先级 | 建议 | 影响面 | 落地成本 |
|---|---|---|---|
| P1 | CODEGEN-011 R-C3/R-M1（VM 面 B/C 与静默吞解析失败）——§五 明示后启动 | vm.zig/generator.zig | 未实测 |
| P2 | 非规范 goto 发射器形状改造（#122d 定论） | 核心渲染器 | 大改造，独立评审 |
| P2 | class_uses 的 trait 适配/链记录（ClassMeta 增字段） | ir/emitter/runtime | R-C1 同款模式 |
| P2 | Reflection 族深探（ReflectionMethod invoke 消息形状已对齐；get_class_methods 需发射器支持） | 内省面 | 登记待排 |
| P2 | 属性 Deprecated 双通道形态 | 诊断面 | norm 已对齐 |

---

## 10. 交接提示词（下一会话直接粘贴）

```text
继续处理已知问题

本会话从交接文档接手，请先完整阅读并以其为唯一入口（勿凭记忆开工）：
docs/changes/2026-10-12/交接文档_2026-10-12_session10_名字族CI与goto全谱_R137.md

接手须知：
1. CODEGEN-010/011/012 三张工单已全谱关闭（门 H face=0、门 D8/M/N/O 全绿、主回归 Pass 67/Skip 1），
   HEAD = 9f3b0b9 之后的并行会话扫掠（注意 "1" 式提交的批内容映射见交接 §2.2）。
2. 本会话遗留全部为 P2 登记项（交接 §4.2/§9）：非规范 goto 发射器改造、class_uses trait 枚举、
   get_class_methods 标签发射器支持、Reflection 族深探——各项需独立评审或结构增字段，勿凭记忆开工。
3. 流程铁律六条新增（交接 §7）：验收链运行期间禁改源码；zsh glob 中止；原生 ctor 抛异常须
   Zig error 传播；bufPrint 花括号转义；toString 返回 *PHPString；标签发射器无内建分发。
4. 多会话并行：修复批完成立即提交点名；"1" 式扫掠后用 git log --stat 核对内容归属。
5. 影子基线已重冻结至 be305cfa 代；R-129 注册签名与 R-137 trait 记录的漂移已登记定性。
6. 待 §五 明示项：R-C3（VM 面 B/C）、R-M1（VM 静默吞解析失败）——未获明示不得开工。
```
