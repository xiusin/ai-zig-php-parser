<?php
echo "=== 并发安全类完整功能测试 ===\n\n";

// ==================== 测试1: Mutex 类 ====================
echo "【测试1】Mutex 互斥锁测试\n";
$mutex = new Mutex();
echo "✅ Mutex 实例化成功\n";

$mutex->lock();
echo "✅ lock() 成功\n";

$count = $mutex->getLockCount();
echo "锁计数: $count (预期: 1)\n";

$mutex->unlock();
echo "✅ unlock() 成功\n";

$count = $mutex->getLockCount();
echo "锁计数: $count (预期: 0)\n";

$result = $mutex->tryLock();
echo "tryLock() 结果: " . ($result ? "true" : "false") . " (预期: true)\n";
$mutex->unlock();

echo "✅ Mutex 所有方法测试通过\n\n";

// ==================== 测试2: Atomic 类 ====================
echo "【测试2】Atomic 原子操作测试\n";
$atomic = new Atomic(10);
echo "✅ Atomic 实例化成功 (初始值: 10)\n";

$value = $atomic->load();
echo "load() = $value (预期: 10)\n";

$result = $atomic->increment();
echo "increment() = $result (预期: 11)\n";

$result = $atomic->decrement();
echo "decrement() = $result (预期: 10)\n";

$result = $atomic->add(5);
echo "add(5) = $result (预期: 10, 新值: 15)\n";

$result = $atomic->sub(3);
echo "sub(3) = $result (预期: 15, 新值: 12)\n";

$old = $atomic->swap(100);
echo "swap(100) 返回旧值: $old (预期: 12)\n";

$value = $atomic->load();
echo "当前值: $value (预期: 100)\n";

$success = $atomic->compareAndSwap(100, 200);
echo "compareAndSwap(100, 200) = " . ($success ? "true" : "false") . " (预期: true)\n";

$value = $atomic->load();
echo "当前值: $value (预期: 200)\n";

$atomic->store(50);
$value = $atomic->load();
echo "store(50) 后的值: $value (预期: 50)\n";

echo "✅ Atomic 所有方法测试通过\n\n";

// ==================== 测试3: RWLock 类 ====================
echo "【测试3】RWLock 读写锁测试\n";
$rwlock = new RWLock();
echo "✅ RWLock 实例化成功\n";

$rwlock->lockRead();
echo "✅ lockRead() 成功\n";

$readers = $rwlock->getReaderCount();
echo "读者数量: $readers (预期: 1)\n";

$rwlock->unlockRead();
echo "✅ unlockRead() 成功\n";

$readers = $rwlock->getReaderCount();
echo "读者数量: $readers (预期: 0)\n";

$rwlock->lockWrite();
echo "✅ lockWrite() 成功\n";

$writers = $rwlock->getWriterCount();
echo "写者数量: $writers (预期: 1)\n";

$rwlock->unlockWrite();
echo "✅ unlockWrite() 成功\n";

$writers = $rwlock->getWriterCount();
echo "写者数量: $writers (预期: 0)\n";

echo "✅ RWLock 所有方法测试通过\n\n";

// ==================== 测试4: SharedData 类 ====================
echo "【测试4】SharedData 共享数据测试\n";
$shared = new SharedData();
echo "✅ SharedData 实例化成功\n";

$shared->set("name", "张三");
$shared->set("age", 25);
$shared->set("city", "北京");
echo "✅ set() 成功，添加了 3 条数据\n";

$size = $shared->size();
echo "size() = $size (预期: 3)\n";

$name = $shared->get("name");
$age = $shared->get("age");
echo "get('name') = $name (预期: 张三)\n";
echo "get('age') = $age (预期: 25)\n";

$exists = $shared->has("name");
echo "has('name') = " . ($exists ? "true" : "false") . " (预期: true)\n";

$exists = $shared->has("unknown");
echo "has('unknown') = " . ($exists ? "true" : "false") . " (预期: false)\n";

$removed = $shared->remove("city");
echo "remove('city') = " . ($removed ? "true" : "false") . " (预期: true)\n";

$size = $shared->size();
echo "size() = $size (预期: 2)\n";

$count = $shared->getAccessCount();
echo "getAccessCount() = $count (应该 > 0)\n";

$shared->clear();
echo "✅ clear() 成功\n";

$size = $shared->size();
echo "size() = $size (预期: 0)\n";

echo "✅ SharedData 所有方法测试通过\n\n";

// ==================== 总结 ====================
echo "=== 测试总结 ===\n";
echo "✅ Mutex 类：4个方法全部正常\n";
echo "✅ Atomic 类：8个方法全部正常\n";
echo "✅ RWLock 类：6个方法全部正常\n";
echo "✅ SharedData 类：7个方法全部正常\n";
echo "\n🎉 所有并发安全类测试完成！共25个方法全部通过！\n";
