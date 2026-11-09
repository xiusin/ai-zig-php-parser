<?php
// F-1 修复守卫：Go 语句形 `go callee(args)` 保留 go_stmt ⇒ go_spawn 路径（不得回归）
function worker(string $name, int $a, int $b): void {
    echo $name, '=', $a + $b, "\n";
}
go worker('W3', 5, 6);   // Go 语句形：期望 W3=11（go_spawn 指令路径）
go_wait_all();
echo "DONE\n";
