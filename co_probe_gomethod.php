<?php
// 临时探针：go 语句形的方法/静态方法 callee（当前口径取证）
class W {
    public $tag = "obj";
    public function run($ev) {
        $ev->send("method:" . $this->tag);
    }
    public static function stat($ev) {
        $ev->send("static");
    }
}
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}
$ev = new Channel(4);
$w = new W();
go $w->run($ev);
$ev->send("main1");
go_wait_all();
$r1 = $ev->tryRecv();
$r2 = $ev->tryRecv();
echo "info method r1=$r1 r2=$r2\n";
t("method_spawn", $r1 === "main1" && $r2 === "method:obj");

go W::stat($ev);
$ev->send("main2");
go_wait_all();
$r1 = $ev->tryRecv();
$r2 = $ev->tryRecv();
echo "info static r1=$r1 r2=$r2\n";
t("static_spawn", $r1 === "main2" && $r2 === "static");
echo "DONE\n";
