<?php
// 隔离探针 B：foreach 按值遍历期间向同一数组追加元素，迭代集合是否含新增元素（无 break、无引用）。
// 判据：hits 为迭代次数，count 为最终元素数。PHP 按值 foreach 遍历迭代开始时的元素集合。
$a = [];
for ($i = 0; $i < 20; $i++) {
    $a['k' . $i] = $i;
}
$hits = 0;
$first = true;
foreach ($a as $key => $v) {
    $hits++;
    if ($first) {
        $first = false;
        for ($j = 0; $j < 40; $j++) {
            $a['g' . $j] = -$j;
        }
    }
}
echo "snapshot hits=", $hits, " count=", count($a), "\n";
