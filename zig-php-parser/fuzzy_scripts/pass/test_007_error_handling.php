<?php
// 测试7: 错误处理与异常
function riskyOperation($x, $y) {
    if ($y == 0) {
        throw new InvalidArgumentException("Division by zero!");
    }
    if ($x < 0) {
        throw new RuntimeException("Negative value not allowed!");
    }
    return $x / $y;
}

class CustomException extends Exception {
    private $context = [];
    
    public function __construct(string $msg, array $context = []) {
        parent::__construct($msg);
        $this->context = $context;
    }
    
    public function getContext(): array {
        return $this->context;
    }
}

$results = [];
$testCases = [[10, 2], [10, 0], [-5, 2], [100, 10]];

foreach ($testCases as [$x, $y]) {
    try {
        $results[] = riskyOperation($x, $y);
    } catch (InvalidArgumentException $e) {
        $results[] = "InvalidArg: " . $e->getMessage();
    } catch (RuntimeException $e) {
        $results[] = "Runtime: " . $e->getMessage();
    } catch (Exception $e) {
        $results[] = "Generic: " . $e->getMessage();
    } finally {
        echo "Processed: $x, $y\n";
    }
}

// 多层异常嵌套
try {
    try {
        throw new CustomException("Inner error", ['code' => 500]);
    } catch (CustomException $e) {
        throw new RuntimeException("Wrapped: " . $e->getMessage());
    }
} catch (RuntimeException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

// 错误处理
set_error_handler(function($errno, $errstr) {
    echo "Error [$errno]: $errstr\n";
    return true;
});

@trigger_error("Custom warning", E_USER_WARNING);

print_r($results);
?>