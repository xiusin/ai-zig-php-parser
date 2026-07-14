<?php
// 测试数组工具函数，包括引用参数、引用链赋值、嵌套数组操作

function array_set(array &$arr, string $path, mixed $value, string $sep = '.'): void {
    $keys = explode($sep, $path);
    $current = &$arr;
    foreach ($keys as $i => $key) {
        if (!isset($current[$key])) $current[$key] = [];
        if ($i === count($keys) - 1) {
            $current[$key] = $value;
        } else {
            $current = &$current[$key];
        }
    }
}

function array_get(array $arr, string $path, string $sep = '.'): mixed {
    $keys = explode($sep, $path);
    $current = $arr;
    foreach ($keys as $key) {
        if (!isset($current[$key])) return null;
        $current = $current[$key];
    }
    return $current;
}

function array_has(array $arr, string $path, string $sep = '.'): bool {
    $keys = explode($sep, $path);
    $current = $arr;
    foreach ($keys as $key) {
        if (!isset($current[$key])) return false;
        $current = $current[$key];
    }
    return true;
}

function array_flatten(array $arr): array {
    $result = [];
    foreach ($arr as $value) {
        if (is_array($value)) {
            $result = array_merge($result, array_flatten($value));
        } else {
            $result[] = $value;
        }
    }
    return $result;
}

function array_pluck(array $arr, string $key): array {
    $result = [];
    foreach ($arr as $item) {
        if (is_array($item) && isset($item[$key])) {
            $result[] = $item[$key];
        }
    }
    return $result;
}

// 测试 array_set
$config = [];
array_set($config, 'db.host', 'localhost');
array_set($config, 'db.port', 3306);
array_set($config, 'cache.redis.host', '127.0.0.1');
array_set($config, 'cache.redis.port', 6379);

echo "db_host: " . array_get($config, 'db.host') . "\n";
echo "db_port: " . array_get($config, 'db.port') . "\n";
echo "cache_host: " . array_get($config, 'cache.redis.host') . "\n";
echo "has_db: " . (array_has($config, 'db.host') ? 'true' : 'false') . "\n";
echo "has_missing: " . (array_has($config, 'db.missing') ? 'true' : 'false') . "\n";

// 测试 array_flatten
$nested = [1, [2, 3], [4, [5, 6]]];
$flat = array_flatten($nested);
echo "flatten: " . implode(',', $flat) . "\n";

// 测试 array_pluck
$users = [
    ['name' => 'Alice', 'age' => 30],
    ['name' => 'Bob', 'age' => 25],
    ['name' => 'Charlie', 'age' => 35],
];
$names = array_pluck($users, 'name');
echo "pluck: " . implode(',', $names) . "\n";

// 测试 array_set 覆盖
array_set($config, 'db.host', '127.0.0.1');
echo "db_host_updated: " . array_get($config, 'db.host') . "\n";

// 测试嵌套数组 JSON 输出
echo "array_set: " . json_encode($config) . "\n";
