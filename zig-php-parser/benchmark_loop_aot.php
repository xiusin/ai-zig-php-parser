<?php
// AOT模式循环性能基准测试
echo "Starting loop benchmark (AOT mode)...\n";

$iterations = 100000;
$sum = 0;

$i = 0;
while ($i < $iterations) {
    $sum = $sum + $i;
    $i = $i + 1;
}

echo "Completed ";
echo $iterations;
echo " iterations\n";
echo "Sum: ";
echo $sum;
echo "\n";
