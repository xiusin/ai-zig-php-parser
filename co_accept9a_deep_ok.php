<?php
// 验收组9a：协程内正常深度业务调用（20 层 / 25 层）——64KB 栈内稳定返回
// 注：M1 定长 64KB 栈实测约容纳 ~30 层 PHP 调用帧（每帧 ~2KB），
//     超出由保护页转明确致命错（见 9b）；扩容属 M3 议题（设计 D2=C→A）。
function rec20($n, $acc) {
    if ($n <= 0) {
        return $acc;
    }
    return rec20($n - 1, $acc + $n);
}
function work($ev) {
    $a = rec20(20, 0);
    $b = rec20(25, 0);
    $ev->send("R20:" . $a);
    $ev->send("R25:" . $b);
}
$ev = new Channel(8);
go('work', $ev);
go_wait_all();
$ev->close();
$r20 = 0;
$r25 = 0;
while (true) {
    $e = $ev->recv();
    if ($e === null) {
        break;
    }
    if (strpos($e, 'R20:') === 0) {
        $r20 = (int)substr($e, 4);
    } elseif (strpos($e, 'R25:') === 0) {
        $r25 = (int)substr($e, 4);
    }
}
$ok = $r20 === 210 && $r25 === 325;
echo "r20=$r20 r25=$r25\n";
echo $ok ? "G9A PASS\n" : "G9A FAIL\n";
