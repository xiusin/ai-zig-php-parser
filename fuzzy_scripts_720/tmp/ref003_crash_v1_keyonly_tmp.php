<?php
// 永久探针：AOT-REF-003 崩溃触发点定位 —— 只读键、完全不读值引用槽。
// 判据：与 ref003_crash_min_tmp.php（读 &$ref）对照，分离「键读取」与「引用槽读取」哪一侧野读。
function mkv1(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

$a = mkv1(5);
$v = 0;
$keys_seen = "";
foreach ($a as $key => &$ref) {
    $v++;
    if ($v === 1) {
        for ($j = 0; $j < 200; $j++) {
            $a['g' . $j] = $j;
        }
    }
    $keys_seen .= (string)$key . ",";
    if ($v > 400) {
        break;
    }
}
unset($ref);
echo "V1 key-only visited={$v} count=" . count($a) . " keys=" . substr($keys_seen, 0, 40) . "\n";
