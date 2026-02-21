<?php
$arr = [1, 2, 3, 4];
$flag = 0;
try {
    $flag = 1;
    unset($arr[2]);
} finally {
    $flag = $flag + 10;
}
$cnt = count($arr);
$sum = 0;
foreach ($arr as $v) {
    $sum += $v;
}
echo "TryFinally: $flag,$cnt,$sum (expect 11,3,7)\n";
