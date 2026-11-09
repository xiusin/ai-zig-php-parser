<?php
// 验收组5：嵌套 spawn——协程内再 spawn、父协程 join 子协程、go_wait_all 在协程内调用
// 层级：P/Q 父协程各 spawn 3 子协程，每子再 spawn 2 孙协程；父用 go_join 收子。
// 协程内 go_wait_all 由独立 waiter 协程验证：它等到 P/Q 及全部后代结束后才发 W_WAITED，
// 故 W_WAITED 必须恰为最后一个事件（计数：12 孙 / 6 子 / 2 父始末）。
// ★规避预存 codegen 缺陷（与协程无关，已单独上报 F-2a/F-2b）：断言段用单层 if/elseif，
//   无三元、无 ??、无嵌套 if。
function grandchild($ev, $tag) {
    $ev->send("GC_DONE:" . $tag);
}
function child($ev, $pid, $ci) {
    $g1 = go('grandchild', $ev, $pid . "-" . $ci . "-a");
    $g2 = go('grandchild', $ev, $pid . "-" . $ci . "-b");
    go_join($g1);
    go_join($g2);
    $ev->send("CH_DONE:" . $pid . "-" . $ci);
}
function parent($ev, $pid) {
    $ev->send("P_START:" . $pid);
    $c1 = go('child', $ev, $pid, 1);
    $c2 = go('child', $ev, $pid, 2);
    $c3 = go('child', $ev, $pid, 3);
    go_join($c1);
    go_join($c2);
    go_join($c3);
    $ev->send("P_DONE:" . $pid);
}
function waiter($ev) {
    go_wait_all();
    $ev->send("W_WAITED");
}
$ev = new Channel(64);
go('parent', $ev, 'P');
go('parent', $ev, 'Q');
go('waiter', $ev);
go_wait_all();
$ev->close();
$gc = 0;
$ch = 0;
$ps = 0;
$pd = 0;
$waits = 0;
$after_wait = 0;
$stage = 0;
$total = 0;
while (true) {
    $e = $ev->recv();
    if ($e === null) {
        break;
    }
    $total++;
    if (strpos($e, 'GC_DONE:') === 0) {
        if ($stage === 1) {
            $after_wait++;
        }
        $gc++;
    } elseif (strpos($e, 'CH_DONE:') === 0) {
        if ($stage === 1) {
            $after_wait++;
        }
        $ch++;
    } elseif (strpos($e, 'P_START:') === 0) {
        if ($stage === 1) {
            $after_wait++;
        }
        $ps++;
    } elseif (strpos($e, 'P_DONE:') === 0) {
        if ($stage === 1) {
            $after_wait++;
        }
        $pd++;
    } elseif (strpos($e, 'W_WAITED') === 0) {
        $waits++;
        $stage = 1;
    }
}
$ok = $gc === 12 && $ch === 6 && $ps === 2 && $pd === 2 && $waits === 1 && $after_wait === 0;
echo "gc=$gc ch=$ch ps=$ps pd=$pd waits=$waits after_wait=$after_wait total=$total\n";
echo $ok ? "G5 PASS\n" : "G5 FAIL\n";
