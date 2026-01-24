<?php
// AOT模式算术运算性能基准测试
echo "Starting arithmetic benchmark (AOT mode)...\n";

$iterations = 100000;
$result = 0;

$i = 0;
while ($i < $iterations) {
    $result = $result + $i * 2 - 1;
    $i = $i + 1;
}

echo "Completed ";
echo $iterations;
echo " arithmetic operations\n";
echo "Result: ";
echo $result;
echo "\n";
