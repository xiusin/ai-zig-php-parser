<?php
// 测试：引用迭代 + 嵌套循环 + 复杂表达式
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

echo "Original matrix:\n";
foreach ($matrix as $row) {
    foreach ($row as $val) {
        echo $val . " ";
    }
    echo "\n";
}

// 使用引用修改矩阵
foreach ($matrix as &$row) {
    foreach ($row as &$val) {
        $val = $val * 2 + 1;
    }
}

echo "\nTransformed matrix (val * 2 + 1):\n";
foreach ($matrix as $row) {
    foreach ($row as $val) {
        echo $val . " ";
    }
    echo "\n";
}

// 计算总和
$sum = 0;
foreach ($matrix as $row) {
    foreach ($row as $val) {
        $sum += $val;
    }
}
echo "\nSum: $sum\n";
