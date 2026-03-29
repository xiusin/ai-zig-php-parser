<?php
// 测试10: 引用与指针操作
$a = 10;
$b = &$a;
$b = 20;
echo "a=$a, b=$b\n";

// 数组引用
$arr = [1, 2, 3];
foreach ($arr as &$item) {
    $item *= 2;
}
unset($item);
print_r($arr);

// 函数引用参数 (usort)
$arr2 = [3, 1, 4, 1, 5, 9, 2, 6];
usort($arr2, function($a, $b) {
    return $b <=> $a;
});
print_r($arr2);

// 链式引用操作
$x = 1;
$y = &$x;
$z = &$y;
$z = 100;
echo "x=$x, y=$y, z=$z\n";
?>