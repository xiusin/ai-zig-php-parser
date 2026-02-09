<?php
/**
 * AOT 编译测试 - 类、函数、递归
 */

echo "=== 基础类测试 ===\n";

class Person {
    public $name;
    public $age;
    
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function greet() {
        return "Hello, I'm " . $this->name . ", age " . $this->age;
    }
}

$person = new Person("Alice", 30);
echo $person->greet() . "\n";

echo "\n=== 静态方法测试 ===\n";

class Math {
    public static function add($a, $b) {
        return $a + $b;
    }
    
    public static function multiply($a, $b) {
        return $a * $b;
    }
    
    public static function power($base, $exp) {
        $result = 1;
        for ($i = 0; $i < $exp; $i++) {
            $result = $result * $base;
        }
        return $result;
    }
}

echo "5 + 3 = " . Math::add(5, 3) . "\n";
echo "4 * 7 = " . Math::multiply(4, 7) . "\n";
echo "2 ^ 8 = " . Math::power(2, 8) . "\n";

echo "\n=== 递归函数测试 ===\n";

function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

echo "5! = " . factorial(5) . "\n";
echo "10! = " . factorial(10) . "\n";

function fibonacci($n) {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

echo "fib(10) = " . fibonacci(10) . "\n";

echo "\n=== 链式调用测试 ===\n";

class Calculator {
    public $value = 0;
    
    public function add($n) {
        $this->value = $this->value + $n;
        return $this;
    }
    
    public function multiply($n) {
        $this->value = $this->value * $n;
        return $this;
    }
    
    public function getValue() {
        return $this->value;
    }
}

$calc = new Calculator();
$result = $calc->add(10)->multiply(2)->getValue();
echo "10 + 10 = 20, 20 * 2 = " . $result . "\n";

echo "\n=== 高阶函数测试 ===\n";

function applyTwice($func, $value) {
    return $func($func($value));
}

function double($x) {
    return $x * 2;
}

echo "double(double(5)) = " . applyTwice("double", 5) . "\n";

echo "\n=== 数组操作测试 ===\n";

function sumArray($arr) {
    $sum = 0;
    foreach ($arr as $val) {
        $sum = $sum + $val;
    }
    return $sum;
}

$numbers = [1, 2, 3, 4, 5];
echo "sum([1,2,3,4,5]) = " . sumArray($numbers) . "\n";

echo "\n=== 所有测试完成 ===\n";
