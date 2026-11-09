<?php
// 最小复现：while+break 循环体内尾部「短路条件 if 单语句赋值」后的数组写
function f($ch) {
    $last = [];
    $ok = true;
    while (true) {
        $v = $ch->recv();
        if ($v === null) break;
        if (isset($last[$v]) && $v <= $last[$v]) $ok = false;
        $last[$v] = $v;
    }
    return $ok;
}
$ch = new Channel(0);
$ch->close();
echo f($ch) ? "OK\n" : "NG\n";
