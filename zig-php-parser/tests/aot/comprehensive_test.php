<?php
// 综合测试：复杂嵌套、封装、函数、逻辑
echo "=== Comprehensive AOT Test ===\n\n";

// 1. 复杂类层次结构
class Animal {
    protected $name;
    protected $age;
    
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function speak() {
        return "Animal sound";
    }
    
    public function getInfo() {
        return $this->name . " is " . $this->age . " years old";
    }
}

class Dog extends Animal {
    private $breed;
    
    public function __construct($name, $age, $breed) {
        parent::__construct($name, $age);
        $this->breed = $breed;
    }
    
    public function speak() {
        return "Woof! I'm " . $this->name;
    }
    
    public function getBreed() {
        return $this->breed;
    }
}

// 2. 嵌套循环和条件
function complexNested($n) {
    $result = 0;
    for ($i = 0; $i < $n; $i++) {
        for ($j = 0; $j < $n; $j++) {
            if ($i % 2 == 0) {
                if ($j % 2 == 0) {
                    $result += $i * $j;
                } else {
                    $result += $i + $j;
                }
            } else {
                $result += $i - $j;
            }
        }
    }
    return $result;
}

// 3. 递归函数
function fibonacci($n) {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

// 4. 数组操作
function arrayOperations() {
    $arr = array();
    for ($i = 0; $i < 10; $i++) {
        $arr[] = $i * 2;
    }
    
    $sum = array_sum($arr);
    $count = count($arr);
    $filtered = array();
    
    foreach ($arr as $val) {
        if ($val > 5) {
            $filtered[] = $val;
        }
    }
    
    return array($sum, $count, count($filtered));
}

// 5. 字符串操作
function stringOperations($str) {
    $result = "";
    $len = strlen($str);
    
    for ($i = 0; $i < $len; $i++) {
        $result .= $str;
    }
    
    return strlen($result);
}

// 6. 闭包和高阶函数
function higherOrder($n) {
    $multiplier = function($x) use ($n) {
        return $x * $n;
    };
    
    $result = 0;
    for ($i = 0; $i < 5; $i++) {
        $result += $multiplier($i);
    }
    
    return $result;
}

// 7. 异常处理
function divideWithException($a, $b) {
    if ($b == 0) {
        throw new Exception("Division by zero");
    }
    return $a / $b;
}

// 8. 引用传递
function modifyByReference(&$value) {
    $value *= 2;
}

// 执行测试
echo "1. OOP Test:\n";
$dog = new Dog("Buddy", 5, "Golden Retriever");
echo "   " . $dog->speak() . "\n";
echo "   " . $dog->getInfo() . "\n";
echo "   Breed: " . $dog->getBreed() . "\n\n";

echo "2. Nested Loops Test:\n";
$nested = complexNested(10);
echo "   Result: $nested\n\n";

echo "3. Recursion Test:\n";
$fib = fibonacci(10);
$fact = factorial(5);
echo "   Fibonacci(10): $fib\n";
echo "   Factorial(5): $fact\n\n";

echo "4. Array Operations Test:\n";
list($sum, $count, $filtered) = arrayOperations();
echo "   Sum: $sum, Count: $count, Filtered: $filtered\n\n";

echo "5. String Operations Test:\n";
$strLen = stringOperations("test");
echo "   Result length: $strLen\n\n";

echo "6. Closure Test:\n";
$closure = higherOrder(3);
echo "   Result: $closure\n\n";

echo "7. Exception Test:\n";
try {
    $result = divideWithException(10, 2);
    echo "   10 / 2 = $result\n";
    $result = divideWithException(10, 0);
    echo "   This should not print\n";
} catch (Exception $e) {
    echo "   Caught: " . $e->getMessage() . "\n";
}
echo "\n";

echo "8. Reference Test:\n";
$value = 10;
echo "   Before: $value\n";
modifyByReference($value);
echo "   After: $value\n\n";

// 9. 内存压力测试
echo "9. Memory Stress Test:\n";
$arr = array();
for ($i = 0; $i < 1000; $i++) {
    $arr[] = "String $i";
}
echo "   Created " . count($arr) . " strings\n\n";

// 10. 混合类型操作
echo "10. Mixed Type Test:\n";
$int = 42;
$float = 3.14;
$string = "100";
$bool = true;

$result = $int + $float;
echo "   Int + Float: $result\n";
$result = $int + $string;
echo "   Int + String: $result\n";
$result = $bool ? "true" : "false";
echo "   Bool: $result\n\n";

echo "=== All Tests Completed ===\n";
