<?php
// 验收组15：select 边界（closed send 超时口径 / 混合就绪 / 多 closed recv / send 值所有权）
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}

// ---- a) closed channel 的 send case：视为就绪 ⇒ 立即抛可捕获 Error（D-2 裁决，对齐 Go panic）----
$ch = new Channel(0);
$ch->close();
$t0 = microtime(true);
$msg = "";
try {
    Zig\Select::select([[$ch, 1, 'x']], 20);
} catch (Throwable $e) {
    $msg = $e->getMessage();
}
$dt = microtime(true) - $t0;
t("a.closed_send_throw", $msg === 'send on closed channel');
t("a.noTimeoutWait", $dt < 0.05);
echo "info a dt=" . round($dt, 4) . "\n";

// ---- b) 满缓冲 send case（不就绪）+ 活 recv case ⇒ 必选活 recv ----
$full = new Channel(1);
$full->trySend('a');
$live = new Channel(1);
$live->send('v1');
$pick = Zig\Select::select([[$full, 1, 'x'], [$live, 0]], 50);
t("b.pick_live", is_array($pick) && $pick[0] === 1 && $pick[1] === 'v1');

// ---- b2) closed send + 活 recv 双就绪：随机选中——抛错或取活值，均合法且不得挂死 ----
$dead = new Channel(0);
$dead->close();
$live2 = new Channel(1);
$live2->send('v2');
$out = "";
try {
    $r = Zig\Select::select([[$dead, 1, 'x'], [$live2, 0]], null);
    if (is_array($r) && $r[0] === 1 && $r[1] === 'v2') {
        $out = "recv";
    } else {
        $out = "unexpected";
    }
} catch (Throwable $e) {
    if ($e->getMessage() === 'send on closed channel') {
        $out = "throw";
    } else {
        $out = "unexpected";
    }
}
t("b2.closed_or_live", $out === "recv" || $out === "throw");

// ---- c) 多个 closed 空 channel 的 recv：返回其一 + null ----
$d1 = new Channel(0);
$d2 = new Channel(0);
$d1->close();
$d2->close();
$r = Zig\Select::select([[$d1, 0], [$d2, 0]], 0);
t("c.any_closed_recv", is_array($r) && ($r[0] === 0 || $r[0] === 1) && $r[1] === null);

// ---- d) select send 值所有权：数组经 select 投递后接收方独立可用 ----
function recv_one($ch, $res) {
    $v = $ch->recv();
    $res->send($v);
}
$ch = new Channel(0);
$res = new Channel(1);
go('recv_one', $ch, $res);
$payload = ['k' => 7, 'name' => 'sel'];
$pick = Zig\Select::select([[$ch, 1, $payload]], null);
t("d.pick", $pick === 0);
$payload['k'] = 99; // COW：发送后修改本地不应影响已投递快照
$got = $res->recv();
t("d.payload", is_array($got) && $got['k'] === 7 && $got['name'] === 'sel');

go_wait_all();
echo "G15 DONE\n";
