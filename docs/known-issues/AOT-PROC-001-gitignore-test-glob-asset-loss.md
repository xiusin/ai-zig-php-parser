# `.gitignore` 的 `test_*` 通配吞掉新建测试资产（资产丢失事故）

**问题 ID**: AOT-PROC-001
**优先级**: P0（流程缺陷：已交付的测试资产被静默丢失，且不可从 git 恢复）
**状态**: 事故已复原（S6 按文档重写 7 用例）；**防复发措施待用户裁决**（改 `.gitignore` 或强制 `git add -f`）。**2026-10-04 复核追加**：同类暴露面不止「被 `.gitignore` 挡住」——冻结基线 `baseline_main_zig_md5.tsv` 与 11 个永久门脚本**从未 `git add`**（见「同类暴露面复核」节），防复发选项表已扩为四行，同样待裁决。
**发现日期**: 2026-09-28（#25 负向巡检 A）

---

## 事故链

1. `src/aot/test_liveness_analysis.zig`（2026-07-18 迁移时交付，+243 行 / 7 用例）被 `build.zig:134` 的 `test_files` 引用。
2. 文件被删除后，`git log --all` **查不到任何记录** —— 因为它从未进入版本库。
3. 根因：`.gitignore:16` 有一条通配 `test_*`（本意是忽略根目录编译产物），它同样匹配 `src/aot/test_*.zig` 这类**源代码**：

```
# 根目录编译产物（非源代码）
/test*
test_*
```

4. `git check-ignore -v src/aot/test_liveness_analysis.zig` 实锤命中该规则：

```
.gitignore:16:test_*	src/aot/test_liveness_analysis.zig
```

5. 后果：新建的 `test_*.zig` 在 `git status` 里根本不出现（未跟踪且被忽略），`git add .` 也加不进去，删除后无从恢复；同时 `zig build test` 出现一个**编译步骤失败**（`failed to check cache: file_hash FileNotFound`），此前多个会话把它误记为「leak 门禁固有失败」，掩盖了资产丢失事实。

## 现存同类资产核查

`src/aot/` 下 9 个 `test_*.zig` **是**被跟踪的（`git ls-files` 可见）—— 说明历史上是逐次 `git add -f` 强制入库的。也就是说该通配规则的陷阱一直存在，只是没人再新建过测试文件；本次 S6 重建时若不 `-f`，会**第二次**丢掉同一个文件。

## 复原（S6，已完成）

按 `docs/changes/2026-07-18/Zig0.16测试基础设施迁移_20260718.md` 记载的 7 个回归点重写 `src/aot/test_liveness_analysis.zig`，全部用例绿：

| # | 用例 | 锁定的行为 |
| --- | --- | --- |
| 1 | 线性块内消费即死亡 | 指令级 live 集随消费归零 |
| 2 | 跨块活跃传播 | `live_in` 沿边反向传播到前驱块出口 |
| 3 | PHI incoming 前驱精确语义 | incoming 只对**对应**前驱块末尾活跃；且 incoming 寄存器必须纳入 `max_reg_id`（c047/c050 崩溃根因） |
| 4 | select 三操作数全部计入使用 | cond/then/else 三者皆活 |
| 5 | cond_br 双后继合并 | 单臂使用也要抬升前驱块出口活跃集 |
| 6 | 空函数与空块边界 | 零块函数 `live_in_storage == null`，查询恒 false |
| 7 | 越界索引查询安全 | 块/指令/寄存器三维越界一律 false，不 panic |

其中用例 5 校正了一处**非标准期望**（我最初写错）：终止指令操作数只并入指令级活跃集（`computeInstLiveness` 从块出口集起算后再 `addTerminatorUsedRegs`），**不并入块出口集** —— `live_out[B]` 的语义是「流出边上的活跃值」，被 B 自己的 `cond_br` 消费完即死亡。正因两个判据不对称，发射侧释放寄存器必须同时要求 `isLiveAfter` 与 `isLiveAtBlockExit` 均为假。该不对称已由断言永久锁定。

## 防复发选项（需用户裁决，未擅自改动）

