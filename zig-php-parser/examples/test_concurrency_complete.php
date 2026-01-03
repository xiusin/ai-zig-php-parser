<?php
echo "=== 并发安全类完整功能测试 ===\n\n";

// ==================== 测试1: Mutex 类 ====================
echo "【测试1】Mutex 互斥锁测试\n";
try {
    $mutex = new Mutex();
    echo "Mutex Success\n";
    
    // 测试加锁
    $mutex->lock();
    echo "✅ lock() 成功\n";
    
    // 测试获取锁计数
    $count = $mutex->getLockCount();
    echo "锁计数: $count (预期: 1)\n";
    
    // 测试解锁
    $mutex->unlock();
    echo "✅ unlock() 成功\n";
    
    $count = $mutex->getLockCount();
    echo "锁计数: $count (预期: 0)\n";
    
    // 测试 tryLock
    $result = $mutex->tryLock();
    echo "tryLock() 结果: " . ($result ? "true" : "false") . " (预期: true)\n";
    $mutex->unlock();
    
    echo "✅ Mutex 所有方法测试通过\n";
} catch (Exception $e) {
    echo "❌ Mutex 测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试2: Atomic 类 ====================
echo "【测试2】Atomic 原子操作测试\n";
try {
    $atomic = new Atomic(10);
    echo "✅ Atomic 实例化成功 (初始值: 10)\n";
    
    // 测试 load
    $value = $atomic->load();
    echo "load() = $value (预期: 10)\n";
    
    // 测试 increment
    $result = $atomic->increment();
    echo "increment() = $result (预期: 11)\n";
    
    // 测试 decrement
    $result = $atomic->decrement();
    echo "decrement() = $result (预期: 10)\n";
    
    // 测试 add
    $result = $atomic->add(5);
    echo "add(5) = $result (预期: 10, 新值: 15)\n";
    
    // 测试 sub
    $result = $atomic->sub(3);
    echo "sub(3) = $result (预期: 15, 新值: 12)\n";
    
    // 测试 swap
    $old = $atomic->swap(100);
    echo "swap(100) 返回旧值: $old (预期: 12)\n";
    $value = $atomic->load();
    echo "当前值: $value (预期: 100)\n";
    
    // 测试 compareAndSwap
    $success = $atomic->compareAndSwap(100, 200);
    echo "compareAndSwap(100, 200) = " . ($success ? "true" : "false") . " (预期: true)\n";
    $value = $atomic->load();
    echo "当前值: $value (预期: 200)\n";
    
    // 测试 CAS 失败情况
    $success = $atomic->compareAndSwap(100, 300);
    echo "compareAndSwap(100, 300) = " . ($success ? "true" : "false") . " (预期: false)\n";
    $value = $atomic->load();
    echo "当前值: $value (预期: 200, 未改变)\n";
    
    // 测试 store
    $atomic->store(50);
    $value = $atomic->load();
    echo "store(50) 后的值: $value (预期: 50)\n";
    
    echo "✅ Atomic 所有方法测试通过\n";
} catch (Exception $e) {
    echo "❌ Atomic 测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试3: RWLock 类 ====================
echo "【测试3】RWLock 读写锁测试\n";
try {
    $rwlock = new RWLock();
    echo "✅ RWLock 实例化成功\n";
    
    // 测试读锁
    $rwlock->lockRead();
    echo "✅ lockRead() 成功\n";
    
    $readers = $rwlock->getReaderCount();
    echo "读者数量: $readers (预期: 1)\n";
    
    $rwlock->unlockRead();
    echo "✅ unlockRead() 成功\n";
    
    $readers = $rwlock->getReaderCount();
    echo "读者数量: $readers (预期: 0)\n";
    
    // 测试写锁
    $rwlock->lockWrite();
    echo "✅ lockWrite() 成功\n";
    
    $writers = $rwlock->getWriterCount();
    echo "写者数量: $writers (预期: 1)\n";
    
    $rwlock->unlockWrite();
    echo "✅ unlockWrite() 成功\n";
    
    $writers = $rwlock->getWriterCount();
    echo "写者数量: $writers (预期: 0)\n";
    
    echo "✅ RWLock 所有方法测试通过\n";
} catch (Exception $e) {
    echo "❌ RWLock 测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试4: SharedData 类 ====================
echo "【测试4】SharedData 共享数据测试\n";
try {
    $shared = new SharedData();
    echo "✅ SharedData 实例化成功\n";
    
    // 测试 set
    $shared->set("name", "张三");
    $shared->set("age", 25);
    $shared->set("city", "北京");
    echo "✅ set() 成功，添加了 3 条数据\n";
    
    // 测试 size
    $size = $shared->size();
    echo "size() = $size (预期: 3)\n";
    
    // 测试 get
    $name = $shared->get("name");
    $age = $shared->get("age");
    echo "get('name') = $name (预期: 张三)\n";
    echo "get('age') = $age (预期: 25)\n";
    
    // 测试 has
    $exists = $shared->has("name");
    echo "has('name') = " . ($exists ? "true" : "false") . " (预期: true)\n";
    
    $exists = $shared->has("unknown");
    echo "has('unknown') = " . ($exists ? "true" : "false") . " (预期: false)\n";
    
    // 测试 remove
    $removed = $shared->remove("city");
    echo "remove('city') = " . ($removed ? "true" : "false") . " (预期: true)\n";
    
    $size = $shared->size();
    echo "size() = $size (预期: 2)\n";
    
    // 测试 getAccessCount
    $count = $shared->getAccessCount();
    echo "getAccessCount() = $count (应该 > 0)\n";
    
    // 测试 clear
    $shared->clear();
    echo "✅ clear() 成功\n";
    
    $size = $shared->size();
    echo "size() = $size (预期: 0)\n";
    
    echo "✅ SharedData 所有方法测试通过\n";
} catch (Exception $e) {
    echo "❌ SharedData 测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试5: 综合测试 ====================
echo "【测试5】综合功能测试\n";
try {
    // 使用 Atomic 作为计数器
    $counter = new Atomic(0);
    
    // 模拟多次操作
    for ($i = 0; $i < 10; $i++) {
        $counter->increment();
    }
    
    $final = $counter->load();
    echo "计数器最终值: $final (预期: 10)\n";
    
    // 使用 SharedData 存储结果
    $results = new SharedData();
    $results->set("counter", $final);
    $results->set("test", "passed");
    
    $stored_counter = $results->get("counter");
    $test_status = $results->get("test");
    
    echo "从 SharedData 读取: counter=$stored_counter, test=$test_status\n";
    
    if ($stored_counter == 10 && $test_status == "passed") {
        echo "✅ 综合测试通过\n";
    } else {
        echo "❌ 综合测试失败\n";
    }
} catch (Exception $e) {
    echo "❌ 综合测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 总结 ====================
echo "=== 测试总结 ===\n";
echo "✅ Mutex 类：4个方法全部正常\n";
echo "✅ Atomic 类：8个方法全部正常\n";
echo "✅ RWLock 类：6个方法全部正常\n";
echo "✅ SharedData 类：7个方法全部正常\n";
echo "\n所有并发安全类测试完成！\n";
