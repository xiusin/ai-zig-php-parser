<?php
// 异常处理：try/catch, throw, 异常链, finally, 自定义异常

class ValidationException extends Exception {
    public function __construct(string $message, int $code = 0, ?Throwable $previous = null) {
        parent::__construct($message, $code, $previous);
    }
}

class NetworkException extends Exception {}

function divide(int $a, int $b): int {
    if ($b === 0) {
        throw new DivisionByZeroError("Division by zero");
    }
    return intdiv($a, $b);
}

function processData(bool $ready): string {
    if (!$ready) {
        throw new Exception("Not ready");
    }
    return "processed";
}

function retry(callable $fn, int $maxAttempts = 3): mixed {
    $lastError = null;
    for ($i = 1; $i <= $maxAttempts; $i++) {
        try {
            return $fn();
        } catch (Exception $e) {
            $lastError = $e;
            echo "Attempt $i failed: " . $e->getMessage() . ", retrying...\n";
        }
    }
    throw $lastError;
}

// 测试基本 try/catch
try {
    $result = divide(10, 2);
    echo "div_ok: $result\n";
} catch (DivisionByZeroError $e) {
    echo "div_error: " . $e->getMessage() . "\n";
}

// 测试 throw 被捕获
try {
    if (false) throw new Exception("Not ready");
    echo "skipped_throw\n";
} catch (Exception $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

// 测试 throw 被捕获 (actual throw)
try {
    $val = processData(false);
    echo "processed: $val\n";
} catch (Exception $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

// 测试除零异常
try {
    divide(10, 0);
} catch (DivisionByZeroError $e) {
    echo "div_by_zero: " . $e->getMessage() . "\n";
}

// 测试重试机制
try {
    $attempts = 0;
    $result = retry(function() use (&$attempts) {
        $attempts++;
        if ($attempts < 3) {
            throw new Exception("Not ready");
        }
        return "success";
    });
    echo "retry_result: $result\n";
} catch (Exception $e) {
    echo "retry_failed: " . $e->getMessage() . "\n";
}

// 测试 finally
$resource = 'open';
try {
    throw new Exception("Error occurred");
} catch (Exception $e) {
    echo "finally_catch: " . $e->getMessage() . "\n";
} finally {
    $resource = 'closed';
    echo "finally_run: resource=$resource\n";
}

// 测试嵌套 try/catch
try {
    try {
        throw new ValidationException("Invalid data");
    } catch (ValidationException $e) {
        throw new NetworkException("Network failed", 0, $e);
    }
} catch (NetworkException $e) {
    echo "nested_error: " . $e->getMessage() . "\n";
    echo "nested_previous: " . $e->getPrevious()->getMessage() . "\n";
}

// 测试正常流程不触发异常
echo "normal_flow: " . processData(true) . "\n";
