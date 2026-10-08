<?php
// 内存增长斜率探针（只读取，不改语义）：循环内产生即弃的 PHPString 对象，
// 观测 PHPString header 永久保留（runtime_lib_template.zig:1567-1573）在生产路径的增长。
$n = (int)($argv[1] ?? 100000);
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
