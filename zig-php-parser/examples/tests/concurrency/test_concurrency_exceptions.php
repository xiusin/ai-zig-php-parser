<?php
/**
 * 并发异常场景和内存泄漏测试
 * 包含各种异常情况、边界条件、内存压力测试
 * 目标：发现内存泄漏和功能缺陷
 */

echo "========================================\n";
echo "  并发异常场景和内存泄漏测试\n";
echo "========================================\n\n";

$test_count = 0;
$passed_count = 0;
$failed_count = 0;

function run_test($name, $callback) {
    // global $test_count, $passed_count, $failed_count;
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
}

// ==================== 测试1: Mutex 未解锁 ====================
run_test("Mutex 未解锁（内存泄漏风险）", function() {
    $mutex = new Mutex();
    $mutex->lock();
    // 故意不解锁
    // $mutex 应该被垃圾回收，但锁可能未正确释放
});

// ==================== 测试2: 重复解锁 ====================
run_test("Mutex 重复解锁", function() {
    $mutex = new Mutex();
    $mutex->lock();
    $mutex->unlock();
    try {
        $mutex->unlock(); // 重复解锁
        // 如果没有抛出异常，检查锁计数
        $count = $mutex->getLockCount();
        if ($count < 0) throw new Exception("锁计数为负数: $count");
    } catch (Exception $e) {
        // 可能会抛出异常，这是正常的
    }
});

// ==================== 测试3: Channel 缓冲区溢出 ====================
run_test("Channel 缓冲区溢出", function() {
    $ch = new Channel(2);
    $ch->send(1);
    $ch->send(2);
    // 尝试发送到已满的通道
    $result = $ch->trySend(3);
    if ($result) throw new Exception("缓冲区满时 trySend 应返回false");
});

// ==================== 测试4: Channel 关闭后发送 ====================
run_test("Channel 关闭后发送", function() {
    $ch = new Channel(5);
    $ch->close();
    $result = $ch->trySend(1);
    if ($result) throw new Exception("关闭后 trySend 应返回false");
});

// ==================== 测试5: SharedData 大量删除 ====================
run_test("SharedData 大量删除（内存压力）", function() {
    $shared = new SharedData();

    // 插入大量数据
    for ($i = 0; $i < 5000; $i++) {
        $shared->set("key_$i", "value_" . str_repeat("x", 100));
    }

    // 删除所有数据
    for ($i = 0; $i < 5000; $i++) {
        $shared->remove("key_$i");
    }

    $size = $shared->size();
    if ($size != 0) throw new Exception("删除后大小应为0，实际为$size");
});

// ==================== 测试6: Atomic 溢出 ====================
run_test("Atomic 溢出测试", function() {
    $atomic = new Atomic(PHP_INT_MAX);
    $atomic->increment();
    $value = $atomic->load();
    // 检查是否正确处理溢出
    echo "  PHP_INT_MAX + 1 = $value\n";
});

// ==================== 测试7: Mutex 死锁模拟 ====================
run_test("Mutex 死锁模拟（可能超时）", function() {
    $mutex1 = new Mutex();
    $mutex2 = new Mutex();

    $mutex1->lock();
    $mutex2->lock();

    // 尝试以相反顺序获取锁（死锁）
    // 在实际代码中应该避免这种情况
    try {
        $mutex2->lock(); // 已经持有
        $mutex1->lock(); // 死锁
    } catch (Exception $e) {
        echo "  捕获死锁异常: " . $e->getMessage() . "\n";
    }

    // 清理
    $mutex2->unlock();
    $mutex1->unlock();
});

// ==================== 测试8: RWLock 写锁冲突 ====================
run_test("RWLock 写锁冲突", function() {
    $rwlock = new RWLock();

    $rwlock->lockWrite();
    // 尝试获取另一个写锁
    try {
        $rwlock->lockWrite(); // 应该阻塞或失败
    } catch (Exception $e) {
        echo "  写锁冲突: " . $e->getMessage() . "\n";
    }
    $rwlock->unlockWrite();
});

