<?php
echo "=== 测试 lock 关键词 ===\n\n";

// 测试1: 基本用法
echo "【测试1】基本用法\n";
lock {
    echo "Inside lock block\n";
    $value = 42;
    echo "Value: $value\n";
}
echo "Outside lock block\n\n";

// 测试2: 嵌套 lock
echo "【测试2】嵌套 lock\n";
lock {
    echo "Outer lock\n";
    lock {
        echo "Inner lock\n";
    }
    echo "Back to outer lock\n";
}
echo "Outside all locks\n\n";

// 测试3: lock 中的异常
echo "【测试3】lock 中的异常\n";
try {
    lock {
        echo "Inside lock before exception\n";
        throw new Exception("Test exception");
        echo "This should not be printed\n";
    }
} catch (Exception $e) {
    echo "Caught exception: " . $e->getMessage() . "\n";
    echo "Lock should have been released\n";
}
echo "After try-catch\n\n";

// 测试4: lock 与 Mutex 类结合使用
echo "【测试4】lock 与 Mutex 类结合使用\n";
$mutex = new Mutex();
lock {
    $mutex->lock();
    echo "Inside lock with Mutex\n";
    $mutex->unlock();
}
echo "Outside lock\n\n";

echo "✅ lock 关键词测试完成\n";