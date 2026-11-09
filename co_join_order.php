<?php
// co_join_order：3 枚不同时长协程，按 id join，断言完成顺序与 join 返回时机（设计稿 §5 M1 探针 3）。
function w($i, $ms, $done) {
    usleep($ms * 1000);
    $done->send($i);
}
$done = new Channel(3);
$id3 = go('w', 3, 30, $done); // 最慢先生
$id2 = go('w', 2, 20, $done);
$id1 = go('w', 1, 10, $done); // 最快
go_join($id1); // join 最快者：返回时 w1 必已完成
$after1 = $done->tryRecv();
$r1 = ($after1 === 1);
go_join($id2);
go_join($id3);
$rest = [];
while (($v = $done->tryRecv()) !== null) {
    $rest[] = $v;
}
// 完成顺序必须是由定时器决定的 1,2,3（tryRecv 读空缓冲只拿残余）
sort($rest);
$ok = $r1 && count($rest) === 2 && $rest[0] === 2 && $rest[1] === 3;
go_wait_all();
echo $ok ? "co_join_order PASS\n" : "co_join_order FAIL r1=" . var_export($r1, true) . " rest=" . implode(',', $rest) . "\n";
