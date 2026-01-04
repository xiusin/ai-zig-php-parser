<?php
echo "测试 Mutex 类\n";

$mutex = new Mutex();
echo "Mutex 创建成功\n";

$mutex->lock();
echo "lock() 成功\n";

$count = $mutex->getLockCount();
echo "getLockCount() = $count\n";

$mutex->unlock();
echo "unlock() 成功\n";

echo "测试完成\n";
