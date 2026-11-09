<?php
// 验收组6a：协程内未捕获异常 ⇒ 整程序致命（D1=A），rc=255，文案含协程 id
// 预期：先打印 worker 正常运行，然后 fatal: uncaught RuntimeException ... in coroutine #N，rc=255
function thrower() {
    throw new RuntimeException("boom-in-coroutine");
}
go('thrower');
go_wait_all();
echo "SHOULD-NOT-REACH\n";
