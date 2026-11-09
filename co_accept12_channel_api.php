<?php
// 验收组12：Channel 公开 API 一致性（多协程能力加固）
// 覆盖：capacity/len/isClosed、trySend 满/不满、tryRecv FIFO/空、
//       close 残余取尽、send-on-closed 可捕获 Error、重复 close 幂等、
//       阻塞 receiver/sender 被 close 唤醒、无缓冲 len 口径、
//       select 的 send 分支（单 case 命中 / 下标 case / 满缓冲零超时）、
//       closed 空 channel 的 select recv 就绪、go_join 已完成/空参。
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}
function noop() {
}
function r_blocker($ch, $res) {
    $v = $ch->recv();
    $res->send($v === null ? "null" : "value");
    $res->send($ch->isClosed() ? "closed" : "open");
}
function s_notify($ch, $res) {
    try {
        $ch->send(1);
        $res->send("sent");
    } catch (Throwable $e) {
        $res->send("caught:" . $e->getMessage());
    }
}
function one_recv($ch, $res) {
    $v = $ch->recv();
    $res->send($v === null ? "null" : $v);
}

// ---- a) 基本量 ----
$ch = new Channel(3);
t("a.cap3", $ch->capacity() === 3);
t("a.len0", $ch->len() === 0);
t("a.open", $ch->isClosed() === false);
$ch0 = new Channel(0);
t("a.cap0", $ch0->capacity() === 0);

// ---- b) 有缓冲 trySend 满/不满 ----
t("b.ts1", $ch->trySend(1) === true);
t("b.ts2", $ch->trySend(2) === true);
t("b.ts3", $ch->trySend(3) === true);
t("b.len3", $ch->len() === 3);
t("b.full", $ch->trySend(4) === false);
t("b.len_still3", $ch->len() === 3);

// ---- c) tryRecv FIFO / 空 ----
t("c.1", $ch->tryRecv() === 1);
t("c.2", $ch->tryRecv() === 2);
t("c.len1", $ch->len() === 1);
t("c.3", $ch->tryRecv() === 3);
t("c.empty", $ch->tryRecv() === null);
t("c.len0", $ch->len() === 0);

// ---- d) close 残余取尽 + 关闭后 recv 立即返 null ----
$ch->trySend('x');
$ch->trySend('y');
$ch->close();
t("d.closed", $ch->isClosed() === true);
t("d.len2", $ch->len() === 2);
t("d.x", $ch->tryRecv() === 'x');
t("d.y", $ch->tryRecv() === 'y');
t("d.null", $ch->tryRecv() === null);
$t0 = microtime(true);
$v = $ch->recv();
$dt = microtime(true) - $t0;
t("d.recv_null", $v === null);
t("d.recv_nowait", $dt < 0.05);

// ---- e) send on closed 抛可捕获 Error；trySend 不崩 ----
$msg = "";
try {
    $ch->send(9);
} catch (Throwable $e) {
    $msg = $e->getMessage();
}
t("e.send_throw", $msg === 'send on closed channel');
$r = null;
$msg2 = "";
try {
    $r = $ch->trySend(9);
} catch (Throwable $e) {
    $msg2 = $e->getMessage();
}
echo "info trySend_on_closed r=" . ($r === null ? "null" : ($r === false ? "false" : "true")) . " msg='" . $msg2 . "'\n";
t("e.trySend_safe", $r === false || $msg2 !== "");

// ---- f) 重复 close 幂等 ----
$err = "";
try {
    $ch->close();
    $ch->close();
} catch (Throwable $e) {
    $err = $e->getMessage();
}
t("f.close_idem", $err === "");

// ---- g) 阻塞 receiver 被 close 唤醒（残余取尽后得 null）----
$ch = new Channel(0);
$res = new Channel(2);
go('r_blocker', $ch, $res);
usleep(50000);
$ch->close();
t("g.wake_null", $res->recv() === "null");
t("g.wake_closed", $res->recv() === "closed");

// ---- h) 阻塞 sender 被 close 唤醒（可捕获 Error，值不入队）----
$ch = new Channel(1);
$ch->trySend(10);
$res = new Channel(1);
go('s_notify', $ch, $res);
usleep(50000);
$ch->close();
t("h.send_throw", $res->recv() === "caught:send on closed channel");
t("h.residual", $ch->tryRecv() === 10);

// ---- i) 无缓冲：阻塞 sender 时 len 仍为 0；recv 对接成功 ----
$ch = new Channel(0);
$res = new Channel(1);
go('s_notify', $ch, $res);
usleep(50000);
t("i.len0", $ch->len() === 0);
t("i.pair_value", $ch->recv() === 1);
t("i.pair_sent", $res->recv() === "sent");

// ---- j) select send 分支：接收者已阻塞 ⇒ 命中并投递 ----
$ch = new Channel(0);
$res = new Channel(1);
go('one_recv', $ch, $res);
usleep(50000);
$pick = Zig\Select::select([[$ch, 1, 'hello']], null);
t("j.pick0", $pick === 0);
t("j.delivered", $res->recv() === 'hello');

// ---- k) select send 分支：缓冲已满 + 零超时 ⇒ null 且不投递 ----
$ch = new Channel(1);
$ch->trySend('a');
$pick = Zig\Select::select([[$ch, 1, 'b']], 0);
t("k.full_null", $pick === null);
t("k.len1", $ch->len() === 1);
t("k.kept_a", $ch->tryRecv() === 'a');

// ---- l) closed 空 channel：select recv case 就绪，取残余后 null ----
$ch = new Channel(0);
$ch->close();
$r = Zig\Select::select([[$ch, 0]], 0);
t("l.closed_ready", is_array($r) && $r[0] === 0 && $r[1] === null);

// ---- m) select send 分支下标：第 0 case 不就绪、第 1 case 就绪 ----
$ch1 = new Channel(0);
$ch2 = new Channel(0);
$res = new Channel(1);
go('one_recv', $ch2, $res);
usleep(50000);
$pick = Zig\Select::select([[$ch1, 0], [$ch2, 1, 'z']], null);
t("m.pick1", $pick === 1);
t("m.delivered", $res->recv() === 'z');

// ---- n) 多阻塞 sender 被 close 集体唤醒 ----
$ch = new Channel(1);
$ch->trySend(0);
$res = new Channel(3);
go('s_notify', $ch, $res);
go('s_notify', $ch, $res);
go('s_notify', $ch, $res);
usleep(50000);
$ch->close();
$n = 0;
for ($i = 0; $i < 3; $i++) {
    if ($res->recv() === "caught:send on closed channel") {
        $n++;
    }
}
t("n.all_caught", $n === 3);

// ---- o) go_join 已完成协程立即返回；go_join(null) = wait_all ----
$id = go('noop');
go_join($id);
go_join($id);
go_join(null);
t("o.join_done", true);

go_wait_all();
echo "G12 DONE\n";
