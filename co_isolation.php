<?php
// co_isolation：协程内 throw 自捕获、异常旗/@抑制深度/作用域与 main 互不串扰（设计稿 §5 M1 探针 6）。
function worker($ch) {
    // 协程内 throw 并自捕获：异常旗私有，不外溢
    try {
        throw new LogicException("inner");
    } catch (LogicException $e) {
        $ch->send("caught:" . $e->getMessage());
    }
    // @ 抑制在协程内独立生效（不回流 main）
    @$u = $co_undef_var_isolation;
    $ch->send("suppress-ok");
    return 7;
}
$ch = new Channel(2);
$id = go('worker', $ch);
$m1 = $ch->recv();
$m2 = $ch->recv();
go_join($id);

$ok = ($m1 === "caught:inner") && ($m2 === "suppress-ok");

// 异常旗隔离：协程已自捕获，main 的异常通道必须干净——main 自抛自捕验证路由不错位
try {
    throw new InvalidArgumentException("main-own");
} catch (InvalidArgumentException $e) {
    $ok = $ok && ($e->getMessage() === "main-own");
}

// @ 抑制隔离：main 未压 @，未定义变量必须照常出 Warning（由运行器 grep 佐证）
$probe = $main_undef_var_isolation;

echo $ok ? "co_isolation PASS\n" : "co_isolation FAIL m1=$m1 m2=$m2\n";
