<?php
// 验收组18a：go_join_error 异常收取面（D1=B 可选，不破坏 D1=A）
// 覆盖：类型/消息、二次收取 null、正常协程 null、多失败逐枚收取、
//       未知 id、动态调用、协程内收取子协程异常、收取后 wait_all 不致命。
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}
function boom_err($tag) {
    throw new RuntimeException("fail-" . $tag);
}
function ok_fn($ev) {
    $ev->send("ok");
}
function child_fail() {
    throw new Exception("nested");
}
function parent_collect($res) {
    $cid = go('child_fail');
    $e = go_join_error($cid);
    if ($e === null) {
        $res->send("null");
    } else {
        $res->send($e->getMessage());
    }
}

// ---- a) 单个失败：类型 + 消息；二次收取为 null ----
$id1 = go('boom_err', 'A');
$e1 = go_join_error($id1);
t("a.type", $e1 instanceof RuntimeException);
t("a.msg", $e1 !== null && $e1->getMessage() === "fail-A");
t("a.second_null", go_join_error($id1) === null);

// ---- b) 正常结束 ⇒ null；协程副作用已生效 ----
$ev = new Channel(1);
$id2 = go('ok_fn', $ev);
t("b.null", go_join_error($id2) === null);
t("b.side", $ev->recv() === "ok");

// ---- c) 多协程多失败：逐枚收取互不串扰 ----
$ids = [];
for ($i = 0; $i < 3; $i++) {
    $ids[] = go('boom_err', "M" . $i);
}
$m0 = "";
$m1 = "";
$m2 = "";
$k = 0;
foreach ($ids as $id) {
    $e = go_join_error($id);
    $msg = $e === null ? "null" : $e->getMessage();
    if ($k === 0) {
        $m0 = $msg;
    } elseif ($k === 1) {
        $m1 = $msg;
    } else {
        $m2 = $msg;
    }
    $k++;
}
t("c.all", $m0 === "fail-M0" && $m1 === "fail-M1" && $m2 === "fail-M2");

// ---- d) 未知 id ⇒ null ----
t("d.unknown", go_join_error(999999) === null);

// ---- e) 动态调用面（$f(...)）----
$f = 'go_join_error';
$id3 = go('boom_err', 'DYN');
$e3 = $f($id3);
t("e.dynamic", $e3 instanceof RuntimeException && $e3->getMessage() === "fail-DYN");

// ---- f) 协程内收取子协程异常 ----
$res = new Channel(1);
go('parent_collect', $res);
t("f.nested", $res->recv() === "nested");

// ---- g) 全部收取后 wait_all 不致命（能打印 DONE 即证）----
go_wait_all();
echo "G18A DONE\n";
