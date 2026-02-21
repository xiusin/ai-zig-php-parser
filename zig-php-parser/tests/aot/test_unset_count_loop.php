<?php
$arr = [1, 2, 3, 4];
unset($arr[1]);
$cnt = count($arr);
$sum = 0;
foreach ($arr as $v) {
    $sum += $v;
}
echo "UnsetCnt: $cnt,$sum (expect 3,8)\n";
