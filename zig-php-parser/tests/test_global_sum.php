<?php
// 全局作用域累加测试
$sum = 0;
for ($i = 0; $i < 3; $i++) {
    $sum += 1;
}
echo "Result: $sum (expect 3)\n";
