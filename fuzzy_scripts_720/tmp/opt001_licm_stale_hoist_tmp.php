<?php
// AOT-OPT-001 永久取证探针：LICM 提升「循环不变量」的候选缺口（任务 #95）
//
// 路由方式教训（两次实测否证，留档勿再踩）：
//   1) 顶层 `if/elseif/…/else` 链 + 每臂一个循环：初版 ⇒ 默认档与 licm 档**臂 2–5 输出全空**。
//   2) 改为**独立 if** + `$argv[1]` 选路：⇒ **shape 1 正确、shape 2–5 仍全空（两档相同）**，
//      且 main.zig 行数 4623 → 8290（代码确实发射了）⇒ 空输出与 elseif 无关，
//      **`$argv` 数值选路在本探针几何下不可靠**，不能作为「一形一崩」族的路由载体（REF-004 那轮能用的前提是每形都走同一入口）。
//   ⇒ 本版**不用任何选路**：五形顺序执行、各打印一行，一次编译一次运行即可读全族（S1 可能死循环 ⇒ 放最后并带 guard）。
//
// PHP 真值（顺序执行全部五形）：
//   S2 total=160 n=5 / S3 acc=[11][11,22][11,22,33] sum=66 / S4 out=12 / S5 seen=3,4,5, / S1 sum=6 guard=3
// 判据：AOT 输出须逐行等值；若 LICM 把循环不变量误判提升 ⇒ 对应行数值冻结（`n=`、`sum=`、`seen=` 变常量）或 HANG_GUARD。
// 禁止删除本文件；两档各编译一次即覆盖五形。

$bag = [10, 20];
$total = 0;
for ($i = 0; $i < 3; $i++) {
    if ($i % 2 === 0) {
        $total += array_sum($bag);
    }
    $bag[] = $i * 100;
}
echo "S2 total=$total n=" . count($bag) . "\n";

$rows = [];
$acc = '';
foreach ([1, 2, 3] as $k) {
    $rows[] = $k * 11;
    $acc .= '[' . implode(',', $rows) . ']';
}
echo "S3 acc=$acc sum=" . array_sum($rows) . "\n";

$fixed = [7, 8, 9];
$out = 0;
for ($i = 0; $i < 3; $i++) {
    $out += $i + count($fixed);   // count($fixed) 真循环不变 ⇒ 提升安全（对照形）
}
echo "S4 out=$out\n";

$s = 'ab';
$seen = '';
for ($i = 0; $i < 3; $i++) {
    $s = $s . 'c';
    $seen .= strlen($s) . ',';
}
echo "S5 seen=$seen\n";

$q = [3, 2, 1];
$sum = 0;
$guard = 0;
while (count($q) > 0) {
    $v = array_pop($q);
    $sum += $v;
    $guard++;
    if ($guard > 50) { echo "S1 HANG_GUARD sum=$sum\n"; break; }
}
echo "S1 sum=$sum guard=$guard\n";
