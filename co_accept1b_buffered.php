<?php
// 验收组1b：生产者-消费者，cap=8 有缓冲，3 生产者 × 100 + 2 消费者交叉
// 验证：元素总数=300、全域无丢失无重复（恰好覆盖 0..299）、per-producer 子序列单调
function producer($ch, $base, $n) {
    for ($i = 0; $i < $n; $i++) {
        $ch->send($base + $i); // 满则让出
    }
}
function consumer($ch, $res, $per) {
    $last = [];
    $count = 0;
    $order_ok = true;
    $vals = [];
    while (true) {
        $v = $ch->recv();
        if ($v === null) break;
        $seq = $v % $per;
        $pid = ($v - $seq) / $per;
        if (isset($last[$pid]) && $seq <= $last[$pid]) $order_ok = false;
        $last[$pid] = $seq;
        $vals[] = $v;
        $count++;
    }
    $res->send([$count, $order_ok, $vals]);
}
$ch = new Channel(8);
$res = new Channel(3);
$cids = [];
for ($c = 0; $c < 2; $c++) {
    $cids[] = go('consumer', $ch, $res, 100);
}
$pids = [];
for ($p = 0; $p < 3; $p++) {
    $pids[] = go('producer', $ch, $p * 100, 100);
}
foreach ($pids as $id) {
    go_join($id);
}
$ch->close();
$total = 0;
$order_ok = true;
$all = [];
for ($c = 0; $c < 2; $c++) {
    $r = $res->recv();
    $total += $r[0];
    if (!$r[1]) $order_ok = false;
    foreach ($r[2] as $v) {
        $all[] = $v;
    }
}
sort($all);
$cover_ok = count($all) === 300;
if ($cover_ok) {
    for ($i = 0; $i < 300; $i++) {
        if ($all[$i] !== $i) {
            $cover_ok = false;
            break;
        }
    }
}
$ok = $total === 300 && $order_ok && $cover_ok;
echo $ok ? "G1B PASS total=$total order_ok=1 cover_ok=1\n"
         : "G1B FAIL total=$total order_ok=" . ($order_ok ? 1 : 0) . " cover_ok=" . ($cover_ok ? 1 : 0) . "\n";
