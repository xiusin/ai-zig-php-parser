<?php
$arr = [1, 2, 3];
foreach ($arr as &$v) {
    $v = $v + 10;
}
unset($v);
$sum = 0;
foreach ($arr as $x) {
    $sum += $x;
}
echo "ForeachRef: $sum (expect 36)\n";
