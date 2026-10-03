<?php
// 隔离探针 F：foreach 体内「先嵌套 for 扩容，再单语句 if + break」——
// 与已通过的 ref002_iso_a（无扩容）/ ref002_iso_b（无 break）唯一区别是两者共存。
// 判据：hits 必须停在 4；若跑到原集合长度（20），则 break 分支在该形状下丢失发射（非引用类缺陷）。
$a = [];
for ($i = 0; $i < 20; $i++) {
    $a['k' . $i] = $i;
}
$hits = 0;
foreach ($a as $key => $value) {
    $hits++;
    if ($hits === 1) {
        for ($j = 0; $j < 40; $j++) {
            $a['g' . $j] = -$j;
        }
    }
    if ($hits > 3) {
        break;
    }
}
echo "F hits=", $hits, " count=", count($a), "\n";
