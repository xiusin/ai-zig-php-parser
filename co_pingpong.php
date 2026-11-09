<?php
// co_pingpong：2 协程经 2 无缓冲 channel 往返 1000 次，终值断言（设计稿 §5 M1 探针 1）。
function pong($in, $out) {
    for ($i = 0; $i < 1000; $i++) {
        $v = $in->recv();
        $out->send($v + 1);
    }
}
$in = new Channel(0);
$out = new Channel(0);
$id = go('pong', $in, $out);
$ok = true;
for ($i = 0; $i < 1000; $i++) {
    $in->send($i);
    $r = $out->recv();
    if ($r !== $i + 1) {
        $ok = false;
        echo "mismatch at $i: got ";
        var_dump($r);
        break;
    }
}
go_join($id);
echo $ok ? "co_pingpong PASS\n" : "co_pingpong FAIL\n";
