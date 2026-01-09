<?php
/**
 * 验证并发类是否被正确注册
 */

echo "=== 验证并发类注册 ===\n\n";

// 测试 Mutex 类
echo "测试 Mutex 类:\n";
try {
    $mutex = new Mutex();
    echo "✅ Mutex 类实例化成功\n";

    $mutex->lock();
    echo "✅ Mutex::lock() 调用成功\n";

    $count = $mutex->getLockCount();
    echo "✅ Mutex::getLockCount() 调用成功，结果: $count\n";

    $mutex->unlock();
    echo "✅ Mutex::unlock() 调用成功\n";

    $result = $mutex->tryLock();
    echo "✅ Mutex::tryLock() 调用成功，结果: " . ($result ? "true" : "false") . "\n";

    $mutex->unlock();
    echo "✅ Mutex 所有方法测试通过\n";
} catch (Exception $e) {
    echo "❌ Mutex 类测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// 测试 Atomic 类
echo "测试 Atomic 类:\n";
try {
    $atomic = new Atomic(10);
    echo "✅ Atomic 类实例化成功\n";

    $value = $atomic->load();
    echo "✅ Atomic::load() 调用成功，结果: $value\n";

    $atomic->increment();
    echo "✅ Atomic::increment() 调用成功\n";

    $value = $atomic->load();
    echo "✅ Atomic::load() 调用成功，结果: $value\n";

    echo "✅ Atomic 所有方法测试通过\n";
} catch (Exception $e) {
    echo "❌ Atomic 类测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// 测试 RWLock 类
echo "测试 RWLock 类:\n";
try {
    $rwlock = new RWLock();
    echo "✅ RWLock 类实例化成功\n";

    $rwlock->lockRead();
    echo "✅ RWLock::lockRead() 调用成功\n";

    $rwlock->unlockRead();
    echo "✅ RWLock::unlockRead() 调用成功\n";

    $rwlock->lockWrite();
    echo "✅ RWLock::lockWrite() 调用成功\n";

    $rwlock->unlockWrite();
    echo "✅ RWLock::unlockWrite() 调用成功\n";

    echo "✅ RWLock 所有方法测试通过\n";
} catch (Exception $e) {
    echo "❌ RWLock 类测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// 测试 SharedData 类
echo "测试 SharedData 类:\n";
try {
    $shared = new SharedData();
    echo "✅ SharedData 类实例化成功\n";

    $shared->set("key", "value");
    echo "✅ SharedData::set() 调用成功\n";

    $value = $shared->get("key");
    echo "✅ SharedData::get() 调用成功，结果: $value\n";

    $size = $shared->size();
    echo "✅ SharedData::size() 调用成功，结果: $size\n";

    echo "✅ SharedData 所有方法测试通过\n";
} catch (Exception $e) {
    echo "❌ SharedData 类测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// 测试 Channel 类
echo "测试 Channel 类:\n";
try {
    $ch = new Channel(5);
    echo "✅ Channel 类实例化成功\n";

    $ch->send(100);
    echo "✅ Channel::send() 调用成功\n";

    $value = $ch->recv();
    echo "✅ Channel::recv() 调用成功，结果: $value\n";

    $len = $ch->len();
    echo "✅ Channel::len() 调用成功，结果: $len\n";

    echo "✅ Channel 所有方法测试通过\n";
} catch (Exception $e) {
    echo "❌ Channel 类测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

echo "=== 验证完成 ===\n";
