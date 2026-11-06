# 批次十四：回调 throw 可捕获推广（map/filter）+ by-ref/校验缺口六连修

- 日期：2026-11-05 ｜ 状态：uncommitted ｜ 范围：`src/aot/native_linker.zig`（+163）、`src/aot/runtime_lib_template.zig`（+237，模板热区已空获准）
- 前序：批次十三（接球后缀 helper + usort 族/array_walk 修复 + 普查表）

## 1. 高层摘要（TL;DR）

两线并进：
1. **回调 throw 可捕获推广**：批次十三的 `emitBuiltinCallCatchSuffix` 接入三枚命名专列站（valued 名单站 :25407、valued `php_array_filter` 支 :25572、void 名单站 :26505）⇒ `array_map`/`array_filter`（含 USE_BOTH/USE_KEY flag 三形）回调 throw 与 PHP 8.5.8 逐字对齐。
2. **模板六连修**（每项先取 PHP 8.5.8 真值，每刀后 AOT 产物实测）：①usort 族比较器可调用校验（12 形态文案逐形对齐）；②`array_multisort` 先校验后排序 + SORT_DESC 常量订正；③sort 族九成员非数组可捕获 TypeError（替 noreturn fatal）；④`settype` 非法 $type ValueError + `array_splice` 非数组 TypeError；⑤`preg_replace_callback` 补 limit/$count 形参（修 arity 编译失败）+ 回调 throw 时 $count 增量语义（模板 Style-A 化 + 发射器 `emitRefParamsExceptionWriteback`）；⑥`array_walk_recursive` 回调 by-ref 装槽生效。

## 2. 影响范围

| 面 | 内容 |
|---|---|
| 修复 | array_map/array_filter 回调 throw 可捕获；usort 族比较器校验；multisort 校验+DESC 订正；sort 族/settype/splice/walk_recursive 参数 TypeError/ValueError；preg_replace_callback 5 参（含 count 三态写回）；walk_recursive 回调生效 |
| 不变 | 成功路径生成码（接球后缀仅 error 介入）；批十三全部修复面（复测逐字一致）；f042/f164 等守护面 |
| 波及登记 | `builtin_function_map` 缺 sort 族（varfn 分发既有缺口）；`preg_replace`/`preg_filter` $count 未接（替换引擎签名深入，P2）；test_065 dim-set 缺陷（既有，另案） |

## 3. 核心变更

| # | 变更 | 位置 | 说明 |
|---|---|---|---|
| 1 | 接球后缀接三专列站 | nlk :25407/:25572/:26505 | `array_map`/`array_filter` 回调 throw 可捕获（may_raise 门控） |
| 2 | `throwArgTypeError` + `zppGivenTypeName` | 模板 :30264/:30283 | 可捕获 ZPP TypeError（bool⇒true/false、对象⇒类名，逐字对齐 PHP 措辞） |
| 3 | sort 族九成员非数组分支 | 模板 php_sort/rsort/asort/arsort/ksort/krsort/shuffle/natsort/natcasesort | `emitTypeFatalError`(noreturn)/静默 false ⇒ 统一可捕获 TypeError |
| 4 | `validateSortCallback` | 模板 :30294 | usort 族比较器 12 形态文案（closure/__invoke/func/Class::method/[obj|class,m]/int…） |
| 5 | `php_array_multisort` 前置校验 | 模板 :30745 | 先校验后排序（TypeError/ValueError 文案逐形对齐；合法 flag 集 [0,6]∪[8,14] 实测）+ **SORT_DESC==3 常量订正**（旧硬编码 ==2 永不命中） |
| 6 | `php_settype`/`php_array_splice` | 模板 :31901/:30158 | 非法 type ⇒ ValueError（同文案同出口）；非数组 splice ⇒ TypeError |
| 7 | `php_preg_replace_callback` 扩形参 | 模板 :35099 | +limit/$count；count 入口清零、defer 末尾写、errdefer throw 增量写；回调点 Style-A 化 |
| 8 | `emitRefParamsExceptionWriteback` | nlk :22631 | ref_params 实参异常写回（make_ref→store→global_get 链，自然过滤）；挂两通用尾站 |
| 9 | builtin_map 登记 | nlk :4745/:4786/:5008 | preg_replace_callback：ref_params={4}+handler_params=5+缺省补齐；settype may_raise 归位 true |
| 10 | `php_array_walk_recursive_inner` | 模板 :34312 | 叶子 make_ref 装槽（R-1b 成例）⇒ 回调 by-ref 生效；首参非数组 TypeError |

## 4. 可视化概览（Code & Logic Map）

### 4.1 preg_replace_callback count 三态写回（⑤ 核心链路）

```mermaid
sequenceDiagram
    participant GEN as 生成码调用点
    participant TPL as php_preg_replace_callback
    participant CB as 用户回调(throw)
    GEN->>GEN: reg_9=getGlobalVar($c); ref_aware_store(reg_8,reg_9); reg_10=make_ref(reg_8)
    GEN->>TPL: call(..., reg_10)
    TPL->>TPL: count cell 清零（入口）
    TPL->>CB: invoke(match)
    CB-->>TPL: error.RuntimeError（挂起异常）
    Note over TPL: ★Style-A 化：catch err ⇒ hasException ⇒ return null<br/>（defer 已把 replace_count=1 写进 cell=reg_8）
    TPL-->>GEN: null + 挂起异常
    GEN->>GEN: ★emitRefParamsExceptionWriteback：<br/>if (hasException()) setGlobalVar("$c", reg_8)
    GEN->>GEN: if (hasException()) ⇒ 路由到 catch 块
```

