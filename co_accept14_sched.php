<?php
// 验收组14：多协程调度能力（join 多等待者 / 动态 wait_all / 定时器顺序 / 双侧 close / 高争用数据面）
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}

// ---- a) 同一目标被 3 个协程 join：目标结束后 3 者全继续 ----
function target_a($ev) {
    usleep(30000);
    $ev->send("T");
}
function joiner_a($id, $ev, $tag) {
    go_join($id);
    $ev->send($tag);
}
$ev = new Channel(8);
$tid = go('target_a', $ev);
$j1 = go('joiner_a', $tid, $ev, "J1");
$j2 = go('joiner_a', $tid, $ev, "J2");
$j3 = go('joiner_a', $tid, $ev, "J3");
$got = [];
for ($i = 0; $i < 4; $i++) {
    $got[] = $ev->recv();
}
$n_t = 0;
$n_j = 0;
foreach ($got as $g) {
    if ($g === "T") {
        $n_t++;
    } else {
        $n_j++;
    }
}
t("a.target_once", $n_t === 1);
t("a.joiners_all", $n_j === 3);
go_join($j1);
go_join($j2);
go_join($j3);

// ---- b) 动态 wait_all：waiter 等待期间 main 继续 spawn，必须等到全部结束 ----
$ev2 = new Channel(16);
function late_worker($ev, $tag, $delay) {
    usleep($delay);
    $ev->send("D:" . $tag);
}
function waiter_b($ev) {
    go_wait_all();
    $ev->send("W");
}
$wid = go('waiter_b', $ev2);
go('late_worker', $ev2, "a", 20000);
go('late_worker', $ev2, "b", 40000);
go('late_worker', $ev2, "c", 60000);
go_join($wid);
$ev2->close();
$seen = [];
while (true) {
    $e = $ev2->recv();
    if ($e === null) {
        break;
    }
    $seen[] = $e;
}
$w_pos = -1;
$d_count = 0;
foreach ($seen as $i => $e) {
    if ($e === "W") {
        $w_pos = $i;
    } else {
        $d_count++;
    }
}
t("b.dynamic_wait_all", $d_count === 3 && $w_pos === 3);

// ---- c) 多定时器按截止时间顺序唤醒 ----
$ev3 = new Channel(8);
function sleeper($ev, $tag, $us) {
    usleep($us);
    $ev->send($tag);
}
go('sleeper', $ev3, "s30", 30000);
go('sleeper', $ev3, "s80", 80000);
go('sleeper', $ev3, "s130", 130000);
go('sleeper', $ev3, "s180", 180000);
$order = [];
for ($i = 0; $i < 4; $i++) {
    $order[] = $ev3->recv();
}
$order_ok = $order[0] === "s30" && $order[1] === "s80" && $order[2] === "s130" && $order[3] === "s180";
t("c.timer_order", $order_ok);

// ---- d) 双侧 close：3 发送者 + 3 接收者同时阻塞，close 后全部干净退出 ----
function sender_d($ch, $ev) {
    try {
        $ch->send("v");
        $ev->send("S:ok");
    } catch (Throwable $e) {
        $ev->send("S:err");
    }
}
function recver_d($ch, $ev) {
    $v = $ch->recv();
    $ev->send($v === null ? "R:null" : "R:got");
}
$ch = new Channel(0);
$ev4 = new Channel(8);
for ($i = 0; $i < 3; $i++) {
    go('sender_d', $ch, $ev4);
}
for ($i = 0; $i < 3; $i++) {
    go('recver_d', $ch, $ev4);
}
usleep(50000);
$ch->close();
$sw = 0;
$se = 0;
$rn = 0;
$rg = 0;
for ($i = 0; $i < 6; $i++) {
    $r = $ev4->recv();
    if ($r === "S:ok") {
        $sw++;
    } elseif ($r === "S:err") {
        $se++;
    } elseif ($r === "R:null") {
        $rn++;
    } else {
        $rg++;
    }
}
echo "info d send_ok=$sw send_err=$se recv_null=$rn recv_got=$rg\n";
// 无缓冲通道：每次成功 send 必对应一次成功 recv（直接对接），反之亦然。
t("d.both_sides_clean", $sw + $se === 3 && $rn + $rg === 3 && $sw === $rg);

// ---- e) 高争用数据面：40 生产者 × 50 数组 + 4 消费者，无缓冲通道 ----
function prod_e($ch, $base) {
    for ($i = 0; $i < 50; $i++) {
        $ch->send(["k" => $base + $i, "pad" => $base]);
    }
}
function cons_e($ch, $res, $n) {
    $sum = 0;
    $cnt = 0;
    while ($cnt < $n) {
        $item = $ch->recv();
        if ($item === null) {
            break;
        }
        $sum += $item['k'];
        $cnt++;
    }
    $res->send([$cnt, $sum]);
}
$ch = new Channel(0);
$res = new Channel(4);
for ($c = 0; $c < 4; $c++) {
    go('cons_e', $ch, $res, 500);
}
for ($p = 0; $p < 40; $p++) {
    go('prod_e', $ch, $p * 50);
}
$total = 0;
$cnt_total = 0;
for ($c = 0; $c < 4; $c++) {
    $r = $res->recv();
    $cnt_total += $r[0];
    $total += $r[1];
}
$expect_cnt = 2000;
$expect_sum = 0;
for ($p = 0; $p < 40; $p++) {
    for ($i = 0; $i < 50; $i++) {
        $expect_sum += $p * 50 + $i;
    }
}
t("e.data_face", $cnt_total === $expect_cnt && $total === $expect_sum);

go_wait_all();

// ---- f) main 内 sleep/usleep 驱动就绪协程（Go 式「go 后 sleep 让 worker 跑」）----
$GLOBALS['flag_f'] = 0;
function worker_f() {
    $GLOBALS['flag_f'] = 1;
}
go('worker_f');
$t0 = microtime(true);
usleep(60000);
$dt = microtime(true) - $t0;
t("f.main_sleep_runs_worker", $GLOBALS['flag_f'] === 1);
t("f.main_sleep_wallclock", $dt >= 0.05);

echo "G14 DONE\n";
