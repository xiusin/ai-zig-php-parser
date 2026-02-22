<?php
// 超级复杂的 PHP 功能测试

echo "=== Advanced PHP Features Test ===\n\n";

// 1. 复杂的类继承和接口
interface Logger {
    public function log(string $message): void;
}

interface Validator {
    public function validate(mixed $data): bool;
}

abstract class BaseService implements Logger {
    protected array $logs = [];
    
    public function log(string $message): void {
        $this->logs[] = $message;
    }
    
    public function getLogs(): array {
        return $this->logs;
    }
    
    abstract public function process(mixed $data): mixed;
}

class DataProcessor extends BaseService implements Validator {
    private int $processCount = 0;
    
    public function validate(mixed $data): bool {
        if (is_array($data)) {
            return count($data) > 0;
        }
        return $data !== null;
    }
    
    public function process(mixed $data): mixed {
        $this->log("Processing data");
        $this->processCount++;
        
        if (!$this->validate($data)) {
            $this->log("Validation failed");
            return null;
        }
        
        if (is_array($data)) {
            return array_map(function($item) {
                return $item * 2;
            }, $data);
        }
        
        return $data;
    }
    
    public function getProcessCount(): int {
        return $this->processCount;
    }
}

echo "1. Complex OOP Test:\n";
$processor = new DataProcessor();
$result = $processor->process([1, 2, 3, 4, 5]);
echo "   Processed: " . implode(", ", $result) . "\n";
echo "   Process count: " . $processor->getProcessCount() . "\n";
echo "   Logs: " . count($processor->getLogs()) . "\n";
echo "\n";

// 2. 复杂的闭包和高阶函数
echo "2. Advanced Closures Test:\n";

function createMultiplier(int $factor): callable {
    return function(int $x) use ($factor): int {
        return $x * $factor;
    };
}

function compose(callable $f, callable $g): callable {
    return function($x) use ($f, $g) {
        return $f($g($x));
    };
}

$double = createMultiplier(2);
$triple = createMultiplier(3);
$addTen = function($x) { return $x + 10; };

$composed = compose($double, $addTen);
echo "   compose(double, addTen)(5) = " . $composed(5) . "\n";

$pipeline = compose($triple, compose($double, $addTen));
echo "   pipeline(5) = " . $pipeline(5) . "\n";
echo "\n";

// 3. 复杂的数组操作
echo "3. Advanced Array Operations Test:\n";

$data = [
    ['name' => 'Alice', 'age' => 30, 'score' => 85],
    ['name' => 'Bob', 'age' => 25, 'score' => 92],
    ['name' => 'Charlie', 'age' => 35, 'score' => 78],
    ['name' => 'David', 'age' => 28, 'score' => 95],
];

// 过滤、映射、归约
$highScorers = array_filter($data, function($person) {
    return $person['score'] >= 85;
});

$names = array_map(function($person) {
    return $person['name'];
}, $highScorers);

$totalScore = array_reduce($highScorers, function($carry, $person) {
    return $carry + $person['score'];
}, 0);

echo "   High scorers: " . implode(", ", $names) . "\n";
echo "   Total score: " . $totalScore . "\n";
echo "   Average: " . ($totalScore / count($highScorers)) . "\n";
echo "\n";

// 4. 复杂的字符串处理
echo "4. Advanced String Operations Test:\n";

$text = "Hello World! This is a test.";
$words = explode(" ", $text);
$wordCount = count($words);
$charCount = strlen($text);

$reversed = array_reverse($words);
$reversedText = implode(" ", $reversed);

echo "   Original: $text\n";
echo "   Words: $wordCount, Chars: $charCount\n";
echo "   Reversed: $reversedText\n";
echo "\n";

// 5. 复杂的递归算法
echo "5. Advanced Recursion Test:\n";

function quicksort(array $arr): array {
    if (count($arr) <= 1) {
        return $arr;
    }
    
    $pivot = $arr[0];
    $left = [];
    $right = [];
    
    for ($i = 1; $i < count($arr); $i++) {
        if ($arr[$i] < $pivot) {
            $left[] = $arr[$i];
        } else {
            $right[] = $arr[$i];
        }
    }
    
    return array_merge(quicksort($left), [$pivot], quicksort($right));
}

$unsorted = [64, 34, 25, 12, 22, 11, 90];
$sorted = quicksort($unsorted);
echo "   Unsorted: " . implode(", ", $unsorted) . "\n";
echo "   Sorted: " . implode(", ", $sorted) . "\n";
echo "\n";

// 6. 复杂的异常处理
echo "6. Advanced Exception Handling Test:\n";

class ValidationException extends Exception {}
class ProcessingException extends Exception {}

function processWithValidation(mixed $data): mixed {
    if ($data === null) {
        throw new ValidationException("Data cannot be null");
    }
    
    if (is_array($data) && count($data) === 0) {
        throw new ProcessingException("Array cannot be empty");
    }
    
    return $data;
}

try {
    $result1 = processWithValidation([1, 2, 3]);
    echo "   Result 1: " . implode(", ", $result1) . "\n";
    
    try {
        $result2 = processWithValidation([]);
    } catch (ProcessingException $e) {
        echo "   Caught ProcessingException: " . $e->getMessage() . "\n";
    }
    
    $result3 = processWithValidation(null);
} catch (ValidationException $e) {
    echo "   Caught ValidationException: " . $e->getMessage() . "\n";
} catch (Exception $e) {
    echo "   Caught Exception: " . $e->getMessage() . "\n";
}
echo "\n";

// 7. 复杂的类型转换和判断
echo "7. Advanced Type Operations Test:\n";

function analyzeType(mixed $value): string {
    if (is_int($value)) return "integer: $value";
    if (is_float($value)) return "float: $value";
    if (is_string($value)) return "string: $value";
    if (is_bool($value)) return "bool: " . ($value ? "true" : "false");
    if (is_array($value)) return "array: " . count($value) . " elements";
    if (is_null($value)) return "null";
    return "unknown";
}

echo "   " . analyzeType(42) . "\n";
echo "   " . analyzeType(3.14) . "\n";
echo "   " . analyzeType("hello") . "\n";
echo "   " . analyzeType(true) . "\n";
echo "   " . analyzeType([1, 2, 3]) . "\n";
echo "   " . analyzeType(null) . "\n";
echo "\n";

// 8. 复杂的循环和控制流
echo "8. Advanced Control Flow Test:\n";

$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

$sum = 0;
$count = 0;

foreach ($matrix as $row) {
    foreach ($row as $value) {
        if ($value % 2 === 0) {
            $sum += $value;
            $count++;
        }
    }
}

echo "   Even numbers sum: $sum\n";
echo "   Even numbers count: $count\n";
echo "   Average: " . ($count > 0 ? $sum / $count : 0) . "\n";
echo "\n";

echo "=== All Advanced Tests Passed ===\n";
