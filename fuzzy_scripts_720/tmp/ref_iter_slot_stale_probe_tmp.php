<?php
// 永久探针：迭代期引用仍交出「容器裸槽指针」的两条同源路径（AOT-REF-002 R-1 / R-5）。
// 与 AOT-REF-001 D2 同一机理，但产出点不同：
//   php_array_iter_value_ref（runtime_lib_template.zig:7984）返回 Value.initRef(mixed 槽指针)；
//   php_array_walk（:25562）用 Value.initRef(entry.value_ptr) 构造回调首参；
//   ArrayIterator.current（:7763）缓存 Elements.Entry（含 key_ptr/value_ptr），迭代期间数组增长即悬垂。
// 判据：引用写入必须写回容器，且容器在增长后仍可读回同一值。
$a = [];
for ($i = 0; $i < 100; $i++) {
    $a['k' . $i] = $i;
}
$hits = 0;
foreach ($a as $key => $ref) {
    $hits++;
    if ($hits === 1) {
        for ($j = 0; $j < 200; $j++) {
            $a['g' . $j] = -$j;
        }
        $a['k7'] = 555;
    }
    if ($hits > 3) {
        break;
    }
}
echo "foreach-value-scan hits=", $hits, " k7=", $a['k7'], " count=", count($a), "\n";

$b = [];
for ($i = 0; $i < 60; $i++) {
    $b['b' . $i] = $i;
}
$mutated = 0;
array_walk($b, function (&$val, $key) use (&$mutated, &$b) {
    if ($mutated === 0) {
        for ($j = 0; $j < 120; $j++) {
            $b['w' . $j] = $j;
        }
    }
    $mutated++;
    if ($mutated <= 2) {
        $val = 4242;
    }
});
echo "array_walk visited=", $mutated, " b0=", $b['b0'], " count=", count($b), "\n";
