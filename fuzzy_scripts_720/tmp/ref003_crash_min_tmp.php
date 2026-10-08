<?php
// 永久探针：AOT-REF-003 最小崩溃复现 —— 持引用 foreach 迭代期间向同一容器追加（强制桶搬迁）。
// 与 ref003_liveset_bisect_tmp.php 的 F3 同形，此处单独成文件以便定位崩溃点与抓取 stderr。
// 判据：AOT 不得崩溃（PHP 真值 visited=205 count=205）。
function mkb(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

$a3 = mkb(5);
$v3 = 0;
fwrite(STDERR, "[probe] before loop\n");
foreach ($a3 as $key => &$ref) {
    $v3++;
    if ($v3 === 1) {
        for ($j = 0; $j < 200; $j++) {
            $a3['g' . $j] = $j;
        }
        fwrite(STDERR, "[probe] after grow, count=" . count($a3) . "\n");
    }
    if ($v3 > 400) {
        break;
    }
}
unset($ref);
fwrite(STDERR, "[probe] after loop\n");
echo "C1 byref-grow visited={$v3} count=" . count($a3) . " g199=" . ($a3['g199'] ?? 'none') . "\n";
