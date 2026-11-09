<?php
// 验收组7：sleep()/usleep() 自动让出（D5=A）——协程内让出、main 内真阻塞
// a) 协程 A sleep 150ms；协程 B 每 20ms 打点 ×5。若 sleep 真让出，B 的点必须出现在 A 完成之前，
//    且 A 的实际耗时 >= 150ms。
// b) main 内 usleep(100ms) 期间无其它协程可推进（真阻塞），实测耗时 >= 0.1s。
function sleeper($ev) {
    $t0 = microtime(true);
    usleep(150000);
    $dt = microtime(true) - $t0;
    $ev->send("A_DONE:" . round($dt * 1000));
}
function ticker($ev) {
    for ($i = 1; $i <= 5; $i++) {
        usleep(20000);
        $ev->send("B_TICK:" . $i);
    }
}
$ev = new Channel(16);
go('sleeper', $ev);
go('ticker', $ev);
go_wait_all();
$ev->close();
$seq = "";
$atick = 0;
$a_done_ms = 0;
while (true) {
    $e = $ev->recv();
    if ($e === null) {
        break;
    }
    if (strpos($e, 'B_TICK:') === 0) {
        $atick++;
        if ($a_done_ms === 0) {
            $seq .= "B";
        }
    } elseif (strpos($e, 'A_DONE:') === 0) {
        $a_done_ms = (int)substr($e, 7);
    }
}
// a) 睡眠期间 B 至少推进 5 次（全部在 A 完成前）
$a_ok = $atick === 5 && $seq === "BBBBB" && $a_done_ms >= 145;
// b) main 真阻塞
$t0 = microtime(true);
usleep(100000);
$main_ms = (microtime(true) - $t0) * 1000;
$b_ok = $main_ms >= 95;
echo "ticks=$atick a_ms=$a_done_ms main_ms=" . round($main_ms) . "\n";
echo ($a_ok && $b_ok) ? "G7 PASS\n" : ("G7 FAIL a_ok=" . ($a_ok ? 1 : 0) . " b_ok=" . ($b_ok ? 1 : 0) . "\n");
