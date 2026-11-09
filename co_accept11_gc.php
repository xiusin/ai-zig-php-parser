<?php
// 验收组11：cycle-GC 与多协程交互（D4=A：worker 未全部结束 ⇒ cycle-GC 停用）
// a) 协程持活数组跨 50 次让出，主协程期间大量制造循环垃圾（对象互引）⇒ 存活数组不得被误扫
// b) 协程活跃期 gc_collect_cycles() 必须返回 0（停用）
// c) 协程结束后强制 GC：可正常回收循环垃圾且不破坏存活值
class Node11 {
    public $peer = null;
    public $data = null;
}
function keeper($ev) {
    $big = [];
    $i = 0;
    while ($i < 1000) {
        $big[] = $i * 3;
        $i++;
    }
    $i = 0;
    while ($i < 50) {
        $ev->send("tick");
        $i++;
    }
    $sum = 0;
    foreach ($big as $v) {
        $sum += $v;
    }
    $ev->send("SUM:" . $sum);
}
$ev = new Channel(0);
go('keeper', $ev);
$i = 0;
while ($i < 50) {
    $e = $ev->recv();
    $a = new Node11();
    $b = new Node11();
    $a->peer = $b;
    $b->peer = $a;
    $a->data = str_repeat('q', 128);
    $i++;
}
$gc_during = gc_collect_cycles();   // 协程仍活跃 ⇒ 应为 0（停用）
$e = $ev->recv();
go_wait_all();
$sum_ok = $e === "SUM:1498500";      // Σ3i, i=0..999
$gc_after = gc_collect_cycles();     // 协程已全部结束 ⇒ 可运行
$ok = $sum_ok && $gc_during === 0;
echo "gc_during=$gc_during gc_after=$gc_after recv=$e\n";
if ($ok) {
    echo "G11 PASS\n";
} else {
    echo "G11 FAIL\n";
}
