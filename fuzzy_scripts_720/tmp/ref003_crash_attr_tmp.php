<?php
// 永久探针：AOT-REF-003 崩溃归因 —— 崩在「迭代器自身推进/释放」还是「搬迁后对槽的再读取」？
// W1 对照：持引用 foreach，追加目标是另一个数组（被遍历容器不搬迁）⇒ 必须不崩溃。
// W2 判据：持引用 foreach，首轮追加后立即 break ⇒ 若仍崩溃 ⇒ 崩在迭代器推进/释放自身；
//         若不崩溃 ⇒ 崩在搬迁之后对 key/引用槽的再次读取。
function mkw(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

$b = mkw(5);
$x = [];
$w1 = 0;
foreach ($b as $key => &$ref) {
    $w1++;
    if ($w1 === 1) {
        for ($j = 0; $j < 200; $j++) {
            $x['g' . $j] = $j;
        }
    }
    if ($w1 > 400) {
        break;
    }
}
unset($ref);
echo "W1 grow-other-array visited={$w1} count_b=" . count($b) . " count_x=" . count($x) . "\n";

$a = mkw(5);
$w2 = 0;
foreach ($a as $key => &$ref) {
    $w2++;
    if ($w2 === 1) {
        for ($j = 0; $j < 200; $j++) {
            $a['g' . $j] = $j;
        }
        break;
    }
}
unset($ref);
echo "W2 grow-then-break visited={$w2} count=" . count($a) . " g199=" . ($a['g199'] ?? 'none') . "\n";

$y = mkw(5);
$w3 = 0;
foreach ($y as $key => &$ref) {
    $w3++;
    if ($w3 === 1) {
        for ($j = 0; $j < 200; $j++) {
            $y['g' . $j] = $j;
        }
        continue;
    }
    if ($w3 > 400) {
        break;
    }
}
unset($ref);
echo "W3 grow-then-continue visited={$w3} count=" . count($y) . " g199=" . ($y['g199'] ?? 'none') . "\n";