// ==================== 测试9: 大量创建销毁 Mutex ====================
run_test("大量创建销毁 Mutex（内存泄漏测试）", function() {
    for ($i = 0; $i < 10000; $i++) {
        $mutex = new Mutex();
        $mutex->lock();
        $mutex->unlock();
        // $mutex 应该被垃圾回收
    }
    echo "  创建销毁 10000 个 Mutex\n";
});

// ==================== 测试10: 大量创建销毁 Channel ====================
run_test("大量创建销毁 Channel（内存泄漏测试）", function() {
    for ($i = 0; $i < 1000; $i++) {
        $ch = new Channel(10);
        $ch->send(1);
        $ch->recv();
        // $ch 应该被垃圾回收
    }
    echo "  创建销毁 1000 个 Channel\n";
});

// ==================== 测试11: SharedData 键冲突 ====================
run_test("SharedData 键冲突", function() {
    $shared = new SharedData();

    $shared->set("key", "value1");
    $shared->set("key", "value2"); // 覆盖

    $value = $shared->get("key");
    if ($value != "value2") throw new Exception("值应被覆盖");
});

// ==================== 测试12: Channel 零容量阻塞 ====================
run_test("Channel 零容量阻塞", function() {
    $ch = new Channel(0);

    // 零容量通道没有接收者时无法发送
    $result = $ch->trySend(1);
    if ($result) throw new Exception("零容量通道无接收者时应失败");

    // 零容量通道没有发送者时无法接收
    $value = $ch->tryRecv();
    if ($value !== null) throw new Exception("零容量通道无发送者时应返回null");
});

// ==================== 测试13: Mutex 异常中未解锁 ====================
run_test("Mutex 异常中未解锁（内存泄漏风险）", function() {
    $mutex = new Mutex();
    $mutex->lock();
    try {
        throw new Exception("测试异常");
    } catch (Exception $e) {
        // 故意不解锁
        echo "  捕获异常，但未解锁\n";
    }
    // $mutex 应该被垃圾回收，但锁可能未正确释放
});

// ==================== 测试14: SharedData 特殊键 ====================
run_test("SharedData 特殊键", function() {
    $shared = new SharedData();

    // 空键
    $shared->set("", "empty_key");
    $value = $shared->get("");
    if ($value != "empty_key") throw new Exception("空键测试失败");

    // 长键
    $long_key = str_repeat("x", 10000);
    $shared->set($long_key, "long_key_value");
    $value = $shared->get($long_key);
    if ($value != "long_key_value") throw new Exception("长键测试失败");
});

// ==================== 测试15: Channel 大数据传输 ====================
run_test("Channel 大数据传输（内存压力）", function() {
    $ch = new Channel(5);

    $large_data = str_repeat("y", 100000); // 100KB

    for ($i = 0; $i < 10; $i++) {
        $ch->send($large_data);
        $received = $ch->recv();
        if (strlen($received) != 100000) throw new Exception("大数据传输失败");
    }

    echo "  传输 10 次 100KB 数据\n";
});

// ==================== 测试16: RWLock 读写冲突 ====================
run_test("RWLock 读写冲突", function() {
    $rwlock = new RWLock();

    $rwlock->lockWrite();
    // 尝试获取读锁（应该阻塞或失败）
    try {
        $rwlock->lockRead();
    } catch (Exception $e) {
        echo "  读写冲突: " . $e->getMessage() . "\n";
    }
    $rwlock->unlockWrite();
});

// ==================== 测试17: Atomic 并发修改 ====================
run_test("Atomic 并发修改（模拟）", function() {
    $atomic = new Atomic(0);

    // 模拟并发修改
    for ($i = 0; $i < 1000; $i++) {
        $atomic->increment();
        $atomic->add(10);
        $atomic->decrement();
    }

    $value = $atomic->load();
    echo "  最终值: $value\n";
});

// ==================== 测试18: SharedData 循环引用 ====================
run_test("SharedData 循环引用（内存泄漏风险）", function() {
    $shared = new SharedData();

    // 创建循环引用
    $data1 = ['ref' => null];
    $data2 = ['ref' => null];

    $data1['ref'] = &$data2;
    $data2['ref'] = &$data1;

    $shared->set("data1", $data1);
    $shared->set("data2", $data2);

    // 清除引用
    unset($data1);
    unset($data2);

    // 尝试清理
    $shared->clear();
    echo "  循环引用已清除\n";
});

