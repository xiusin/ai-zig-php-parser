<?php
// 测试46: 复杂的list解构与短数组语法 - 嵌套解构、跳过元素、引用解构
// 测试目的：验证PHP 7.1+的方括号数组解构和嵌套解构功能

// 基本list解构
$coordinates = [100, 200, [300, 400]];
list($x, $y, list($z1, $z2)) = $coordinates;
echo "Point: x=$x, y=$y, z1=$z1, z2=$z2\n";

// 短数组语法解构（PHP 7.1+）
[$a, $b, [$c, $d]] = [1, 2, [3, 4]];
echo "Short syntax: a=$a, b=$b, c=$c, d=$d\n";

// 带键的解构（PHP 7.4+）
$userData = ['id' => 42, 'profile' => ['name' => 'Alice', 'email' => 'alice@test.com']];
['id' => $userId, 'profile' => ['name' => $userName, 'email' => $userEmail]] = $userData;
echo "Keyed destructuring: ID=$userId, Name=$userName, Email=$userEmail\n";

// 跳过元素
$csvLine = ['2024', 'Product', '999.99', 'In Stock', '100'];
[, $productName, $price, , $quantity] = $csvLine;
echo "Product: $productName, Price: $price, Qty: $quantity\n";

// 引用解构（修改原数组）
$mutable = [10, 20, 30];
list(&$ref1, &$ref2, &$ref3) = $mutable;
$ref1 *= 2;
$ref2 *= 3;
$ref3 *= 4;
echo "Modified via refs: " . implode(", ", $mutable) . "\n";

// foreach中的list解构
$matrix = [
    ['x' => 1, 'y' => 2, 'z' => 3],
    ['x' => 4, 'y' => 5, 'z' => 6],
    ['x' => 7, 'y' => 8, 'z' => 9],
];
$sumX = $sumY = $sumZ = 0;
foreach ($matrix as ['x' => $vx, 'y' => $vy, 'z' => $vz]) {
    $sumX += $vx;
    $sumY += $vy;
    $sumZ += $vz;
}
echo "Sums: X=$sumX, Y=$sumY, Z=$sumZ\n";

// 交换多个变量
$varA = "apple";
$varB = "banana";
$varC = "cherry";
[$varA, $varB, $varC] = [$varC, $varA, $varB];
echo "Swapped: A=$varA, B=$varB, C=$varC\n";

// 与array函数结合使用
[$minVal, $maxVal] = [min([5, 2, 8, 1]), max([5, 2, 8, 1])];
echo "Min: $minVal, Max: $maxVal\n";

// 解构嵌套多维数组
$deepNested = [
    'level1' => [
        'level2' => [
            'level3' => ['target' => 'found!', 'value' => 999]
        ]
    ]
];
['level1' => ['level2' => ['level3' => ['target' => $found, 'value' => $val]]]] = $deepNested;
echo "Deep nested: target=$found, value=$val\n";
?>