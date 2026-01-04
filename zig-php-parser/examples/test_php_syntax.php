<?php

// PHP语法测试脚本 - 包含递归、闭包、全局变量等特性
// Zig-PHP-Parser 测试用例

// ==================== 全局常量 ====================
const APP_NAME = "Zig-PHP-Parser";
const VERSION = "1.0.0";
const DEBUG = true;

// ==================== 全局变量 ====================
$global_counter = 0;
$global_data = ["initialized" => true, "timestamp" => time()];

// ==================== 递归函数 ====================
function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

function fibonacci($n) {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

// ==================== 闭包和匿名函数 ====================
$closure_add = function($a, $b) {
    return $a + $b;
};

$closure_counter = function() use (&$global_counter) {
    $global_counter++;
    return $global_counter;
};

$arrow_function = fn($x) => $x * 2;

// ==================== 静态变量和方法 ====================
class MathUtils {
    public static $instance_count = 0;
    private static $cache = [];

    public static function getInstanceCount() {
        return self::$instance_count;
    }

    public static function fibonacci_static($n) {
        if ($n <= 1) {
            return $n;
        }

        if (isset(self::$cache[$n])) {
            return self::$cache[$n];
        }

        $result = self::fibonacci_static($n - 1) + self::fibonacci_static($n - 2);
        self::$cache[$n] = $result;
        return $result;
    }

    public function __construct() {
        self::$instance_count++;
    }
}

// ==================== 魔术方法 ====================
class TestClass {
    private $data = [];
    private $name;

    public function __construct($name = "TestObject") {
        $this->name = $name;
        echo "Constructing: {$this->name}\n";
    }

    public function __destruct() {
        echo "Destructing: {$this->name}\n";
    }

    public function __clone() {
        $this->name = $this->name . "_cloned";
        echo "Cloning: {$this->name}\n";
    }

    public function __toString() {
        return "TestClass: {$this->name}, Data count: " . count($this->data);
    }

    public function __get($property) {
        return $this->data[$property] ?? "Property {$property} not found";
    }

    public function __set($property, $value) {
        $this->data[$property] = $value;
        echo "Setting {$property} = {$value}\n";
    }

    public function __isset($property) {
        return isset($this->data[$property]);
    }

    public function __unset($property) {
        unset($this->data[$property]);
        echo "Unsetting {$property}\n";
    }

    public function __call($method, $args) {
        return "Called non-existent method: {$method} with " . count($args) . " arguments";
    }

    public static function __callStatic($method, $args) {
        return "Called non-existent static method: {$method}";
    }
}

// ==================== 静态类和方法测试 ====================
class StaticTest {
    public static $static_property = "static value";
    private static $private_static = "private static";

    public static function staticMethod() {
        return "Static method called: " . self::$private_static;
    }

    public static function callPrivateStatic() {
        return self::$private_static;
    }
}

// ==================== Clone测试 ====================
class CloneableClass {
    public $value;

    public function __construct($value) {
        $this->value = $value;
    }

    public function __clone() {
        $this->value = $this->value . " (cloned)";
    }

    public function getValue() {
        return $this->value;
    }
}

// ==================== 数组和对象操作 ====================
$test_array = [
    "numbers" => [1, 2, 3, 4, 5],
    "strings" => ["hello", "world", "php", "zig"],
    "objects" => []
];

// ==================== 主测试逻辑 ====================

echo "=== PHP语法测试开始 ===\n\n";

// 测试全局常量
echo "全局常量测试:\n";
echo "APP_NAME: " . APP_NAME . "\n";
echo "VERSION: " . VERSION . "\n";
echo "DEBUG: " . (DEBUG ? "true" : "false") . "\n\n";

// 测试全局变量
echo "全局变量测试:\n";
echo "global_counter: {$global_counter}\n";
echo "global_data initialized: " . ($global_data["initialized"] ? "true" : "false") . "\n\n";

// 测试递归函数
echo "递归函数测试:\n";
echo "factorial(5) = " . factorial(5) . "\n";
echo "fibonacci(10) = " . fibonacci(10) . "\n\n";

// 测试闭包
echo "闭包测试:\n";
echo "closure_add(3, 4) = " . $closure_add(3, 4) . "\n";
echo "closure_counter() = " . $closure_counter() . "\n";
echo "closure_counter() = " . $closure_counter() . "\n";
echo "arrow_function(5) = " . $arrow_function(5) . "\n\n";

// 测试静态类和方法
echo "静态类和方法测试:\n";
echo "MathUtils::getInstanceCount() = " . MathUtils::getInstanceCount() . "\n";
echo "MathUtils::fibonacci_static(10) = " . MathUtils::fibonacci_static(10) . "\n";
echo "MathUtils::fibonacci_static(10) = " . MathUtils::fibonacci_static(10) . " (cached)\n\n";

// 创建对象实例测试魔术方法
echo "魔术方法测试:\n";
$test_obj = new TestClass("TestInstance");
$test_obj->dynamic_property = "dynamic value";
echo "test_obj->dynamic_property = " . $test_obj->dynamic_property . "\n";
echo "isset(test_obj->dynamic_property) = " . (isset($test_obj->dynamic_property) ? "true" : "false") . "\n";
echo "test_obj->nonexistent = " . $test_obj->nonexistent . "\n";
echo "test_obj->callNonExistent() = " . $test_obj->callNonExistent("arg1", "arg2") . "\n";
echo "TestClass::callStaticNonExistent() = " . TestClass::callStaticNonExistent() . "\n";
echo "(string)test_obj = " . $test_obj . "\n\n";

// 测试clone
echo "Clone测试:\n";
$original = new CloneableClass("original value");
$cloned = clone $original;
echo "original value: " . $original->getValue() . "\n";
echo "cloned value: " . $cloned->getValue() . "\n\n";

// 测试静态方法
echo "静态方法测试:\n";
echo "StaticTest::staticMethod() = " . StaticTest::staticMethod() . "\n";
echo "StaticTest::\$static_property = " . StaticTest::$static_property . "\n";
echo "StaticTest::callPrivateStatic() = " . StaticTest::callPrivateStatic() . "\n\n";

// 测试数组操作
echo "数组操作测试:\n";
$test_array["objects"][] = $test_obj;
$test_array["objects"][] = new TestClass("ArrayObject");
echo "Array has " . count($test_array["numbers"]) . " numbers\n";
echo "Array has " . count($test_array["strings"]) . " strings\n";
echo "Array has " . count($test_array["objects"]) . " objects\n\n";

// 测试全局变量修改
echo "全局变量修改测试:\n";
$global_counter = 100;
echo "Modified global_counter: {$global_counter}\n";
$global_data["modified"] = true;
echo "Added to global_data: " . ($global_data["modified"] ? "true" : "false") . "\n\n";

echo "=== PHP语法测试完成 ===\n";

// 返回测试结果
return [
    "factorial_5" => factorial(5),
    "fibonacci_10" => fibonacci(10),
    "static_fib" => MathUtils::fibonacci_static(10),
    "global_counter" => $global_counter,
    "test_passed" => true
];