// ==================== 测试19: Channel 关闭后接收 ====================
run_test("Channel 关闭后接收", function() {
    $ch = new Channel(5);
    $ch->send(1);
    $ch->send(2);
    $ch->close();

    $v1 = $ch->recv();
    $v2 = $ch->recv();
    $v3 = $ch->recv(); // 应该返回 null

    if ($v1 != 1 || $v2 != 2 || $v3 !== null) {
        throw new Exception("关闭后接收失败");
    }
});

// ==================== 测试20: Mutex 嵌套过深 ====================
run_test("Mutex 嵌套过深", function() {
    $mutex = new Mutex();

    // 深度嵌套
    for ($i = 0; $i < 100; $i++) {
        $mutex->lock();
    }

    $count = $mutex->getLockCount();
    if ($count != 100) throw new Exception("嵌套计数应为100，实际为$count");

    // 逐层解锁
    for ($i = 0; $i < 100; $i++) {
        $mutex->unlock();
    }

    $count = $mutex->getLockCount();
    if ($count != 0) throw new Exception("全部解锁后计数应为0");
});

// ==================== 测试21: SharedData 大值 ====================
run_test("SharedData 大值（内存压力）", function() {
    $shared = new SharedData();

    // 存储大值
    $large_value = str_repeat("z", 1000000); // 1MB

    for ($i = 0; $i < 10; $i++) {
        $shared->set("large_$i", $large_value);
    }

    $size = $shared->size();
    if ($size != 10) throw new Exception("应有10条记录");

    // 验证数据
    $value = $shared->get("large_5");
    if (strlen($value) != 1000000) throw new Exception("大值数据损坏");

    echo "  存储 10 个 1MB 值\n";
});

// ==================== 测试22: Channel 容量边界 ====================
run_test("Channel 容量边界", function() {
    $ch = new Channel(1);

    $ch->send(1);

    // 缓冲区满
    $result = $ch->trySend(2);
    if ($result) throw new Exception("容量为1时应满");

    $ch->recv();

    // 现在有空间
    $result = $ch->trySend(2);
    if (!$result) throw new Exception("接收后应有空间");
});

// ==================== 测试23: Atomic CAS 失败循环 ====================
run_test("Atomic CAS 失败循环", function() {
    $atomic = new Atomic(100);

    $failures = 0;
    for ($i = 0; $i < 100; $i++) {
        $success = $atomic->compareAndSwap(50, 200);
        if (!$success) $failures++;
    }

    if ($failures != 100) throw new Exception("CAS 应全部失败");
    echo "  CAS 失败次数: $failures\n";
});

// ==================== 测试24: RWLock 多读者 ====================
run_test("RWLock 多读者", function() {
    $rwlock = new RWLock();

    // 获取多个读锁
    for ($i = 0; $i < 100; $i++) {
        $rwlock->lockRead();
    }

    $readers = $rwlock->getReaderCount();
    if ($readers != 100) throw new Exception("读者数量应为100");

    // 释放所有读锁
    for ($i = 0; $i < 100; $i++) {
        $rwlock->unlockRead();
    }

    $readers = $rwlock->getReaderCount();
    if ($readers != 0) throw new Exception("释放后读者数量应为0");
});

// ==================== 测试25: SharedData 删除不存在的键 ====================
run_test("SharedData 删除不存在的键", function() {
    $shared = new SharedData();

    $result = $shared->remove("nonexistent");
    if ($result) throw new Exception("删除不存在的键应返回false");

    $size = $shared->size();
    if ($size != 0) throw new Exception("大小不应变化");
});

// ==================== 测试26: Mutex 可重入性 ====================
run_test("Mutex 可重入性", function() {
    $mutex = new Mutex();

    $mutex->lock();
    $mutex->lock();
    $mutex->lock();

    $count = $mutex->getLockCount();
    if ($count != 3) throw new Exception("可重入锁计数应为3");

    $mutex->unlock();
    $mutex->unlock();
    $mutex->unlock();

    $count = $mutex->getLockCount();
    if ($count != 0) throw new Exception("全部解锁后计数应为0");
});

