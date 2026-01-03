<?php

echo "=== for range语法测试 ===\n\n";

// 测试1: for range 10 (无变量)
echo "1. for range 10:\n";
for range 10 {
    echo "* ";
}
echo "\n\n";

// 测试2: for $i range 10 (带变量)
echo "2. for \$i range 10:\n";
for $i range 10 {
    echo "$i ";
}
echo "\n\n";

// 测试3: for $i range 5 (较小范围)
echo "3. for \$i range 5:\n";
for $i range 5 {
    echo "[$i] ";
}
echo "\n\n";

// 测试4: 嵌套for range
echo "4. 嵌套for range:\n";
for $i range 3 {
    echo "行$i: ";
    for $j range 4 {
        echo "$j ";
    }
    echo "\n";
}
echo "\n";

// 测试5: for range中使用变量
echo "5. for range中使用变量:\n";
for $i range 5 {
    $square = $i * $i;
    echo "$i的平方: $square\n";
}
echo "\n";

echo "=== for range语法测试完成 ===\n";

?>
