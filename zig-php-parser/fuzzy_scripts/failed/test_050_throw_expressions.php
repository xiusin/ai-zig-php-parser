<?php
// 测试50: PHP 8.0 throw表达式
class ValidationException extends Exception {}

function validatePositive($num) {
    return $num > 0 ? $num : throw new ValidationException("Must be positive");
}

try {
    echo validatePositive(10) . "\n";
    echo validatePositive(-5) . "\n";
} catch (ValidationException $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

// 在表达式中使用
$value = 0;
try {
    $result = $value !== 0 ? 100 / $value : throw new DivisionByZeroError("Division by zero");
} catch (DivisionByZeroError $e) {
    echo "Division error: " . $e->getMessage() . "\n";
}

// 与null合并结合
function getConfig(string $key) {
    $config = ['debug' => true, 'timeout' => 30];
    return $config[$key] ?? throw new InvalidArgumentException("Unknown key: $key");
}

try {
    echo getConfig('debug') ? "true" : "false";
    echo "\n";
    getConfig('missing');
} catch (InvalidArgumentException $e) {
    echo "Config error: " . $e->getMessage() . "\n";
}

// 三元中的throw
$age = 15;
try {
    $category = $age >= 18 ? "adult" : throw new RuntimeException("Minor access denied");
} catch (RuntimeException $e) {
    echo "Access error: " . $e->getMessage() . "\n";
}
?>