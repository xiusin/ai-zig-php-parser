<?php
// 综合测试：已支持的功能

echo "=== 1. 基本类型和运算 ===\n";
$int = 42;
$float = 3.14;
$string = "Hello";
$bool = true;

echo "Int: $int, Float: $float, String: $string, Bool: " . ($bool ? "true" : "false") . "\n";
echo "Math: " . ($int + 10) . ", " . ($float * 2) . "\n";

echo "\n=== 2. 数组操作 ===\n";
$arr = [1, 2, 3, 4, 5];
echo "Array: " . implode(", ", $arr) . "\n";
echo "Count: " . count($arr) . "\n";
echo "First: " . $arr[0] . ", Last: " . $arr[4] . "\n";

$assoc = ["name" => "Alice", "age" => 30];
echo "Name: " . $assoc["name"] . ", Age: " . $assoc["age"] . "\n";

echo "\n=== 3. 控制流 ===\n";
if ($int > 40) {
    echo "Int is greater than 40\n";
} else {
    echo "Int is not greater than 40\n";
}

for ($i = 0; $i < 3; $i++) {
    echo "Loop $i\n";
}

$sum = 0;
foreach ($arr as $val) {
    $sum += $val;
}
echo "Sum: $sum\n";

echo "\n=== 4. 函数 ===\n";
function add(int $a, int $b): int {
    return $a + $b;
}

function greet(string $name): string {
    return "Hello, $name!";
}

echo "add(5, 3) = " . add(5, 3) . "\n";
echo greet("World") . "\n";

echo "\n=== 5. 类和对象 ===\n";
class Point {
    public int $x;
    public int $y;
    
    public function __construct(int $x, int $y) {
        $this->x = $x;
        $this->y = $y;
    }
    
    public function distance(): float {
        return sqrt($this->x * $this->x + $this->y * $this->y);
    }
    
    public function toString(): string {
        return "Point($this->x, $this->y)";
    }
}

$p = new Point(3, 4);
echo $p->toString() . "\n";
echo "Distance: " . $p->distance() . "\n";

echo "\n=== 6. 静态属性和方法 ===\n";
class Counter {
    public static int $count = 0;
    
    public static function increment(): void {
        self::$count++;
    }
    
    public static function getCount(): int {
        return self::$count;
    }
}

Counter::increment();
Counter::increment();
Counter::increment();
echo "Counter: " . Counter::getCount() . "\n";

echo "\n=== 7. 字符串操作 ===\n";
$str = "  Hello World  ";
echo "Original: '$str'\n";
echo "Trimmed: '" . trim($str) . "'\n";
echo "Upper: " . strtoupper($str) . "\n";
echo "Lower: " . strtolower($str) . "\n";
echo "Length: " . strlen(trim($str)) . "\n";
echo "Substr: " . substr($str, 2, 5) . "\n";

echo "\n=== 8. 数组函数 ===\n";
$numbers = [1, 2, 3, 4, 5];
$doubled = array_map(function($x) { return $x * 2; }, $numbers);
echo "Doubled: " . implode(", ", $doubled) . "\n";

$evens = array_filter($numbers, function($x) { return $x % 2 == 0; });
echo "Evens: " . implode(", ", $evens) . "\n";

echo "\n=== 9. 类型转换 ===\n";
$num_str = "123";
$num = (int)$num_str;
echo "String to int: $num\n";
echo "Int to string: " . (string)$num . "\n";

echo "\n=== 10. 三元运算符 ===\n";
$age = 25;
$status = $age >= 18 ? "adult" : "minor";
echo "Status: $status\n";

echo "\n=== 测试完成 ===\n";
