<?php
// 数组基础测试

// 创建数组
$arr1 = [];
$arr2 = array();
$arr3 = [1, 2, 3, 4, 5];
$arr4 = array('a', 'b', 'c');
$arr5 = ['key1' => 'value1', 'key2' => 'value2'];
$arr6 = array(
    'name' => 'John',
    'age' => 30,
    'active' => true
);

echo "arr3: " . implode(", ", $arr3) . "\n";
echo "arr5: " . var_export($arr5, true) . "\n";

// 访问元素
echo "arr3[0]: " . $arr3[0] . "\n";
echo "arr5['key1']: " . $arr5['key1'] . "\n";

// 修改元素
$arr3[0] = 100;
$arr5['key1'] = 'modified';
echo "modified arr3[0]: " . $arr3[0] . "\n";
echo "modified arr5['key1']: " . $arr5['key1'] . "\n";

// 添加元素
$arr3[] = 6; // 追加
$arr5['key3'] = 'value3'; // 新键
echo "appended arr3: " . implode(", ", $arr3) . "\n";

// 数组函数
echo "count: " . count($arr3) . "\n";
echo "sizeof: " . sizeof($arr3) . "\n";

// 判断
echo "is_array: " . var_export(is_array($arr3), true) . "\n";
echo "array_key_exists: " . var_export(array_key_exists('key1', $arr5), true) . "\n";
echo "in_array: " . var_export(in_array(100, $arr3), true) . "\n";
echo "isset: " . var_export(isset($arr5['key1']), true) . "\n";

// 获取键值
echo "array_keys: " . implode(", ", array_keys($arr5)) . "\n";
echo "array_values: " . implode(", ", array_values($arr5)) . "\n";

// 堆栈操作
$stack = [1, 2, 3];
array_push($stack, 4, 5);
echo "after push: " . implode(", ", $stack) . "\n";
$pop = array_pop($stack);
echo "popped: $pop, remaining: " . implode(", ", $stack) . "\n";

// 队列操作
$queue = [1, 2, 3];
array_unshift($queue, 0);
echo "after unshift: " . implode(", ", $queue) . "\n";
$shift = array_shift($queue);
echo "shifted: $shift, remaining: " . implode(", ", $queue) . "\n";

// 搜索
echo "array_search: " . var_export(array_search(100, $arr3), true) . "\n";
echo "array_search not found: " . var_export(array_search(999, $arr3), true) . "\n";

// 合并
$merged = array_merge([1, 2], [3, 4], [5, 6]);
echo "merged: " . implode(", ", $merged) . "\n";

// 联合运算符
$combined = ['a' => 1, 'b' => 2] + ['b' => 3, 'c' => 4];
echo "union: " . var_export($combined, true) . "\n";

// 切片
echo "array_slice: " . implode(", ", array_slice($arr3, 1, 3)) . "\n";

// 填充
echo "array_fill: " . implode(", ", array_fill(0, 5, 'x')) . "\n";

// 翻转
echo "array_flip: " . var_export(array_flip(['a' => 1, 'b' => 2]), true) . "\n";

// 反转
echo "array_reverse: " . implode(", ", array_reverse([1, 2, 3, 4, 5])) . "\n";

// 随机
$rand_keys = array_rand([1, 2, 3, 4, 5], 2);
echo "array_rand returns array\n";

// 唯一
echo "array_unique: " . implode(", ", array_unique([1, 1, 2, 2, 3, 3])) . "\n";

// 过滤
$filtered = array_filter([1, 2, 3, 4, 5], fn($x) => $x > 2);
echo "array_filter: " . implode(", ", $filtered) . "\n";

// 映射
$mapped = array_map(fn($x) => $x * 2, [1, 2, 3]);
echo "array_map: " . implode(", ", $mapped) . "\n";
