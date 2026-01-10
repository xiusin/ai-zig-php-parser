<?php
// 高阶函数测试
function apply_operation($array, $operation) {
    return array_map($operation, $array);
}

$numbers = [1, 2, 3, 4, 5];
$incremented = apply_operation($numbers, fn($x) => $x + 1);
echo "Incremented: " . implode(", ", $incremented) . "\n";

// 递归函数测试
function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

echo "Factorial of 5: " . factorial(5) . "\n";
?>