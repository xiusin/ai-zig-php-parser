<?php

// 测试Array包装类的链式方法调用

echo "=== 测试Array包装类 ===\n";

// 创建数组
$arr = [1, 2, 3, 4, 5];
echo "原始数组: ";
print_r($arr);

// 数组操作示例（扩展语法，需要VM支持）
// 注意：这些是预期的API设计

// 添加元素
// $arr->push(6);
// echo "添加后: ";
// print_r($arr);

// 移除最后一个元素
// $last = $arr->pop();
// echo "弹出: $last\n";

// 过滤数组
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
// $even = $numbers->filter(fn($n) => $n % 2 == 0);
// echo "偶数: ";
// print_r($even);

// 映射数组
// $doubled = $numbers->map(fn($n) => $n * 2);
// echo "翻倍: ";
// print_r($doubled);

// 切片
// $slice = $numbers->slice(2, 5);
// echo "切片[2:5]: ";
// print_r($slice);

// 反转
// $reversed = $numbers->reverse();
// echo "反转: ";
// print_r($reversed);

// 连接为字符串
$words = ["hello", "world", "from", "PHP"];
// $joined = $words->join(" ");
// echo "连接: $joined\n";

// 检查包含
// $contains = $numbers->contains(5);
// echo "包含5: " . ($contains ? "是" : "否") . "\n";

// 查找索引
// $index = $numbers->indexOf(7);
// echo "7的索引: $index\n";

// 链式调用示例
$data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
// $result = $data
//     ->filter(fn($n) => $n > 5)
//     ->map(fn($n) => $n * 2)
//     ->slice(0, 3);
// echo "链式结果: ";
// print_r($result);

// 合并数组
$arr1 = [1, 2, 3];
$arr2 = [4, 5, 6];
// $merged = $arr1->merge($arr2);
// echo "合并: ";
// print_r($merged);

echo "\n=== Array包装类测试完成 ===\n";
echo "注意: 带注释的代码需要在VM中实现Array类方法支持\n";
