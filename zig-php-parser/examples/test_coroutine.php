<?php

// 测试协程功能

echo "=== 测试协程系统 ===\n";

// 基本协程示例
// go function() {
//     echo "协程1开始\n";
//     sleep(100); // 休眠100ms
//     echo "协程1完成\n";
// };

// go function() {
//     echo "协程2开始\n";
//     sleep(50);
//     echo "协程2完成\n";
// };

// echo "主程序继续执行\n";

echo "\n=== 协程通信（Channel）===\n";

// Channel示例
// $ch = channel_create(10); // 创建容量为10的channel

// 生产者协程
// go function() use ($ch) {
//     for ($i = 1; $i <= 5; $i++) {
//         channel_send($ch, $i);
//         echo "发送: $i\n";
//         sleep(100);
//     }
//     channel_close($ch);
// };

// 消费者协程
// go function() use ($ch) {
//     while (true) {
//         $value = channel_recv($ch);
//         if ($value === null) break;
//         echo "接收: $value\n";
//     }
// };

echo "\n=== WaitGroup示例 ===\n";

// WaitGroup用于等待一组协程完成
// $wg = waitgroup_create();

// $wg->add(3);

// go function() use ($wg) {
//     echo "任务1执行\n";
//     sleep(100);
//     echo "任务1完成\n";
//     $wg->done();
// };

// go function() use ($wg) {
//     echo "任务2执行\n";
//     sleep(150);
//     echo "任务2完成\n";
//     $wg->done();
// };

// go function() use ($wg) {
//     echo "任务3执行\n";
//     sleep(200);
//     echo "任务3完成\n";
//     $wg->done();
// };

// echo "等待所有任务完成...\n";
// $wg->wait();
// echo "所有任务已完成\n";

echo "\n=== 协程上下文隔离 ===\n";

// 每个协程有独立的上下文，不会串数据
// $counter = 0;

// go function() use (&$counter) {
//     for ($i = 0; $i < 5; $i++) {
//         $counter++;
//         echo "协程A: $counter\n";
//         sleep(50);
//     }
// };

// go function() use (&$counter) {
//     for ($i = 0; $i < 5; $i++) {
//         $counter++;
//         echo "协程B: $counter\n";
//         sleep(50);
//     }
// };

echo "\n=== 协程互斥锁 ===\n";

// 使用互斥锁保护共享资源
// $mutex = mutex_create();
// $shared = 0;

// go function() use ($mutex, &$shared) {
//     for ($i = 0; $i < 100; $i++) {
//         $mutex->lock();
//         $shared++;
//         $mutex->unlock();
//     }
// };

// go function() use ($mutex, &$shared) {
//     for ($i = 0; $i < 100; $i++) {
//         $mutex->lock();
//         $shared++;
//         $mutex->unlock();
//     }
// };

// sleep(1000); // 等待协程完成
// echo "共享计数器: $shared\n"; // 应该是200

echo "\n=== 协程测试完成 ===\n";
echo "注意: 带注释的代码需要在VM中实现协程支持\n";
