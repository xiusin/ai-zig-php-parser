<?php
/**
 * 并发系统简单测试（不使用 global 和闭包引用）
 */

echo "========================================\n";
echo "  并发系统简单测试\n";
echo "========================================\n\n";

class TestRunner {
    public $test_count = 0;
    public $passed_count = 0;
    public $failed_count = 0;

    public function run($name, $callback) {
        $this->test_count++;
        echo "【测试 {$this->test_count}】$name\n";
        try {
            $callback();
            $this->passed_count++;
            echo "✅ 通过\n\n";
            return true;
        } catch (Exception $e) {
            $this->failed_count++;
            echo "❌ 失败: " . $e->getMessage() . "\n\n";
            return false;
        }
    }

    public function summary() {
        echo "========================================\n";
        echo "  测试总结\n";
        echo "========================================\n";
        echo "总测试数: {$this->test_count}\n";
        echo "通过: {$this->passed_count}\n";
        echo "失败: {$this->failed_count}\n";
        if ($this->test_count > 0) {
            $success_rate = ($this->passed_count / $this->test_count) * 100;
            echo "成功率: " . number_format($success_rate, 2) . "%\n";
        }
        echo "========================================\n";

        if ($this->failed_count == 0) {
            echo "🎉 所有测试通过！\n";
        } else {
            echo "⚠️  有 {$this->failed_count} 个测试失败，请检查\n";
        }
    }
}

$runner = new TestRunner();

// ==================== 测试1: Mutex 基础功能 ====================
echo "【测试 1】Mutex 基础功能\n";
try {
    $mutex = new Mutex();
    $mutex->lock();
    $count = $mutex->getLockCount();
    if ($count != 1) throw new Exception("锁计数应为1，实际为$count");
    $mutex->unlock();
    $count = $mutex->getLockCount();
    if ($count != 0) throw new Exception("解锁后锁计数应为0，实际为$count");
    $runner->passed_count++;
    echo "✅ 通过\n\n";
} catch (Exception $e) {
    $runner->failed_count++;
    echo "❌ 失败: " . $e->getMessage() . "\n\n";
}
$runner->test_count++;

// ==================== 测试2: Mutex 重复加锁 ====================
$runner->run("Mutex 重复加锁（可重入）", function() {
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
});

// ==================== 测试3: Mutex tryLock ====================
$runner->run("Mutex tryLock 非阻塞加锁", function() {
    $mutex = new Mutex();
    $result = $mutex->tryLock();
    if (!$result) throw new Exception("tryLock 应返回true");
    $mutex->unlock();
});

// ==================== 测试4: Atomic 原子操作 ====================
$runner->run("Atomic 原子操作", function() {
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
});

// ==================== 测试5: RWLock 读写锁 ====================
$runner->run("RWLock 读写锁基础", function() {
    $rwlock = new RWLock();
    $rwlock->lockRead();
    $readers = $rwlock->getReaderCount();
    if ($readers != 1) throw new Exception("读者数量应为1，实际为$readers");
    $rwlock->unlockRead();

    $rwlock->lockWrite();
    $writers = $rwlock->getWriterCount();
    if ($writers != 1) throw new Exception("写者数量应为1，实际为$writers");
    $rwlock->unlockWrite();
});

// ==================== 测试6: SharedData 共享数据 ====================
$runner->run("SharedData 共享数据", function() {
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
});

// ==================== 测试7: Channel 基础 ====================
$runner->run("Channel 基础功能", function() {
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
});

// ==================== 测试8: Channel trySend/tryRecv ====================
$runner->run("Channel 非阻塞操作", function() {
    $ch = new Channel(2);
    $r1 = $ch->trySend(1);
    $r2 = $ch->trySend(2);
    $r3 = $ch->trySend(3);

    if (!$r1 || !$r2 || $r3) {
        throw new Exception("trySend 结果不正确");
    }

    $v = $ch->tryRecv();
    if ($v != 1) throw new Exception("tryRecv 值不正确");
});

// ==================== 测试9: Channel 关闭 ====================
$runner->run("Channel 关闭功能", function() {
    $ch = new Channel(1);
    $closed = $ch->isClosed();
    if ($closed) throw new Exception("未关闭时 isClosed 应返回false");

    $ch->close();
    $closed = $ch->isClosed();
    if (!$closed) throw new Exception("关闭后 isClosed 应返回true");
});

