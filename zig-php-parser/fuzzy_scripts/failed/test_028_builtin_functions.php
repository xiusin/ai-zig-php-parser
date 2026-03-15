<?php
// 测试28: 内置函数综合测试
// 变量处理
$var = "test";
echo "isset: " . (isset($var) ? "yes" : "no") . "\n";
echo "empty: " . (empty($var) ? "yes" : "no") . "\n";
unset($var);
echo "after unset isset: " . (isset($var) ? "yes" : "no") . "\n";

// 类型检查
$values = [1, 1.5, "string", [], true, null, new stdClass()];
$types = ['int', 'float', 'string', 'array', 'bool', 'null', 'object', 'callable'];
foreach ($values as $val) {
    echo gettype($val) . ": ";
    foreach ($types as $type) {
        $fn = "is_$type";
        if (function_exists($fn)) {
            echo ($fn($val) ? "$type=" : "");
        }
    }
    echo "\n";
}

// 类/对象函数
class TestClass {
    public $prop = "value";
    public function method() {}
}

$obj = new TestClass();
echo "get_class: " . get_class($obj) . "\n";
echo "get_parent_class: " . (get_parent_class($obj) ?: "none") . "\n";
echo "class_exists: " . (class_exists('TestClass') ? "yes" : "no") . "\n";
echo "method_exists: " . (method_exists($obj, 'method') ? "yes" : "no") . "\n";
echo "property_exists: " . (property_exists($obj, 'prop') ? "yes" : "no") . "\n";

// 反射类
$rc = new ReflectionClass('TestClass');
echo "Reflection methods: " . count($rc->getMethods()) . "\n";
echo "Reflection properties: " . count($rc->getProperties()) . "\n";

// 调试函数
$arr = ['a' => 1, 'b' => 2];
$debugInfo = print_r($arr, true);
echo "print_r length: " . strlen($debugInfo) . "\n";
$varExport = var_export($arr, true);
echo "var_export: $varExport\n";

// 资源与常量
echo "PHP_VERSION: " . PHP_VERSION . "\n";
echo "PHP_INT_MAX: " . PHP_INT_MAX . "\n";
echo "PHP_INT_MIN: " . PHP_INT_MIN . "\n";
echo "PHP_FLOAT_MAX: " . PHP_FLOAT_MAX . "\n";
echo "PHP_FLOAT_MIN: " . PHP_FLOAT_MIN . "\n";
echo "TRUE: " . (true ? "1" : "0") . "\n";
echo "FALSE: " . (false ? "1" : "0") . "\n";
echo "NULL: " . (null === null ? "null" : "not null") . "\n";

// 系统信息
echo "getcwd: " . getcwd() . "\n";
echo "php_sapi_name: " . php_sapi_name() . "\n";
echo "php_uname: " . php_uname() . "\n";

// 内存
$memUsage = memory_get_usage();
$memPeak = memory_get_peak_usage();
echo "Memory usage: $memUsage\n";
echo "Memory peak: $memPeak\n";

// 执行时间
$start = microtime(true);
for ($i = 0; $i < 1000; $i++) {}
$end = microtime(true);
echo "Loop time: " . ($end - $start) . " seconds\n";
?>
