<?php
// 隔离探针 C：array_walk 回调首参按引用（&$val）写回，**无扩容**。
// 判据：x/y 必须变成 4242（PHP 语义：array_walk 的 value 参数是 by-ref）。
// 若仍为 1|2，则失效点在「闭包形参引用绑定」，与裸槽指针悬垂无关，属另一类缺陷。
$b = [];
$b['x'] = 1;
$b['y'] = 2;
array_walk($b, function (&$val, $key) {
    $val = 4242;
});
echo "walk-nogrow x=", $b['x'], " y=", $b['y'], " count=", count($b), "\n";
