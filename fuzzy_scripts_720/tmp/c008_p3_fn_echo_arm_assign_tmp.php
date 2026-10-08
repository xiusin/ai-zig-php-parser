<?php
// 永久探针 C008-P3（红形）：函数作用域，无 else 链 + echo 结尾臂 + 链后「赋值 + return」
// 实测：链后两条语句整体零发射，函数返回隐式 null ⇒ json_encode(null) = "null"，rc=0。
// 证明丢失范围是「链后全部语句」，不限于 echo。
function fD(array $req): array {
    if (empty($req['d'])) {
        echo "arm-empty\n";
    } elseif (!isset($req['d'])) {
        echo "arm-noset\n";
    }
    $req['tail'] = 1;
    return $req;
}
echo "D=" . json_encode(fD([])) . "\n";
echo "END\n";
