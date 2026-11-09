<?php
// 验收组15：select 边界（closed send 超时口径 / 混合就绪 / 多 closed recv / send 值所有权）
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}

// ---- a) closed channel 的 send case + 有限超时：不就绪 ⇒ 超时返 null ----
$ch = new Channel(0);
$ch->close();
$t0 = microtime(true);
$r = Zig\Select::select([[$ch, 1, 'x']], 20);
$dt = microtime(true) - $t0;
t("a.closed_send_timeout_null", $r === null);
t("a.timeout_elapsed", $dt >= 0.015);
echo "info a dt=" . round($dt, 4) . "\n";

// ---- b) closed send case + 活 recv case：必须选中活 recv ----
$dead = new Channel(0);
$dead->close();
$live = new Channel(1);
$live->send('v1');
$pick = Zig\Select::select([[$dead, 1, 'x'], [$live, 0]], 50);
t("b.pick_live", is_array($pick) && $pick[0] === 1 && $pick[1] === 'v1');

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
