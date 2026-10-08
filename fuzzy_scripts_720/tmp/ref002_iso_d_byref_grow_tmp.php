<?php
// 隔离探针 D：foreach **按引用**（&$ref）遍历期间扩容 —— AOT-REF-002 R-1a 的真实触发路径。
// 判据：$ref = 777 之后 $a['k0'] 必须为 777（写回容器），即使中途插入 40 个新键。
// 若 k0 仍为 0，则 php_array_iter_value_ref 交出的裸 mixed 槽指针确实悬垂（UAF 写）。
$a = [];
for ($i = 0; $i < 20; $i++) {
    $a['k' . $i] = $i;
}
$hits = 0;
foreach ($a as $key => &$ref) {
    $hits++;
    if ($hits === 1) {
        $ref = 777;
        for ($j = 0; $j < 40; $j++) {
            $a['g' . $j] = -$j;
        }
    }
}
echo "byref-grow hits=", $hits, " k0=", $a['k0'], " count=", count($a), "\n";
