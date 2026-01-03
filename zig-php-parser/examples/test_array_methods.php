<?php

// 测试Array方法调用（实际可运行）

echo "=== 测试Array方法调用 ===\n";

// 创建数组
$arr = [1, 2, 3, 4, 5];
echo "原始数组: ";
print_r($arr);

// 添加元素
$arr->push(6);
echo "添加后: ";
print_r($arr);

// 移除最后一个元素
$last = $arr->pop();
echo "弹出: $last\n";
echo "弹出后: ";
print_r($arr);

// 反转数组
$reversed = $arr->reverse();
echo "反转: ";
print_r($reversed);

// 获取键
$keys = $arr->keys();
echo "键: ";
print_r($keys);

// 获取值
$values = $arr->values();
echo "值: ";
print_r($values);

// 数组长度
$count = $arr->count();
echo "长度: $count\n";

// 合并数组
$arr1 = [1, 2, 3];
$arr2 = [4, 5, 6];
$merged = $arr1->merge($arr2);
echo "合并: ";
print_r($merged);

// 过滤数组（需要闭包支持）
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$even = $numbers->filter(fn($n) => $n % 2 == 0);
echo "偶数: ";
print_r($even);

// 映射数组（需要闭包支持）
$doubled = $numbers->map(fn($n) => $n * 2);
echo "翻倍: ";
print_r($doubled);

echo "\n=== Array方法测试完成 ===\n";
