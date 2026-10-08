<?php
// 永久探针：Ref 单元指向容器槽（Value.initRef(entry_ptr)）在容器扩容（rehash 搬迁桶数组）后是否悬垂。
// 与 obj_prop_ref_rehash_probe_tmp.php 同一机理，但走「已实现且看似正常」的数组引用路径：
// php_array_get_ref（runtime_lib_template.zig:4795）与 php_object_get_ref（:19101）都返回
// Value.initRef(容器槽指针)。若取引用之后容器继续增长，槽地址迁移，旧 Ref 即悬垂。
// 判据：$r = 999 之后 $a['k7'] 必须同步为 999（PHP 语义）。
// 附加判据：扩容插入的 150 个元素读回求和正确 ⇒ 证明容器本身搬迁无损坏，差异只可能来自旧 Ref。
$a = [];
for ($i = 0; $i < 50; $i++) {
    $a['k' . $i] = $i;
}

$r = &$a['k7'];

for ($i = 0; $i < 150; $i++) {
    $a['x' . $i] = $i * 2;
}

$r = 999;
echo "k7=", $a['k7'], "|ref=", $r, "\n";

$sum = 0;
for ($i = 0; $i < 150; $i++) {
    $sum += $a['x' . $i];
}
echo "sum=", $sum, "|n=", count($a), "\n";

// 整数键版本：packed → hashed 转换同样会搬迁存储
$b = [10, 20, 30];
$rb = &$b[1];
for ($i = 0; $i < 200; $i++) {
    $b['s' . $i] = $i;
}
$rb = 777;
echo "b1=", $b[1], "|ref=", $rb, "\n";
