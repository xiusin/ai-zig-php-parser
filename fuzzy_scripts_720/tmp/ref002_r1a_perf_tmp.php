<?php
// 临时性能探针（交付后删除）：量化 R-1a 每轮 make_ref 装槽相对按值 foreach 的开销。
function sum_by_ref(array $a): int {
    $s = 0;
    foreach ($a as $key => &$v) {
        $s += $v;
    }
    unset($v);
    return $s;
}

function sum_by_val(array $a): int {
    $s = 0;
    foreach ($a as $key => $v) {
        $s += $v;
    }
    return $s;
}

$a = [];
for ($i = 0; $i < 200000; $i++) {
    $a[$i] = $i % 7;
}

$t0 = microtime(true);
$rv = sum_by_val($a);
$t1 = microtime(true);
$rr = sum_by_ref($a);
$t2 = microtime(true);

printf("by-value sum=%d ms=%.3f\n", $rv, ($t1 - $t0) * 1000);
printf("by-ref   sum=%d ms=%.3f\n", $rr, ($t2 - $t1) * 1000);
printf("ratio by-ref/by-value = %.2f\n", ($t2 - $t1) / ($t1 - $t0));
