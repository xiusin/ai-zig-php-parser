<?php
// co_fanin：8 生产者 → 1 缓冲 channel → 消费者求和，断言总数与无丢失（设计稿 §5 M1 探针 2）。
// ★规避既有 AOT 生成码缺陷：`$v === null && $ch->isClosed()` 短路+方法调+break 在循环内
//   会错误反转 break 条件（与协程无关的预存生成码问题，已另行上报）；改用单条件结构。
function producer($ch, $base) {
    for ($i = 0; $i < 250; $i++) {
        $ch->send($base + $i);
    }
}
function summer($ch, $res) {
    $acc = 0;
    while (true) {
        $v = $ch->recv(); // 阻塞语义：空开则让出，关闭且取尽返 null
        if ($v === null) break;
        $acc += $v;
    }
    $res->send($acc);
}
$ch = new Channel(4);
$res = new Channel(1);
$sid = go('summer', $ch, $res);
$ids = [];
for ($p = 0; $p < 8; $p++) {
    $ids[] = go('producer', $ch, $p * 250);
}
foreach ($ids as $id) {
    go_join($id);
}
$ch->close();
go_join($sid);
$total = $res->recv();
$expect = 0;
for ($p = 0; $p < 8; $p++) {
    for ($i = 0; $i < 250; $i++) {
        $expect += $p * 250 + $i;
    }
}
echo $total === $expect ? "co_fanin PASS total=$total\n" : "co_fanin FAIL total=$total expect=$expect\n";
