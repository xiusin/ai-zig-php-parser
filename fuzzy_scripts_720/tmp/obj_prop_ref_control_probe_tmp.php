<?php
// 永久探针：对象属性引用（$r = &$c->a）的三个隔离场景，用于区分「rehash 使旧 entry_ptr 悬垂」
// 与「属性取引用路径本身未实现引用语义」。
// 场景1（无扩容）：取引用后直接写引用 ⇒ PHP 两边同值 'through-ref'。
// 场景2（取引用后插 1 个属性）：单点插入不跨越扩容阈值 ⇒ 预期仍同步。
// 场景3（先插满 64 个再取引用）：引用在稳定地图上创建，写入必须同步 ⇒
//        若场景3 正常而「取引用后再扩容」异常，则缺陷定位为扩容搬迁槽地址。
$c1 = new stdClass;
$c1->a = 'first';
$r1 = &$c1->a;
$r1 = 'through-ref';
echo "case1=", $c1->a, "|", $r1, "\n";

$c2 = new stdClass;
$c2->b = 'x';
$r2 = &$c2->b;
$c2->extra = 'q';
$r2 = 'after-one-insert';
echo "case2=", $c2->b, "|", $r2, "\n";

$c3 = new stdClass;
for ($i = 0; $i < 64; $i++) {
    $c3->{'p' . $i} = $i * 3;
}
$c3->a = 'first';
$r3 = &$c3->a;
$r3 = 'late-ref';
echo "case3=", $c3->a, "|", $r3, "\n";
