<?php
// co_deadlock：单协程自发自收无缓冲 channel ⇒ 死锁致命（设计稿 §5 M1 探针 4）。
// 验收口径：进程 rc=255，stderr 含 "all coroutines are asleep - deadlock!"（Go 文案对齐）。
$ch = new Channel(0);
$ch->send(1); // 无接收者 ⇒ 永久阻塞 ⇒ 死锁检测
echo "co_deadlock FAIL: no deadlock detected\n";
