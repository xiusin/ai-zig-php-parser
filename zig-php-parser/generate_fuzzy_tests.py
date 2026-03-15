#!/usr/bin/env python3
import os
import random
import string

output_dir = "/Users/xiusin/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts"

# 35-60号：更多OOP和功能测试
test_035 = '''<?php
// 测试35: 构造函数属性提升 (PHP 8.0)
class User {
    public function __construct(
        public string $name,
        public int $age,
        public ?string $email = null
    ) {}
    
    public function getInfo(): string {
        return "{$this->name}, {$this->age} years old" . ($this->email ? " ({$this->email})" : "");
    }
}

class Product {
    public function __construct(
        private string $name,
        private float $price,
        private int $stock = 0
    ) {}
    
    public function getPrice(): float {
        return $this->price;
    }
    
    public function isAvailable(): bool {
        return $this->stock > 0;
    }
}

$user = new User("Alice", 30, "alice@example.com");
echo $user->getInfo() . "\\n";
echo "Name: " . $user->name . "\\n";

$product = new Product("Laptop", 999.99, 10);
echo "Price: " . $product->getPrice() . "\\n";
echo "Available: " . ($product->isAvailable() ? "yes" : "no") . "\\n";

// 只读属性 (PHP 8.1)
class Config {
    public function __construct(
        public readonly string $key,
        public readonly array $values
    ) {}
}

$config = new Config("api_key", ["prod", "dev"]);
echo "Key: " . $config->key . "\\n";
// $config->key = "new"; // 错误：只读属性
?>
'''

# 36号：复杂字符串操作
test_036 = '''<?php
// 测试36: 字符串函数边界测试
$str = "Hello World! 你好世界 🌍";

// 多字节函数
echo "Length: " . strlen($str) . "\\n";
echo "MB Length: " . mb_strlen($str) . "\\n";
echo "Substr (0,5): " . substr($str, 0, 5) . "\\n";
echo "MB Substr (0,5): " . mb_substr($str, 0, 5) . "\\n";

// 字符串位置
$pos = strpos($str, "World");
$mbPos = mb_strpos($str, "世界");
echo "Position of 'World': $pos\\n";
echo "MB Position of '世界': $mbPos\\n";

// 分割
$parts = str_split($str, 3);
echo "Split parts: " . count($parts) . "\\n";

$words = explode(" ", "one two three four");
echo "Words: " . implode("-", $words) . "\\n";

// 填充与截取
$padded = str_pad("test", 10, "*", STR_PAD_BOTH);
echo "Padded: $padded\\n";

$repeated = str_repeat("ab", 5);
echo "Repeated: $repeated\\n";

// 比较
echo "Compare 'a' vs 'b': " . strcmp("a", "b") . "\\n";
echo "Case compare 'A' vs 'a': " . strcasecmp("A", "a") . "\\n";

// 打乱
$shuffled = str_shuffle("abcdef");
echo "Shuffled: $shuffled\\n";

// 翻译表
$trans = strtr("hello world", "eo", "30");
echo "Translated: $trans\\n";

// 词首字母大写
$title = ucwords("hello world test");
echo "Title case: $title\\n";
?>
'''

# 37号：数组搜索与排序
test_037 = '''<?php
// 测试37: 数组搜索与高级排序
$fruits = ["apple", "banana", "cherry", "date", "elderberry"];

// 搜索
$pos = array_search("cherry", $fruits);
echo "Position of 'cherry': $pos\\n";

$exists = in_array("banana", $fruits);
echo "'banana' exists: " . ($exists ? "yes" : "no") . "\\n";

// 键搜索
$assoc = ["id" => 1, "name" => "test", "status" => "active"];
$hasKey = array_key_exists("name", $assoc);
echo "Key 'name' exists: " . ($hasKey ? "yes" : "no") . "\\n";

// 排序
$numbers = [5, 2, 8, 1, 9, 3];
sort($numbers);
echo "Sorted: " . implode(", ", $numbers) . "\\n";

rsort($numbers);
echo "Reverse sorted: " . implode(", ", $numbers) . "\\n";

// 关联数组排序
$ages = ["Alice" => 30, "Bob" => 25, "Charlie" => 35];
asort($ages);
echo "Age sorted by value: ";
print_r($ages);

ksort($ages);
echo "Age sorted by key: ";
print_r($ages);

// 自定义排序
$words = ["apple", "pie", "strawberry", "kiwi"];
usort($words, function($a, $b) {
    return strlen($a) <=> strlen($b);
});
echo "Sorted by length: " . implode(", ", $words) . "\\n";

// 多维排序
$users = [
    ["name" => "Alice", "age" => 30],
    ["name" => "Bob", "age" => 25],
    ["name" => "Charlie", "age" => 35],
];

array_multisort(array_column($users, 'age'), SORT_ASC, $users);
echo "Users sorted by age:\\n";
print_r($users);

// 自然排序
$files = ["file1.txt", "file10.txt", "file2.txt"];
natsort($files);
echo "Natural sorted: " . implode(", ", $files) . "\\n";
?>
'''

