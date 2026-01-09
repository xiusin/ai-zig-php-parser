<?php

class MyException extends Exception {
    public function myMethod(): string {
        return "Custom method called!";
    }
}

class AnotherException extends Exception {
    public string $customField = "test";

    public function getCustomInfo(): string {
        return "Custom info: " . $this->customField;
    }
}

// Test 1: Basic exception type preservation
echo "=== Test 1: Basic exception type preservation ===\n";
try {
    throw new MyException("Test message", 123);
} catch (Exception $e) {
    $type = get_class($e);
    echo "Exception type: $type\n";
    echo "Message: " . $e->getMessage() . "\n";
    echo "Code: " . $e->getCode() . "\n";
    echo "Has myMethod: " . (method_exists($e, 'myMethod') ? "yes" : "no") . "\n";
    if (method_exists($e, 'myMethod')) {
        echo "myMethod result: " . $e->myMethod() . "\n";
    }
    echo "Test 1 " . ($type === "MyException" ? "PASSED" : "FAILED") . "\n";
}

echo "\n";

// Test 2: Different exception type
echo "=== Test 2: AnotherException type preservation ===\n";
try {
    throw new AnotherException("Another test", 456);
} catch (Exception $e) {
    $type = get_class($e);
    echo "Exception type: $type\n";
    echo "Has getCustomInfo: " . (method_exists($e, 'getCustomInfo') ? "yes" : "no") . "\n";
    if (method_exists($e, 'getCustomInfo')) {
        echo "getCustomInfo result: " . $e->getCustomInfo() . "\n";
    }
    echo "Test 2 " . ($type === "AnotherException" ? "PASSED" : "FAILED") . "\n";
}

echo "\n";

// Test 3: Nested try-catch with type preservation
echo "=== Test 3: Nested exception handling ===\n";
try {
    try {
        throw new MyException("Nested exception", 789);
    } catch (Exception $inner) {
        echo "Inner catch - type: " . get_class($inner) . "\n";
        echo "Inner catch - has myMethod: " . (method_exists($inner, 'myMethod') ? "yes" : "no") . "\n";
        throw new AnotherException("Outer exception", 999);
    }
} catch (Exception $e) {
    $type = get_class($e);
    echo "Outer catch - type: $type\n";
    echo "Outer catch - has getCustomInfo: " . (method_exists($e, 'getCustomInfo') ? "yes" : "no") . "\n";
    echo "Test 3 " . ($type === "AnotherException" ? "PASSED" : "FAILED") . "\n";
}

echo "\n";

// Test 4: instanceof check
echo "=== Test 4: instanceof checks ===\n";
try {
    throw new MyException("Instanceof test", 111);
} catch (Exception $e) {
    $is_exception = $e instanceof Exception;
    $is_my_exception = $e instanceof MyException;
    echo "e instanceof Exception: " . ($is_exception ? "true" : "false") . "\n";
    echo "e instanceof MyException: " . ($is_my_exception ? "true" : "false") . "\n";
    echo "Test 4 " . ($is_exception and $is_my_exception ? "PASSED" : "FAILED") . "\n";
}

echo "\nAll tests completed!\n";
