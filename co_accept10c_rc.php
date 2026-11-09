<?php
// 验收组10c：跨协程传「数组+字符串」20 万次，RC 不泄漏不早释
// 预期：sum=Σ0..199999=19999900000；RSS 有界（/usr/bin/time -l 观测）；rc=0
function consumer10($ch, $n, $done) {
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
$N = 200000;
$work = new Channel(64);
$done = new Channel(1);
go('consumer10', $work, $N, $done);
$i = 0;
while ($i < $N) {
    $payload = ['k' => $i, 's' => str_repeat('x', 64)];
    $work->send($payload);
    $i++;
}
$work->close();
$sum = $done->recv();
$expect = $N * ($N - 1) / 2;
$ok = $sum === $expect;
echo "sum=$sum expect=$expect\n";
if ($ok) {
    echo "G10C PASS\n";
} else {
    echo "G10C FAIL\n";
}
