# 批次二十二（Q4）：B 类核心 32 枚——真值驱动实现 + 双表同口径登记

## 1. TL;DR

Q4 清单 32 枚 B 类内建函数全部按 PHP 8.5.8 实测真值实现并双表登记（编译期 `builtin_map` + 运行期变量调用表），直调 ≡ 变量调用。其中 `html_entity_decode` 的四张实体表（HTML401/XHTML/XML1/HTML5 共 2022 条）由新写的反射生成器 `scripts/gen_html_entity_table.php` 导出（可重跑可 diff，禁手抄）；`metaphone` 照 PHP 8.5.8 `metaphone.c` 逐条移植；`soundex`/`version_compare`/`str_increment` 等规则全部经真值探针钉死后落码。落地期修掉 6 枚实现坑（Zig 0.17 窄型溢出、hex 减基错位等，见 §4）。

## 2. 影响范围

| 层 | 文件 | 变更 |
|---|---|---|
| 运行时模板 | `src/aot/runtime_lib_template.zig` | +Q4 区（32 handler + 32 wrapper + q4HexVal/相似度/版本比较内核）；常量族补 ENT_*/JSON_ERROR_*；gc 统计计数器 |
| 编译期 | `src/aot/native_linker.zig` | builtin_map +32（:4737-4770）；名单站接球通道 +6（fprintf/merge_recursive/replace_recursive/json_validate/gc_disable/gc_status，双处）；copyOtherRuntimeFiles +实体表 |
| 生成器 | `scripts/gen_html_entity_table.php`（新） | 实体表反射导出（方向反转：字符→实体 转 实体→字符，键序稳定） |
| 生成物 | `src/aot/html_entity_table_generated.zig`（新，2047 行） | 四张实体表（253/253/5/1511） |

## 3. 核心变更

- **A 风格**（26 枚）：编译期逐个传参 + `optional_defaults` 声明式补齐（如 `levenshtein` 5 参 3 默认、`substr_compare` 5 参 2 默认）；`similar_text` 的 `$percent` 走 Q3 Ref 协议（`ref_params={2}`）。
- **B 风格**（6 枚变参/整切片）：handler 直接收 `args: []const Value`，发射走名单站接球通道——与变量调用面天然同码。
- **真值钉死的非平凡语义**：
  - quoted_printable_encode：tab 恒编码、空格仅 `\r\n` 前编、裸 `\n`→`=0A`、串尾空格原样、75 列软换行
  - convert_uuencode：45 字节/行、0→'`'、恒产结束行；uudecode 空/畸形 ⇒ Warning+false
  - str_increment/decrement：全进位前缀按**首字符**类别（Z9→AA0）；decrement 穿透首字符 ⇒ 长>1 收缩、长 1 ValueError（带值措辞）
  - version_compare 尾部规则：剩余首段数字 ⇒ 该侧大（1.0<1.0.0 且 1.0<1.0.0alpha）
  - json_validate：写 `last_json_error_code`（成功置 NONE），整文本 UTF-8 校验（等价口径：JSON 非 ASCII 合法位只在字符串字面量）
  - html_entity_decode：命名实体严格分号、数字实体 `&#x;` 支持、码点 0/代理区/超界原样、flags 选四表

## 4. 可视化（mermaid）

```mermaid
flowchart LR
    subgraph 生成期
        G[scripts/gen_html_entity_table.php] -->|get_html_translation_table ×4 flags| T[html_entity_table_generated.zig]
    end
    subgraph 编译期
        A[PHP 直调] --> B[builtin_map 查表<br/>handler_params/optional_defaults 补齐]
        B --> C{{A 风格逐个传参}}
        B --> D{{B 风格名单站接球<br/>整切片}}
    end
    subgraph 运行期
        E[变量调用 $f(...)] --> F[php_invoke_callable<br/>Q3 Ref 归一化]
        F --> G2[registry wrapBuiltin_*]
    end
    C --> H[php_q4_* handler 单一实现]
    D --> H
    G2 --> H
    H --> T
```

## 5. 详细变更分析

- 端：AOT 编译产物（用户 PHP 脚本）；影响面：32 枚此前 `Call to undefined function` 的 B 类函数全部可用。
- 涉及文件：上表 4 文件 + 探针 `/tmp/aot_census/q4_truth_{str,fmt,arr,misc}.php`、`q4_edge.php`。
- 变更点：全部新增，无既有行为改动（常量族为纯补登）。

### 落地期坑（全修）

| 坑 | 根因 | 修法 |
|---|---|---|
| uuencode 45 字节行行首坍缩 | Zig 0.17 `@min(comptime_int,usize)` 窄型化 ⇒ +32 溢出 | 显式 `const n: usize` |
| qp_decode `=3D`→']' | `toLower` 后按原字符减基 | 抽 `q4HexVal` 统一（3 处同修） |
| needs_allocator=false 错位 | 5 枚 handler 多带 allocator 形参 | 去形参（真不用） |
| version_compare 尾向反 | 符号表意混乱 | side_wins 重述 + 秩翻转 |
| `**` 数组重复语法 | Zig 0.17 空白规则 | `@splat` |
| 内嵌 struct 形参 shadow | norm.f allocator 撞外层 | 改名 |

## 6. 影响与风险评估

- **破坏式变更**：无（纯新增 + 常量补登）。
- 特别注意：`similar_text` 经 cufa 的 `[&$p]` 引用元素形不生效——属既有待批族（§250.4 数组元素引用），探针已标注。
- 复测路径：`zig build` → 4 真值探针 + q4_edge 对拍 PHP → 41 格面板零转移。

## 7. 遗留

| 项 | 处置 |
|---|---|
| cufa 数组元素引用形（similar_text 等 out 参） | 待批（§250.4，需 parser/ast + PHPArray 元素 Ref 语义） |
| html_entity_decode 的 ENT_SUBSTITUTE 无效 UTF-8 替换 | 输入假定有效（AOT 字符串口径），未测面 |
| gc_status 时间计数器（application_time 等 4 键） | AOT 未埋点 ⇒ 0.0（如实，非桩） |

## 8. 后续建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|---|---|---|---|
| P1 | 数组元素引用（`[&$m]`） | 中-大 | 待批后立项：解开则 cufa out 参族全通 |
| P2 | htmlentities 全家（ENT_HTML5 编码向复用同表） | 小 | 表已在，htmlentities 只覆盖 5 基本实体可扩 |
| P2 | metaphone 非 traditional 形 | 小 | PHP 内部不用，语料零频；登记不实现 |
