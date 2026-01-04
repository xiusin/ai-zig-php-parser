<?php
echo "=== 并发安全类基础测试 ===\n\n";

// 测试 Mutex 类
echo "【测试1】Mutex 类实例化\n";
try {
    $mutex = new Mutex();
    echo "✅ Mutex 实例化成功\n";
    echo "对象类型: " . get_class($mutex) . "\n";
} catch (Exception $e) {
    echo "❌ Mutex 实例化失败: " . $e->getMessage() . "\n";
}
echo "\n";

// 测试 Atomic 类
echo "【测试2】Atomic 类实例化\n";
try {
    $atomic = new Atomic(0);
    echo "✅ Atomic 实例化成功\n";
    echo "对象类型: " . get_class($atomic) . "\n";
} catch (Exception $e) {
    echo "❌ Atomic 实例化失败: " . $e->getMessage() . "\n";
}
echo "\n";

// 测试 RWLock 类
echo "【测试3】RWLock 类实例化\n";
try {
    $rwlock = new RWLock();
    echo "✅ RWLock 实例化成功\n";
    echo "对象类型: " . get_class($rwlock) . "\n";
} catch (Exception $e) {
    echo "❌ RWLock 实例化失败: " . $e->getMessage() . "\n";
}
echo "\n";

// 测试 SharedData 类
echo "【测试4】SharedData 类实例化\n";
try {
    $shared = new SharedData();
    echo "✅ SharedData 实例化成功\n";
    echo "对象类型: " . get_class($shared) . "\n";
} catch (Exception $e) {
    echo "❌ SharedData 实例化失败: " . $e->getMessage() . "\n";
}
echo "\n";

echo "=== 测试完成 ===\n";
