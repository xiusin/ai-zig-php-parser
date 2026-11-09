<?php
// 验收组3：4 段流水线 gen → double → square → summer，段间 channel 传 close
// 验证：close 逐段传播、close 后残余元素仍被处理、最终结果正确、全程无「close 后 send」
function stage_gen($out, $n) {
    for ($i = 1; $i <= $n; $i++) {
        $out->send($i);
    }
    $out->close(); // 源关闭：下游取尽残余后 recv 得 null
}
function stage_double($in, $out) {
    while (true) {
        $v = $in->recv();
        if ($v === null) break; // 上游 close 且取尽
        $out->send($v * 2);
    }
    $out->close(); // close 传播
}
function stage_square($in, $out) {
    while (true) {
        $v = $in->recv();
        if ($v === null) break;
        $out->send($v * $v);
    }
    $out->close(); // close 传播
}
function stage_summer($in, $out) {
    $acc = 0;
    $cnt = 0;
    while (true) {
        $v = $in->recv();
        if ($v === null) break;
        $acc += $v;
        $cnt++;
    }
    $out->send([$acc, $cnt]); // close 前把汇总送出
    $out->close();
}
$ch1 = new Channel(4);
$ch2 = new Channel(4);
$ch3 = new Channel(4);
$ch4 = new Channel(1);
go('stage_gen', $ch1, 50);
go('stage_double', $ch1, $ch2);
go('stage_square', $ch2, $ch3);
go('stage_summer', $ch3, $ch4);
$r = $ch4->recv();
go_wait_all();
// Σ(2k)², k=1..50 = 4·Σk² = 4·50·51·101/6 = 171700
$expect = 171700;
$ok = $r !== null && $r[0] === $expect && $r[1] === 50;
echo $ok ? "G3 PASS sum={$r[0]} cnt={$r[1]}\n"
         : "G3 FAIL r=" . ($r === null ? "null" : "[{$r[0]},{$r[1]}]") . " expect=[$expect,50]\n";