# 38号：匿名类
test_038 = '''<?php
// 测试38: 匿名类
$logger = new class {
    private $logs = [];
    
    public function log(string $msg): void {
        $this->logs[] = date("H:i:s") . " - " . $msg;
    }
    
    public function getLogs(): array {
        return $this->logs;
    }
};

$logger->log("First message");
$logger->log("Second message");
print_r($logger->getLogs());

// 带构造函数的匿名类
$counter = new class(10) {
    private $count;
    
    public function __construct(int $start) {
        $this->count = $start;
    }
    
    public function increment(): int {
        return ++$this->count;
    }
    
    public function getCount(): int {
        return $this->count;
    }
};

echo "Counter start: " . $counter->getCount() . "\\n";
echo "After increment: " . $counter->increment() . "\\n";

// 实现接口的匿名类
interface Greetable {
    public function greet(string $name): string;
}

$greeter = new class implements Greetable {
    public function greet(string $name): string {
        return "Hello, $name!";
    }
};

echo $greeter->greet("World") . "\\n";

// 继承的匿名类
class BaseProcessor {
    public function process($data) {
        return "Processed: $data";
    }
}

$processor = new class extends BaseProcessor {
    public function process($data) {
        return parent::process(strtoupper($data));
    }
};

echo $processor->process("test") . "\\n";

// 使用trait的匿名类
trait Timestamp {
    public function now(): string {
        return date("Y-m-d H:i:s");
    }
}

$timer = new class {
    use Timestamp;
};

echo "Current time: " . $timer->now() . "\\n";
?>
'''

# 39号：类常量与最终
test_039 = '''<?php
// 测试39: 类常量、最终类与方法
class DatabaseConfig {
    // 常量
    public const HOST = "localhost";
    public const PORT = 3306;
    protected const USER = "admin";
    private const PASS = "secret";
    
    // 最终常量 (PHP 8.1+)
    final public const VERSION = "1.0";
    
    public static function getDSN(): string {
        return "mysql:host=" . self::HOST . ";port=" . self::PORT;
    }
}

class ExtendedConfig extends DatabaseConfig {
    // 可以覆盖父类常量
    public const HOST = "remotehost";
    
    // 不能覆盖final常量
    // public const VERSION = "2.0"; // 错误
}

echo "Base HOST: " . DatabaseConfig::HOST . "\\n";
echo "Extended HOST: " . ExtendedConfig::HOST . "\\n";
echo "VERSION: " . DatabaseConfig::VERSION . "\\n";

// 最终类
final class Utility {
    public static function formatDate($date): string {
        return date("Y-m-d", strtotime($date));
    }
}

// 不能继承final类
// class MyUtility extends Utility {} // 错误

// 最终方法
class BaseService {
    public function process($data): array {
        return [$data];
    }
    
    final public function validate($data): bool {
        return !empty($data);
    }
}

class DerivedService extends BaseService {
    // 可以覆盖非final方法
    public function process($data): array {
        return array_merge(parent::process($data), ["extra"]);
    }
    
    // 不能覆盖final方法
    // public function validate($data): bool {} // 错误
}

$service = new DerivedService();
print_r($service->process("test"));
echo "Valid: " . ($service->validate("data") ? "yes" : "no") . "\\n";

// 只读类 (PHP 8.2+)
// readonly class ImmutablePoint {
//     public function __construct(public float $x, public float $y) {}
// }
?>
'''

