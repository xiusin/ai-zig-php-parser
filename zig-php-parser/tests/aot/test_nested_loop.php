<?php

// 测试嵌套循环

echo "Testing nested loops...\n";

$sum = 0;
for ($i = 0; $i < 3; $i++) {
    echo "Outer: $i\n";
    for ($j = 0; $j < 3; $j++) {
        echo "  Inner: $j\n";
        $sum += $i * $j;
    }
}

echo "Sum: $sum\n";
echo "Done!\n";
