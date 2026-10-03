<?php
// 永久探针：AOT-CODEGEN-005 RC-4 取证最小单形（仅 Y1）—— 便于 --dump-zig-path / --dump-ir 阅读。
// 判据：visited 必须为 1（break 生效）；AOT 实测曾为 5 且循环后 echo 打印两次。
function mkr4m(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

$b1 = mkr4m(5);
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
echo "Y1MIN visited={$w1} count_x=" . count($x1) . "\n";
