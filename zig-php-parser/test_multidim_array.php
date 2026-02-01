<?php
// 测试多维数组访问

// 创建二维数组
$matrix = [[1, 2, 3], [4, 5, 6], [7, 8, 9]];

// 访问二维数组元素
echo "matrix[0][0] = ";
echo $matrix[0][0];
echo "\n";

echo "matrix[1][1] = ";
echo $matrix[1][1];
echo "\n";

echo "matrix[2][2] = ";
echo $matrix[2][2];
echo "\n";

// 修改二维数组元素
$matrix[1][1] = 99;
echo "After modification, matrix[1][1] = ";
echo $matrix[1][1];
echo "\n";

// 三维数组
$cube = [
    [[1, 2], [3, 4]],
    [[5, 6], [7, 8]]
];

echo "cube[0][0][0] = ";
echo $cube[0][0][0];
echo "\n";

echo "cube[1][1][1] = ";
echo $cube[1][1][1];
echo "\n";
