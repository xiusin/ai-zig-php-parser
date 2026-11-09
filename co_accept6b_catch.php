<?php
// 验收组6b：协程内 try/catch 正常拦截；异常旗快照不串扰其他协程
// A 协程反复 throw+catch（100 次），B 协程同时正常计算；main 事后无异常残留
function catcher($ev) {
    $caught = 0;
    for ($i = 0; $i < 100; $i++) {
        try {
            throw new RuntimeException("x" . $i);
        } catch (RuntimeException $e) {
            $caught++;
        }
    }
    $ev->send("A_CAUGHT:" . $caught);
}
function calculator($ev) {
    $acc = 0;
    for ($i = 1; $i <= 500; $i++) {
        $acc += $i;
    }
    $ev->send("B_ACC:" . $acc);
}
$ev = new Channel(8);
go('catcher', $ev);
go('calculator', $ev);
go_wait_all();
$ev->close();
$a = "";
$b = "";
while (true) {
    $e = $ev->recv();
    if ($e === null) {
        break;
    }
    if (strpos($e, 'A_CAUGHT:') === 0) {
        $a = substr($e, 9);
    } elseif (strpos($e, 'B_ACC:') === 0) {
        $b = substr($e, 6);
    }
}
// main 侧无异常残留：$a/$b 正常产出即证（若旗标串扰，后续语句会被异常通道截断）
$ok = $a === "100" && $b === "125250";
echo "a=$a b=$b\n";
echo $ok ? "G6B PASS\n" : "G6B FAIL\n";
