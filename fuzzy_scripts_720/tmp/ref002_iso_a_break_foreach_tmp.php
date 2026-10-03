<?php
// 隔离探针 A：foreach 体内单语句 if + break 是否生效（无扩容、无引用）。
// 判据：hits 必须停在 4。若输出 20，则 break 分支发射丢失，与引用无关。
$a = [];
for ($i = 0; $i < 20; $i++) {
    $a['k' . $i] = $i;
}
$hits = 0;
foreach ($a as $key => $value) {
    $hits++;
    if ($hits > 3) {
        break;
    }
}
echo "break-only hits=", $hits, " count=", count($a), "\n";
