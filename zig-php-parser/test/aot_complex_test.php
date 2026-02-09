<?php
// 复杂特性综合测试

// ========== 1. 复杂类和方法 ==========
class Animal {
    public $name;
    public $age;
    
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

class Dog {
    public $name;
    public $age;
    public $breed;
    
    public function __construct($name, $age, $breed) {
        $this->name = $name;
        $this->age = $age;
        $this->breed = $breed;
    }
    
    public function speak() {
        return "Woof! I'm " . $this->name;
    }
    
    public function getBreed() {
        return $this->breed;
    }
    
    public function getInfo() {
        return $this->name . " is " . $this->age . " years old";
    }
}

class Cat {
    public $name;
    public $age;
    
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function speak() {
        return "Meow! I'm " . $this->name;
    }
    
    public function purr() {
        return $this->name . " is purring";
    }
}

echo "=== 类和对象测试 ===\n";
$dog = new Dog("Buddy", 3, "Golden Retriever");
echo $dog->speak() . "\n";
echo $dog->getInfo() . "\n";
echo "Breed: " . $dog->getBreed() . "\n";

$cat = new Cat("Whiskers", 2);
echo $cat->speak() . "\n";
echo $cat->purr() . "\n\n";

// ========== 2. 复杂数组操作 ==========
echo "=== 复杂数组操作 ===\n";

$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$sum = 0;
foreach ($numbers as $num) {
    $sum += $num;
}
echo "Sum: " . $sum . "\n";

// 嵌套数组
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

echo "Matrix:\n";
foreach ($matrix as $row) {
    foreach ($row as $val) {
        echo $val . " ";
    }
    echo "\n";
}

// 关联数组
$person = [
    "name" => "John",
    "age" => 30,
    "city" => "New York"
];

echo "Person: " . $person["name"] . ", " . $person["age"] . ", " . $person["city"] . "\n\n";

// ========== 3. 闭包和高阶函数 ==========
echo "=== 闭包和高阶函数 ===\n";

function makeMultiplier($factor) {
    return function($x) use ($factor) {
        return $x * $factor;
    };
}

$double = makeMultiplier(2);
$triple = makeMultiplier(3);

echo "double(5) = " . $double(5) . "\n";
echo "triple(5) = " . $triple(5) . "\n";

function applyTwice($func, $value) {
    return $func($func($value));
}

echo "applyTwice(double, 5) = " . applyTwice($double, 5) . "\n\n";

// ========== 4. 复杂递归 ==========
echo "=== 复杂递归 ===\n";

function ackermann($m, $n) {
    if ($m == 0) {
        return $n + 1;
    } elseif ($n == 0) {
        return ackermann($m - 1, 1);
    } else {
        return ackermann($m - 1, ackermann($m, $n - 1));
    }
}

echo "ackermann(2, 3) = " . ackermann(2, 3) . "\n";

function gcd($a, $b) {
    if ($b == 0) {
        return $a;
    }
    return gcd($b, $a % $b);
}

echo "gcd(48, 18) = " . gcd(48, 18) . "\n\n";

// ========== 5. 字符串处理 ==========
echo "=== 字符串处理 ===\n";

$text = "Hello World";
echo "Original: " . $text . "\n";
echo "Length: " . strlen($text) . "\n";
echo "Upper: " . strtoupper($text) . "\n";
echo "Lower: " . strtolower($text) . "\n";
echo "Substr(0,5): " . substr($text, 0, 5) . "\n";
echo "Replace: " . str_replace("World", "PHP", $text) . "\n\n";

// ========== 6. 数学运算 ==========
echo "=== 数学运算 ===\n";

echo "abs(-42) = " . abs(-42) . "\n";
echo "sqrt(16) = " . sqrt(16) . "\n";
echo "pow(2, 10) = " . pow(2, 10) . "\n";
echo "max(5, 10) = " . max(5, 10) . "\n";
echo "min(5, 10) = " . min(5, 10) . "\n";
echo "round(3.7) = " . round(3.7) . "\n";
echo "floor(3.7) = " . floor(3.7) . "\n";
echo "ceil(3.2) = " . ceil(3.2) . "\n\n";

// ========== 7. 类型检查和转换 ==========
echo "=== 类型检查和转换 ===\n";

$var1 = 42;
$var2 = "123";
$var3 = 3.14;
$var4 = true;

echo "is_int(42): " . (is_int($var1) ? "true" : "false") . "\n";
echo "is_string('123'): " . (is_string($var2) ? "true" : "false") . "\n";
echo "is_float(3.14): " . (is_float($var3) ? "true" : "false") . "\n";
echo "is_bool(true): " . (is_bool($var4) ? "true" : "false") . "\n";
echo "is_numeric('123'): " . (is_numeric($var2) ? "true" : "false") . "\n\n";

// ========== 8. 复杂控制流 ==========
echo "=== 复杂控制流 ===\n";

for ($i = 1; $i <= 5; $i++) {
    if ($i % 2 == 0) {
        echo $i . " is even\n";
    } else {
        echo $i . " is odd\n";
    }
}

$count = 0;
while ($count < 3) {
    echo "Count: " . $count . "\n";
    $count++;
}

echo "\n";

// ========== 9. 静态方法 ==========
echo "=== 静态方法 ===\n";

class MathHelper {
    public static function square($x) {
        return $x * $x;
    }
    
