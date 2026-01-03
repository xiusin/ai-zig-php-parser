<?php

echo "测试箭头函数\n";

$numbers = [1, 2, 3, 4, 5];

// 使用箭头函数
$squared = array_map(fn($x) => $x * $x, $numbers);

echo "原数组: ";
foreach ($numbers as $n) {
    echo $n . " ";
}
echo "\n";

echo "平方后: ";
foreach ($squared as $n) {
    echo $n . " ";
}
echo "\n";

?>
