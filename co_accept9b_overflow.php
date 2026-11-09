<?php
// 验收组9b：协程内递归冲破 64KB 栈边界 ⇒ 保护页触发明确致命错（非静默踩栈）
// 预期：Fatal error: stack overflow in coroutine #N (guard page hit)，rc=255
function deep($n) {
    if ($n <= 0) {
        return 0;
    }
    return 1 + deep($n - 1);
}
function victim($ev) {
    $ev->send("START");
    $r = deep(200000);
    $ev->send("R:" . $r);
}
$ev = new Channel(4);
go('victim', $ev);
go_wait_all();
echo "SHOULD-NOT-REACH\n";
