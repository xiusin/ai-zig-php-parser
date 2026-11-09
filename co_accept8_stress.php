<?php
// 验收组8：压测——1 万协程 spawn + join
// 验证：全部完成、结果正确（Σ0..9999）、耗时、虚拟内存/RSS（由 /usr/bin/time -l 观测）、进程退净 rc=0
$N = 10000;
function echo_i($res, $i) {
    $res->send($i);
}
$res = new Channel(1024);
$ids = [];
$t0 = microtime(true);
for ($i = 0; $i < $N; $i++) {
    $ids[] = go('echo_i', $res, $i);
}
$t_spawn = (microtime(true) - $t0) * 1000;
$sum = 0;
$cnt = 0;
while ($cnt < $N) {
    $v = $res->recv();
    if ($v === null) {
        break;
    }
    $sum += $v;
    $cnt++;
}
$t_drain = (microtime(true) - $t0) * 1000;
foreach ($ids as $id) {
    go_join($id);
}
$t_all = (microtime(true) - $t0) * 1000;
$expect = $N * ($N - 1) / 2;
$ok = $cnt === $N && $sum === $expect;
echo "cnt=$cnt sum=$sum expect=$expect\n";
echo "spawn_ms=" . round($t_spawn) . " drain_ms=" . round($t_drain) . " total_ms=" . round($t_all) . "\n";
echo $ok ? "G8 PASS\n" : "G8 FAIL\n";
