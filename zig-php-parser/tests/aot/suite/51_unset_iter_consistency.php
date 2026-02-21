<?php
$arr = [1, 2, 3, 4, 5];
$sum = 0;
for ($i = 0; $i < 5; $i++) {
    if ($i % 2 == 0) {
        unset($arr[$i]);
    }
}
$cnt = count($arr);
foreach ($arr as $v) {
    $sum += $v;
}
echo "UnsetIter: $cnt,$sum (expect 2,6)\n";
