# AOT 产物未绑定 `$argv` / `$argc` 超全局（CLI 取参能力缺失）

**问题 ID**: AOT-RUNTIME-001
**优先级**: P1（能力缺口：真实 CLI 脚本按 `$argv[1]` 取参，AOT 下恒为未定义）
**状态**: 已根治（S4，2026-09-29），并实测与 PHP CLI 逐字节等值
**发现日期**: 2026-09-28（#25 负向巡检 B）

---

## 问题描述

发射的 `main` 只把命令行参数塞进 `$_SERVER['argv']` / `$_SERVER['argc']` 副本，`global_vars` 里从未写入 `$argv` / `$argc`。PHP CLI SAPI 中 `$argv`/`$argc` 是**全局变量**，因此脚本里 `$argv[1]`、`count($argv)`、`$argc` 在 AOT 产物中一律读到未定义（`null`/空），而解释器下正常。

位置（改前）：`src/aot/native_linker.zig` 发射前导 `$_SERVER` 组装块（约 1883-1898）。

## 复现代码

`fuzzy_scripts_720/tmp/argv_support_probe_tmp.php`（永久探针，勿删）：

```php
<?php
echo "argc=" . $argc . " n=" . (int)($argv[1] ?? -1) . " cnt=" . count($argv) . "\n";
```

```
cd /Users/wangjianjun/products/parser
timeout 300 zig-out/bin/php-interpreter --compile --no-debug-info fuzzy_scripts_720/tmp/argv_support_probe_tmp.php
timeout 10 fuzzy_scripts_720/tmp/aot_compile_argv_support_probe_tmp alpha 42 gamma
/opt/homebrew/bin/php fuzzy_scripts_720/tmp/argv_support_probe_tmp.php alpha 42 gamma
```

## 根治

在发射前导的 `$_SERVER` 块内，先让 `global_vars` 取得 `argv_arr` 的**首份所有权**，再按原顺序写入 `$_SERVER` 副本：

```zig
// PHP CLI 语义：$argv/$argc 是全局变量，仅放入 $_SERVER 副本不足够。
// 先由 global_vars 取得 argv_arr 的首份所有权，
// 随后 $_SERVER 写入时按值语义自行 retain，避免 ref_count>1 触发 COW 浅拷贝。
try global_vars.put(try allocator.dupe(u8, "$argv"), runtime.Value.initArray(argv_arr));
try global_vars.put(try allocator.dupe(u8, "$argc"), runtime.Value.initInt(@intCast(arg_idx)));
```

顺序是关键约束：若先写 `$_SERVER` 再写全局，两处会共享同一 `ref_count`，后续任何一次写入都触发 COW 分叉，`$argv` 与 `$_SERVER['argv']` 语义不再是同一份视图。

## 实测（改后，2026-09-29）

| 输入 | AOT 产物 | PHP 8.5 解释器 | 结论 |
| --- | --- | --- | --- |
| `alpha 42 gamma` | `argc=4 n=0 cnt=4` | `argc=4 n=0 cnt=4` | 逐字节等值 |
| 无参数 | `argc=1 n=-1 cnt=1` | `argc=1 n=-1 cnt=1` | 逐字节等值 |

`$argv[0]` 语义核对：发射代码遍历 `std.process.Args.Iterator.init(init_arg.args)`，实测 `cnt=4`（3 个实参 + 程序名）⇒ Zig 0.16 的 `Init.Minimal.args` **含 argv[0]**，与 PHP 的 `$argv[0]`（脚本路径）位序一致，不存在错位。AOT 下 `$argv[0]` 取值为产物路径（编译期无脚本文件），属编译型产物的固有差异，不计为 DIFF。

## 代价与复测

- 该修复改动**每一个** AOT 产物的发射前导 ⇒ 72 项 `main.zig` 逐字节 md5 冻结基线必须整体重采集（S7）。
- 复测路径：上述探针命令 + `bash scripts/regression_test_720.sh`（68 脚本逐字节输出对比）。
- `$_SERVER['SCRIPT_FILENAME']` 仍取自第一个 CLI 参数（即产物路径），这是改前既有行为，本题未触碰；若后续要求与 PHP 的脚本路径语义对齐，需另行立项（编译期把源文件路径烧进产物）。
