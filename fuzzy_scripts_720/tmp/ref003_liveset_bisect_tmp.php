<?php
// 永久探针：AOT-REF-003 因子 bisect —— 「持引用迭代期间的元素集合语义」与「容器换代」分离。
// 每个因子独立数组、独立输出行；判据 = 访问轮数 visited、容器 count、被写元素读回值。
function lsa(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

// F1 对照：按值 foreach + 首轮追加 3 键（小量，不依赖搬迁）
$a1 = lsa(5);
$v1 = 0;
foreach ($a1 as $key => $value) {
    $v1++;
    if ($v1 === 1) {
        $a1['n1'] = 111;
        $a1['n2'] = 222;
        $a1['n3'] = 333;
    }
    if ($v1 > 20) {
        break;
    }
}
echo "F1 byvalue-small visited={$v1} count=" . count($a1) . " n1=" . ($a1['n1'] ?? 'none') . "\n";

// F2 持引用 foreach + 首轮追加 3 键（小量：若仍不访问新键 ⇒ 纯集合语义问题，与搬迁无关）
$a2 = lsa(5);
$v2 = 0;
foreach ($a2 as $key => &$ref) {
    $v2++;
    if ($v2 === 1) {
        $a2['n1'] = 111;
        $a2['n2'] = 222;
        $a2['n3'] = 333;
    }
    if ($v2 > 20) {
        break;
    }
}
unset($ref);
echo "F2 byref-small visited={$v2} count=" . count($a2) . " n1=" . ($a2['n1'] ?? 'none') . "\n";

// F3 持引用 foreach + 首轮追加 200 键（大量：强制桶搬迁）
$a3 = lsa(5);
$v3 = 0;
foreach ($a3 as $key => &$ref) {
    $v3++;
    if ($v3 === 1) {
        for ($j = 0; $j < 200; $j++) {
            $a3['g' . $j] = $j;
        }
    }
    if ($v3 > 400) {
        break;
    }
}
unset($ref);
echo "F3 byref-grow visited={$v3} count=" . count($a3) . " g199=" . ($a3['g199'] ?? 'none') . "\n";

// F4 持引用 foreach + 追加后写引用（判据：写回落在哪个容器）
$a4 = lsa(5);
$v4 = 0;
foreach ($a4 as $key => &$ref) {
    $v4++;
    if ($v4 === 1) {
        for ($j = 0; $j < 60; $j++) {
            $a4['g' . $j] = $j;
        }
        $ref = 4242;
    }
    if ($v4 > 200) {
        break;
    }
}
unset($ref);
echo "F4 byref-grow-write visited={$v4} count=" . count($a4) . " k0=" . $a4['k0'] . "\n";

// F5 持引用 foreach + 迭代结束后残留引用别名写入（PHP 经典语义：最后一个 $ref 仍绑定 $a[end]）
$a5 = lsa(4);
foreach ($a5 as $key => &$ref) {
    $ref = $ref + 1;
}
$a5['x1'] = 999;
echo "F5 dangling-ref-after-loop last=" . $ref . " k3=" . $a5['k3'] . " count=" . count($a5) . "\n";

// F6 array_walk + 首轮追加 3 键（小量）
$a6 = lsa(5);
$w6 = 0;
array_walk($a6, function (&$val, $key) use (&$a6, &$w6) {
    $w6++;
    if ($w6 === 1) {
        $a6['n1'] = 111;
        $a6['n2'] = 222;
        $a6['n3'] = 333;
    }
    if ($w6 > 20) {
        return;
    }
});
echo "F6 walk-small visited={$w6} count=" . count($a6) . " n1=" . ($a6['n1'] ?? 'none') . "\n";

// F7 array_walk + 首轮追加 200 键（大量），并写 &$val
$a7 = lsa(5);
$w7 = 0;
array_walk($a7, function (&$val, $key) use (&$a7, &$w7) {
    $w7++;
    if ($w7 === 1) {
        for ($j = 0; $j < 200; $j++) {
            $a7['g' . $j] = $j;
        }
        $val = 5566;
    }
    if ($w7 > 400) {
        return;
    }
});
echo "F7 walk-grow visited={$w7} count=" . count($a7) . " k0=" . $a7['k0'] . " g199=" . ($a7['g199'] ?? 'none') . "\n";
