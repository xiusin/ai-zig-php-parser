# PHPString 头永久持有 + 属性键 dupe 无主（生产级内存/性能共因负向）

**问题 ID**: AOT-MEM-001
**优先级**: P0（高，长运行即 RSS 线性增长且伴随 sys 时间爆炸）
**状态**: 已根治（S1 分配器止血 + S2 头归还池 + S3 属性键所有权统一，2026-09-29）
**发现日期**: 2026-09-28（#25 取证：核实 leak 门禁与性能负向）

---

## 问题描述

AOT 产物运行期存在两处「分配有主、归零无主」的所有权缺口：

1. **PHPString 头（40B/个）永久持有**
   `PHPString.deinit`（`src/aot/runtime_lib_template.zig`）原先只释放 `data` 缓冲区，把头部标记为 `is_static = true` 后**故意不调** `destroyPHPString`，注释理由为「防止同一 Value 被 AOT cleanup 多次释放」。于是每个字符串头永久占用，`php_string_pool`（`std.heap.MemoryPool(PHPString)`）的槽位永不回流。

2. **属性键 `dupe` 无主**
   `setProperty` 走 `properties.getOrPut` + `allocator.dupe(u8, name)`，但 `std.StringHashMap.deinit()` 只回收桶数组、`remove()` 不释放键，故每个属性名副本都没有回收点；同时 SPL 内部对象（`ArrayIterator`/`SplFixedArray`/`SplStack`/`SplQueue`）与 `php_clone` 直接把**字面量键/借用键**塞进同一张表，键所有权混杂 ⇒ 任何「统一释放」的写法都会 UAF。

## 复现代码

`fuzzy_scripts_720/tmp/leak_header_slope_probe_tmp.php`（永久探针，勿删）：循环内产生即弃字符串，N 由 `$argv[1]` 传入（100k / 400k 双点取斜率）。
`fuzzy_scripts_720/tmp/leak_int_control_probe_tmp.php`（永久对照探针）：同规模整数循环，证明斜率归因于字符串头而非循环本身。

```
cd /Users/wangjianjun/products/parser
timeout 120 /usr/bin/time -l fuzzy_scripts_720/tmp/aot_compile_leak_header_slope_probe_tmp 400000
timeout 120 /usr/bin/time -l /opt/homebrew/bin/php fuzzy_scripts_720/tmp/leak_header_slope_probe_tmp.php 400000
```

## 改前实测（2026-09-28，page_allocator + 头不归还）

| 场景（400k 迭代） | 墙钟 | sys | 峰值 RSS | 输出正确性 |
| --- | --- | --- | --- | --- |
| AOT（改前） | 9.5s | 7.1s | 153.9MB（自 9.4MB 起，+360B/迭代） | 与 PHP 逐字节等值 |
| PHP 8.5 解释器 | 0.09s | — | 22.5MB | 基准 |

斜率取证：100k/400k 双点差 ÷ 迭代差 = **360 B/迭代**（= 每迭代 9 个字符串头 × 40B）；整数对照循环 400k 迭代 RSS 保持 9.4MB（斜率≈0），实锤归因字符串头。
`ZIGPHP_ALLOC_STATS=1` 的 `php_string_live_objects` 退出时仅报 36 —— 计数在 `deinit` 里已递减，**监控看不到头持有**，属监控盲点。

## 根治链条（三步，顺序即依赖顺序）

| 步 | 变更 | 位置 | 效果 |
| --- | --- | --- | --- |
| S1 | 发射的 `main` 底账分配器 `page_allocator` → `std.heap.smp_allocator` | `src/aot/native_linker.zig:1894`（发射模板字符串行 `\\    const allocator = std.heap.smp_allocator;`，全文件唯一命中；**2026-10-03 重新 grep**，原登记 `:1863` 为 2026-09-30 代次） | 消除逐缓冲 mmap/munmap，sys 时间 7.1s → 0.00s（止血，不改所有权） |
| S2 | `PHPString.deinit` 末尾调用 `destroyPHPString(self, allocator)` 把头归还池 | `src/aot/runtime_lib_template.zig`（PHPString.deinit） | 头斜率归零；三处绕过池的头分配（`php_strrchr`/`php_stristr`/`php_interpolate`）收敛到 `allocPHPString`，分配/归还所有器对称 |
| S3 | 新增属性写入唯一入口 `putProperty`，键一律自有化；`unsetProperty`/`gcDestroyObject` 回收键；12 处 SPL 字面量键 + `php_clone` + `initWithMeta` + 数组转对象全部改走该入口 | `src/aot/runtime_lib_template.zig` | 属性键 dupe 泄漏清零；消除「释放字面量键」与「clone 共享键二次释放」两类潜在 UAF |

