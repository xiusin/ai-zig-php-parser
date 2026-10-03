<?php
// 永久探针：AOT-CODEGEN-005 RC-5 取证族 —— 臂尾裸 break/continue 与「真实 merge 块（if 之后有兄弟语句）」的组合。
// 每个形状独立成段，输出带标签，便于逐形比对 PHP 真值与 AOT 产物，不改编译器即可定位丢失的必要条件。
// 判据：所有标签行 PHP 与 AOT 必须逐字节一致。

function rc5mkr(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

// F-A：臂尾 continue + 无兄弟语句（merge 即外层延续块）——RC-4 已闭环的子形，作正对照。
$b = rc5mkr(4);
$w = 0;
$hit = 0;
$x = [];
foreach ($b as $key => $val) {
    $w++;
    if ($w < 3) {
        for ($j = 0; $j < 2; $j++) {
            $x[$w . "_" . $j] = $j;
        }
        continue;
    }
}
echo "F-A visited={$w} hit={$hit} count_x=" . count($x) . "\n";

// F-C：有兄弟语句（真实 if_merge_ 块）但臂尾【无】裸 continue —— 判定裸折边是否为必要条件。
$b = rc5mkr(4);
$w = 0;
$hit = 0;
$x = [];
foreach ($b as $key => $val) {
    $w++;
    if ($w < 3) {
        for ($j = 0; $j < 2; $j++) {
            $x[$w . "_" . $j] = $j;
        }
    }
    $hit++;
}
echo "F-C visited={$w} hit={$hit} count_x=" . count($x) . "\n";

// F-B（=Y6MIN）：臂尾 continue + 兄弟语句 $hit++ —— RC-5 主形。
$b = rc5mkr(4);
$w = 0;
$hit = 0;
$x = [];
foreach ($b as $key => $val) {
    $w++;
    if ($w < 3) {
        for ($j = 0; $j < 2; $j++) {
            $x[$w . "_" . $j] = $j;
        }
        continue;
    }
    $hit++;
}
echo "F-B visited={$w} hit={$hit} count_x=" . count($x) . "\n";

// F-D：同 F-B，但兄弟语句写成显式 else 臂（merge 与 else 目标分离）——判定 else_is_coalesce 归属。
$b = rc5mkr(4);
$w = 0;
$hit = 0;
$x = [];
foreach ($b as $key => $val) {
    $w++;
    if ($w < 3) {
        for ($j = 0; $j < 2; $j++) {
            $x[$w . "_" . $j] = $j;
        }
        continue;
    } else {
        $hit++;
    }
}
echo "F-D visited={$w} hit={$hit} count_x=" . count($x) . "\n";

// F-E：同 F-B，兄弟语句改为纯副作用（echo），排除「仅 PHI 目标变量丢失」的解释。
$b = rc5mkr(4);
$w = 0;
$x = [];
foreach ($b as $key => $val) {
    $w++;
    if ($w < 3) {
        for ($j = 0; $j < 2; $j++) {
            $x[$w . "_" . $j] = $j;
        }
        continue;
    }
    echo "E{$w} ";
}
echo "\nF-E count_x=" . count($x) . "\n";

// F-F：同 F-B，内层循环换成 while —— 判定丢失是否 for 专属。
$b = rc5mkr(4);
$w = 0;
$hit = 0;
$x = [];
foreach ($b as $key => $val) {
    $w++;
    if ($w < 3) {
        $k = 0;
        while ($k < 2) {
            $x[$w . "_" . $k] = $k;
            $k++;
        }
        continue;
    }
    $hit++;
}
echo "F-F visited={$w} hit={$hit} count_x=" . count($x) . "\n";

// F-G：同 F-B，臂尾换成 break —— 判定 break 形是否同因。
$b = rc5mkr(4);
$w = 0;
$hit = 0;
$x = [];
foreach ($b as $key => $val) {
    $w++;
    if ($w < 3) {
        for ($j = 0; $j < 2; $j++) {
            $x[$w . "_" . $j] = $j;
        }
        break;
    }
    $hit++;
}
echo "F-G visited={$w} hit={$hit} count_x=" . count($x) . "\n";

// F-H：同 F-B，外层换成 for —— 判定丢失是否 foreach 专属。
$hit = 0;
$x = [];
for ($i = 0; $i < 4; $i++) {
    $w = $i;
    if ($w < 3) {
        for ($j = 0; $j < 2; $j++) {
            $x[$i . "_" . $j] = $j;
        }
        continue;
    }
    $hit++;
}
echo "F-H hit={$hit} count_x=" . count($x) . "\n";
