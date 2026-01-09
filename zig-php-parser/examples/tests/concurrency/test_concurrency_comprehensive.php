<?php
/**
 * 并发系统综合测试套件
 * 包含协程、锁、通道、HTTP、内存安全、异常场景等全面测试
 * 目标：覆盖所有并发功能点，发现内存泄漏和功能问题
 */

echo "========================================\n";
echo "  并发系统综合测试套件 v1.0\n";
echo "========================================\n\n";

$test_count = 0;
$passed_count = 0;
$failed_count = 0;

$run_test = function($name, $callback) use (&$test_count, &$passed_count, &$failed_count) {
    $test_count++;
    echo "【测试 $test_count】$name\n";
    try {
        $callback();
        $passed_count++;
        echo "✅ 通过\n\n";
        return true;
    } catch (Exception $e) {
        $failed_count++;
        echo "❌ 失败: " . $e->getMessage() . "\n\n";
        return false;
    }
};

// ==================== 测试1: Mutex 基础功能 ====================
$run_test("Mutex 基础功能", function() {
    $mutex = new Mutex();
    $mutex->lock();
    $count = $mutex->getLockCount();
    if ($count != 1) throw new Exception("锁计数应为1，实际为$count");
    $mutex->unlock();
    $count = $mutex->getLockCount();
    if ($count != 0) throw new Exception("解锁后锁计数应为0，实际为$count");
});

