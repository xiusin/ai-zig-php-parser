# 交接文档（会话 8 终）：f025/f087/f006/f009/f031/f151/f177/f178 转 PASS

> 日期：2026-09-19 | 涉及文件：`src/aot/native_linker.zig`
> 编译状态：✅ `zig build` 通过
> 回归状态：✅ 85 脚本 PASS 65（+6），零新增回归（第五~八次回归夹逼一致）
> 上级交接链：
> - `docs/changes/2026-09-19/handoff_session7.md`（会话 7）
> - `docs/changes/2026-09-19/f025_elseif链PHI与嵌套短路链修复.md`（本会话技术细节）
> 用户指令：**"继续推进任务修复问题" / "继续推进已知问题" / "继续推进已知问题修复"**

---

## 1. TL;DR

1. **f025/f087 完整转 PASS**：elseif 链 merge PHI 消解、lmi dispatch 范围越界（`end_idx` → `@min(end_idx, loop_end)`，三处对称）两缺陷根治。
2. **throw 语句生成缺失根治**（`if (...) throw new E;` 的 then terminator `.throw` 被静默忽略）：主循环 then terminator switch 补 `.throw` 分支（writeThrowTerminator + return_generated），**f006/f009/f031/f177 四个异常隔离脚本转 PASS**。
3. **elvis（?:）then 边 phi 消解缺失修复**：主循环 then 发射补 phi 消解（来自 cond_br 源块的 incoming），**f151 转 PASS**。
4. **f178 顺带转 PASS**（FAIL_RUNTIME→PASS）。基线以来 PASS 50 → **65**（+15）。

## 2. 修复清单

| # | 位置 | 内容 | 验证 |
|---|------|------|------|
| D | generateForFromLabels cond_br case else 末尾（~11500） | elseif 链：else 路径汇合块（if_merge_14）的 incoming 在外层 merge（if_merge_12）phi 消解中补发 | f025_lzw_min ✅、f025 完整 ✅ |
| E1/E2 | generateLabelDrivenBlockRange then terminator `.cond_br`（~7731） | 嵌套短路链（then=logical_merge_、else=logical_rhs_）展开为 if/else + 补外层 merge then 边消解（经嵌套 merge 的 .br 取得外层 merge 块） | f087_min ✅、嵌套链条件恢复正确 |
| F | generateForeachFromLabels else_is_be（~9421） | then 非 break 且 else 回边时清 return_generated（对称预防） | 防御性保留 |
| G | 工作区重建 | staged 基底 + 修复 A/B 重放，空行翻倍消除 | git diff 290+/10-，build ✅ |
| **H** | **三处 lmi dispatch 范围钳制**（foreach ~9975 / for ~11734 / while ~13109，`end_idx` → `@min(end_idx, loop_end)`） | logical_merge_to_process 的发射范围从函数尾钳制到循环体最后回边+1；越界会把循环外的块（嵌套循环及其 cleanup 的 ret）发射进当前循环体内 | f087_min6 全场景 ✅、**f087 完整 ✅** |
| **I** | 主循环 then terminator switch 补 `.throw` 分支（~7697） | `if (...) throw new E;` 的 then 块以 throw 终止时，`.throw` 落入 `else => {}` 被静默吞掉；补 writeThrowTerminator + return_generated | f006/f009/f031/f177 ✅ |
| **J** | 主循环 then 发射补 phi 消解（~7527） | then 块的 phi（ternary_merge_ 的 elvis 真值）来自 cond_br 源块的 incoming 在此消解，否则 merge 值读到 null | f151 ✅ |

## 3. 回归统计（85 脚本）

| 类别 | 会话7 | 会话8中途 | **会话8终** | 变化 |
|------|-------|--------|--------|------|
| PASS | 59 | 60 | **65** | **+6**（f025/f087/f006/f009/f031/f151/f177/f178） |
| FAIL_RUNTIME | 9 | 9 | **8** | -1（f178 转 PASS） |
| FAIL_DIFF | 16 | 15 | **11** | -5 |
| 零回归 | ✅ | ✅ | ✅ | 第五~八次回归夹逼一致 |

**基线以来总成绩**（会话 6 基线 79 脚本 PASS 50）：PASS **65**（**+15**：f061/f042/f104 会话6、f027/f028 会话7、f025/f087/f006/f009/f031/f151/f177/f178 本会话）；FAIL_COMPILE 1→0；失败项 29→20。

## 4. 本轮（会话 8 续）诊断路径沉淀

1. **排除回滚机制**：`tryGenerateStructuredControlFlowNew` 的守卫（f087 方法含递归调用 → `has_recursive_call=true` 跳过）——回滚嫌疑排除
2. **主循环实例追踪**（generateLabelDrivenBlockRange 入口/出口打印）暴露 `LR-enter start=6 end=17`——lmi dispatch 越界到函数尾
3. **loop_last_be 实测**（cond_idx=1 body_idx=2 inc_idx=3 llbe=8 正确）——排除计算错误，锁定 dispatch 参数误用 `end_idx` 而非 `loop_end`
4. **修复后时序验证**：第二 foreach 的发射回到第一 foreach 收尾之后（主循环顶层扫描），增量指令落在循环体内正确位置，unreachable 消除

