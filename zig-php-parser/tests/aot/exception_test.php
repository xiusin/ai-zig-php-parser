<?php
// 简单的异常处理测试

class MyException extends Exception {}

// 测试 1: 基本 try-catch
echo "Test 1: Basic try-catch\n";
try {
    echo "Before throw\n";
    throw new MyException("Test error");
    echo "After throw (should not print)\n";
} catch (MyException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}
echo "After catch\n\n";

// 测试 2: 不抛出异常
echo "Test 2: No exception\n";
try {
    echo "No error here\n";
} catch (MyException $e) {
    echo "Should not catch\n";
}
echo "Completed\n\n";

// 测试 3: finally 块
echo "Test 3: Finally block\n";
$executed = false;
try {
    echo "In try\n";
} finally {
    echo "In finally\n";
    $executed = true;
}
echo "Finally executed: " . ($executed ? "yes" : "no") . "\n\n";

// 测试 4: try-catch-finally
// 注意：多个 try-catch 块会导致寄存器重用问题
// 单独的 try-catch-finally 工作正常（见 minimal_exception.php）
echo "Test 4: Try-catch-finally\n";
try {
    throw new MyException("Error in try");
} catch (MyException $e) {
    echo "Caught in catch\n";
} finally {
    echo "Executed finally\n";
}

echo "\nAll tests completed!\n";
