<?php
// 数组函数性能测试
echo "=== 数组函数性能测试 ===\n";

$iterations = 5000;

// 创建测试数组（手动创建，避免range()解析问题）
$test_array = array();
for ($i = 1; $i <= 100; $i++) {
    $test_array[] = $i;
}
$assoc_array = array('a' => 1, 'b' => 2, 'c' => 3, 'd' => 4, 'e' => 5);

// 数组基本操作
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $count = count($test_array);
    $is_empty = empty($test_array);
    $size = sizeof($test_array);
}
$end = microtime(true);
echo sprintf("count/empty/sizeof %d 次: %.4f 秒\n", $iterations, $end - $start);

// 数组访问
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $first = $test_array[0];
    $last = $test_array[count($test_array) - 1];
    $middle = $test_array[50];
}
$end = microtime(true);
echo sprintf("数组访问 %d 次: %.4f 秒\n", $iterations, $end - $start);

// 数组修改
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $arr = $test_array;
    $arr[] = $i; // 追加
    $arr[10] = $i * 2; // 修改
    // unset($arr[5]); // 删除 - 暂时注释，避免解析问题
}
$end = microtime(true);
echo sprintf("数组修改 %d 次: %.4f 秒\n", $iterations, $end - $start);

// 数组栈操作
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $arr = $test_array;
    array_push($arr, $i);
    array_push($arr, $i + 1, $i + 2);
    $popped = array_pop($arr);
    array_unshift($arr, -$i);
    $shifted = array_shift($arr);
}
$end = microtime(true);
echo sprintf("栈操作(push/pop/unshift/shift) %d 次: %.4f 秒\n", $iterations, $end - $start);

// 数组搜索
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $exists = in_array(50, $test_array);
    $key = array_search(25, $test_array);
    $keys = array_keys($assoc_array);
    $values = array_values($assoc_array);
}
$end = microtime(true);
echo sprintf("数组搜索 %d 次: %.4f 秒\n", $iterations, $end - $start);

// 数组排序
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $arr = $test_array;
    shuffle($arr);
    sort($arr);
    rsort($arr);
}
$end = microtime(true);
echo sprintf("数组排序(shuffle/sort/rsort) %d 次: %.4f 秒\n", $iterations, $end - $start);

// 数组过滤和映射
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $filtered = array_filter($test_array, function($x) { return $x % 2 == 0; });
    $mapped = array_map(function($x) { return $x * 2; }, $test_array);
    $reduced = array_reduce($test_array, function($carry, $item) { return $carry + $item; }, 0);
}
$end = microtime(true);
echo sprintf("数组函数(filter/map/reduce) %d 次: %.4f 秒\n", $iterations, $end - $start);

// 数组合并和分割
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $merged = array_merge($test_array, [101, 102, 103]);
    $sliced = array_slice($test_array, 10, 20);
    $chunked = array_chunk($test_array, 10);
}
$end = microtime(true);
echo sprintf("数组合并分割 %d 次: %.4f 秒\n", $iterations, $end - $start);

// 关联数组操作
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $arr = $assoc_array;
    $arr['new_key'] = $i;
    $value = $arr['a'] ?? 'default';
    $exists = isset($arr['b']);
    // unset($arr['c']); // 暂时注释，避免解析问题
}
$end = microtime(true);
echo sprintf("关联数组操作 %d 次: %.4f 秒\n", $iterations, $end - $start);
