<?php
$arr = [1, 2, 3, 4, 5];
$sum = 0;
foreach ($arr as $k => $v) {
    if ($k == 1) {
        continue;
    }
    if ($v == 4) {
        break;
    }
    $sum += $v + $k;
}
echo "ForeachCtrl: $sum (expect 6)\n";
