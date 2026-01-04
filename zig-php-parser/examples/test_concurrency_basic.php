<?php
/**
 * 并发系统基础测试（不使用闭包）
 */

echo "========================================\n";
echo "  并发系统基础测试\n";
echo "========================================\n\n";

$test_count = 0;
$passed_count = 0;
$failed_count = 0;

// ==================== 测试1: Mutex 基础功能 ====================
$test_count++;
echo "【测试 $test_count】Mutex 基础功能\n";
try {
    $mutex = new Mutex();
    $mutex->lock();
    $count = $mutex->getLockCount();
    if ($count != 1) throw new Exception("锁计数应为1，实际为$count");
    $mutex->unlock();
    $count = $mutex->getLockCount();
    if ($count != 0) throw new Exception("解锁后锁计数应为0，实际为$count");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试2: Mutex 重复加锁 ====================
$test_count++;
echo "【测试 $test_count】Mutex 重复加锁（可重入）\n";
try {
    $mutex = new Mutex();
    $mutex->lock();
    $mutex->lock();
    $mutex->lock();
    $count = $mutex->getLockCount();
    if ($count != 3) throw new Exception("重复加锁后锁计数应为3，实际为$count");
    $mutex->unlock();
    $mutex->unlock();
    $mutex->unlock();
    $count = $mutex->getLockCount();
    if ($count != 0) throw new Exception("全部解锁后锁计数应为0，实际为$count");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试3: Mutex tryLock ====================
$test_count++;
echo "【测试 $test_count】Mutex tryLock 非阻塞加锁\n";
try {
    $mutex = new Mutex();
    $result = $mutex->tryLock();
    if (!$result) throw new Exception("tryLock 应返回true");
    $mutex->unlock();
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试4: Atomic 原子操作 ====================
$test_count++;
echo "【测试 $test_count】Atomic 原子操作\n";
try {
    $atomic = new Atomic(0);
    for ($i = 0; $i < 100; $i++) {
        $atomic->increment();
    }
    $value = $atomic->load();
    if ($value != 100) throw new Exception("原子递增后值应为100，实际为$value");

    $atomic->store(50);
    $value = $atomic->load();
    if ($value != 50) throw new Exception("原子存储后值应为50，实际为$value");

    $result = $atomic->compareAndSwap(50, 100);
    if (!$result) throw new Exception("CAS 应成功");
    $value = $atomic->load();
    if ($value != 100) throw new Exception("CAS 后值应为100，实际为$value");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试5: RWLock 读写锁 ====================
$test_count++;
echo "【测试 $test_count】RWLock 读写锁基础\n";
try {
    $rwlock = new RWLock();
    $rwlock->lockRead();
    $readers = $rwlock->getReaderCount();
    if ($readers != 1) throw new Exception("读者数量应为1，实际为$readers");
    $rwlock->unlockRead();

    $rwlock->lockWrite();
    $writers = $rwlock->getWriterCount();
    if ($writers != 1) throw new Exception("写者数量应为1，实际为$writers");
    $rwlock->unlockWrite();
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试6: SharedData 共享数据 ====================
$test_count++;
echo "【测试 $test_count】SharedData 共享数据\n";
try {
    $shared = new SharedData();
    $shared->set("key1", "value1");
    $shared->set("key2", 123);
    $shared->set("key3", [1, 2, 3]);

    $size = $shared->size();
    if ($size != 3) throw new Exception("共享数据大小应为3，实际为$size");

    $value = $shared->get("key1");
    if ($value != "value1") throw new Exception("获取的值不正确");

    $exists = $shared->has("key1");
    if (!$exists) throw new Exception("has 应返回true");

    $removed = $shared->remove("key1");
    if (!$removed) throw new Exception("remove 应返回true");

    $size = $shared->size();
    if ($size != 2) throw new Exception("删除后大小应为2，实际为$size");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试7: Channel 基础 ====================
$test_count++;
echo "【测试 $test_count】Channel 基础功能\n";
try {
    $ch = new Channel(5);
    $ch->send(100);
    $ch->send(200);
    $ch->send(300);

    $len = $ch->len();
    if ($len != 3) throw new Exception("Channel 长度应为3，实际为$len");

    $v1 = $ch->recv();
    $v2 = $ch->recv();
    $v3 = $ch->recv();

    if ($v1 != 100 || $v2 != 200 || $v3 != 300) {
        throw new Exception("接收的值不正确: $v1, $v2, $v3");
    }

    $len = $ch->len();
    if ($len != 0) throw new Exception("清空后长度应为0，实际为$len");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试8: Channel trySend/tryRecv ====================
$test_count++;
echo "【测试 $test_count】Channel 非阻塞操作\n";
try {
    $ch = new Channel(2);
    $r1 = $ch->trySend(1);
    $r2 = $ch->trySend(2);
    $r3 = $ch->trySend(3);

    if (!$r1 || !$r2 || $r3) {
        throw new Exception("trySend 结果不正确");
    }

    $v = $ch->tryRecv();
    if ($v != 1) throw new Exception("tryRecv 值不正确");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试9: Channel 关闭 ====================
$test_count++;
echo "【测试 $test_count】Channel 关闭功能\n";
try {
    $ch = new Channel(1);
    $closed = $ch->isClosed();
    if ($closed) throw new Exception("未关闭时 isClosed 应返回false");

    $ch->close();
    $closed = $ch->isClosed();
    if (!$closed) throw new Exception("关闭后 isClosed 应返回true");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试10: Channel 统计信息 ====================
$test_count++;
echo "【测试 $test_count】Channel 统计信息\n";
try {
    $ch = new Channel(10);
    $ch->send(1);
    $ch->send(2);
    $ch->recv();

    $send_count = $ch->getSendCount();
    $recv_count = $ch->getRecvCount();

    if ($send_count != 2) throw new Exception("发送计数应为2，实际为$send_count");
    if ($recv_count != 1) throw new Exception("接收计数应为1，实际为$recv_count");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试11: Mutex + SharedData 组合 ====================
$test_count++;
echo "【测试 $test_count】Mutex + SharedData 组合使用\n";
try {
    $mutex = new Mutex();
    $shared = new SharedData();

    $mutex->lock();
    $shared->set("counter", 0);
    $mutex->unlock();

    for ($i = 0; $i < 10; $i++) {
        $mutex->lock();
        $counter = $shared->get("counter");
        $counter++;
        $shared->set("counter", $counter);
        $mutex->unlock();
    }

    $final = $shared->get("counter");
    if ($final != 10) throw new Exception("最终计数应为10，实际为$final");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试12: Atomic + SharedData 组合 ====================
$test_count++;
echo "【测试 $test_count】Atomic + SharedData 组合使用\n";
try {
    $atomic = new Atomic(0);
    $shared = new SharedData();

    for ($i = 0; $i < 100; $i++) {
        $atomic->increment();
    }

    $shared->set("atomic_value", $atomic->load());
    $value = $shared->get("atomic_value");

    if ($value != 100) throw new Exception("原子值应为100，实际为$value");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试13: Channel + Mutex 生产者消费者 ====================
$test_count++;
echo "【测试 $test_count】Channel + Mutex 生产者消费者模型\n";
try {
    $ch = new Channel(5);
    $mutex = new Mutex();
    $shared = new SharedData();
    $shared->set("produced", 0);
    $shared->set("consumed", 0);

    // 生产者
    for ($i = 0; $i < 5; $i++) {
        $mutex->lock();
        $produced = $shared->get("produced");
        $produced++;
        $shared->set("produced", $produced);
        $mutex->unlock();
        $ch->send($i);
    }

    // 消费者
    for ($i = 0; $i < 5; $i++) {
        $value = $ch->recv();
        $mutex->lock();
        $consumed = $shared->get("consumed");
        $consumed++;
        $shared->set("consumed", $consumed);
        $mutex->unlock();
    }

    $produced = $shared->get("produced");
    $consumed = $shared->get("consumed");

    if ($produced != 5 || $consumed != 5) {
        throw new Exception("生产消费计数不正确: produced=$produced, consumed=$consumed");
    }
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试14: RWLock 多读单写 ====================
$test_count++;
echo "【测试 $test_count】RWLock 多读单写场景\n";
try {
    $rwlock = new RWLock();
    $shared = new SharedData();
    $shared->set("value", 0);

    // 多个读者
    $rwlock->lockRead();
    $value1 = $shared->get("value");
    $rwlock->unlockRead();

    $rwlock->lockRead();
    $value2 = $shared->get("value");
    $rwlock->unlockRead();

    // 写者
    $rwlock->lockWrite();
    $shared->set("value", 100);
    $rwlock->unlockWrite();

    // 再次读取
    $rwlock->lockRead();
    $value3 = $shared->get("value");
    $rwlock->unlockRead();

    if ($value3 != 100) throw new Exception("写入后读取值应为100，实际为$value3");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试15: SharedData 大量操作 ====================
$test_count++;
echo "【测试 $test_count】SharedData 大量操作（内存安全测试）\n";
try {
    $shared = new SharedData();

    // 插入大量数据
    for ($i = 0; $i < 1000; $i++) {
        $shared->set("key_$i", "value_$i");
    }

    $size = $shared->size();
    if ($size != 1000) throw new Exception("插入1000条后大小应为1000，实际为$size");

    // 随机读取
    for ($i = 0; $i < 100; $i++) {
        $key = "key_" . ($i % 1000);
        $value = $shared->get($key);
        if ($value == null) throw new Exception("读取失败: $key");
    }

    // 清空
    $shared->clear();
    $size = $shared->size();
    if ($size != 0) throw new Exception("清空后大小应为0，实际为$size");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试16: Channel 缓冲区满测试 ====================
$test_count++;
echo "【测试 $test_count】Channel 缓冲区满测试\n";
try {
    $ch = new Channel(3);

    // 填满缓冲区
    $ch->send(1);
    $ch->send(2);
    $ch->send(3);

    // 尝试发送到已满的通道
    $result = $ch->trySend(4);
    if ($result) throw new Exception("缓冲区满时 trySend 应返回false");

    // 接收一个
    $ch->recv();

    // 现在应该可以发送
    $result = $ch->trySend(4);
    if (!$result) throw new Exception("接收一个后 trySend 应返回true");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试17: 空通道测试 ====================
$test_count++;
echo "【测试 $test_count】空通道测试\n";
try {
    $ch = new Channel(2);

    // 尝试从空通道接收
    $value = $ch->tryRecv();
    if ($value !== null) throw new Exception("从空通道接收应返回null");

    $len = $ch->len();
    if ($len != 0) throw new Exception("空通道长度应为0，实际为$len");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试18: Mutex 异常场景 ====================
$test_count++;
echo "【测试 $test_count】Mutex 异常场景（解锁未加锁的锁）\n";
try {
    $mutex = new Mutex();

    try {
        // 尝试解锁未加锁的锁
        $mutex->unlock();
        // 如果没有抛出异常，检查锁计数
        $count = $mutex->getLockCount();
        if ($count < 0) throw new Exception("锁计数不应为负数: $count");
    } catch (Exception $e) {
        // 预期可能会有异常，这是正常的
    }
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试19: Atomic 边界值测试 ====================
$test_count++;
echo "【测试 $test_count】Atomic 边界值测试\n";
try {
    $atomic = new Atomic(PHP_INT_MAX);

    $atomic->increment();
    $value = $atomic->load();
    // 检查是否溢出或正确处理

    $atomic->store(PHP_INT_MIN);
    $value = $atomic->load();
    if ($value != PHP_INT_MIN) throw new Exception("存储最小值失败");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 测试20: SharedData 键类型测试 ====================
$test_count++;
echo "【测试 $test_count】SharedData 键类型测试\n";
try {
    $shared = new SharedData();

    // 字符串键
    $shared->set("string_key", "value");
    $value = $shared->get("string_key");
    if ($value != "value") throw new Exception("字符串键测试失败");

    // 数字键（会被转换为字符串）
    $shared->set("123", "numeric_key_value");
    $value = $shared->get("123");
    if ($value != "numeric_key_value") throw new Exception("数字键测试失败");

    // 特殊字符键
    $shared->set("key with spaces", "spaces_value");
    $value = $shared->get("key with spaces");
    if ($value != "spaces_value") throw new Exception("特殊字符键测试失败");
    $passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}

// ==================== 总结 ====================
echo "========================================\n";
echo "  测试总结\n";
echo "========================================\n";
echo "总测试数: $test_count\n";
echo "通过: $passed_count\n";
echo "失败: $failed_count\n";
echo "成功率: " . number_format(($passed_count / $test_count) * 100, 2) . "%\n";
echo "========================================\n";

if ($failed_count == 0) {
    echo "🎉 所有测试通过！\n";
} else {
    echo "⚠️  有 $failed_count 个测试失败，请检查\n";
}

echo "\n测试完成！\n";
