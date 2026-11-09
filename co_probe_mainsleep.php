<?php
// 临时探针：main 内 sleep/usleep 与活跃协程的交互（当前 D5=A 口径取证）
$GLOBALS['ran'] = 0;
function worker_ms() {
    $GLOBALS['ran'] = 1;
}
go('worker_ms');
usleep(100000);
echo "after_sleep ran=" . $GLOBALS['ran'] . "\n";
go_wait_all();
echo "after_wait ran=" . $GLOBALS['ran'] . "\n";
echo "DONE\n";
