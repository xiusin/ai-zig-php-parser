<?php
// 永久探针：AOT-REF-003 因子 bisect 第二段（F4–F7）。
// 与 ref003_liveset_bisect_tmp.php 同判据，单独成文件是因为该文件的 F3 会崩溃中断后续因子。
function mkc(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

// F4 持引用 foreach + 追加后写引用（判据：写回落在哪个容器）—— 大量追加，可能崩溃
$a4 = mkc(5);
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

// F4b 与 F4 同形但只追加 3 键（小量，不搬迁）：分离「搬迁崩溃」与「集合语义」
$a4b = mkc(5);
$v4b = 0;
foreach ($a4b as $key => &$ref) {
    $v4b++;
    if ($v4b === 1) {
        $a4b['n1'] = 111;
        $a4b['n2'] = 222;
        $a4b['n3'] = 333;
        $ref = 4242;
    }
    if ($v4b > 20) {
        break;
    }
}
unset($ref);
echo "F4b byref-small-write visited={$v4b} count=" . count($a4b) . " k0=" . $a4b['k0'] . "\n";

// F5 持引用 foreach 正常结束（无追加）后残留引用别名写入
$a5 = mkc(4);
foreach ($a5 as $key => &$ref) {
    $ref = $ref + 1;
}
$a5['x1'] = 999;
echo "F5 dangling-ref-after-loop last=" . $ref . " k3=" . $a5['k3'] . " count=" . count($a5) . "\n";

// F6 array_walk + 首轮追加 3 键（小量）
$a6 = mkc(5);
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

// F7 array_walk + 首轮追加 60 键并写 &$val
$a7 = mkc(5);
$w7 = 0;
array_walk($a7, function (&$val, $key) use (&$a7, &$w7) {
    $w7++;
    if ($w7 === 1) {
        for ($j = 0; $j < 60; $j++) {
            $a7['g' . $j] = $j;
        }
        $val = 5566;
    }
    if ($w7 > 200) {
        return;
    }
});
echo "F7 walk-grow visited={$w7} count=" . count($a7) . " k0=" . $a7['k0'] . " g59=" . ($a7['g59'] ?? 'none') . "\n";