### 4.2 sort 族校验分层（①②③ 统一形制）

```mermaid
flowchart TD
    A[sort 族/usort 族调用] --> B{arg1 isArray?}
    B -->|否| C[throwArgTypeError<br/>可捕获 TypeError<br/>PHP 文案: ...must be of type array, X given]
    B -->|是| D{usort 族?}
    D -->|是| E{validateSortCallback<br/>12 形态}
    E -->|非法| F[throwThrowable TypeError<br/>逐形文案]
    E -->|合法| G[原排序逻辑]
    D -->|multisort| H{全参数校验<br/>flag∈[0,6]∪[8,14] / 尺寸一致}
    H -->|非法| I[TypeError/ValueError<br/>数组全保持原样]
    H -->|合法| J[DESC==3 检测 + 排序]
```

## 5. 详细变更分析（PHP↔AOT 逐字对照）

| 探针 | 内容 | 结果 |
|---|---|---|
| p20-p25 | array_filter 三形/array_map 函数上下文/嵌套/顶层 rc=255 | 全 **SAME** |
| probe_b14_sort_na(2) | sort 族九成员 × str/int/float/null/true/obj 非数组 | **SAME**（obj id #0 既有差异豁免） |
| probe_b14_usort_cb | usort 12 形态回调校验 + arg1 优先 + 合法回调正向 | **SAME** |
| probe_b14_multisort | 尺寸不一致/非数组/非法 flag/合法 flag 边界(7,9,11,15)/DESC | **SAME** |
| probe_b14_settype_splice | bogus type/非字符串 type/别名/null/splice 非数组+正常 | **SAME** |
| probe_b14_pregcb(+stmt/top) | 5 参 count=2/1/0、throw 时 count=1 增量、语句形、顶层 rc=255 | **SAME**（top 仅栈帧细节豁免） |
| probe_b14_walkrec | 递归修改/嵌套键/throw 前缀 [10,2]/非数组 TypeError | **SAME** |
| probe_b14_top_fatal/settype | 顶层未捕获 rc=255 + 文案 | **一致** |

**守护面**：f042/f164/test_063/test_029/test_010/test_051/preg_guard 全 **SAME**；批十三 throw 探针复测与批十三后状态**逐字一致**（usort 族中间态差异系已裁决不碰项）。`timeout 600 zig build` rc=0（每刀均 AOT 产物实测，无 F-38 类模板错位）。

## 6. 影响与风险评估

- **破坏式变更**：否。接球后缀仅 error 路径介入；校验新增于「旧静默/旧 fatal」路径（旧行为本即偏离 PHP）；成功路径逐字节同构。
- **行为变化点（修复性）**：sort 族非数组 noreturn fatal ⇒ 可捕获 TypeError（顶层无 try 仍 fatal rc=255，文案对齐）；multisort 非法参先校验不改动数组（旧：改一半返 false）；settype bogus type 抛错（旧静默 false）。
- **风险点**：`preg_replace_callback` 双注册点（nlk :4745/:4786）已同步；`emitRefParamsExceptionWriteback` 仅 ref_params 声明函数触发且链过滤，str_replace 守护实测零转移；settype may_raise 归位 true 后守护面无转移。
- **复测路径**：§5 探针表全量（`probe_b14_*.php` 留存）。

## 7. 遗留问题 / 潜在问题

| # | 项 | 处置 |
|---|---|---|
| a | `builtin_function_map` 仅收 usort/array_walk(_recursive)，缺 sort 族其余成员 ⇒ `$fn="rsort"; $fn($v)` 静默 false（PHP 正常分发） | 既有独立缺口（varfn 分发表覆盖差远超 sort 族），登记，专项盘点 |
| b | `preg_replace`/`preg_filter` $count 未接（模板无 count 形参；补需改 `pregReplaceSequence` 返回结构带计数，深入替换引擎） | 登记 P2（机制已备：ref_params+写回块+⑤成例） |
| c | `fuzzy_scripts/test_065_array_walk.php` 编译失败（dim-set 字符串分支 `reg_0 = __arr_deref` 缺 `.*`，alloca 类型错） | 既有缺陷（该脚本无 try 块、生成码不含本批后缀，与本批无关），登记另案 |
| d | usort 族 throw 后数组中间态（PHP 无契约） | 批次十三已裁决不碰，维持 |
| e | 守护脚本实测：`preg_replace('x','y','xax',-1,$c3)`（$c3 未定义）AOT 发 Undefined Warning（PHP by-ref 静默 vivify） | 与 b 同案登记（by-ref 未定义静默通道） |

## 8. 后续开发/优化建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|---|---|---|---|
| P1 | ⑦-a：`builtin_function_map` 与发射器 `builtin_map` 覆盖差全量盘点补齐（varfn 分发） | 全部内建 | 中 |
| P2 | ⑦-b：`pregReplaceSequence` 返回结构带计数 ⇒ preg_replace/preg_filter $count 接通（⑤ 机制直接复用） | preg 族 | 中 |
| P2 | ⑦-c：dim-set 字符串分支 alloca 解引用遗漏（test_065） | 发射器 dim-set 支 | 小 |
| P2 | ⑦-e：by-ref 实参未定义变量的静默 vivify 通道（全局/局部两形） | IR+发射器 | 中 |
| P3 | array_walk 非数组首参同 ③⑥ 口径（现 error.InvalidArgument 裸错） | 模板一行 | 小 |