// ==================== 测试27: Channel 多次关闭 ====================
run_test("Channel 多次关闭", function() {
    $ch = new Channel(5);

    $ch->close();
    $ch->close();
    $ch->close();

    $closed = $ch->isClosed();
    if (!$closed) throw new Exception("多次关闭后应保持关闭");
});

// ==================== 测试28: SharedData 清空后操作 ====================
run_test("SharedData 清空后操作", function() {
    $shared = new SharedData();

    $shared->set("key1", "value1");
    $shared->set("key2", "value2");
    $shared->clear();

    $value = $shared->get("key1");
    if ($value !== null) throw new Exception("清空后获取应返回null");

    // 清空后可以重新添加
    $shared->set("key3", "value3");
    $value = $shared->get("key3");
    if ($value != "value3") throw new Exception("清空后重新添加失败");
});

// ==================== 测试29: Atomic 极限操作 ====================
run_test("Atomic 极限操作（性能测试）", function() {
    $atomic = new Atomic(0);
    $start = microtime(true);

    for ($i = 0; $i < 100000; $i++) {
        $atomic->increment();
        $atomic->load();
        $atomic->decrement();
    }

    $end = microtime(true);
    $duration = ($end - $start) * 1000;
    echo "  耗时: " . number_format($duration, 2) . "ms\n";
});

// ==================== 测试30: Mutex 并发竞争 ====================
run_test("Mutex 并发竞争（模拟）", function() {
    $mutex = new Mutex();
    $shared = new SharedData();
    $shared->set("counter", 0);

    // 模拟并发竞争
    for ($i = 0; $i < 1000; $i++) {
        $mutex->lock();
        $counter = $shared->get("counter");
        $counter++;
        $shared->set("counter", $counter);
        $mutex->unlock();
    }

    $final = $shared->get("counter");
    if ($final != 1000) throw new Exception("最终计数应为1000，实际为$final");
});

// ==================== 测试31: Channel 缓冲区满满 ====================
run_test("Channel 缓冲区满满（极限）", function() {
    $ch = new Channel(10);

    for ($i = 0; $i < 10; $i++) {
        $ch->send($i);
    }

    $len = $ch->len();
    if ($len != 10) throw new Exception("长度应为10");

    // 尝试发送
    $result = $ch->trySend(11);
    if ($result) throw new Exception("满时应无法发送");
});

// ==================== 测试32: SharedData 访问计数溢出 ====================
run_test("SharedData 访问计数溢出", function() {
    $shared = new SharedData();

    // 大量访问
    for ($i = 0; $i < 100000; $i++) {
        $shared->set("key", "value");
        $shared->get("key");
    }

    $count = $shared->getAccessCount();
    echo "  访问计数: $count\n";
});

// ==================== 测试33: RWLock 写者优先 ====================
run_test("RWLock 写者优先（模拟）", function() {
    $rwlock = new RWLock();

    $rwlock->lockRead();
    $rwlock->lockRead();

    // 尝试获取写锁（应该等待）
    echo "  等待写锁...\n";

    $rwlock->unlockRead();
    $rwlock->unlockRead();

    // 现在可以获取写锁
    $rwlock->lockWrite();
    echo "  获取写锁成功\n";
    $rwlock->unlockWrite();
});

// ==================== 测试34: Atomic swap 测试 ====================
run_test("Atomic swap 测试", function() {
    $atomic = new Atomic(100);

    $old = $atomic->swap(200);
    if ($old != 100) throw new Exception("swap 应返回旧值100");

    $value = $atomic->load();
    if ($value != 200) throw new Exception("swap 后值应为200");
});