# 40号：反射API深度测试
test_040 = '''<?php
// 测试40: 反射API深度测试
class ReflectedClass {
    private string $privateProp = "private";
    protected int $protectedProp = 42;
    public array $publicProp = [];
    
    private function privateMethod(): string {
        return "private";
    }
    
    protected function protectedMethod(): int {
        return 42;
    }
    
    public function publicMethod(string $arg): string {
        return "Result: $arg";
    }
    
    public static function staticMethod(): string {
        return "static";
    }
}

$ref = new ReflectionClass("ReflectedClass");

echo "Class name: " . $ref->getName() . "\\n";
echo "Is instantiable: " . ($ref->isInstantiable() ? "yes" : "no") . "\\n";
echo "Is final: " . ($ref->isFinal() ? "yes" : "no") . "\\n";

// 属性
$props = $ref->getProperties();
echo "\\nProperties (" . count($props) . "):\\n";
foreach ($props as $prop) {
    echo "  " . $prop->getName() . " - " . ($prop->isPrivate() ? "private" : ($prop->isProtected() ? "protected" : "public")) . "\\n";
}

// 方法
$methods = $ref->getMethods();
echo "\\nMethods (" . count($methods) . "):\\n";
foreach ($methods as $method) {
    echo "  " . $method->getName() . "()\\n";
}

// 创建实例并访问私有属性
$instance = $ref->newInstance();
$privateProp = $ref->getProperty("privateProp");
$privateProp->setAccessible(true);
echo "\\nPrivate property value: " . $privateProp->getValue($instance) . "\\n";

// 调用私有方法
$privateMethod = $ref->getMethod("privateMethod");
$privateMethod->setAccessible(true);
echo "Private method result: " . $privateMethod->invoke($instance) . "\\n";

// 检查参数
$publicMethod = $ref->getMethod("publicMethod");
$params = $publicMethod->getParameters();
echo "\\nParameters of publicMethod:\\n";
foreach ($params as $param) {
    echo "  " . $param->getName() . " - type: " . ($param->getType() ? $param->getType()->getName() : "none") . "\\n";
}

// 反射函数
function testFunction(int $a, string $b = "default"): bool {
    return $a > 0;
}

$funcRef = new ReflectionFunction("testFunction");
echo "\\nFunction: " . $funcRef->getName() . "\\n";
echo "Parameters count: " . $funcRef->getNumberOfParameters() . "\\n";
echo "Required parameters: " . $funcRef->getNumberOfRequiredParameters() . "\\n";

// 调用
$result = $funcRef->invoke(10, "test");
echo "Invoke result: " . ($result ? "true" : "false") . "\\n";
?>
'''

# 41-45：更多边界测试
test_041 = '''<?php
// 测试41: 数值边界与溢出
$maxInt = PHP_INT_MAX;
$minInt = PHP_INT_MIN;

echo "PHP_INT_MAX: $maxInt\\n";
echo "PHP_INT_MIN: $minInt\\n";

// 溢出测试
$overflow = $maxInt + 1;
echo "MAX + 1: $overflow\\n";
echo "Type: " . gettype($overflow) . "\\n";

$underflow = $minInt - 1;
echo "MIN - 1: $underflow\\n";

// 浮点数精度
$a = 0.1;
$b = 0.2;
$c = 0.3;
echo "0.1 + 0.2 == 0.3: " . (($a + $b == $c) ? "true" : "false") . "\\n";
echo "0.1 + 0.2: " . ($a + $b) . "\\n";

// 科学计数法
$sci = 1.5e10;
echo "1.5e10: $sci\\n";
echo "1.5e-5: " . 1.5e-5 . "\\n";

// INF和NAN
$inf = 1.0 / 0.0;
$nan = 0.0 / 0.0;
echo "1.0/0.0: $inf\\n";
echo "0.0/0.0: $nan\\n";
echo "is_inf: " . (is_infinite($inf) ? "yes" : "no") . "\\n";
echo "is_nan: " . (is_nan($nan) ? "yes" : "no") . "\\n";
echo "is_finite: " . (is_finite(1.0) ? "yes" : "no") . "\\n";

// 大数处理
$big = "9223372036854775808"; // 超过64位整数
echo "Big string number: $big\\n";

// GMP扩展检查
if (extension_loaded("gmp")) {
    $gmp1 = gmp_init("12345678901234567890");
    $gmp2 = gmp_init("98765432109876543210");
    $sum = gmp_add($gmp1, $gmp2);
    echo "GMP sum: " . gmp_strval($sum) . "\\n";
} else {
    echo "GMP extension not loaded\\n";
}

// BCMath扩展检查
if (extension_loaded("bcmath")) {
    $bc1 = "12345678901234567890.12345";
    $bc2 = "98765432109876543210.54321";
    $sum = bcadd($bc1, $bc2, 5);
    echo "BCMath sum: $sum\\n";
} else {
    echo "BCMath extension not loaded\\n";
}
?>
'''

