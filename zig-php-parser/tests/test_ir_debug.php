<?php
// 最小化测试：验证加法链累加器的IR生成
function test_simple() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $sum += $i + 1;
    }
    return $sum;
}

$result = test_simple();
echo "Result: $result (expect 6)\n";