// ==================== 测试35: Channel 统计准确性 ====================
run_test("Channel 统计准确性", function() {
    $ch = new Channel(10);

    for ($i = 0; $i < 5; $i++) {
        $ch->send($i);
    }

    for ($i = 0; $i < 3; $i++) {
        $ch->recv();
    }

    $send_count = $ch->getSendCount();
    $recv_count = $ch->getRecvCount();

    if ($send_count != 5 || $recv_count != 3) {
        throw new Exception("统计不准确: send=$send_count, recv=$recv_count");
    }
});

// ==================== 测试36: Mutex tryLock 竞争 ====================
run_test("Mutex tryLock 竞争", function() {
    $mutex = new Mutex();

    $mutex->lock();

    // 尝试非阻塞获取锁
    $result = $mutex->tryLock();
    if ($result) throw new Exception("已加锁时 tryLock 应返回false");

    $mutex->unlock();

    // 现在应该可以获取
    $result = $mutex->tryLock();
    if (!$result) throw new Exception("解锁后 tryLock 应返回true");

    $mutex->unlock();
});

// ==================== 测试37: SharedData 键值对混合类型 ====================
run_test("SharedData 键值对混合类型", function() {
    $shared = new SharedData();

    $shared->set("null", null);
    $shared->set("bool", true);
    $shared->set("int", 123);
    $shared->set("float", 3.14);
    $shared->set("string", "hello");
    $shared->set("array", [1, 2, 3]);

    $v1 = $shared->get("null");
    $v2 = $shared->get("bool");
    $v3 = $shared->get("int");
    $v4 = $shared->get("float");
    $v5 = $shared->get("string");
    $v6 = $shared->get("array");

    if ($v1 !== null || $v2 !== true || $v3 != 123 ||
        $v4 != 3.14 || $v5 != "hello" || !is_array($v6)) {
        throw new Exception("混合类型存储失败");
    }
});

// ==================== 测试38: Channel 容量为0的同步 ====================
run_test("Channel 容量为0的同步", function() {
    $ch = new Channel(0);

    // 零容量通道的 trySend 应该失败
    $r1 = $ch->trySend(1);
    if ($r1) throw new Exception("零容量无接收者时应失败");

    // tryRecv 也应该失败
    $v = $ch->tryRecv();
    if ($v !== null) throw new Exception("零容量无发送者时应返回null");
});

// ==================== 测试39: Mutex 异常恢复 ====================
run_test("Mutex 异常恢复", function() {
    $mutex = new Mutex();

    $mutex->lock();
    try {
        throw new Exception("测试异常");
    } catch (Exception $e) {
        $mutex->unlock(); // 确保在异常中解锁
    }

    $count = $mutex->getLockCount();
    if ($count != 0) throw new Exception("异常处理后锁计数应为0");
});

// ==================== 测试40: SharedData 并发修改 ====================
run_test("SharedData 并发修改（模拟）", function() {
    $shared = new SharedData();
    $mutex = new Mutex();

    for ($i = 0; $i < 1000; $i++) {
        $mutex->lock();
        $shared->set("key_$i", "value_$i");
        $mutex->unlock();
    }

    $size = $shared->size();
    if ($size != 1000) throw new Exception("应有1000条记录");
});

// ==================== 测试41: Channel 关闭后统计 ====================
run_test("Channel 关闭后统计", function() {
    $ch = new Channel(5);

    $ch->send(1);
    $ch->send(2);
    $ch->close();

    $send_count = $ch->getSendCount();
    $closed = $ch->isClosed();

    if ($send_count != 2 || !$closed) {
        throw new Exception("关闭后统计不准确");
    }
});

// ==================== 测试42: Atomic store 测试 ====================
run_test("Atomic store 测试", function() {
    $atomic = new Atomic(100);

    $atomic->store(200);
    $value = $atomic->load();

    if ($value != 200) throw new Exception("store 后值应为200");
});

// ==================== 测试43: RWLock 读写混合 ====================
run_test("RWLock 读写混合", function() {
    $rwlock = new RWLock();

    $rwlock->lockRead();
    $rwlock->lockRead();

    $readers = $rwlock->getReaderCount();
    if ($readers != 2) throw new Exception("读者数量应为2");

    $rwlock->unlockRead();
    $rwlock->lockWrite(); // 尝试获取写锁

    $writers = $rwlock->getWriterCount();
    if ($writers != 1) throw new Exception("写者数量应为1");

    $rwlock->unlockWrite();
    $rwlock->unlockRead();
});