test_042 = '''<?php
// 测试42: 数组哈希与冲突
// 字符串键的哈希行为
$keys = ["a", "b", "c", "0", "1", "2", "00", "01", "true", "false", "null", ""];
$arr = [];
foreach ($keys as $key) {
    $arr[$key] = "value_$key";
}
echo "Array with string keys:\\n";
print_r($arr);

// 数字字符串键转换
$numKeys = ["0" => "zero", "1" => "one", "2" => "two"];
$intKeys = [0 => "zero_int", 1 => "one_int"];
echo "Numeric string vs int keys:\\n";
echo "numKeys[0]: " . $numKeys[0] . "\\n";
echo "numKeys[\"0\"]: " . $numKeys["0"] . "\\n";

// 大数组性能
$large = [];
for ($i = 0; $i < 1000; $i++) {
    $large["key_$i"] = $i;
}
echo "Large array size: " . count($large) . "\\n";
echo "Memory usage: " . memory_get_usage() . " bytes\\n";

// 稀疏数组
$sparse = [];
$sparse[0] = "first";
$sparse[1000] = "middle";
$sparse[10000] = "last";
echo "Sparse array count: " . count($sparse) . "\\n";
echo "Array keys: " . implode(", ", array_keys($sparse)) . "\\n";

// 数组指针操作
$arr = ["a" => 1, "b" => 2, "c" => 3];
reset($arr);
while (key($arr) !== null) {
    echo key($arr) . " => " . current($arr) . "\\n";
    next($arr);
}

// each()函数 (已废弃，但测试兼容性)
// reset($arr);
// while (list($key, $val) = each($arr)) {
//     echo "$key => $val\\n";
// }
?>
'''

test_043 = '''<?php
// 测试43: 变量变量与动态特性
$a = "hello";
$$a = "world";
echo "hello = $hello\\n";

// 动态函数调用
$func = "strlen";
echo "Dynamic strlen: " . $func("test") . "\\n";

// 动态方法调用
class Dynamic {
    public function method1(): string {
        return "method1 called";
    }
    
    public function method2(): string {
        return "method2 called";
    }
}

$obj = new Dynamic();
$method = "method1";
echo $obj->$method() . "\\n";

// 动态类名
$class = "Dynamic";
$instance = new $class();
echo get_class($instance) . "\\n";

// 可变变量嵌套
$x = "y";
$y = "z";
$z = "final value";
echo "$$$x = " . $$x . "\\n";
echo "$$$$x = " . $$$x . "\\n";

// 动态属性
$prop = "dynamic";
$obj->$prop = "dynamic value";
echo "obj->dynamic = " . $obj->dynamic . "\\n";

// call_user_func
echo call_user_func("strlen", "hello") . "\\n";
echo call_user_func_array([$obj, "method1"], []) . "\\n";

// 动态include (这里只模拟路径)
// $file = "config.php";
// include $file;

// compact与extract
$var1 = "value1";
$var2 = "value2";
$arr = compact("var1", "var2");
echo "Compacted: ";
print_r($arr);

extract(["newVar" => "extracted"]);
echo "Extracted: $newVar\\n";

// 变量引用
$ref1 = "original";
$ref2 = &$ref1;
$ref2 = "modified";
echo "ref1 = $ref1, ref2 = $ref2\\n";
?>
'''