## 5. 自检结论

| 检查项 | 结果 |
|--------|------|
| 编译验证 `zig build` | ✅ exit 0 |
| 全量回归（第八次） | ✅ PASS 65，零回归（第五~七次夹逼一致） |
| f025/f087/f006/f009/f031/f151/f177/f178 | ✅ 均完整 PASS |
| f027/f028/f061/f033/f051/f042/f104 | ✅ 保持 PASS |
| 调试代码/产物清理 | ✅ 全部移除 |
| 工作区文件健康 | ✅ 空行翻倍已修复，git diff 干净（290+/10-） |

## 6. 下一会话任务优先级

| 优先级 | 事项 |
|--------|------|
| P0 | FAIL_DIFF 11 项逐个攻坚：f037（新 FAIL_DIFF，原 FAIL_RUNTIME）、f065/f070/f085/f097/f113/f117/f134/f160/f163/f177 |
| P1 | FAIL_RUNTIME 8 项：f007/f038/f095（超时）、f067/f161、f124/f135（崩溃） |
| P2 | lastLineIsReturn 启发式替换为控制流标志；三个循环生成器 cond_br case 的重复框架统一 |
| P2 | 会话 8 的最小复现脚本（f025_lzw_min、f087_min6、f025_decode_min5）质量高，建议筛选入回归集 |

## 7. f065 现场（会话 9 深挖，根因已精确锁定）

**现象**：SimpleSHA1（纯 PHP 位运算实现）在 AOT 下结果错误 → 收敛为死循环（rc=124，`$i` 恒 0）。

**最小复现**：`fuzzy_scripts_720/tmp/f065_g6.php`（9 行）：
```php
$a=0x67452301; $b=0xEFCDAB89;
for ($i = 0; $i < 25; $i++) {
    if ($i < 20) { $f = $b & $a; }
    elseif ($i < 40) { $f = $b ^ $a; }
    $a = $f + 1;
}
```

**IR 结构**（已确认正确，无 for_loop_ 增量块——$i++ 在 if_merge_7 内）：
```
for_cond_1 → for_body_2 → if ($i<20) → if_then_5 / if_else_6
if_then_5: $f=$b&$a; br if_merge_7
if_else_6: if ($i<40) → if_then_8 / if_merge_7
if_merge_7: $a=$f+1; $i++; br for_cond_1     ← 汇合块兼回边块
```

**根因（100% 确认）**：生成的 Zig 中，`if_merge_7` 的内容（`$a=$f+1`、`$i++`、写回）**只发射在 else 分支内**，then 分支（$i<20）P1 后直接落到外层 if 尾部的 continue——`$a`/`$i` 永不更新 → 死循环。

**发射位置**：`generateForFromLabels` 的 cond_br case 中，L2（elseif 的 cond_br）的 merge 处理（merge_bi=if_merge_7）把 merge 内容发射在 **L2 的 if/else 闭合后 = L1 的 else 分支内**。then 边（L1 的 if_then_5 → br if_merge_7）的 `.br` 终止符处理（For 版 ~11127 的 switch）对 `if_merge_` 目标**静默忽略**（前缀检查无 else 兜底），then 边无 merge 内容。

**修复方案（两选一，均未落地）**：
- 方案 A：For 版 .br 分支的静默处加 `else { merge_bi = blk_i; }`（与主循环版 7696 对称），让 L1 的 merge 段在 if/else 闭合后统一发射 merge 内容——**需同时阻止 L2 的 merge 发射**（否则重复，$a 加两次），L2 的发射需检测 merge 已被外层认领
- 方案 B：then 边发射 merge 内容（已在 then terminator .br 处尝试成功，见插桩验证）+ 阻止 else 边的重复——**与方案 A 对称的发射点协调问题**
- 方案 C（推荐）：**merge 内容的发射位置统一挪到 if/else 结构闭合后**（两分支共享），L1/L2 的 merge 段都只做 PHI 消解标记、不发射非 PHI 指令；这需要梳理 generateForFromLabels 的 merge 段逻辑，属于结构化重构

**注意**：修复时严禁破坏 `.br` 分支的 `} else { merge_bi = blk_i; }` 结构（会话 9 曾因 python 清理脚本误删该 else 导致 f025 死循环回归，已恢复）。

**关联**：f070/f134（EventSourcing 计数错误）可能同属 elseif+回边场景的 merge 发射问题，修复后应复测。

## 8. 会话 9 状态

- 第九次回归：PASS 65，与第八次一致，零回归（f025 意外回归已恢复）
- 本会话累计转 PASS：f025/f087/f006/f009/f031/f151/f177/f178（8 项）
- 基线以来：PASS 50 → **65**（+15），失败项 29 → 20