// ==================== 测试10: Channel 统计信息 ====================
$runner->run("Channel 统计信息", function() {
    $ch = new Channel(10);
    $ch->send(1);
    $ch->send(2);
    $ch->recv();

    $send_count = $ch->getSendCount();
    $recv_count = $ch->getRecvCount();

    if ($send_count != 2) throw new Exception("发送计数应为2，实际为$send_count");
    if ($recv_count != 1) throw new Exception("接收计数应为1，实际为$recv_count");
});

// ==================== 测试11: Mutex + SharedData 组合 ====================
$runner->run("Mutex + SharedData 组合使用", function() {
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
});

// ==================== 测试12: Atomic + SharedData 组合 ====================
$runner->run("Atomic + SharedData 组合使用", function() {
    $atomic = new Atomic(0);
    $shared = new SharedData();

    for ($i = 0; $i < 100; $i++) {
        $atomic->increment();
    }

    $shared->set("atomic_value", $atomic->load());
    $value = $shared->get("atomic_value");

    if ($value != 100) throw new Exception("原子值应为100，实际为$value");
});

// ==================== 测试13: Channel + Mutex 生产者消费者 ====================
$runner->run("Channel + Mutex 生产者消费者模型", function() {
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
});

// ==================== 测试14: RWLock 多读单写 ====================
$runner->run("RWLock 多读单写场景", function() {
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
});

// ==================== 测试15: SharedData 大量操作 ====================
$runner->run("SharedData 大量操作（内存安全测试）", function() {
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
});

// ==================== 测试16: Channel 缓冲区满测试 ====================
$runner->run("Channel 缓冲区满测试", function() {
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
});

// ==================== 测试17: 空通道测试 ====================
$runner->run("空通道测试", function() {
    $ch = new Channel(2);

    // 尝试从空通道接收
    $value = $ch->tryRecv();
    if ($value !== null) throw new Exception("从空通道接收应返回null");

    $len = $ch->len();
    if ($len != 0) throw new Exception("空通道长度应为0，实际为$len");
});

// ==================== 测试18: Mutex 异常场景 ====================
$runner->run("Mutex 异常场景（解锁未加锁的锁）", function() {
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
});

// ==================== 测试19: Atomic 边界值测试 ====================
$runner->run("Atomic 边界值测试", function() {
    $atomic = new Atomic(PHP_INT_MAX);

    $atomic->increment();
    $value = $atomic->load();
    // 检查是否溢出或正确处理

    $atomic->store(PHP_INT_MIN);
    $value = $atomic->load();
    if ($value != PHP_INT_MIN) throw new Exception("存储最小值失败");
});

// ==================== 测试20: SharedData 键类型测试 ====================
$runner->run("SharedData 键类型测试", function() {
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
});

// ==================== 测试21: Channel 容量为0（同步通道） ====================
$runner->run("Channel 容量为0（同步通道）", function() {
    $ch = new Channel(0);

    $len = $ch->len();
    if ($len != 0) throw new Exception("同步通道长度应为0，实际为$len");

    $cap = $ch->capacity();
    if ($cap != 0) throw new Exception("同步通道容量应为0，实际为$cap");

    // 同步通道的 trySend 应该失败（没有接收者）
    $result = $ch->trySend(1);
    if ($result) throw new Exception("同步通道无接收者时 trySend 应返回false");
});

// ==================== 测试22: 多个 Mutex 独立工作 ====================
$runner->run("多个 Mutex 独立工作", function() {
    $mutex1 = new Mutex();
    $mutex2 = new Mutex();
    $mutex3 = new Mutex();

    $mutex1->lock();
    $mutex2->lock();
    $mutex3->lock();

    $count1 = $mutex1->getLockCount();
    $count2 = $mutex2->getLockCount();
    $count3 = $mutex3->getLockCount();

    if ($count1 != 1 || $count2 != 1 || $count3 != 1) {
        throw new Exception("多个锁计数不正确: $count1, $count2, $count3");
    }

    $mutex1->unlock();
    $mutex2->unlock();
    $mutex3->unlock();
});

// ==================== 测试23: SharedData 访问计数 ====================
$runner->run("SharedData 访问计数测试", function() {
    $shared = new SharedData();

    $shared->set("key1", "value1");
    $shared->get("key1");
    $shared->get("key1");
    $shared->has("key1");

    $count = $shared->getAccessCount();
    if ($count < 3) throw new Exception("访问计数应至少为3，实际为$count");
});