test_044 = '''<?php
// 测试44: 内存管理与性能
$start = microtime(true);

// 大量对象创建
$objects = [];
for ($i = 0; $i < 100; $i++) {
    $objects[] = new stdClass();
}
unset($objects);

// 大量字符串操作
$str = "";
for ($i = 0; $i < 100; $i++) {
    $str .= str_repeat("x", 10);
}
echo "String length: " . strlen($str) . "\\n";
unset($str);

// 内存峰值
echo "Peak memory: " . memory_get_peak_usage() . " bytes\\n";
echo "Current memory: " . memory_get_usage() . " bytes\\n";

// 垃圾回收
gc_enable();
$cycles = gc_collect_cycles();
echo "Collected cycles: $cycles\\n";

// 循环引用垃圾回收
$a = new stdClass();
$b = new stdClass();
$a->ref = $b;
$b->ref = $a;
unset($a, $b);

$cycles2 = gc_collect_cycles();
echo "Collected cycles after circular ref: $cycles2\\n";

// 资源使用
$end = microtime(true);
echo "Execution time: " . ($end - $start) . " seconds\\n";

// getrusage (Unix系统)
if (function_exists("getrusage")) {
    $usage = getrusage();
    echo "User time: " . $usage["ru_utime.tv_sec"] . "\\n";
}

// 内存限制
$limit = ini_get("memory_limit");
echo "Memory limit: $limit\\n";
?>
'''

test_045 = '''<?php
// 测试45: 流与过滤器
$data = "Hello World! This is test data.";

// 临时流
$temp = fopen("php://temp", "r+");
fwrite($temp, $data);
rewind($temp);
$read = fread($temp, 1024);
echo "From temp stream: $read\\n";
fclose($temp);

// 内存流
$memory = fopen("php://memory", "r+");
fwrite($memory, $data);
rewind($memory);
$content = stream_get_contents($memory);
echo "From memory stream: " . strlen($content) . " bytes\\n";
fclose($memory);

// 输入输出流 (只检查是否存在)
echo "STDIN defined: " . (defined("STDIN") ? "yes" : "no") . "\\n";
echo "STDOUT defined: " . (defined("STDOUT") ? "yes" : "no") . "\\n";
echo "STDERR defined: " . (defined("STDERR") ? "yes" : "no") . "\\n";

// 流元数据
$temp2 = fopen("php://temp", "r+");write($temp2, "test");
$meta = stream_get_meta_data($temp2);
echo "Stream metadata:\\n";
print_r($meta);
fclose($temp2);

// 字符串编码转换
if (function_exists("iconv")) {
    $utf8 = "Hello World";
    $gbk = @iconv("UTF-8", "GBK", $utf8);
    echo "Iconv available: yes\\n";
} else {
    echo "Iconv available: no\\n";
}

if (function_exists("mb_convert_encoding")) {
    echo "MBString available: yes\\n";
} else {
    echo "MBString available: no\\n";
}

// 压缩流
if (extension_loaded("zlib")) {
    echo "Zlib available: yes\\n";
    $compressed = gzencode("test data");
    echo "Compressed size: " . strlen($compressed) . "\\n";
} else {
    echo "Zlib available: no\\n";
}
?>
'''

# 将脚本写入文件
scripts = [
    ("test_035_constructor_promotion.php", test_035),
    ("test_036_string_boundary.php", test_036),
    ("test_037_array_search_sort.php", test_037),
    ("test_038_anonymous_class.php", test_038),
    ("test_039_constants_final.php", test_039),
    ("test_040_reflection_deep.php", test_040),
    ("test_041_number_boundary.php", test_041),
    ("test_042_array_hash.php", test_042),
    ("test_043_variable_variables.php", test_043),
    ("test_044_memory_performance.php", test_044),
    ("test_045_stream_filter.php", test_045),
]

for filename, content in scripts:
    with open(f"{output_dir}/{filename}", "w") as f:
        f.write(content)
    print(f"Generated: {filename}")

print("\\nScripts 35-45 generated successfully!")
