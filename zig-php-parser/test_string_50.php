<?php
// 中等规模的字符串拼接测试（50次）
$result = "";
$i = 0;
while ($i < 50) {
    $result = $result . "x";
    $i = $i + 1;
}
echo "Length: ";
echo strlen($result);
echo "\n";
