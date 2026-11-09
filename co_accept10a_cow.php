<?php
// 验收组10a：channel 传数组/对象的 COW 隔离与对象句柄语义
// a) 数组：send 后发送方修改不影响接收方快照；接收方修改不影响发送方
// b) 对象：PHP 句柄语义共享（同一对象，修改可见）
class Box10 {
    public $v = 1;
}
$ch = new Channel(1);
$a = [1, 2, 3];
$ch->send($a);
$a[] = 99;                 // 发送后改发送方
$r = $ch->recv();          // 接收方快照
$cow_send_ok = count($r) === 3;
$r[] = 77;                 // 接收方改副本
$cow_recv_ok = count($a) === 4;

$b = new Box10();
$ch->send($b);
$b->v = 42;
$rb = $ch->recv();
$obj_ok = $rb === $b;

$ok = $cow_send_ok && $cow_recv_ok && $obj_ok;
echo "cow_send=" . ($cow_send_ok ? 1 : 0) . " cow_recv=" . ($cow_recv_ok ? 1 : 0) . " obj=" . ($obj_ok ? 1 : 0) . "\n";
if ($ok) {
    echo "G10A PASS\n";
} else {
    echo "G10A FAIL\n";
}
