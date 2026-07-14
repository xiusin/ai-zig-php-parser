<?php
// 引用处理：引用参数、引用返回、数组元素引用

function inc(&$val, int $amount = 10): void {
    $val += $amount;
}

function &find_ref(array &$arr, string $key): mixed {
    return $arr[$key];
}

function swap(&$a, &$b): void {
    $tmp = $a;
    $a = $b;
    $b = $tmp;
}

// 测试基本引用参数
$x = 5;
inc($x);
echo "by_ref: $x\n";

// 测试带参数引用
$y = 100;
inc($y, 50);
echo "by_ref_50: $y\n";

// 测试交换
$a = 1;
$b = 2;
swap($a, $b);
echo "swapped: a=$a, b=$b\n";

// 测试数组元素引用
$arr = ['x' => 10, 'y' => 20];
$ref = &$arr['x'];
$ref = 99;
echo "array_ref: " . $arr['x'] . "\n";

// 测试嵌套引用
$data = ['a' => ['b' => ['c' => 1]]];
$inner = &$data['a']['b']['c'];
$inner = 42;
echo "nested_ref: " . $data['a']['b']['c'] . "\n";

// 测试引用传递后修改
$values = [3, 1, 4, 1, 5, 9, 2, 6];
foreach ($values as &$v) {
    $v *= 2;
}
unset($v);
echo "doubled: " . implode(',', $values) . "\n";

// 测试引用返回
$config = ['host' => 'localhost', 'port' => 3306];
$hostRef = &find_ref($config, 'host');
$hostRef = '127.0.0.1';
echo "ref_return: " . $config['host'] . "," . $config['port'] . "\n";

// 测试多次引用操作
$counter = 0;
inc($counter);
inc($counter);
inc($counter, 5);
echo "counter: $counter\n";
