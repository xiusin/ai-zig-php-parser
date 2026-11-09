<?php
// 验收组16：协程边界对象生命周期（句柄共享 / 闭包捕获 / 多协程共享对象）
// 说明：本组不断言 __destruct 的即时时机——AOT 的对象析构时点是既有全局行为
//       （无协程对照脚本同样如此），不属于协程能力面；本组只验证协程收尾后
//       主侧句柄仍可用、捕获对象不被提前释放、多协程共享修改可见、进程干净退出。
class DBox {
    public $tag = "";
    public $count = 0;
    public function __construct($tag) {
        $this->tag = $tag;
    }
    public function bump() {
        $this->count = $this->count + 1;
    }
}
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}
function hold_obj($o, $ev) {
    usleep(20000);
    $o->bump();
    $ev->send("held:" . $o->tag);
}

// ---- a) 对象作协程实参：协程内修改对主侧可见；协程结束后主侧句柄仍可用 ----
$ev = new Channel(2);
$o = new DBox("co-arg");
go('hold_obj', $o, $ev);
go_wait_all();
t("a.held", $ev->recv() === "held:co-arg");
t("a.shared_handle", $o->tag === "co-arg");
$o->bump();
t("a.usable_after", $o->count === 2);

// ---- b) 闭包捕获对象：变量 unset 后协程仍可用（闭包持有引用，不得提前释放）----
$o2 = new DBox("captured");
$ev2 = new Channel(1);
$fn = function () use ($o2, $ev2) {
    usleep(20000);
    $ev2->send("cap:" . $o2->tag);
};
go($fn);
unset($fn);
unset($o2);
go_wait_all();
t("b.captured_usable", $ev2->recv() === "cap:captured");

// ---- c) 多协程共享同一对象：4 协程各持引用并修改，主侧见到 4 次 ----
$shared = new DBox("shared");
function touch_obj($o, $ev, $i) {
    usleep(5000 * $i);
    $o->bump();
    $ev->send($o->tag . ":" . $i);
}
$ev3 = new Channel(4);
for ($i = 0; $i < 4; $i++) {
    go('touch_obj', $shared, $ev3, $i);
}
go_wait_all();
$n = 0;
$bad = 0;
while (true) {
    $m = $ev3->tryRecv();
    if ($m === null) {
        break;
    }
    if (strpos($m, "shared:") === 0) {
        $n++;
    } else {
        $bad++;
    }
}
t("c.shared_all", $n === 4 && $bad === 0);
t("c.shared_mutation", $shared->count === 4);

echo "G16 DONE\n";
