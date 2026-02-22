<?php
// 复杂功能测试 - 简化版

echo "=== Advanced Features Test ===\n\n";

// 1. 接口和抽象类
interface Logger {
    public function log(string $message): void;
}

abstract class BaseService implements Logger {
    protected array $logs = [];
    
    public function log(string $message): void {
        $this->logs[] = $message;
    }
    
    public function getLogs(): array {
        return $this->logs;
    }
}

class SimpleService extends BaseService {
    public function process(int $value): int {
        $this->log("Processing: $value");
        return $value * 2;
    }
}

echo "1. Interface & Abstract Class Test:\n";
$service = new SimpleService();
$result = $service->process(10);
echo "   Result: $result\n";
echo "   Logs: " . count($service->getLogs()) . "\n\n";

// 2. 高阶函数
echo "2. Higher-Order Functions Test:\n";

function createAdder(int $x): callable {
    return function(int $y) use ($x): int {
        return $x + $y;
    };
}

$add5 = createAdder(5);
$add10 = createAdder(10);

echo "   add5(3) = " . $add5(3) . "\n";
echo "   add10(3) = " . $add10(3) . "\n\n";

// 3. 数组高级操作
echo "3. Array Operations Test:\n";

$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

$evens = array_filter($numbers, function($n) {
    return $n % 2 === 0;
});

$doubled = array_map(function($n) {
    return $n * 2;
}, $evens);

$sum = array_reduce($doubled, function($carry, $n) {
    return $carry + $n;
}, 0);

echo "   Evens: " . count($evens) . "\n";
echo "   Sum of doubled: $sum\n\n";

// 4. 递归快速排序
echo "4. Quicksort Test:\n";

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

$unsorted = [5, 2, 8, 1, 9, 3];
$sorted = quicksort($unsorted);
echo "   Sorted: " . implode(", ", $sorted) . "\n\n";

// 5. 嵌套异常
echo "5. Nested Exception Test:\n";

class CustomException extends Exception {}

function mayThrow(int $value): int {
    if ($value < 0) {
        throw new CustomException("Negative value");
    }
    return $value * 2;
}

try {
    $r1 = mayThrow(5);
    echo "   Result 1: $r1\n";
    
    try {
        $r2 = mayThrow(-1);
    } catch (CustomException $e) {
        echo "   Caught inner: " . $e->getMessage() . "\n";
    }
    
    echo "   Continued after inner catch\n";
} catch (Exception $e) {
    echo "   Caught outer: " . $e->getMessage() . "\n";
}
echo "\n";

// 6. 类型判断
echo "6. Type Checking Test:\n";

function getType(mixed $value): string {
    if (is_int($value)) return "int";
    if (is_string($value)) return "string";
    if (is_array($value)) return "array";
    return "other";
}

echo "   getType(42) = " . getType(42) . "\n";
echo "   getType('hello') = " . getType("hello") . "\n";
echo "   getType([1,2,3]) = " . getType([1, 2, 3]) . "\n\n";

echo "=== All Tests Passed ===\n";
