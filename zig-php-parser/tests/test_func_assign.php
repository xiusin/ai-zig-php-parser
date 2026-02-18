<?php
// 函数作用域普通赋值测试
function test_assign() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $sum = $sum + 1;
    }
    return $sum;
}

$result = test_assign();
echo "Result: $result (expect 3)\n";
