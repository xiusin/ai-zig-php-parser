<?php
/**
 * 永久探针（AOT-TYPE-001 §P2 口径分歧定性 + AOT-REF-002 R-6 引用 cell 回收上界量化）
 *
 * 静态分歧（实测行号，代次 fbe6382a/32797）：
 *   - writePtrAwareAssign 的「alloca ← ref_ptr ∧ 目标是引用参数 alloca」支 retain（:1348 写 .* + :1349 retain）
 *   - 引用参数实参初始化路径的同一几何不 retain（:21069，同块三支后仅 break）
 * 本探针取该几何下的**可观测差异**：若少 retain ⇒ 计数偏低 ⇒ 提前释放（症状 = 值变空/变垃圾/段错误）；
 * 若多余释放路径不存在 ⇒ 输出与 PHP 逐字节等值，静态分歧不成立为缺陷。
 *
 * MEM=* 行按设计不参与 AOT↔PHP 等值比较（分配器不同），单独登记为 R-6 上界读数。
 */

// S1 引用参数被整体改写为堆字符串（长串，触发堆分配与释放）
function s1_overwrite(string &$s): void
{
    $s = str_repeat("A", 4096) . "|tail";
}

// S2 两个引用参数互换（同一值同时被两个 ref 槽指向 ⇒ 双重释放最易暴露）
function s2_swap(string &$a, string &$b): void
{
    $t = $a;
    $a = $b;
    $b = $t;
}

// S3 引用参数指向数组，callee 追加后 caller 读回（COW 换代路径）
function s3_append(array &$a, int $n): void
{
    for ($i = 0; $i < $n; $i++) {
        $a[] = "e" . $i;
    }
}

// S4 嵌套调用：同一变量的引用参数跨两帧（旧帧释放时新帧仍持引用）
function s4_nested(string &$s): void
{
    s1_overwrite($s);
    echo "S4-inner=" . substr($s, 0, 8) . " len=" . strlen($s) . "\n";
    s1_overwrite($s);
}

// S5 引用参数与局部别名共存（unset 局部名后 ref 槽仍须有效）
function s5_alias(string &$s): void
{
    $alias = $s;
    unset($alias);
    $s = $s . "|after-unset";
}

$long = str_repeat("B", 2048);
echo "S0-init=" . substr($long, 0, 6) . " len=" . strlen($long) . "\n";

s1_overwrite($long);
echo "S1=" . substr($long, 4090) . " len=" . strlen($long) . "\n";

$x = "X" . str_repeat("c", 100);
$y = "Y" . str_repeat("d", 100);
s2_swap($x, $y);
echo "S2 x=" . substr($x, 0, 3) . strlen($x) . " y=" . substr($y, 0, 3) . strlen($y) . "\n";

$arr = ["seed" => str_repeat("Z", 512)];
s3_append($arr, 5);
echo "S3 count=" . count($arr) . " last=" . $arr[4] . " seedlen=" . strlen($arr["seed"]) . "\n";

$nest = str_repeat("N", 64);
s4_nested($nest);
echo "S4=" . substr($nest, 4090) . " len=" . strlen($nest) . "\n";

$al = str_repeat("E", 300);
s5_alias($al);
echo "S5 tail=" . substr($al, 295) . " len=" . strlen($al) . "\n";

// R-6 量化：同一引用参数压入堆值 N 次，观察引用 cell 是否归还（斜率 = 每轮泄漏上界）
$m0 = memory_get_usage();
$pressure = str_repeat("P", 128);
for ($k = 0; $k < 200000; $k++) {
    s1_overwrite($pressure);
}
$m1 = memory_get_usage();
echo "MEM_AFTER=" . $m1 . " DELTA=" . ($m1 - $m0) . "\n";
echo "PRESSURE-ALIVE=" . strlen($pressure) . " head=" . substr($pressure, 0, 4) . "\n";

echo "DONE\n";
