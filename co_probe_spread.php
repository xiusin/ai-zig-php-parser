<?php
// 临时探针：普通语句的 ... 展开调用（作为 go 语句形 spread 的对照）
function sum3($a, $b, $c) {
    echo "sum=" . ($a + $b + $c) . "\n";
}
$args = [7, 8];
sum3(1, ...$args);
$f = 'sum3';
$f(2, ...$args);
echo "DONE\n";
