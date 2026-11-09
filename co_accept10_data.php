<?php
// 验收组10：数据面正确性——channel 传数组/对象，COW 隔离与 RC（不泄漏不早释）
// a) 数组 COW：send 后发送方修改不影响接收方快照；接收方修改不影响发送方
// b) 对象按 PHP 句柄语义共享（同一对象，修改可见）
// c) RC 压测：20 万次跨协程传「数组+字符串」并丢弃，值正确且 RSS 有界（由 /usr/bin/time -l 观测）
class Box {
    public $v = 1;
}
function consumer($ch, $n, $done) {
    $sum = 0;
    $i = 0;
    while ($i < $n) {
        $item = $ch->recv();
        if ($item === null) {
            break;
        }
        $sum += $item['k'];
        $i++;
    }
    $done->send($sum);
}
$ch = new Channel(1);
$a = [1, 2, 3];
$ch->send($a);
$a[] = 99;
$r = $ch->recv();
$cow_send_ok = count($r) === 3;
if (count($r) === 3) {
    if ($r[2] !== 3) {
        $cow_send_ok = false;
    }
}
$r[] = 77;
$cow_recv_ok = count($a) === 4;
if (count($a) === 4) {
    if ($a[3] !== 99) {
        $cow_recv_ok = false;
    }
}
$b = new Box();
$ch->send($b);
$b->v = 42;
$rb = $ch->recv();
$obj_ok = $rb === $b;
if ($obj_ok) {
    if ($rb->v !== 42) {
        $obj_ok = false;
    }
}
// c) RC 压测
$N = 200000;
$work = new Channel(64);
$done = new Channel(1);
go('consumer', $work, $N, $done);
$i = 0;
while ($i < $N) {
    $payload = ['k' => $i, 's' => str_repeat('x', 64)];
    $work->send($payload);
    $i++;
}
$work->close();
$sum = $done->recv();
$expect = $N * ($N - 1) / 2;
$rc_ok = $sum === $expect;
$ok = $cow_send_ok && $cow_recv_ok && $obj_ok && $rc_ok;
echo "cow_send=" . ($cow_send_ok ? 1 : 0) . " cow_recv=" . ($cow_recv_ok ? 1 : 0) . " obj=" . ($obj_ok ? 1 : 0) . " rc_sum=$sum\n";
echo $ok ? "G10 PASS\n" : "G10 FAIL\n";
