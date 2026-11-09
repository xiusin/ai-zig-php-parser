<?php
// 验收组4：select 多 channel 竞争 + 随机公平性 + default(零超时) + 超时 + 无就绪阻塞
// 面：Zig\Select::select([[channel, op, ?value], ...], ?ms timeout)（op 0=recv）
// a) 公平性：两 channel 持续有货，select 2000 次分布应各 ~50%（容差 ±10%）
// b) default：timeout=0 无就绪 ⇒ 立即返 null
// c) 超时：timeout=150ms 无就绪 ⇒ ~150ms 返 null
// d) 无就绪阻塞：timeout=null，协程内 select 等另一协程喂食（顺带验证 sleep 让出）

function feeder($ch) {
    $i = 0;
    while (true) {
        try {
            $ch->send($i); // close 后抛可捕获 Error ⇒ 本协程退出
            $i++;
        } catch (Throwable $e) {
            return;
        }
    }
}
function delayer($ch) {
    usleep(150000); // 协程内自动让出（D5=A）
    $ch->send('ping');
}

$fail = [];

// ---- a) 公平性 ----
$ch1 = new Channel(1);
$ch2 = new Channel(1);
go('feeder', $ch1);
go('feeder', $ch2);
$cnt = [0, 0];
for ($i = 0; $i < 2000; $i++) {
    $r = Zig\Select::select([[$ch1, 0], [$ch2, 0]], null);
    if ($r === null) {
        $fail[] = "a: select returned null with live feeders";
        break;
    }
    $cnt[$r[0]]++;
}
$ch1->close();
$ch2->close();
go_wait_all();
$lo = 900;
$hi = 1100;
$fair = $cnt[0] >= $lo && $cnt[0] <= $hi;
echo "a: dist={$cnt[0]},{$cnt[1]}\n";
if (!$fair) $fail[] = "a: unfair dist {$cnt[0]}/{$cnt[1]} expect [900,1100]";

// ---- b) default（零超时无就绪立即返 null）----
$ch3 = new Channel(0);
$t0 = microtime(true);
$r = Zig\Select::select([[$ch3, 0]], 0);
$dt = microtime(true) - $t0;
echo "b: r=" . ($r === null ? "null" : "value") . " dt=" . round($dt, 3) . "s\n";
if ($r !== null || $dt > 0.05) $fail[] = "b: default branch failed r/dt=" . ($r === null ? "null" : "value") . "/$dt";

// ---- c) 超时分支 ----
$ch4 = new Channel(0);
$t0 = microtime(true);
$r = Zig\Select::select([[$ch4, 0]], 150);
$dt = microtime(true) - $t0;
echo "c: r=" . ($r === null ? "null" : "value") . " dt=" . round($dt, 3) . "s\n";
if ($r !== null || $dt < 0.14 || $dt > 0.6) $fail[] = "c: timeout branch failed r/dt=" . ($r === null ? "null" : "value") . "/$dt";

// ---- d) 无就绪时阻塞（无超时），另一协程 150ms 后喂食 ----
$ch5 = new Channel(0);
go('delayer', $ch5);
$t0 = microtime(true);
$r = Zig\Select::select([[$ch5, 0]], null);
$dt = microtime(true) - $t0;
go_wait_all();
$okd = $r !== null && $r[0] === 0 && $r[1] === 'ping' && $dt >= 0.14;
echo "d: r=" . ($r === null ? "null" : "[{$r[0]},{$r[1]}]") . " dt=" . round($dt, 3) . "s\n";
if (!$okd) $fail[] = "d: blocking select failed";

if (count($fail) === 0) {
    echo "G4 PASS all\n";
} else {
    foreach ($fail as $f) echo "G4 FAIL $f\n";
}