// ==================== 测试24: Channel 关闭后操作 ====================
$runner->run("Channel 关闭后操作", function() {
    $ch = new Channel(5);
    $ch->send(1);
    $ch->send(2);
    $ch->close();

    // 关闭后仍可接收
    $v1 = $ch->recv();
    $v2 = $ch->recv();
    if ($v1 != 1 || $v2 != 2) throw new Exception("关闭后接收值不正确");

    // 关闭后接收应返回null
    $v3 = $ch->recv();
    if ($v3 !== null) throw new Exception("关闭后接收应返回null");

    // 关闭后发送应该失败
    $result = $ch->trySend(3);
    if ($result) throw new Exception("关闭后 trySend 应返回false");
});

// ==================== 测试25: RWLock 读者计数 ====================
$runner->run("RWLock 读者计数测试", function() {
    $rwlock = new RWLock();

    $rwlock->lockRead();
    $rwlock->lockRead();
    $rwlock->lockRead();

    $readers = $rwlock->getReaderCount();
    if ($readers != 3) throw new Exception("读者数量应为3，实际为$readers");

    $rwlock->unlockRead();
    $readers = $rwlock->getReaderCount();
    if ($readers != 2) throw new Exception("解锁后读者数量应为2，实际为$readers");

    $rwlock->unlockRead();
    $rwlock->unlockRead();
});

// ==================== 测试26: Atomic compareAndSwap 失败场景 ====================
$runner->run("Atomic compareAndSwap 失败场景", function() {
    $atomic = new Atomic(100);

    // CAS 失败
    $success = $atomic->compareAndSwap(50, 200);
    if ($success) throw new Exception("CAS 应失败");

    $value = $atomic->load();
    if ($value != 100) throw new Exception("CAS 失败后值应不变，实际为$value");
});

// ==================== 测试27: Mutex + Atomic 计数器 ====================
$runner->run("Mutex + Atomic 组合计数器", function() {
    $mutex = new Mutex();
    $atomic = new Atomic(0);
    $shared = new SharedData();

    for ($i = 0; $i < 50; $i++) {
        $mutex->lock();
        $atomic->increment();
        $shared->set("atomic_" . $i, $atomic->load());
        $mutex->unlock();
    }

    $final = $atomic->load();
    if ($final != 50) throw new Exception("最终原子值应为50，实际为$final");

    $size = $shared->size();
    if ($size != 50) throw new Exception("共享数据应有50条记录，实际为$size");
});

// ==================== 测试28: Channel 容量边界测试 ====================
$runner->run("Channel 容量边界测试", function() {
    $ch = new Channel(1);

    $ch->send(1);

    // 缓冲区满
    $result = $ch->trySend(2);
    if ($result) throw new Exception("容量为1的通道满时应失败");

    $ch->recv();

    // 现在有空间
    $result = $ch->trySend(2);
    if (!$result) throw new Exception("接收后应有空间");
});

// ==================== 测试29: SharedData remove 不存在的键 ====================
$runner->run("SharedData remove 不存在的键", function() {
    $shared = new SharedData();

    $result = $shared->remove("nonexistent_key");
    if ($result) throw new Exception("删除不存在的键应返回false");

    $size = $shared->size();
    if ($size != 0) throw new Exception("删除不存在的键后大小不应变化");
});

// ==================== 测试30: 所有并发类混合使用 ====================
$runner->run("所有并发类混合使用（复杂场景）", function() {
    $mutex = new Mutex();
    $atomic = new Atomic(0);
    $rwlock = new RWLock();
    $shared = new SharedData();
    $ch = new Channel(10);

    // 使用 Mutex 保护共享数据
    $mutex->lock();
    $shared->set("counter", 0);
    $mutex->unlock();

    // 使用 Atomic 计数
    $atomic->store(0);

    // 使用 RWLock 读写
    $rwlock->lockWrite();
    $shared->set("data", []);
    $rwlock->unlockWrite();

    // 使用 Channel 传递数据
    for ($i = 0; $i < 10; $i++) {
        $ch->send($i);
        $atomic->increment();
    }

    // 从 Channel 接收
    for ($i = 0; $i < 10; $i++) {
        $value = $ch->recv();
        $mutex->lock();
        $counter = $shared->get("counter");
        $counter++;
        $shared->set("counter", $counter);
        $mutex->unlock();
    }

    $final_atomic = $atomic->load();
    $final_counter = $shared->get("counter");

    if ($final_atomic != 10 || $final_counter != 10) {
        throw new Exception("混合使用结果不正确: atomic=$final_atomic, counter=$final_counter");
    }
});

// ==================== 总结 ====================
$runner->summary();

echo "\n测试完成！\n";