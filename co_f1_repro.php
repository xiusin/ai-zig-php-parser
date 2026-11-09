<?php
// F-1 复现探针：裸 go(...) 语句多实参不得静默丢参（AOT-CODEGEN-012 §7 F-1）
// 修复前：parseGo 把 ($f, 1, 2) 当括号表达式逗号折叠 ⇒ callable 变成末值，静默丢参
// 修复后：分流 function_call，与赋值形同路径
function worker(string $name, int $a, int $b): void {
    echo $name, '=', $a + $b, "\n";
}
go('worker', 'W1', 10, 20);        // 裸语句形（修复目标）：期望 W1=30
$id = go('worker', 'W2', 1, 2);    // 赋值形（预存正常）：期望 W2=3
go_wait_all();
echo "DONE\n";
