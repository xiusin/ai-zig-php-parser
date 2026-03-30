<?php
// Test 006: Exception handling, errors, and error handling
class ExceptionLab {
    public function triggerDivisionByZero(): float {
        return 10 / 0;
    }

    public function triggerTypeError(): int {
        return $undefined_var + 1;
    }

    public function triggerArrayAccess(): mixed {
        $arr = [];
        return $arr['nonexistent'];
    }

    public function triggerOutOfBounds(): int {
        $arr = [1, 2, 3];
        return $arr[100];
    }

    public function safeDivision(float $a, float $b): float {
        if ($b == 0) {
            throw new DivisionByZeroError("Cannot divide by zero");
        }
        return $a / $b;
    }

    public function parseWithException(string $input): array {
        $result = json_decode($input, true, 512, JSON_THROW_ON_ERROR);
        return $result;
    }
}

function custom_error_handler(int $errno, string $errstr, string $errfile, int $errline): bool {
    echo "Custom Error [$errno]: $errstr in $errfile:$errline\n";
    return true;
}

function custom_exception_handler(Throwable $ex): void {
    echo "Exception: " . get_class($ex) . " - " . $ex->getMessage() . "\n";
}

set_error_handler('custom_error_handler');
set_exception_handler('custom_exception_handler');

$lab = new ExceptionLab();

// Test try-catch with various exceptions
try {
    echo "Test 1: Division by zero\n";
    $result = $lab->triggerDivisionByZero();
    echo "Result: $result\n";
} catch (DivisionByZeroError $e) {
    echo "Caught: " . get_class($e) . ": " . $e->getMessage() . "\n";
} catch (Throwable $e) {
    echo "Caught generic: " . get_class($e) . ": " . $e->getMessage() . "\n";
}

try {
    echo "Test 2: Safe division\n";
    $result = $lab->safeDivision(10, 2);
    echo "10/2 = $result\n";
    $result = $lab->safeDivision(10, 0);
    echo "Should not reach here\n";
} catch (DivisionByZeroError $e) {
    echo "Caught division by zero: " . $e->getMessage() . "\n";
}

try {
    echo "Test 3: JSON throw on error\n";
    $result = $lab->parseWithException('{"valid": true}');
    echo "Parsed: " . json_encode($result) . "\n";
    $result = $lab->parseWithException('invalid json{');
} catch (JsonException $e) {
    echo "Caught JSON error: " . $e->getMessage() . "\n";
}

// Test error_get_last
trigger_error("Test notice", E_USER_NOTICE);
$last = error_get_last();
echo "Last error: " . ($last ? $last['message'] : 'none') . "\n";

// Test warning handling
try {
    echo "Test 4: Warning via trigger_error\n";
    trigger_error("Test warning", E_USER_WARNING);
} catch (Error $e) {
    echo "Caught Error: " . $e->getMessage() . "\n";
}

echo "Script completed\n";