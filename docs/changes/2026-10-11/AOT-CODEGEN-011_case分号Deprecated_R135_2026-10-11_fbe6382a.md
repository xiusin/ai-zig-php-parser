# AOT-CODEGEN-011 case 分号终结符 Deprecated（R-B1 消息面收口）_R135_2026-10-11_fbe6382a

## 1. 高层摘要（TL;DR）

1. **R-B1 消息面残差收口**：`case X;` / `default;` 分号终结符现在发射与 PHP **逐字节一致**的 `PHP Deprecated:  Case statements followed by a semicolon (;) are deprecated, use a colon (:) instead`（三模式：AOT 编译日志 + 解释器 stderr；AOT 运行产物不受影响）。
2. **实现路径**：parse 期诊断无法跨层调用 AOT 运行时 emitDeprecated（compiler/aot 模块边界 + 运行时位置全局 parse 期未设）⇒ 走 **PHPContext 诊断通道**：`Error` 结构加 `is_deprecated` 标记（复用 errors 列表）+ `PHPContext.addDeprecatedWarning(msg, line)`（行号经提取的 `currLine`）+ main 双入口按 PHP 形态打印（解释器 stderr / AOT 编译日志）。
3. **自纠一处**：AOT 入口的解析失败检查原用 `errors.items.len > 0` + `items[0]` —— Deprecated 入列后纯 Deprecated 脚本会被误判解析失败 ⇒ 改为跳过 `is_deprecated` 项的 first-fatal 扫描；两处 catch 分支的 "Parse error" 列印同步过滤。
4. **验收**：三模式探针（AOT 编译日志 1 命中 / 解释器 stderr 与 PHP 逐字节一致 / 值输出 `A` 一致）；门 N/O 保持 7/6 全绿（norm 剥 Deprecated 行）；门 D8/M 保持；`zig build test` 通过；链 XIV 主回归见报表。

## 2. 核心变更

| # | 变更 | 文件 | 内容 |
|---|---|---|---|
| 1 | `Error.is_deprecated` 标记 | compiler/root.zig | 非致命诊断标记（默认 false，既有解析错误零扰动） |
| 2 | `PHPContext.addDeprecatedWarning(msg, line)` | compiler/root.zig | 复用 errors 列表的 Deprecated 记录（arena 拷贝消息） |
| 3 | `currLine()` 提取 | compiler/parser.zig | reportError 的行号计算提取为助手（DRY） |
| 4 | 两处分号分支接线 | compiler/parser.zig case/default 臂 | 分号消费时 `addDeprecatedWarning("Case statements followed by a semicolon (;) are deprecated, use a colon (:) instead", currLine())` |
| 5 | main 双入口打印 | main.zig 解释器入口 + AOT 入口 | `PHP Deprecated:  {msg} in {file} on line {line}`（解释器 stderr / AOT 编译日志）；解析失败检查跳过 is_deprecated；catch 分支列印过滤 |

## 3. 验收读数

| 项 | 结果 |
|---|---|
| AOT 编译日志 | Deprecated 1 命中 ✅ |
| 解释器 stderr | 与 PHP 逐字节一致 ✅ |
| 值输出 | `A` 三模式一致 ✅ |
| 门 N/O | 7/7、6/6 全绿（Deprecated 行 norm 剥除，判据 = 值输出） |
| D8/M | `defect_red=0` / `red=0 green=19` 保持 |
| 主回归 | Pass 67 / Skip 1（链 XIV 报表） |

## 4. 遗留与建议

| 优先级 | 事项 |
|---|---|
| **P0** | 「提交」：R-135 批（root/parser/main 三文件）+ R-134 门 N/O 资产 + 工单 011 修订分票点名 |
| P2 | Deprecated 的 stderr/stdout 双通道形态（当前单条 stderr；PHP 双写由 display 机制对齐——norm 已对齐） |
| P2 | R-C3（VM 面 B/C）、R-M1（VM 静默吞解析失败）维持登记（§五） |