    public static function cube($x) {
        return $x * $x * $x;
    }
}

echo "square(5) = " . MathHelper::square(5) . "\n";
echo "cube(3) = " . MathHelper::cube(3) . "\n\n";

// ========== 10. 复杂对象交互 ==========
echo "=== 复杂对象交互 ===\n";

class Calculator {
    private $result;
    
    public function __construct($initial = 0) {
        $this->result = $initial;
    }
    
    public function add($value) {
        $this->result += $value;
        return $this;
    }
    
    public function multiply($value) {
        $this->result *= $value;
        return $this;
    }
    
    public function subtract($value) {
        $this->result -= $value;
        return $this;
    }
    
    public function divide($value) {
        if ($value != 0) {
            $this->result /= $value;
        }
        return $this;
    }
    
    public function getResult() {
        return $this->result;
    }
}

$calc = new Calculator(10);
$result = $calc->add(5)->multiply(2)->subtract(10)->divide(2)->getResult();
echo "Calculator result: " . $result . "\n\n";

// ========== 11. 数组函数 ==========
echo "=== 数组函数 ===\n";

$arr = [5, 2, 8, 1, 9, 3];
echo "Original: [" . implode(", ", $arr) . "]\n";
echo "Count: " . count($arr) . "\n";
echo "Sum: " . array_sum($arr) . "\n";

$arr2 = [1, 2, 3];
$arr3 = [4, 5, 6];
$merged = array_merge($arr2, $arr3);
echo "Merged: [" . implode(", ", $merged) . "]\n\n";

// ========== 12. 复杂条件表达式 ==========
echo "=== 复杂条件表达式 ===\n";

function classify($num) {
    if ($num > 0 && $num < 10) {
        return "small positive";
    } elseif ($num >= 10 && $num < 100) {
        return "medium positive";
    } elseif ($num >= 100) {
        return "large positive";
    } elseif ($num < 0 && $num > -10) {
        return "small negative";
    } else {
        return "other";
    }
}

echo "classify(5): " . classify(5) . "\n";
echo "classify(50): " . classify(50) . "\n";
echo "classify(500): " . classify(500) . "\n";
echo "classify(-5): " . classify(-5) . "\n\n";

// ========== 13. 嵌套函数调用 ==========
echo "=== 嵌套函数调用 ===\n";

function add($a, $b) {
    return $a + $b;
}

function multiply($a, $b) {
    return $a * $b;
}

$result = multiply(add(2, 3), add(4, 5));
echo "multiply(add(2,3), add(4,5)) = " . $result . "\n\n";

// ========== 14. 对象数组 ==========
echo "=== 对象数组 ===\n";

class Point {
    public $x;
    public $y;
    
    public function __construct($x, $y) {
        $this->x = $x;
        $this->y = $y;
    }
    
    public function distance() {
        return sqrt($this->x * $this->x + $this->y * $this->y);
    }
}

$points = [
    new Point(3, 4),
    new Point(5, 12),
    new Point(8, 15)
];

foreach ($points as $i => $point) {
    $dist = $point->distance();
    echo "Point " . $i . ": (" . $point->x . ", " . $point->y . ") distance = " . $dist . "\n";
}

echo "\n=== 所有测试完成 ===\n";
