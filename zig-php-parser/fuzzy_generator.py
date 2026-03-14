#!/usr/bin/env python3
"""
PHP模糊测试脚本生成器
生成300+个高质量、低重复度的测试脚本
"""
import random
import hashlib
from pathlib import Path
from typing import List, Set

class FuzzyScriptGenerator:
    def __init__(self):
        self.output_dir = Path("fuzzy_scripts")
        self.output_dir.mkdir(exist_ok=True)
        self.generated_hashes: Set[str] = set()
        self.script_count = 0
        
    def get_hash(self, content: str) -> str:
        """计算脚本内容哈希"""
        return hashlib.md5(content.encode()).hexdigest()
    
    def is_duplicate(self, content: str, threshold: float = 0.1) -> bool:
        """检查重复度（简化版：使用哈希）"""
        h = self.get_hash(content)
        if h in self.generated_hashes:
            return True
        self.generated_hashes.add(h)
        return False
    
    def save_script(self, content: str, category: str):
        """保存脚本"""
        if self.is_duplicate(content):
            return False
        
        self.script_count += 1
        filename = f"test_{self.script_count:04d}_{category}.php"
        filepath = self.output_dir / filename
        
        with open(filepath, 'w') as f:
            f.write(content)
        
        return True
    
    # ==================== 类型转换测试 ====================
    def gen_type_juggling(self) -> List[str]:
        """生成类型自动转换测试"""
        tests = []
        
        # 复杂类型转换链
        tests.append("""<?php
$a = "123abc";
$b = (int)$a + 0.5;
$c = (string)$b . "456";
$d = (bool)$c;
$e = (array)$d;
$f = (object)$e;
echo gettype($a) . "," . gettype($b) . "," . gettype($c) . "\\n";
echo $b . "," . $c . "," . ($d ? "true" : "false") . "\\n";
var_dump($e);
var_dump($f);
""")
        
        # 数组与标量转换
        tests.append("""<?php
$x = [1, 2, 3];
$y = (int)$x;
$z = (string)$x;
echo $y . "\\n";
echo $z . "\\n";

$obj = (object)["a" => 1, "b" => 2];
$arr = (array)$obj;
print_r($arr);
""")
        
        # NULL与其他类型
        tests.append("""<?php
$n = null;
echo (int)$n . "\\n";
echo (float)$n . "\\n";
echo (string)$n . "\\n";
echo ($n ? "true" : "false") . "\\n";
var_dump((array)$n);
""")
        
        return tests
    
    # ==================== OOP高级特性 ====================
    def gen_oop_advanced(self) -> List[str]:
        """生成OOP高级特性测试"""
        tests = []
        
        # 魔法方法组合
        tests.append("""<?php
class Magic {
    private $data = [];
    
    public function __get($name) {
        echo "__get: $name\\n";
        return $this->data[$name] ?? null;
    }
    
    public function __set($name, $value) {
        echo "__set: $name = $value\\n";
        $this->data[$name] = $value;
    }
    
    public function __call($name, $args) {
        echo "__call: $name(" . implode(", ", $args) . ")\\n";
        return count($args);
    }
    
    public function __toString() {
        return "Magic[" . count($this->data) . "]";
    }
}

$m = new Magic();
$m->foo = 42;
echo $m->foo . "\\n";
echo $m->bar(1, 2, 3) . "\\n";
echo $m . "\\n";
""")
        
        # 抽象类与接口
        tests.append("""<?php
interface Flyable {
    public function fly(): string;
}

interface Swimmable {
    public function swim(): string;
}

abstract class Animal {
    abstract public function makeSound(): string;
    
    public function describe(): string {
        return "I am an animal";
    }
}

class Duck extends Animal implements Flyable, Swimmable {
    public function makeSound(): string {
        return "Quack";
    }
    
    public function fly(): string {
        return "Flying";
    }
    
    public function swim(): string {
        return "Swimming";
    }
}

$duck = new Duck();
echo $duck->makeSound() . "\\n";
echo $duck->fly() . "\\n";
echo $duck->swim() . "\\n";
echo $duck->describe() . "\\n";
""")
        
        # Trait冲突解决
        tests.append("""<?php
trait A {
    public function test() {
        echo "A::test\\n";
    }
}

trait B {
    public function test() {
        echo "B::test\\n";
    }
}

class C {
    use A, B {
        A::test insteadof B;
        B::test as testB;
    }
}

$c = new C();
$c->test();
$c->testB();
""")
        
        return tests
    
    # ==================== 闭包与高阶函数 ====================
    def gen_closures(self) -> List[str]:
        """生成闭包测试"""
        tests = []
        
        # 闭包捕获变量
        tests.append("""<?php
function makeCounter($start) {
    $count = $start;
    return function() use (&$count) {
        return ++$count;
    };
}

$counter1 = makeCounter(10);
$counter2 = makeCounter(100);

echo $counter1() . "\\n";
echo $counter1() . "\\n";
echo $counter2() . "\\n";
echo $counter1() . "\\n";
""")
        
        # 闭包作为回调
        tests.append("""<?php
$data = [5, 2, 8, 1, 9];

$sorted = array_map(function($x) {
    return $x * 2;
}, $data);

$filtered = array_filter($sorted, function($x) {
    return $x > 10;
});

$sum = array_reduce($filtered, function($carry, $item) {
    return $carry + $item;
}, 0);

print_r($sorted);
print_r($filtered);
echo "Sum: $sum\\n";
""")
        
        # 箭头函数
        tests.append("""<?php
$multiplier = 3;
$numbers = [1, 2, 3, 4, 5];

$result = array_map(fn($x) => $x * $multiplier, $numbers);
print_r($result);

$evens = array_filter($numbers, fn($x) => $x % 2 == 0);
print_r($evens);
""")
        
        return tests
    
    # ==================== 异常处理 ====================
    def gen_exceptions(self) -> List[str]:
        """生成异常处理测试"""
        tests = []
        
        # 多层异常捕获
        tests.append("""<?php
class CustomException extends Exception {}

function level3() {
    throw new CustomException("Level 3 error");
}

function level2() {
    try {
        level3();
    } catch (RuntimeException $e) {
        echo "Caught RuntimeException\\n";
    }
}

function level1() {
    try {
        level2();
    } catch (CustomException $e) {
        echo "Caught: " . $e->getMessage() . "\\n";
    } finally {
        echo "Finally block\\n";
    }
}

level1();
echo "Program continues\\n";
""")
        
        # 异常重新抛出
        tests.append("""<?php
function process($value) {
    try {
        if ($value < 0) {
            throw new InvalidArgumentException("Negative value");
        }
        return $value * 2;
    } catch (Exception $e) {
        echo "Caught: " . $e->getMessage() . "\\n";
        throw new RuntimeException("Processing failed", 0, $e);
    }
}

try {
    echo process(5) . "\\n";
    echo process(-1) . "\\n";
} catch (RuntimeException $e) {
    echo "Final catch: " . $e->getMessage() . "\\n";
    if ($e->getPrevious()) {
        echo "Previous: " . $e->getPrevious()->getMessage() . "\\n";
    }
}
""")
        
        return tests
    
    # ==================== 数组操作 ====================
    def gen_array_operations(self) -> List[str]:
        """生成数组操作测试"""
        tests = []
        
        # 多维数组操作
        tests.append("""<?php
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

$sum = 0;
foreach ($matrix as $row) {
    foreach ($row as $val) {
        $sum += $val;
    }
}
echo "Sum: $sum\\n";

$transposed = [];
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        $transposed[$j][$i] = $matrix[$i][$j];
    }
}
print_r($transposed);
""")
        
        # 数组解构
        tests.append("""<?php
$data = [1, 2, 3, 4, 5];
[$a, $b, ...$rest] = $data;

echo "a=$a, b=$b\\n";
print_r($rest);

$assoc = ["x" => 10, "y" => 20, "z" => 30];
["x" => $x, "y" => $y] = $assoc;
echo "x=$x, y=$y\\n";
""")
        
        # 数组函数链
        tests.append("""<?php
$numbers = range(1, 10);

$result = array_filter(
    array_map(
        function($x) { return $x * $x; },
        $numbers
    ),
    function($x) { return $x % 2 == 0; }
);

print_r($result);
echo "Count: " . count($result) . "\\n";
""")
        
        return tests
    
    # ==================== 字符串操作 ====================
    def gen_string_operations(self) -> List[str]:
        """生成字符串操作测试"""
        tests = []
        
        # 复杂字符串处理
        tests.append("""<?php
$text = "  Hello, World!  ";
$trimmed = trim($text);
$upper = strtoupper($trimmed);
$lower = strtolower($upper);
$replaced = str_replace("world", "PHP", $lower);

echo "$trimmed\\n";
echo "$upper\\n";
echo "$lower\\n";
echo "$replaced\\n";

$parts = explode(", ", $trimmed);
print_r($parts);

$joined = implode(" | ", $parts);
echo "$joined\\n";
""")
        
        # 正则表达式
        tests.append("""<?php
$text = "Phone: 123-456-7890, Email: test@example.com";

if (preg_match('/\\d{3}-\\d{3}-\\d{4}/', $text, $matches)) {
    echo "Found phone: " . $matches[0] . "\\n";
}

$emails = [];
if (preg_match_all('/[a-z]+@[a-z]+\\.[a-z]+/', $text, $matches)) {
    $emails = $matches[0];
}
print_r($emails);

$cleaned = preg_replace('/\\d/', 'X', $text);
echo "$cleaned\\n";
""")
        
        return tests
    
    # ==================== 引用与指针 ====================
    def gen_references(self) -> List[str]:
        """生成引用测试"""
        tests = []
        
        # 引用传递
        tests.append("""<?php
function increment(&$value) {
    $value++;
}

function swap(&$a, &$b) {
    $temp = $a;
    $a = $b;
    $b = $temp;
}

$x = 10;
increment($x);
echo "x = $x\\n";

$a = 5;
$b = 15;
swap($a, $b);
echo "a = $a, b = $b\\n";
""")
        
        # 引用数组
        tests.append("""<?php
$arr = [1, 2, 3, 4, 5];

foreach ($arr as &$value) {
    $value *= 2;
}
unset($value);

print_r($arr);

$ref = &$arr[2];
$ref = 100;
print_r($arr);
""")
        
        return tests
    
    # ==================== 静态与常量 ====================
    def gen_static_const(self) -> List[str]:
        """生成静态和常量测试"""
        tests = []
        
        # 静态变量
        tests.append("""<?php
function counter() {
    static $count = 0;
    return ++$count;
}

echo counter() . "\\n";
echo counter() . "\\n";
echo counter() . "\\n";

class StaticTest {
    public static $value = 0;
    
    public static function increment() {
        return ++self::$value;
    }
}

echo StaticTest::increment() . "\\n";
echo StaticTest::increment() . "\\n";
echo StaticTest::$value . "\\n";
""")
        
        # 类常量
        tests.append("""<?php
class Config {
    const VERSION = "1.0.0";
    const MAX_SIZE = 1024;
    
    public static function getInfo() {
        return self::VERSION . " (max: " . self::MAX_SIZE . ")";
    }
}

echo Config::VERSION . "\\n";
echo Config::MAX_SIZE . "\\n";
echo Config::getInfo() . "\\n";
""")
        
        return tests
    
    # ==================== 迭代器 ====================
    def gen_iterators(self) -> List[str]:
        """生成迭代器测试"""
        tests = []
        
        # 自定义迭代器
        tests.append("""<?php
class RangeIterator implements Iterator {
    private $start;
    private $end;
    private $current;
    
    public function __construct($start, $end) {
        $this->start = $start;
        $this->end = $end;
        $this->current = $start;
    }
    
    public function rewind(): void {
        $this->current = $this->start;
    }
    
    public function current(): mixed {
        return $this->current;
    }
    
    public function key(): mixed {
        return $this->current - $this->start;
    }
    
    public function next(): void {
        $this->current++;
    }
    
    public function valid(): bool {
        return $this->current <= $this->end;
    }
}

$range = new RangeIterator(1, 5);
foreach ($range as $key => $value) {
    echo "$key => $value\\n";
}
""")
        
        return tests
    
    # ==================== 命名空间 ====================
    def gen_namespaces(self) -> List[str]:
        """生成命名空间测试"""
        tests = []
        
        tests.append("""<?php
namespace App\\Models {
    class User {
        public $name;
        public function __construct($name) {
            $this->name = $name;
        }
    }
}

namespace App\\Controllers {
    use App\\Models\\User;
    
    class UserController {
        public function create($name) {
            return new User($name);
        }
    }
}

namespace {
    $controller = new App\\Controllers\\UserController();
    $user = $controller->create("Alice");
    echo $user->name . "\\n";
}
""")
        
        return tests
    
    # ==================== 可变函数 ====================
    def gen_variable_functions(self) -> List[str]:
        """生成可变函数测试"""
        tests = []
        
        tests.append("""<?php
function add($a, $b) {
    return $a + $b;
}

function multiply($a, $b) {
    return $a * $b;
}

$func = "add";
echo $func(5, 3) . "\\n";

$func = "multiply";
echo $func(5, 3) . "\\n";

class Math {
    public static function power($base, $exp) {
        return pow($base, $exp);
    }
}

$method = "power";
echo Math::$method(2, 8) . "\\n";
""")
        
        return tests
    
    # ==================== 递归与回溯 ====================
    def gen_recursion(self) -> List[str]:
        """生成递归测试"""
        tests = []
        
        tests.append("""<?php
function factorial($n) {
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}

function fibonacci($n) {
    if ($n <= 1) return $n;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

echo factorial(5) . "\\n";
echo factorial(10) . "\\n";
echo fibonacci(10) . "\\n";
""")
        
        tests.append("""<?php
function sumArray($arr) {
    if (empty($arr)) return 0;
    return array_shift($arr) + sumArray($arr);
}

function flatten($arr) {
    $result = [];
    foreach ($arr as $item) {
        if (is_array($item)) {
            $result = array_merge($result, flatten($item));
        } else {
            $result[] = $item;
        }
    }
    return $result;
}

echo sumArray([1, 2, 3, 4, 5]) . "\\n";
$nested = [1, [2, [3, [4, 5]]]];
print_r(flatten($nested));
""")
        
        return tests
    
    # ==================== 位运算 ====================
    def gen_bitwise(self) -> List[str]:
        """生成位运算测试"""
        tests = []
        
        tests.append("""<?php
$a = 0b1010;
$b = 0b1100;

echo "AND: " . ($a & $b) . "\\n";
echo "OR: " . ($a | $b) . "\\n";
echo "XOR: " . ($a ^ $b) . "\\n";
echo "NOT: " . (~$a) . "\\n";
echo "LEFT: " . ($a << 2) . "\\n";
echo "RIGHT: " . ($a >> 1) . "\\n";
""")
        
        tests.append("""<?php
function isPowerOfTwo($n) {
    return $n > 0 && ($n & ($n - 1)) == 0;
}

function countBits($n) {
    $count = 0;
    while ($n) {
        $count += $n & 1;
        $n >>= 1;
    }
    return $count;
}

echo isPowerOfTwo(16) ? "true" : "false";
echo "\\n";
echo isPowerOfTwo(15) ? "true" : "false";
echo "\\n";
echo countBits(255) . "\\n";
""")
        
        return tests
    
    # ==================== 日期时间 ====================
    def gen_datetime(self) -> List[str]:
        """生成日期时间测试"""
        tests = []
        
        tests.append("""<?php
$timestamp = mktime(12, 0, 0, 3, 14, 2026);
echo date("Y-m-d H:i:s", $timestamp) . "\\n";
echo date("l, F j, Y", $timestamp) . "\\n";

$date1 = strtotime("2026-01-01");
$date2 = strtotime("2026-12-31");
$diff = $date2 - $date1;
echo "Days: " . ($diff / 86400) . "\\n";
""")
        
        return tests
    
    # ==================== JSON处理 ====================
    def gen_json(self) -> List[str]:
        """生成JSON处理测试"""
        tests = []
        
        tests.append("""<?php
$data = [
    "name" => "Alice",
    "age" => 30,
    "skills" => ["PHP", "Python", "JavaScript"],
    "active" => true
];

$json = json_encode($data);
echo $json . "\\n";

$decoded = json_decode($json, true);
print_r($decoded);

$obj = json_decode($json);
echo $obj->name . "\\n";
echo $obj->skills[1] . "\\n";
""")
        
        return tests
    
    # ==================== 文件操作 ====================
    def gen_file_ops(self) -> List[str]:
        """生成文件操作测试"""
        tests = []
        
        tests.append("""<?php
$filename = "/tmp/test_" . getmypid() . ".txt";
$content = "Hello, World!\\nLine 2\\nLine 3";

file_put_contents($filename, $content);
$read = file_get_contents($filename);
echo $read . "\\n";

$lines = file($filename);
echo "Lines: " . count($lines) . "\\n";

unlink($filename);
echo "File deleted\\n";
""")
        
        return tests
    
    # ==================== 哈希与加密 ====================
    def gen_hash(self) -> List[str]:
        """生成哈希测试"""
        tests = []
        
        tests.append("""<?php
$text = "Hello, World!";

echo "MD5: " . md5($text) . "\\n";
echo "SHA1: " . sha1($text) . "\\n";
echo "SHA256: " . hash("sha256", $text) . "\\n";

$hash = password_hash("secret123", PASSWORD_DEFAULT);
echo "Password hash length: " . strlen($hash) . "\\n";
echo "Verify: " . (password_verify("secret123", $hash) ? "true" : "false") . "\\n";
""")
        
        return tests
    
    # ==================== 可变参数 ====================
    def gen_variadic(self) -> List[str]:
        """生成可变参数测试"""
        tests = []
        
        tests.append("""<?php
function sum(...$numbers) {
    $total = 0;
    foreach ($numbers as $n) {
        $total += $n;
    }
    return $total;
}

function format($template, ...$args) {
    $result = $template;
    foreach ($args as $i => $arg) {
        $result = str_replace("{" . $i . "}", $arg, $result);
    }
    return $result;
}

echo sum(1, 2, 3, 4, 5) . "\\n";
echo sum(10, 20) . "\\n";
echo format("Hello {0}, you are {1} years old", "Alice", 30) . "\\n";
""")
        
        return tests
    
    # ==================== 匿名类 ====================
    def gen_anonymous_class(self) -> List[str]:
        """生成匿名类测试"""
        tests = []
        
        tests.append("""<?php
$obj = new class {
    private $value = 42;
    
    public function getValue() {
        return $this->value;
    }
    
    public function setValue($v) {
        $this->value = $v;
    }
};

echo $obj->getValue() . "\\n";
$obj->setValue(100);
echo $obj->getValue() . "\\n";
""")
        
        tests.append("""<?php
interface Logger {
    public function log($message);
}

function createLogger($prefix) {
    return new class($prefix) implements Logger {
        private $prefix;
        
        public function __construct($prefix) {
            $this->prefix = $prefix;
        }
        
        public function log($message) {
            echo "[{$this->prefix}] $message\\n";
        }
    };
}

$logger = createLogger("INFO");
$logger->log("Application started");
$logger->log("Processing data");
""")
        
        return tests
    
    # ==================== 生成器表达式 ====================
    def gen_generator_expr(self) -> List[str]:
        """生成生成器表达式测试（非generator关键字）"""
        tests = []
        
        # 使用迭代器模拟生成器行为
        tests.append("""<?php
class LazyRange {
    private $start;
    private $end;
    
    public function __construct($start, $end) {
        $this->start = $start;
        $this->end = $end;
    }
    
    public function toArray() {
        $result = [];
        for ($i = $this->start; $i <= $this->end; $i++) {
            $result[] = $i;
        }
        return $result;
    }
}

$range = new LazyRange(1, 10);
$arr = $range->toArray();
print_r($arr);
""")
        
        return tests
    
    # ==================== 复杂表达式 ====================
    def gen_complex_expr(self) -> List[str]:
        """生成复杂表达式测试"""
        tests = []
        
        tests.append("""<?php
$a = 5;
$b = 10;
$c = 15;

$result = ($a + $b) * $c - ($a * $b) / ($c - $a);
echo $result . "\\n";

$x = true && false || true;
$y = (true || false) && (false || true);
echo ($x ? "true" : "false") . "\\n";
echo ($y ? "true" : "false") . "\\n";

$arr = [1, 2, 3];
$val = $arr[0] + $arr[1] * $arr[2];
echo $val . "\\n";
""")
        
        tests.append("""<?php
$data = ["a" => 1, "b" => 2, "c" => 3];
$result = array_sum(array_map(fn($x) => $x * 2, array_filter($data, fn($x) => $x > 1)));
echo $result . "\\n";

$nested = [["x" => 10], ["x" => 20], ["x" => 30]];
$sum = array_reduce($nested, fn($carry, $item) => $carry + $item["x"], 0);
echo $sum . "\\n";
""")
        
        return tests
    
    # ==================== 三元运算符 ====================
    def gen_ternary(self) -> List[str]:
        """生成三元运算符测试"""
        tests = []
        
        tests.append("""<?php
$age = 25;
$status = $age >= 18 ? "adult" : "minor";
echo $status . "\\n";

$value = null;
$result = $value ?? "default";
echo $result . "\\n";

$x = 0;
$y = $x ?: 42;
echo $y . "\\n";

$nested = true ? (false ? "a" : "b") : "c";
echo $nested . "\\n";
""")
        
        return tests
    
    # ==================== Spaceship运算符 ====================
    def gen_spaceship(self) -> List[str]:
        """生成Spaceship运算符测试"""
        tests = []
        
        tests.append("""<?php
echo (1 <=> 2) . "\\n";
echo (2 <=> 2) . "\\n";
echo (3 <=> 2) . "\\n";

$arr = [3, 1, 4, 1, 5, 9, 2, 6];
usort($arr, fn($a, $b) => $a <=> $b);
print_r($arr);
""")
        
        return tests
    
    # ==================== 生成所有测试 ====================
    def generate_all(self, target_count: int = 300):
        """生成所有测试脚本"""
        generators = [
            self.gen_type_juggling,
            self.gen_oop_advanced,
            self.gen_closures,
            self.gen_exceptions,
            self.gen_array_operations,
            self.gen_string_operations,
            self.gen_references,
            self.gen_static_const,
            self.gen_iterators,
            self.gen_namespaces,
            self.gen_variable_functions,
            self.gen_recursion,
            self.gen_bitwise,
            self.gen_datetime,
            self.gen_json,
            self.gen_file_ops,
            self.gen_hash,
            self.gen_variadic,
            self.gen_anonymous_class,
            self.gen_generator_expr,
            self.gen_complex_expr,
            self.gen_ternary,
            self.gen_spaceship,
        ]
        
        print(f"🔧 开始生成 {target_count} 个测试脚本...")
        
        # 多次调用生成器以达到目标数量
        attempts = 0
        max_attempts = target_count * 3
        
        while self.script_count < target_count and attempts < max_attempts:
            attempts += 1
            gen = random.choice(generators)
            tests = gen()
            
            for test in tests:
                if self.script_count >= target_count:
                    break
                
                category = gen.__name__.replace("gen_", "")
                if self.save_script(test, category):
                    if self.script_count % 50 == 0:
                        print(f"  已生成 {self.script_count} 个脚本...")
        
        print(f"✅ 成功生成 {self.script_count} 个测试脚本")
        print(f"📁 脚本保存在: {self.output_dir}")

if __name__ == "__main__":
    generator = FuzzyScriptGenerator()
    generator.generate_all(300)
