<?php
// 永久探针：对象属性按引用取用后，properties 地图扩容（rehash）是否使既有引用失效。
// 机理：php_object_get_ref 返回 Value.initRef(entry_ptr)，entry_ptr 指向 StringHashMap 的值槽；
//       之后再写入新属性名可能触发 put → 底层桶数组 realloc，槽地址迁移 ⇒ 旧引用悬垂。
// 判据①：$r 是 &$c->a 的引用，写 $r 后 $c->a 必须为 'through-ref'（引用未被 rehash 打断）。
// 判据②：中途插入的 64 个属性读回求和 = 6048（rehash 后所有槽仍完好）。
// 判据③：写 $c->a = 'plain-set' 后 $r 同步变 'plain-set'（PHP 引用共享同一值，非快照）。
// 说明：使用 stdClass 以避开 PHP 8.3+ 动态属性 Deprecated 噪声（判据本身不受影响）。
$c = new stdClass;
$c->a = 'first';

$r = &$c->a;

for ($i = 0; $i < 64; $i++) {
    $c->{'p' . $i} = $i * 3;
}

$r = 'through-ref';
echo $c->a, "\n";

$sum = 0;
for ($i = 0; $i < 64; $i++) {
    $sum += $c->{'p' . $i};
}
echo "sum=", $sum, "\n";

$c->a = 'plain-set';
echo "after-plain=", $c->a, "|ref=", $r, "\n";