| 优先级 | 方案 | 影响面 | 落地成本 |
| --- | --- | --- | --- |
| P0 | `.gitignore` 增补负向规则 `!src/**/test_*.zig` | 仅放开源代码目录内的测试文件；根目录产物仍被 `/test*` 拦住 | 1 行，零代码风险（**属配置变更，按宪法 §六 须先获确认**） |
| P1 | 立刻 `git add -f src/aot/test_liveness_analysis.zig` 并纳入提交 | 单文件入库，防第二次丢失 | 1 命令（AI 不执行提交，需老铁操作） |
| P2 | `build.zig` 的 `test_files` 增存在性断言（缺失即 fail-fast 并打印明确原因） | 把「文件缺失」从 `file_hash FileNotFound` 这种隐晦报错变为显式错误 | 约 5 行 |
| **P0（2026-10-04 复核新增）** | 把 `fuzzy_scripts_720/baseline_main_zig_md5.tsv`（72 行数据 = 语料 68 条 + 常驻探针 4 条：`stack_deep_probe_tmp`、`budget_gate_{stress,og7k,small}_probe_tmp`；工作区唯一副本）与 11 个未入库的永久门脚本一并 `git add` 并纳入提交 | 漂移/等值证据链从「单副本文件」升格为「版本库资产」；不影响任何生成码与基线哈希 | 12 个文件入库（**AI 不执行提交，需老铁「提交」指令**；建议与 A+D 批同批或紧随其后） |

## 同类暴露面复核（2026-10-04，只读实测，零代码改动）

用同一套方法（`git ls-files` / `git log --` / `git check-ignore -v`）复核本修复链依赖的**其他单副本资产**，发现一类**后果相同、成因不同**的暴露面：不是被 `.gitignore` 吞掉，而是**从未 `git add`**。

| 资产 | 实测 | 判定 |
|---|---|---|
| `fuzzy_scripts_720/baseline_main_zig_md5.tsv` | `git log --oneline -- <path>` 返回 **0 条**；`git check-ignore -v` 输出 `NOT ignored`；`wc -l` = 78（`grep -c '^#'` = 6 行注释头，`grep -vc '^#'` = 72 行数据） | **冻结基线在工作区之外没有任何副本**。漂移门的判据完全依赖此文件（现读数 `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0`）⇒ 一旦被 `git clean -fd` 或误删，「逐字节等值」这条证据链不可恢复，只能重冻结；而重冻结会抹掉 09-29 那次 S7 冻结以来的全部历史等值性 |
| `fuzzy_scripts_720/tmp/*.sh` 门脚本 | 未跟踪 **11** 个 ／ 已跟踪 **4** 个（`c005_full_drift_tmp.sh`、`c005_probe_run_tmp.sh`、`c005_rc4_probe_run_tmp.sh`、`c005_rc5_probe_run_tmp.sh`） | 未跟踪组含本轮登记的**永久门**：`c006_tl_probe_run_tmp.sh`（CODEGEN-006 九形门）、`c006_d_probe_run_tmp.sh`（D 批双臂门）、`c005_dowhile_probe_run_tmp.sh`（do-while 门），另有 REF-001/002/003 与 `f12_determinism`、`f161_spotcheck`、`s7_baseline_spotcheck`、`rc5b_shadow_scan` 历史门 ⇒ 与基线同属「删了就没了」类 |
| `fuzzy_scripts_720/tmp/c005_full_drift_tmp.sh` | `git ls-files` 命中（`0ff09cf` 首次入库） | ✅ 漂移**配方**已入库，缺的是它读取的**数据**（上第一行） |

**结论（方法论）**：`.gitignore` 陷阱与「压根没 add」导致同一个后果——已交付的验收资产在 git 里不存在。因此入库检查必须两条并列：`git check-ignore` 只能证明「没被规则挡住」，**不能**证明「已经在库里」；唯一可靠判据是 `git ls-files --error-unmatch <path>`（未入库即非零退出）。

## 复测路径

```
cd /Users/wangjianjun/products/parser
git check-ignore -v src/aot/test_liveness_analysis.zig   # 命中即为陷阱仍在
git ls-files src/aot/ | grep -c '^src/aot/test_'          # 入库数量
timeout 300 zig build test -- --filter "liveness"         # 7 用例
```

2026-10-04 追加（单副本资产入库核查；下列两条均为**本轮实测值**，非预期值）：

```bash
cd /Users/wangjianjun/products/parser
git ls-files --error-unmatch fuzzy_scripts_720/baseline_main_zig_md5.tsv   # 实测 rc=1 ⇒ 未入库
for f in fuzzy_scripts_720/tmp/*.sh; do
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 || echo "MISSING: $f"
done                                                        # 实测 11 行 MISSING / 共 15 个 .sh（4 个已入库）
```
