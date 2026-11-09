<?php
// 临时探针：变量持有的闭包/函数名字符串作为 go 体（Ref 化口径）
function cb_fn($res) {
    $res->send('named');
}
function t($name, $cond) {
    if ($cond) {
        echo "ok $name\n";
    } else {
        echo "FAIL $name\n";
    }
}
$res = new Channel(4);
$fn = function () use ($res) {
    $res->send('var-closure');
};
go($fn);
go_wait_all();
t("var_closure", $res->tryRecv() === 'var-closure');
$name = 'cb_fn';
go($name, $res);
go_wait_all();
t("var_fnname", $res->tryRecv() === 'named');
$res->close();
echo "DONE\n";
