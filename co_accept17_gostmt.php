<?php
// 验收组17：Go 语句形必须真 spawn（不得同步调用）
// a) `go worker(...)`：main 先继续，worker 后执行（并发语义）
// b) `go $fn(...)`：变量闭包 callee spawn，实参完整传递
// c) `go function(){...}(...)`：闭包字面量 callee spawn
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}
function worker_stmt($ev, $tag, $a, $b) {
    $ev->send("W:" . $tag . ":" . ($a + $b));
}

// ---- a) 裸函数名语句形 ----
$ev = new Channel(2);
go worker_stmt($ev, 'A', 5, 6);
$ev->send("main1");
go_wait_all();
$r1 = $ev->recv();
$r2 = $ev->recv();
t("a.spawn_order", $r1 === "main1" && $r2 === "W:A:11");

// ---- b) 变量闭包 callee ----
$ev2 = new Channel(2);
$fn = function ($ev, $x) {
    $ev->send("fn:" . $x);
};
go $fn($ev2, 'V');
$ev2->send("main2");
go_wait_all();
$r1 = $ev2->recv();
$r2 = $ev2->recv();
t("b.var_callable", $r1 === "main2" && $r2 === "fn:V");

// ---- c) 闭包字面量 callee ----
$ev3 = new Channel(2);
go function ($ev, $x) {
    $ev->send("lit:" . $x);
}($ev3, 'L');
$ev3->send("main3");
go_wait_all();
$r1 = $ev3->recv();
$r2 = $ev3->recv();
t("c.literal_closure", $r1 === "main3" && $r2 === "lit:L");

// ---- d) 语句形 spawn 的失败传播：未定义函数在 spawn 点抛可捕获 Error ----
$msg = "";
try {
    go undefined_stmt_fn('x');
} catch (Throwable $e) {
    $msg = $e->getMessage();
}
t("d.undefined_throw", $msg === 'Call to undefined function undefined_stmt_fn()');

// ---- e) 方法 callee：`go $obj->method(...)` 必须 spawn ----
class G17W {
    public $tag = "obj";
    public function run($ev, $x) {
        $ev->send("m:" . $this->tag . ":" . $x);
    }
    public static function stat($ev, $x) {
        $ev->send("s:" . $x);
    }
}
$ev4 = new Channel(2);
$w = new G17W();
go $w->run($ev4, 'A');
$ev4->send("main4");
go_wait_all();
$r1 = $ev4->recv();
$r2 = $ev4->recv();
t("e.method_spawn", $r1 === "main4" && $r2 === "m:obj:A");

// ---- f) 静态方法 callee：`go Class::method(...)` 必须 spawn ----
$ev5 = new Channel(2);
go G17W::stat($ev5, 'B');
$ev5->send("main5");
go_wait_all();
$r1 = $ev5->recv();
$r2 = $ev5->recv();
t("f.static_spawn", $r1 === "main5" && $r2 === "s:B");

// ---- g) `...` 展开：语句形 spawn 的实参摊平 ----
$ev6 = new Channel(2);
$args = [7, 8];
go worker_stmt($ev6, 'C', ...$args);
$ev6->send("main6");
go_wait_all();
$r1 = $ev6->recv();
$r2 = $ev6->recv();
t("g.spread_spawn", $r1 === "main6" && $r2 === "W:C:15");

// ---- h) 作用域限定符 callee：self:: / static:: / parent:: 必须在 spawn 点固化 ----
class G17Base {
    public static function greet($ev, $tag) {
        $ev->send($tag);
    }
}
class G17Child extends G17Base {
    public function run_scope($ev) {
        go self::greet($ev, 'self');
        go static::greet($ev, 'static');
        go parent::greet($ev, 'parent');
    }
}
$ev7 = new Channel(4);
$c = new G17Child();
$c->run_scope($ev7);
$ev7->send("main7");
go_wait_all();
$r1 = $ev7->recv();
$r2 = $ev7->recv();
$r3 = $ev7->recv();
$r4 = $ev7->recv();
$scope_ok = $r1 === "main7" && $r2 === "self" && $r3 === "static" && $r4 === "parent";
t("h.scope_qualifier", $scope_ok);

echo "G17 DONE\n";
