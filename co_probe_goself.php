<?php
// 临时探针：类内 go self::method(...) / go static::method(...)
class SW {
    public static function work($ev, $tag) {
        $ev->send($tag);
    }
    public function run($ev) {
        go self::work($ev, 'self');
        go static::work($ev, 'static');
    }
}
$ev = new Channel(3);
$w = new SW();
$w->run($ev);
$ev->send("main");
go_wait_all();
$r = [];
for ($i = 0; $i < 3; $i++) {
    $r[] = $ev->tryRecv();
}
echo "got=" . implode(",", $r) . "\n";
echo $r[0] === "main" ? "PASS order\n" : "FAIL order\n";
$ok = false;
if ($r[1] === "self" && $r[2] === "static") {
    $ok = true;
}
if ($r[1] === "static" && $r[2] === "self") {
    $ok = true;
}
echo $ok ? "PASS bodies\n" : "FAIL bodies\n";
echo "DONE\n";
