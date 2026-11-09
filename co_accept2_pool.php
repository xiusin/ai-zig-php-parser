<?php
// 验收组2：worker 池——4 worker 消费 500 任务，结果汇总 channel 统计
// 验证：全量完成（500）、每任务恰好一次、结果值正确（平方）、不死锁；
// 负载分布仅观察报告（N:1 协作式调度不保证均衡，Go 同）。
function worker($tasks, $results, $wid) {
    $mine = 0;
    while (true) {
        $t = $tasks->recv();
        if ($t === null) break;
        $results->send([$wid, $t, $t * $t]);
        $mine++;
    }
    return $mine;
}
function producer($tasks, $m) {
    for ($i = 0; $i < $m; $i++) {
        $tasks->send($i);
    }
    $tasks->close();
}
$tasks = new Channel(16);
$results = new Channel(64);
$W = 4;
$M = 500;
$wids = [];
for ($w = 0; $w < $W; $w++) {
    $wids[] = go('worker', $tasks, $results, $w);
}
// 投递方独立成协程：main 从即刻起持续 drain results，
// 否则「main 投满 tasks 阻塞 + worker 投满 results 阻塞」双向依赖死锁（Go 同构亦死锁）。
go('producer', $tasks, $M);
$done = 0;
$dist = [0, 0, 0, 0];
$correct = true;
$seen = [];
while ($done < $M) {
    $r = $results->recv();
    if ($r === null) break;
    $dist[$r[0]]++;
    if (isset($seen[$r[1]])) $correct = false;
    $seen[$r[1]] = true;
    if ($r[2] !== $r[1] * $r[1]) $correct = false;
    $done++;
}
go_wait_all();
$count_ok = $done === $M && count($seen) === $M;
$ok = $count_ok && $correct;
echo "dist=", implode(',', $dist), "\n";
echo $ok ? "G2 PASS done=$done correct=1\n" : "G2 FAIL done=$done correct=" . ($correct ? 1 : 0) . "\n";
