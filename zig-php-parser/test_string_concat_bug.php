<?php
// 测试字符串拼接段错误
$str = "Hello";
for ($i = 0; $i < 10; $i++) {
    $str = $str . " World";
    echo $str . "\n";
}
echo "Final: " . $str . "\n";
