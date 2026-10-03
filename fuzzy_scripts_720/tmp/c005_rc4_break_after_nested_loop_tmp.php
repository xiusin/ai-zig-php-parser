<?php
// 永久探针：AOT-CODEGEN-005 RC-4 候选取证 —— 「同一 if 臂内、内层循环之后紧跟的裸 break」是否发射。
// 与 ref003_crash_attr_tmp.php 的 W2 同形，但把追加目标改为**另一个数组**，
// 以剥离 AOT-REF-003 的 P0 崩溃（容器搬迁）干扰，只留发射侧变量。
// 判据：每形 visited 必须等于 PHP 真值（break 生效时应停在 1）。

function mkr4(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

// Y1 foreach 持引用 + 臂内 for 之后 break
$b1 = mkr4(5);
$x1 = [];
$w1 = 0;
foreach ($b1 as $key => &$ref) {
    $w1++;
    if ($w1 === 1) {
        for ($j = 0; $j < 4; $j++) {
            $x1['g' . $j] = $j;
        }
        break;
    }
}
unset($ref);
echo "Y1 byref visited={$w1} count_x=" . count($x1) . " key=" . (string)$key . "\n";

// Y2 foreach 按值 + 臂内 for 之后 break
$b2 = mkr4(5);
$x2 = [];
$w2 = 0;
foreach ($b2 as $key => $val) {
    $w2++;
    if ($w2 === 1) {
        for ($j = 0; $j < 4; $j++) {
            $x2['g' . $j] = $j;
        }
        break;
    }
}
echo "Y2 byval visited={$w2} count_x=" . count($x2) . "\n";

// Y3 外层 for + 臂内 for 之后 break
$w3 = 0;
$x3 = [];
for ($i = 0; $i < 5; $i++) {
    $w3++;
    if ($w3 === 1) {
        for ($j = 0; $j < 4; $j++) {
            $x3['g' . $j] = $j;
        }
        break;
    }
}
echo "Y3 outer-for visited={$w3} count_x=" . count($x3) . "\n";

// Y4 外层 while + 臂内 for 之后 break
$w4 = 0;
$x4 = [];
while ($w4 < 5) {
    $w4++;
    if ($w4 === 1) {
        for ($j = 0; $j < 4; $j++) {
            $x4['g' . $j] = $j;
        }
        break;
    }
}
echo "Y4 outer-while visited={$w4} count_x=" . count($x4) . "\n";

// Y5 臂内 for 之后 break + 后置兄弟语句（验证 break 若被误当「臂尾直落」会不会连带丢后置语句）
$b5 = mkr4(5);
$x5 = [];
$w5 = 0;
$tail = "none";
foreach ($b5 as $key => $val) {
    $w5++;
    if ($w5 === 1) {
        for ($j = 0; $j < 4; $j++) {
            $x5['g' . $j] = $j;
        }
        break;
    }
    $tail = "seen{$w5}";
}
echo "Y5 visited={$w5} tail={$tail} count_x=" . count($x5) . "\n";

// Y6 臂内 for 之后 continue（同族另一分支）
$b6 = mkr4(5);
$x6 = [];
$w6 = 0;
$hit = 0;
foreach ($b6 as $key => $val) {
    $w6++;
    if ($w6 < 3) {
        for ($j = 0; $j < 2; $j++) {
            $x6[$w6 . "_" . $j] = $j;
        }
        continue;
    }
    $hit++;
}
echo "Y6 visited={$w6} hit={$hit} count_x=" . count($x6) . "\n";
