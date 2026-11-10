<?php
// 验收组18b：go_join 不收异常 ⇒ 未收取的协程异常在 join 点按 D1=A 致命（rc=255）
function boom_join() {
    throw new RuntimeException("join-fatal");
}
$id = go('boom_join');
go_join($id);
echo "NOT_REACHED\n";
