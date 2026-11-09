<?php
// 验收组13：协程调用面能力矩阵（多协程能力加固）
// 覆盖：闭包体 / __invoke 对象体 / [$obj,'method'] 数组体 / 'Class::static' 字符串体 /
//       未知函数字符串（记录实际口径，不得挂死）/ Mutex / Atomic / RWLock / SharedData
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}
function info($name, $v) {
    if ($v === null) {
        echo "info $name=null\n";
    } elseif ($v === true) {
        echo "info $name=true\n";
    } elseif ($v === false) {
        echo "info $name=false\n";
    } else {
        echo "info $name=" . $v . "\n";
    }
}
class Inv {
    public function __invoke($res, $tag) {
        $res->send($tag);
    }
}
class Worker {
    public $tag = "";
    public function __construct($tag) {
        $this->tag = $tag;
    }
    public function run($res) {
        $res->send($this->tag);
    }
    public static function stat($res) {
        $res->send("static");
    }
}

// ---- a) 闭包体 ----
$res = new Channel(4);
go(function () use ($res) {
    $res->send('closure');
});
go_wait_all();
t("a.closure", $res->tryRecv() === 'closure');

// ---- b) __invoke 对象体 ----
$inv = new Inv();
go($inv, $res, 'invoke');
go_wait_all();
t("b.invoke", $res->tryRecv() === 'invoke');

// ---- c) 数组 callable [$obj, 'method'] ----
$w = new Worker("array");
go([$w, 'run'], $res);
go_wait_all();
t("c.array_callable", $res->tryRecv() === 'array');

// ---- d) 静态方法字符串 'Class::method' ----
go('Worker::stat', $res);
go_wait_all();
t("d.static_string", $res->tryRecv() === 'static');

// ---- e) 未知函数字符串：spawn 点抛可捕获 Error（不得静默空跑）----
$emsg = "";
try {
    go('no_such_function_xyz', $res);
} catch (Throwable $e) {
    $emsg = $e->getMessage();
}
t("e.unknown_fn_throw", $emsg === 'Call to undefined function no_such_function_xyz()');
info("e.unknown_fn", $res->tryRecv());

// ---- e2) 非法数组 callable / 无 __invoke 对象：spawn 点抛可捕获 TypeError ----
$emsg2 = "";
try {
    go([$w, 'no_such_method'], $res);
} catch (Throwable $e) {
    $emsg2 = $e->getMessage();
}
t("e2.bad_method_throw", strpos($emsg2, 'must be a valid callback') !== false);
$emsg3 = "";
try {
    go($w, $res);
} catch (Throwable $e) {
    $emsg3 = $e->getMessage();
}
t("e3.no_invoke_throw", strpos($emsg3, 'must be a valid callback') !== false);

// ---- f) Mutex：4 协程 × 500 次加锁自增 ----
function mutex_worker($m, $acc, $n) {
    for ($i = 0; $i < $n; $i++) {
        $m->lock();
        $acc->store($acc->load() + 1);
        $m->unlock();
    }
}
$m = new Mutex();
$acc = new Atomic(0);
for ($i = 0; $i < 4; $i++) {
    go('mutex_worker', $m, $acc, 500);
}
go_wait_all();
t("f.mutex_sum", $acc->load() === 2000);
t("f.mutex_lockcount", $m->getLockCount() === 0);

// ---- g) Atomic：increment/add/sub 均返新值（D-3 裁决）----
$a2 = new Atomic(5);
t("g.atomic_inc", $a2->increment() === 6);
t("g.atomic_add_new", $a2->add(4) === 10);
t("g.atomic_sub_new", $a2->sub(3) === 7);
t("g.atomic_load", $a2->load() === 7);

// ---- h) RWLock / SharedData 基本面 ----
$rw = new RWLock();
$rw->lockRead();
$rw->unlockRead();
$rw->lockWrite();
$rw->unlockWrite();
t("h.rwlock", true);
$sd = new SharedData();
$sd->set("k", "v");
t("h.shareddata", $sd->get("k") === "v");

// ---- i) is_callable 的作用域限定符解析（F-1-d 附带修正）----
class SCBase {
    public static function pm() {
    }
}
class ScopeCallable extends SCBase {
    public static function m() {
    }
    public function probe($out) {
        $out->send(is_callable(['self', 'm']) ? "self_yes" : "self_no");
        $out->send(is_callable(['static', 'm']) ? "static_yes" : "static_no");
        $out->send(is_callable(['parent', 'pm']) ? "parent_yes" : "parent_no");
        $out->send(is_callable('self::m') ? "str_yes" : "str_no");
        go self::m2($out);
    }
    public static function m2($out) {
        $out->send("spawned");
    }
}
$out = new Channel(5);
$sc = new ScopeCallable();
$sc->probe($out);
go_wait_all();
t("i.is_callable_self", $out->recv() === "self_yes");
t("i.is_callable_static", $out->recv() === "static_yes");
t("i.is_callable_parent", $out->recv() === "parent_yes");
t("i.is_callable_str", $out->recv() === "str_yes");
t("i.go_self_spawn", $out->recv() === "spawned");

$res->close();
echo "G13 DONE\n";
