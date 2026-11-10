<?php
// 验收组18c：go_wait_all 是同步点 ⇒ 未收取的协程异常按 D1=A 致命（rc=255）
function boom_wait() {
    throw new LogicException("waitall-fatal");
}
go('boom_wait');
go_wait_all();
echo "NOT_REACHED\n";
