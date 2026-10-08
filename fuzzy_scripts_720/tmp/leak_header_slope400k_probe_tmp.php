<?php
// 斜率对照探针：与 leak_header_slope_probe_tmp.php 同构，N 硬编码 400000
// （AOT 侧 $argv 全局未绑定，无法参数化，故用两份常量文件取斜率）。
$n = 400000;
$acc = 0;
for ($i = 0; $i < $n; $i++) {
    $s = strtoupper("abc" . $i);
    $t = $s . "_suffix";
    $acc += strlen($t);
    $u = trim("  " . $t . "  ");
    $acc += strlen($u);
    $v = strrev($u);
    $acc += strlen($v);
}
echo $acc . "\n";