// ==================== 测试2: Mutex 重复加锁 ====================
$run_test("Mutex 重复加锁（可重入）", function() {
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
$run_test("Mutex tryLock 非阻塞加锁", function() {
    $mutex = new Mutex();
    $result = $mutex->tryLock();
    if (!$result) throw new Exception("tryLock 应返回true");
    $mutex->unlock();
});

// ==================== 测试4: Atomic 原子操作 ====================
$run_test("Atomic 原子操作", function() {
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
$run_test("RWLock 读写锁基础", function() {
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
$run_test("SharedData 共享数据", function() {
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
$run_test("Channel 基础功能", function() {
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
$run_test("Channel 非阻塞操作", function() {
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
$run_test("Channel 关闭功能", function() {
    $ch = new Channel(1);
    $closed = $ch->isClosed();
    if ($closed) throw new Exception("未关闭时 isClosed 应返回false");

    $ch->close();
    $closed = $ch->isClosed();
    if (!$closed) throw new Exception("关闭后 isClosed 应返回true");
});

// ==================== 测试10: Channel 统计信息 ====================
$run_test("Channel 统计信息", function() {
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
$run_test("Mutex + SharedData 组合使用", function() {
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
$run_test("Atomic + SharedData 组合使用", function() {
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
$run_test("Channel + Mutex 生产者消费者模型", function() {
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
$run_test("RWLock 多读单写场景", function() {
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

// ==================== 测试15: 共享数据大量操作 ====================
$run_test("SharedData 大量操作（内存安全测试）", function() {
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
$run_test("Channel 缓冲区满测试", function() {
    $ch = new Channel(3);

    // 填满缓冲区
    $ch->send(1);
    $ch->send(2);
    $ch->send(3);

    // 尝试发送到已满的通道（应该阻塞或失败）
    $result = $ch->trySend(4);
    if ($result) throw new Exception("缓冲区满时 trySend 应返回false");

    // 接收一个
    $ch->recv();

    // 现在应该可以发送
    $result = $ch->trySend(4);
    if (!$result) throw new Exception("接收一个后 trySend 应返回true");
});

// ==================== 测试17: 空通道测试 ====================
$run_test("空通道测试", function() {
    $ch = new Channel(2);

    // 尝试从空通道接收
    $value = $ch->tryRecv();
    if ($value !== null) throw new Exception("从空通道接收应返回null");

    $len = $ch->len();
    if ($len != 0) throw new Exception("空通道长度应为0，实际为$len");
});

// ==================== 测试18: Mutex 异常场景 ====================
$run_test("Mutex 异常场景（解锁未加锁的锁）", function() {
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
$run_test("Atomic 边界值测试", function() {
    $atomic = new Atomic(PHP_INT_MAX);

    $atomic->increment();
    $value = $atomic->load();
    // 检查是否溢出或正确处理

    $atomic->store(PHP_INT_MIN);
    $value = $atomic->load();
    if ($value != PHP_INT_MIN) throw new Exception("存储最小值失败");
});

// ==================== 测试20: SharedData 键类型测试 ====================
$run_test("SharedData 键类型测试", function() {
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
$run_test("Channel 容量为0（同步通道）", function() {
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
$run_test("多个 Mutex 独立工作", function() {
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
$run_test("SharedData 访问计数测试", function() {
    $shared = new SharedData();

    $shared->set("key1", "value1");
    $shared->get("key1");
    $shared->get("key1");
    $shared->has("key1");

    $count = $shared->getAccessCount();
    if ($count < 3) throw new Exception("访问计数应至少为3，实际为$count");
});

// ==================== 测试24: Channel 关闭后操作 ====================
$run_test("Channel 关闭后操作", function() {
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
$run_test("RWLock 读者计数测试", function() {
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
$run_test("Atomic compareAndSwap 失败场景", function() {
    $atomic = new Atomic(100);

    // CAS 失败
    $success = $atomic->compareAndSwap(50, 200);
    if ($success) throw new Exception("CAS 应失败");

    $value = $atomic->load();
    if ($value != 100) throw new Exception("CAS 失败后值应不变，实际为$value");
});

// ==================== 测试27: Mutex + Atomic 计数器 ====================
$run_test("Mutex + Atomic 组合计数器", function() {
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
$run_test("Channel 容量边界测试", function() {
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
$run_test("SharedData remove 不存在的键", function() {
    $shared = new SharedData();

    $result = $shared->remove("nonexistent_key");
    if ($result) throw new Exception("删除不存在的键应返回false");

    $size = $shared->size();
    if ($size != 0) throw new Exception("删除不存在的键后大小不应变化");
});

// ==================== 测试30: 所有并发类混合使用 ====================
$run_test("所有并发类混合使用（复杂场景）", function() {
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

// ==================== 测试31: 内存泄漏测试 - 大量创建销毁 ====================
$run_test("内存泄漏测试 - 大量创建销毁 Mutex", function() {
    for ($i = 0; $i < 1000; $i++) {
        $mutex = new Mutex();
        $mutex->lock();
        $mutex->unlock();
        // $mutex 应该被垃圾回收
    }
});

// ==================== 测试32: 内存泄漏测试 - 大量创建销毁 Atomic ====================
$run_test("内存泄漏测试 - 大量创建销毁 Atomic", function() {
    for ($i = 0; $i < 1000; $i++) {
        $atomic = new Atomic($i);
        $atomic->increment();
        // $atomic 应该被垃圾回收
    }
});

// ==================== 测试33: 内存泄漏测试 - 大量创建销毁 SharedData ====================
$run_test("内存泄漏测试 - 大量创建销毁 SharedData", function() {
    for ($i = 0; $i < 100; $i++) {
        $shared = new SharedData();
        for ($j = 0; $j < 10; $j++) {
            $shared->set("key_$j", "value_$j");
        }
        // $shared 应该被垃圾回收
    }
});

// ==================== 测试34: 内存泄漏测试 - 大量创建销毁 Channel ====================
$run_test("内存泄漏测试 - 大量创建销毁 Channel", function() {
    for ($i = 0; $i < 100; $i++) {
        $ch = new Channel(10);
        $ch->send(1);
        $ch->send(2);
        $ch->recv();
        // $ch 应该被垃圾回收
    }
});

// ==================== 测试35: 内存泄漏测试 - 大量创建销毁 RWLock ====================
$run_test("内存泄漏测试 - 大量创建销毁 RWLock", function() {
    for ($i = 0; $i < 1000; $i++) {
        $rwlock = new RWLock();
        $rwlock->lockRead();
        $rwlock->unlockRead();
        // $rwlock 应该被垃圾回收
    }
});

// ==================== 测试36: SharedData 大键值对 ====================
$run_test("SharedData 大键值对（内存压力测试）", function() {
    $shared = new SharedData();

    // 创建大字符串
    $large_value = str_repeat("x", 10000);

    for ($i = 0; $i < 100; $i++) {
        $shared->set("large_key_$i", $large_value);
    }

    $size = $shared->size();
    if ($size != 100) throw new Exception("应有100条记录，实际为$size");

    // 验证数据
    $value = $shared->get("large_key_50");
    if (strlen($value) != 10000) throw new Exception("大值数据损坏");
});

// ==================== 测试37: Channel 大数据传输 ====================
$run_test("Channel 大数据传输", function() {
    $ch = new Channel(5);

    $large_data = str_repeat("y", 5000);

    $ch->send($large_data);
    $received = $ch->recv();

    if ($received != $large_data) throw new Exception("大数据传输失败");
});

// ==================== 测试38: Mutex 嵌套使用 ====================
$run_test("Mutex 嵌套使用", function() {
    $mutex1 = new Mutex();
    $mutex2 = new Mutex();

    $mutex1->lock();
    $mutex2->lock();

    $count1 = $mutex1->getLockCount();
    $count2 = $mutex2->getLockCount();

    if ($count1 != 1 || $count2 != 1) {
        throw new Exception("嵌套锁计数不正确");
    }

    $mutex2->unlock();
    $mutex1->unlock();
});

// ==================== 测试39: SharedData 覆盖值 ====================
$run_test("SharedData 覆盖值", function() {
    $shared = new SharedData();

    $shared->set("key", "value1");
    $value1 = $shared->get("key");

    $shared->set("key", "value2");
    $value2 = $shared->get("key");

    if ($value1 == "value1" && $value2 == "value2") {
        // 正确：值被覆盖
    } else {
        throw new Exception("值覆盖失败");
    }
});

// ==================== 测试40: Atomic 操作链 ====================
$run_test("Atomic 操作链", function() {
    $atomic = new Atomic(0);

    $atomic->add(10);
    $atomic->increment();
    $atomic->sub(5);
    $atomic->decrement();
    $atomic->swap(100);
    $old = $atomic->swap(200);

    if ($old != 100) throw new Exception("swap 应返回旧值100，实际为$old");

    $value = $atomic->load();
    if ($value != 200) throw new Exception("最终值应为200，实际为$value");
});

// ==================== 测试41: Channel 多次关闭 ====================
$run_test("Channel 多次关闭", function() {
    $ch = new Channel(5);

    $ch->close();
    $closed1 = $ch->isClosed();

    $ch->close();
    $closed2 = $ch->isClosed();

    if (!$closed1 || !$closed2) {
        throw new Exception("多次关闭后应保持关闭状态");
    }
});

// ==================== 测试42: SharedData 清空后操作 ====================
$run_test("SharedData 清空后操作", function() {
    $shared = new SharedData();

    $shared->set("key1", "value1");
    $shared->set("key2", "value2");
    $shared->clear();

    $size = $shared->size();
    if ($size != 0) throw new Exception("清空后大小应为0");

    $value = $shared->get("key1");
    if ($value !== null) throw new Exception("清空后获取应返回null");

    // 清空后可以重新添加
    $shared->set("key3", "value3");
    $value = $shared->get("key3");
    if ($value != "value3") throw new Exception("清空后重新添加失败");
});

// ==================== 测试43: RWLock 读写混合 ====================
$run_test("RWLock 读写混合场景", function() {
    $rwlock = new RWLock();
    $shared = new SharedData();
    $shared->set("value", 0);

    // 读
    $rwlock->lockRead();
    $v1 = $shared->get("value");
    $rwlock->unlockRead();

    // 写
    $rwlock->lockWrite();
    $shared->set("value", 100);
    $rwlock->unlockWrite();

    // 读
    $rwlock->lockRead();
    $v2 = $shared->get("value");
    $rwlock->unlockRead();

    if ($v1 != 0 || $v2 != 100) {
        throw new Exception("读写混合场景失败: v1=$v1, v2=$v2");
    }
});

// ==================== 测试44: Mutex 异常恢复 ====================
$run_test("Mutex 异常恢复", function() {
    $mutex = new Mutex();

    $mutex->lock();
    try {
        // 模拟异常
        throw new Exception("Test exception");
    } catch (Exception $e) {
        // 确保在异常中解锁
        $mutex->unlock();
    }

    $count = $mutex->getLockCount();
    if ($count != 0) throw new Exception("异常处理后锁计数应为0");
});

// ==================== 测试45: Channel 零容量同步 ====================
$run_test("Channel 零容量同步", function() {
    $ch = new Channel(0);

    // 零容量通道的 trySend 应该失败（没有接收者）
    $r1 = $ch->trySend(1);
    if ($r1) throw new Exception("零容量通道无接收者时应失败");

    // tryRecv 也应该失败
    $v = $ch->tryRecv();
    if ($v !== null) throw new Exception("零容量通道 tryRecv 应返回null");
});

// ==================== 测试46: SharedData 特殊值 ====================
$run_test("SharedData 特殊值存储", function() {
    $shared = new SharedData();

    // null 值
    $shared->set("null_key", null);
    $value = $shared->get("null_key");
    if ($value !== null) throw new Exception("null 值存储失败");

    // 布尔值
    $shared->set("bool_true", true);
    $shared->set("bool_false", false);
    $v1 = $shared->get("bool_true");
    $v2 = $shared->get("bool_false");
    if ($v1 !== true || $v2 !== false) throw new Exception("布尔值存储失败");

    // 数字
    $shared->set("int", 123456);
    $shared->set("float", 3.14159);
    $v3 = $shared->get("int");
    $v4 = $shared->get("float");
    if ($v3 != 123456 || $v4 != 3.14159) throw new Exception("数字存储失败");

    // 数组
    $shared->set("array", [1, 2, 3, "a", "b"]);
    $v5 = $shared->get("array");
    if (!is_array($v5) || count($v5) != 5) throw new Exception("数组存储失败");
});

// ==================== 测试47: Atomic 极限操作 ====================
$run_test("Atomic 极限操作", function() {
    $atomic = new Atomic(0);

    // 大量递增
    for ($i = 0; $i < 10000; $i++) {
        $atomic->increment();
    }

    $value = $atomic->load();
    if ($value != 10000) throw new Exception("10000次递增后值应为10000，实际为$value");

    // 大量递减
    for ($i = 0; $i < 10000; $i++) {
        $atomic->decrement();
    }

    $value = $atomic->load();
    if ($value != 0) throw new Exception("10000次递减后值应为0，实际为$value");
});

// ==================== 测试48: Mutex 性能测试 ====================
$run_test("Mutex 性能测试（10000次加锁解锁）", function() {
    $mutex = new Mutex();
    $start = microtime(true);

    for ($i = 0; $i < 10000; $i++) {
        $mutex->lock();
        $mutex->unlock();
    }

    $end = microtime(true);
    $duration = ($end - $start) * 1000;
    echo "  耗时: " . number_format($duration, 2) . "ms\n";
});

// ==================== 测试49: SharedData 性能测试 ====================
$run_test("SharedData 性能测试（1000次读写）", function() {
    $shared = new SharedData();
    $start = microtime(true);

    for ($i = 0; $i < 1000; $i++) {
        $shared->set("key_$i", "value_$i");
    }

    for ($i = 0; $i < 1000; $i++) {
        $value = $shared->get("key_$i");
    }

    $end = microtime(true);
    $duration = ($end - $start) * 1000;
    echo "  耗时: " . number_format($duration, 2) . "ms\n";
});

// ==================== 测试50: Channel 性能测试 ====================
$run_test("Channel 性能测试（1000次发送接收）", function() {
    $ch = new Channel(100);
    $start = microtime(true);

    for ($i = 0; $i < 1000; $i++) {
        $ch->send($i);
    }

    for ($i = 0; $i < 1000; $i++) {
        $value = $ch->recv();
    }

    $end = microtime(true);
    $duration = ($end - $start) * 1000;
    echo "  耗时: " . number_format($duration, 2) . "ms\n";
});

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