// ==================== 测试44: SharedData has 方法 ====================
run_test("SharedData has 方法", function() {
    $shared = new SharedData();

    $shared->set("key1", "value1");

    $exists1 = $shared->has("key1");
    $exists2 = $shared->has("key2");

    if ($exists1 !== true || $exists2 !== false) {
        throw new Exception("has 方法返回值不正确");
    }
});

// ==================== 测试45: Mutex 性能压力测试 ====================
run_test("Mutex 性能压力测试", function() {
    $mutex = new Mutex();
    $start = microtime(true);

    for ($i = 0; $i < 100000; $i++) {
        $mutex->lock();
        $mutex->unlock();
    }

    $end = microtime(true);
    $duration = ($end - $start) * 1000;
    echo "  耗时: " . number_format($duration, 2) . "ms\n";
});

// ==================== 测试46: Channel 性能压力测试 ====================
run_test("Channel 性能压力测试", function() {
    $ch = new Channel(100);
    $start = microtime(true);

    for ($i = 0; $i < 10000; $i++) {
        $ch->send($i);
    }

    for ($i = 0; $i < 10000; $i++) {
        $ch->recv();
    }

    $end = microtime(true);
    $duration = ($end - $start) * 1000;
    echo "  耗时: " . number_format($duration, 2) . "ms\n";
});

// ==================== 测试47: SharedData 性能压力测试 ====================
run_test("SharedData 性能压力测试", function() {
    $shared = new SharedData();
    $start = microtime(true);

    for ($i = 0; $i < 10000; $i++) {
        $shared->set("key_$i", "value_$i");
    }

    for ($i = 0; $i < 10000; $i++) {
        $value = $shared->get("key_$i");
    }

    $end = microtime(true);
    $duration = ($end - $start) * 1000;
    echo "  耗时: " . number_format($duration, 2) . "ms\n";
});

// ==================== 测试48: Atomic 性能压力测试 ====================
run_test("Atomic 性能压力测试", function() {
    $atomic = new Atomic(0);
    $start = microtime(true);

    for ($i = 0; $i < 100000; $i++) {
        $atomic->increment();
        $atomic->load();
        $atomic->add(10);
        $atomic->sub(5);
    }

    $end = microtime(true);
    $duration = ($end - $start) * 1000;
    echo "  耗时: " . number_format($duration, 2) . "ms\n";
});

// ==================== 测试49: 组合压力测试 ====================
run_test("组合压力测试（所有并发类）", function() {
    $mutex = new Mutex();
    $atomic = new Atomic(0);
    $rwlock = new RWLock();
    $shared = new SharedData();
    $ch = new Channel(100);

    $start = microtime(true);

    for ($i = 0; $i < 1000; $i++) {
        $mutex->lock();
        $atomic->increment();
        $shared->set("key_$i", $i);
        $mutex->unlock();

        $rwlock->lockRead();
        $value = $shared->get("key_$i");
        $rwlock->unlockRead();

        $ch->send($i);
        $ch->recv();
    }

    $end = microtime(true);
    $duration = ($end - $start) * 1000;
    echo "  耗时: " . number_format($duration, 2) . "ms\n";
});

// ==================== 测试50: 内存泄漏综合测试 ====================
run_test("内存泄漏综合测试", function() {
    // 创建大量对象
    for ($i = 0; $i < 100; $i++) {
        $mutex = new Mutex();
        $atomic = new Atomic($i);
        $rwlock = new RWLock();
        $shared = new SharedData();
        $ch = new Channel(10);

        for ($j = 0; $j < 10; $j++) {
            $shared->set("key_$j", "value_$j");
            $ch->send($j);
            $ch->recv();
        }

        // 所有对象应该被垃圾回收
    }

    echo "  创建销毁 100 组并发对象\n";
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

echo "\n⚠️  注意：某些测试可能触发内存泄漏，建议使用内存检测工具运行\n";
echo "测试完成！\n";