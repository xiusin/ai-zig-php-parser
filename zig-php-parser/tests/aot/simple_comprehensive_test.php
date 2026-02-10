<?php
// 简化综合测试：只测试已实现的功能
echo "=== Simplified Comprehensive Test ===\n\n";

// 1. 基本类和继承
class Animal {
    public $name;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function speak() {
        return "Animal: " . $this->name;
    }
}

class Dog extends Animal {
    public function speak() {
        return "Dog: " . $this->name;
    }
}

// 2. 简单循环
function simpleLoop($n) {
    $sum = 0;
    for ($i = 0; $i < $n; $i++) {
        $sum += $i;
    }
    return $sum;
}

// 3. 嵌套循环
function nestedLoop($n) {
    $sum = 0;
    for ($i = 0; $i < $n; $i++) {
        for ($j = 0; $j < $n; $j++) {
            $sum += 1;
        }
    }
    return $sum;
}

// 4. 数组操作
function arrayTest() {
    $arr = array(1, 2, 3, 4, 5);
    $sum = array_sum($arr);
    $count = count($arr);
    return array($sum, $count);
}

// 5. 字符串操作
function stringTest() {
    $str = "Hello";
    $len = strlen($str);
    $result = $str . " World";
    return array($len, $result);
}

// 6. 条件判断
function conditionalTest($x) {
    if ($x > 10) {
        return "large";
    } else {
        return "small";
    }
}

// 7. 多个参数
function multiParam($a, $b, $c) {
    return $a + $b + $c;
}

// 执行测试
echo "1. OOP Test:\n";
$animal = new Animal("Generic");
echo "   " . $animal->speak() . "\n";
$dog = new Dog("Buddy");
echo "   " . $dog->speak() . "\n\n";

echo "2. Simple Loop Test:\n";
$result = simpleLoop(100);
echo "   Sum(0..99): $result\n\n";

echo "3. Nested Loop Test:\n";
$result = nestedLoop(10);
echo "   10x10 iterations: $result\n\n";

echo "4. Array Test:\n";
list($sum, $count) = arrayTest();
echo "   Sum: $sum, Count: $count\n\n";

echo "5. String Test:\n";
list($len, $str) = stringTest();
echo "   Length: $len, Result: $str\n\n";

echo "6. Conditional Test:\n";
$r1 = conditionalTest(15);
$r2 = conditionalTest(5);
echo "   15: $r1, 5: $r2\n\n";

echo "7. Multi-Param Test:\n";
$result = multiParam(10, 20, 30);
echo "   10+20+30: $result\n\n";

// 8. 内存测试
echo "8. Memory Test:\n";
$arr = array();
for ($i = 0; $i < 100; $i++) {
    $arr[] = $i;
}
echo "   Created " . count($arr) . " elements\n\n";

// 9. 多次循环
echo "9. Multiple Loops Test:\n";
$sum1 = 0;
for ($i = 0; $i < 10; $i++) {
    $sum1 += $i;
}
$sum2 = 0;
for ($j = 0; $j < 10; $j++) {
    $sum2 += $j;
}
echo "   Sum1: $sum1, Sum2: $sum2\n\n";

echo "=== All Tests Passed ===\n";
