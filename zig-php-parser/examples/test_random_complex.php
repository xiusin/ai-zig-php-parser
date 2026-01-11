<?php
/**
 * 综合复杂随机测试脚本（简化版）
 * 移除了不支持的语法：联合类型、箭头函数引用
 */

// 测试类层次结构
abstract class Animal {
    protected $name;
    protected $age;

    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }

    abstract public function makeSound();

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

    public function makeSound() {
        return "Woof!";
    }

    public function getBreed() {
        return $this->breed;
    }
}

class Cat extends Animal {
    private $indoor;

    public function __construct($name, $age, $indoor = true) {
        parent::__construct($name, $age);
        $this->indoor = $indoor;
    }

    public function makeSound() {
        return "Meow!";
    }

    public function isIndoor() {
        return $this->indoor;
    }
}

// 测试高阶函数和闭包
function createCounter($start) {
    $count = $start;
    return function() use (&$count) {
        $count = $count + 1;
        return $count;
    };
}

function compose($f, $g) {
    return function($x) use ($f, $g) {
        return $f($g($x));
    };
}

// 测试数组操作
function deepMerge($a, $b) {
    foreach ($b as $key => $value) {
        if (is_array($value) && isset($a[$key]) && is_array($a[$key])) {
            $a[$key] = deepMerge($a[$key], $value);
        } else {
            $a[$key] = $value;
        }
    }
    return $a;
}

function groupBy($arr, $keyFn) {
    $result = [];
    foreach ($arr as $item) {
        $key = (string)$keyFn($item);
        if (!isset($result[$key])) {
            $result[$key] = [];
        }
        $result[$key][] = $item;
    }
    return $result;
}

// 测试字符串处理
function slugify($text) {
    $text = strtolower($text);
    $text = str_replace(" ", "-", $text);
    $text = preg_replace("/[^a-z0-9-]/", "", $text);
    return $text;
}

function truncate($text, $length, $suffix = "...") {
    if (strlen($text) <= $length) {
        return $text;
    }
    return substr($text, 0, $length) . $suffix;
}

// 测试函数组合
function addOne($n) { return $n + 1; }
function double($n) { return $n * 2; }
function isEven($n) { return $n % 2 == 0; }

echo "=== Complex Features Test ===\n\n";

// 1. 类继承测试
echo "1. Class Inheritance Test:\n";
$dog = new Dog("Buddy", 3, "Golden Retriever");
echo "   Dog: " . $dog->getInfo() . "\n";
echo "   Sound: " . $dog->makeSound() . "\n";
echo "   Breed: " . $dog->getBreed() . "\n";

$cat = new Cat("Whiskers", 5, false);
echo "   Cat: " . $cat->getInfo() . "\n";
echo "   Sound: " . $cat->makeSound() . "\n";
echo "   Indoor: " . ($cat->isIndoor() ? "Yes" : "No") . "\n\n";

// 2. 闭包测试
echo "2. Closure Test:\n";
$counter = createCounter(10);
echo "   Counter: " . $counter() . "\n";
echo "   Counter: " . $counter() . "\n";
echo "   Counter: " . $counter() . "\n\n";

// 3. 函数组合测试
echo "3. Function Composition Test:\n";
$f = compose("addOne", "double");
echo "   compose(addOne, double)(3) = " . $f(3) . " (expected: 7)\n\n";

// 4. 深度数组合并测试
echo "4. Deep Array Merge Test:\n";
$a = ["a" => 1, "b" => ["x" => 10, "y" => 20], "c" => 3];
$b = ["b" => ["y" => 200, "z" => 30], "c" => 300, "d" => 4];
$merged = deepMerge($a, $b);
echo "   Merged: " . json_encode($merged) . "\n\n";

// 5. 数组分组测试
echo "5. Array Grouping Test:\n";
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$evens = [];
$odds = [];
foreach ($numbers as $n) {
    if ($n % 2 == 0) {
        $evens[] = $n;
    } else {
        $odds[] = $n;
    }
}
echo "   Even: [" . implode(", ", $evens) . "]\n";
echo "   Odd: [" . implode(", ", $odds) . "]\n\n";

// 6. 字符串处理测试
echo "6. String Processing Test:\n";
$text = "Hello World from PHP";
echo "   Original: " . $text . "\n";
echo "   Slugified: " . slugify($text) . "\n";
echo "   Truncated: " . truncate($text, 10, "...") . "\n\n";

// 7. 数组操作测试
echo "7. Array Operations Test:\n";
$products = [
    ["name" => "Apple", "price" => 1.50],
    ["name" => "Banana", "price" => 0.75],
    ["name" => "Orange", "price" => 1.25],
    ["name" => "Grape", "price" => 3.00]
];
$names = [];
foreach ($products as $p) { $names[] = $p["name"]; }
echo "   Product names: " . implode(", ", $names) . "\n";
$total = 0;
foreach ($products as $p) { $total = $total + $p["price"]; }
echo "   Total price: $" . number_format($total, 2) . "\n\n";

// 8. 嵌套闭包测试
echo "8. Nested Closure Test:\n";
$multiplier = function($factor) {
    return function($n) use ($factor) {
        return $n * $factor;
    };
};
$double = $multiplier(2);
$triple = $multiplier(3);
echo "   double(5) = " . $double(5) . "\n";
echo "   triple(5) = " . $triple(5) . "\n\n";

// 9. 回调函数测试
echo "9. Callback Function Test:\n";
$process = function($arr, $callback) {
    $result = [];
    foreach ($arr as $item) {
        $result[] = $callback($item);
    }
    return $result;
};
$numbers = [1, 2, 3, 4, 5];
$squared = $process($numbers, function($n) { return $n * $n; });
echo "   Squared: " . implode(", ", $squared) . "\n\n";

echo "=== Test Complete ===\n";