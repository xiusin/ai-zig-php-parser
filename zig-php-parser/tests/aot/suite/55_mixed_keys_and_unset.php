<?php
$arr = [];
$arr[0] = 1;
$arr[1] = 2;
$arr["a"] = 3;
$arr["b"] = 4;
unset($arr[1]);
unset($arr["a"]);
$cnt = count($arr);
$sum = 0;
foreach ($arr as $v) {
    $sum += $v;
}
echo "MixKeyUnset: $cnt,$sum (expect 2,5)\n";
