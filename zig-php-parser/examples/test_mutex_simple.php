<?php
echo "测试 Mutex 类\n";
$mutex = new Mutex();
echo "Mutex 创建成功\n";
$mutex->lock();
echo "lock() 调用成功\n";