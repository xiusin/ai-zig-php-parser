<?php
// 随机测试脚本 #5 - Try-Catch 和异常处理

echo "=== Random Test #5: Try-Catch ===\n";

// 基础异常
try {
    throw new Exception("Test exception");
} catch (Exception $e) {
    echo "Caught Exception: " . $e->getMessage() . "\n";
}

// 多 catch 块
try {
    $x = 1 / 0;
} catch (DivisionByZeroError $e) {
    echo "DivisionByZeroError: " . $e->getMessage() . "\n";
} catch (Exception $e) {
    echo "General Exception: " . $e->getMessage() . "\n";
}

// 嵌套 try-catch
try {
    try {
        throw new Exception("Inner exception");
    } catch (Exception $e) {
        echo "Inner catch: " . $e->getMessage() . "\n";
        throw new Exception("Outer exception", 0, $e);
    }
} catch (Exception $e) {
    echo "Outer catch: " . $e->getMessage() . "\n";
    echo "Previous: " . ($e->getPrevious() ? $e->getPrevious()->getMessage() : "none") . "\n";
}

// 异常中的变量
try {
    $value = 42;
    if ($value > 10) {
        throw new Exception("Value too large: $value");
    }
} catch (Exception $e) {
    echo "Variable in exception: " . $e->getMessage() . "\n";
}

// finally 块
$finally_ran = false;
try {
    throw new Exception("Test finally");
} catch (Exception $e) {
    echo "Catch block\n";
} finally {
    $finally_ran = true;
    echo "Finally block ran\n";
}
echo "Finally flag: " . ($finally_ran ? "true" : "false") . "\n";

// 返回值与 finally
function testFinallyReturn() {
    try {
        return "try return";
    } finally {
        echo "Finally in return\n";
    }
}
echo "testFinallyReturn: " . testFinallyReturn() . "\n";

// 异常传播
function throwException($msg) {
    throw new Exception($msg);
}

try {
    throwException("Nested throw");
} catch (Exception $e) {
    echo "Caught nested: " . $e->getMessage() . "\n";
}

echo "=== Test #5 Complete ===\n";
