<?php
// 测试：基本引用迭代
$numbers = [10, 20, 30, 40, 50];

echo "Original: ";
foreach ($numbers as $n) {
    echo $n . " ";
}
echo "\n";

// 引用修改
foreach ($numbers as &$n) {
    $n += 5;
}

echo "After +5: ";
foreach ($numbers as $n) {
    echo $n . " ";
}
echo "\n";

// 再次修改
foreach ($numbers as &$n) {
    $n *= 2;
}

echo "After *2: ";
foreach ($numbers as $n) {
    echo $n . " ";
}
echo "\n";
