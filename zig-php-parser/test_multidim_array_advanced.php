<?php
// 高级多维数组测试

// 1. 动态创建多维数组
$data = [];
$data[0] = [];
$data[0][0] = 10;
$data[0][1] = 20;
$data[1] = [];
$data[1][0] = 30;
$data[1][1] = 40;

echo "Dynamic array: data[0][0] = ";
echo $data[0][0];
echo "\n";

echo "Dynamic array: data[1][1] = ";
echo $data[1][1];
echo "\n";

// 2. 混合索引的多维数组
$mixed = [];
$mixed[0] = [];
$mixed[0][0] = 100;
$mixed[0][1] = 200;
$mixed[1] = [];
$mixed[1][0] = 300;

echo "Mixed array: mixed[0][1] = ";
echo $mixed[0][1];
echo "\n";

echo "Mixed array: mixed[1][0] = ";
echo $mixed[1][0];
echo "\n";

// 3. 嵌套数组修改
$nested = [[1, 2], [3, 4]];
$nested[0][0] = 99;
$nested[1][1] = 88;

echo "Modified nested[0][0] = ";
echo $nested[0][0];
echo "\n";

echo "Modified nested[1][1] = ";
echo $nested[1][1];
echo "\n";

// 4. 四维数组
$four_d = [[[[1]]]];
echo "4D array: four_d[0][0][0][0] = ";
echo $four_d[0][0][0][0];
echo "\n";
