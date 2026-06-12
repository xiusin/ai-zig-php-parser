<?php
// 杂项函数测试

// 变量处理
echo "=== Variable Functions ===\n";
$var = 'test';
echo "isset: " . var_export(isset($var), true) . "\n";
echo "empty: " . var_export(empty($var), true) . "\n";
echo "is_null: " . var_export(is_null($var), true) . "\n";
echo "gettype: " . gettype($var) . "\n";
echo "gettype null: " . gettype(null) . "\n";

// 类型检查函数
echo "\n=== Type Check Functions ===\n";
$values = [
    'int' => 42,
    'float' => 3.14,
    'string' => 'hello',
    'bool' => true,
    'array' => [1, 2, 3],
    'object' => new stdClass(),
    'null' => null,
    'resource' => fopen('php://memory', 'r')
];

foreach ($values as $type => $value) {
    echo "$type: ";
    echo "is_int=" . var_export(is_int($value), true) . ", ";
    echo "is_float=" . var_export(is_float($value), true) . ", ";
    echo "is_string=" . var_export(is_string($value), true) . "\n";
}
fclose($values['resource']);

// 序列化
echo "\n=== Serialization ===\n";
$data = ['name' => 'Alice', 'age' => 25, 'active' => true];
$serialized = serialize($data);
echo "Serialized: $serialized\n";
$unserialized = unserialize($serialized);
echo "Unserialized name: " . $unserialized['name'] . "\n";

// JSON
echo "\n=== JSON ===\n";
$json = json_encode($data);
echo "JSON: $json\n";
$decoded = json_decode($json, true);
echo "Decoded: " . var_export($decoded, true) . "\n";

// 唯一标识
echo "\n=== Unique IDs ===\n";
echo "uniqid: " . uniqid() . "\n";
echo "uniqid with prefix: " . uniqid('test_') . "\n";

// 进程信息
echo "\n=== Process Info ===\n";
echo "getmypid: " . getmypid() . "\n";
echo "getmygid: " . var_export(function_exists('getmygid'), true) . "\n";

// 内存信息
echo "\n=== Memory Info ===\n";
echo "memory_get_usage: " . memory_get_usage() . "\n";
echo "memory_get_peak_usage: " . memory_get_peak_usage() . "\n";
echo "memory_get_usage real: " . memory_get_usage(true) . "\n";

// 时间测量
echo "\n=== Timing ===\n";
$start = microtime(true);
usleep(1000); // 1ms
$end = microtime(true);
echo "Elapsed: " . sprintf("%.6f", $end - $start) . " seconds\n";

// 杂项
echo "\n=== Misc ===\n";
echo "phpversion: " . phpversion() . "\n";
echo "php_sapi_name: " . php_sapi_name() . "\n";
echo "PHP_OS: " . PHP_OS . "\n";

// 常量检查
echo "\n=== Constants ===\n";
echo "defined('PHP_VERSION'): " . var_export(defined('PHP_VERSION'), true) . "\n";
echo "constant('PHP_VERSION'): " . constant('PHP_VERSION') . "\n";

// 扩展检查
echo "\n=== Extensions ===\n";
echo "extension_loaded('core'): " . var_export(extension_loaded('core'), true) . "\n";
echo "extension_loaded('nonexistent'): " . var_export(extension_loaded('nonexistent'), true) . "\n";

// 字节转换
echo "\n=== Byte Conversion ===\n";
$bytes = 1536;
echo "Human readable: ";
if ($bytes >= 1073741824) {
    echo number_format($bytes / 1073741824, 2) . ' GB';
} elseif ($bytes >= 1048576) {
    echo number_format($bytes / 1048576, 2) . ' MB';
} elseif ($bytes >= 1024) {
    echo number_format($bytes / 1024, 2) . ' KB';
} else {
    echo $bytes . ' B';
}
echo "\n";

echo "\nMisc function tests completed\n";