**S2 安全前提（取证结论，非假设）**：`release()` 的「僵尸头再释放」（`is_static && ref_count == 0`）计数器在 400k 字符串探针（累计 3,600,045 个头）与 68 脚本语料全程均为 **0**，原注释所述的多次释放场景不存在。合法静态串恒为 `ref_count == 1`（`initStatic`/`StaticStringEntry`）或 `999999`（`EMPTY_STRING`），与僵尸签名可区分。
`MemoryPool.destroy` 会覆写槽位起始字节作为空闲链指针 ⇒ **`destroyPHPString` 必须是 `deinit` 的最后一次写**。

## 改后实测（2026-09-29，同一测量法 `/usr/bin/time -l`）

| 场景（400k 迭代） | 墙钟 | sys | 峰值 RSS | 输出正确性 |
| --- | --- | --- | --- | --- |
| AOT（S1+S2 后） | 0.71s | 0.00s | **2.98MB**（100k 与 400k 完全相同 ⇒ 斜率 0） | `18866670` = PHP 逐字节等值 |
| PHP 8.5 解释器 | 0.18s | 0.02s | 22.46MB | 基准 |

相对改前：内存 153.9MB → 2.98MB（−98%），墙钟 9.5s → 0.71s（13×）。对 PHP 的差距从 105× 慢收敛到 3.9× 慢，且内存反超 PHP 7.5× 更省（池化复用 vs 解释器字符串驻留表）。

## 残余风险与复测路径

- **读已释放头**：归还池后，若仍有路径持有已释放 `*PHPString` 并读取，读到的是被复用的合法头（safe-mode 不会 panic），**唯一有效检测器是 68 脚本逐字节输出回归**（`bash scripts/regression_test_720.sh`），不能以「单测全绿」代替。
- **单位测试口径**：`zig build test` 原 25 个 `allocPHPString@357` leak 步骤随 S2 消失；`test_runtime_comprehensive` 泄漏检查全绿。
- **监控盲点未修**：`php_string_objects`/`php_string_live_objects` 仍看不到「头已归还池但 Value 仍被引用」这一档，后续可加池级 busy/free 计数（P2）。

## 关联

- 变更总结：`docs/changes/2026-09-29/`（本次会话）
- 相关缺陷：`AOT-CODEGEN-004`（编译期栈溢出，与本题运行期负向同属「实测出来的代价」类问题）

## 锚点代次刷新（2026-10-05，当前工作区代次 `fbe6382a`／32797 行实测；只读巡检，零代码改动）

| 锚点 | 旧登记（2026-10-03） | **当前树实测** | 实测依据 |
|---|---|---|---|
| S1 发射的 `main` 底账分配器模板行 | `src/aot/native_linker.zig:1894` | **`:2137`** | `grep -n "smp_allocator"` = **唯一命中**，该行逐字为 `\\    const allocator = std.heap.smp_allocator;`（发射模板字符串内） |
| S2 / S3 落点（`PHPString.deinit`、`putProperty` 等） | `src/aot/runtime_lib_template.zig`（未标行号） | **未漂移** | 该文件最后一次提交为 `b21cdfd`（2026-09-30），晚于它的 A／D／R9-B 三批与 #74 均未触碰；工作区 `git status --porcelain` 干净 |

⇒ S1 的三处实测结论（sys 时间 7.1s → 0.00s、所有权口径、`destroyPHPString` 必须是 `deinit` 最后一次写）均与行号无关，**「已根治」判定维持**；后续若回取 S1 只需按 `:2137` 定位。
