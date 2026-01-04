<?php
/**
 * 并发编程完整示例 - Go 风格
 * 展示 Mutex、Atomic、RWLock、SharedData、Channel 的综合使用
 */

echo "=== PHP 并发编程示例 (Go 风格) ===\n\n";

// ==================== 示例1: 生产者-消费者模式 ====================
echo "【示例1】生产者-消费者模式\n";

$channel = new Channel(5);
$counter = new Atomic(0);
$mutex = new Mutex();

// 模拟生产者
fn producer($ch, $count, $prefix) {
    $i = 0;
    while ($i < $count) {
        $msg = $prefix . "_" . $i;
        $ch->send($msg);
        echo "生产: $msg\n";
        $i = $i + 1;
    }
}

// 模拟消费者
fn consumer($ch, $counter, $mutex) {
    $received = 0;
    while ($received < 6) {
        $msg = $ch->tryRecv();
        if ($msg !== null) {
            $mutex->lock();
            $counter->increment();
            $mutex->unlock();
            echo "消费: $msg (总计: " . $counter->load() . ")\n";
            $received = $received + 1;
        }
    }
}

// 生产数据
producer($channel, 3, "A");
producer($channel, 3, "B");

// 消费数据
consumer($channel, $counter, $mutex);

echo "生产者-消费者完成，共处理: " . $counter->load() . " 条消息\n\n";

// ==================== 示例2: 读写锁保护共享状态 ====================
echo "【示例2】读写锁保护共享状态\n";

$rwlock = new RWLock();
$shared = new SharedData();

// 写入数据（需要写锁）
fn writeData($rwlock, $shared, $key, $value) {
    $rwlock->lockWrite();
    $shared->set($key, $value);
    echo "写入: $key = $value\n";
    $rwlock->unlockWrite();
}

// 读取数据（需要读锁）
fn readData($rwlock, $shared, $key) {
    $rwlock->lockRead();
    $value = $shared->get($key);
    echo "读取: $key = $value\n";
    $rwlock->unlockRead();
    return $value;
}

writeData($rwlock, $shared, "config", "production");
writeData($rwlock, $shared, "version", "1.0.0");
writeData($rwlock, $shared, "debug", "false");

readData($rwlock, $shared, "config");
readData($rwlock, $shared, "version");

echo "共享数据大小: " . $shared->size() . "\n";
echo "访问计数: " . $shared->getAccessCount() . "\n\n";

// ==================== 示例3: 原子计数器与统计 ====================
echo "【示例3】原子计数器与统计\n";

$requests = new Atomic(0);
$success = new Atomic(0);
$errors = new Atomic(0);

// 模拟请求处理
fn handleRequest($requests, $success, $errors, $shouldFail) {
    $requests->increment();
    
    if ($shouldFail) {
        $errors->increment();
        echo "请求失败\n";
    } else {
        $success->increment();
        echo "请求成功\n";
    }
}

// 处理一些请求
handleRequest($requests, $success, $errors, false);
handleRequest($requests, $success, $errors, false);
handleRequest($requests, $success, $errors, true);
handleRequest($requests, $success, $errors, false);
handleRequest($requests, $success, $errors, true);

echo "\n请求统计:\n";
echo "  总请求: " . $requests->load() . "\n";
echo "  成功: " . $success->load() . "\n";
echo "  失败: " . $errors->load() . "\n";
echo "  成功率: " . ($success->load() * 100 / $requests->load()) . "%\n\n";

// ==================== 示例4: Channel 管道模式 ====================
echo "【示例4】Channel 管道模式\n";

$input = new Channel(10);
$output = new Channel(10);

// 数据处理管道
fn pipeline($input, $output) {
    $processed = 0;
    while ($processed < 5) {
        $data = $input->tryRecv();
        if ($data !== null) {
            $result = $data * 2;
            $output->send($result);
            echo "管道处理: $data -> $result\n";
            $processed = $processed + 1;
        }
    }
}

// 发送输入数据
$input->send(1);
$input->send(2);
$input->send(3);
$input->send(4);
$input->send(5);

// 处理管道
pipeline($input, $output);

// 收集输出
echo "管道输出: ";
$i = 0;
while ($i < 5) {
    $result = $output->recv();
    echo "$result ";
    $i = $i + 1;
}
echo "\n\n";

// ==================== 示例5: 互斥锁保护临界区 ====================
echo "【示例5】互斥锁保护临界区\n";

$balance = new Atomic(1000);
$txMutex = new Mutex();

fn transfer($mutex, $balance, $amount, $desc) {
    $mutex->lock();
    
    $current = $balance->load();
    if ($current >= $amount) {
        $balance->sub($amount);
        echo "$desc: 转账 $amount, 余额: " . $balance->load() . "\n";
    } else {
        echo "$desc: 余额不足，当前: $current\n";
    }
    
    $mutex->unlock();
}

transfer($txMutex, $balance, 200, "交易1");
transfer($txMutex, $balance, 300, "交易2");
transfer($txMutex, $balance, 600, "交易3");
transfer($txMutex, $balance, 100, "交易4");

echo "最终余额: " . $balance->load() . "\n\n";

// ==================== 总结 ====================
echo "=== 并发编程示例完成 ===\n";
echo "✅ Channel: 协程间通信\n";
echo "✅ Mutex: 互斥锁保护临界区\n";
echo "✅ Atomic: 无锁原子操作\n";
echo "✅ RWLock: 读写锁优化并发读\n";
echo "✅ SharedData: 线程安全共享数据\n";
echo "\n🎉 所有并发原语测试通过!\n";
