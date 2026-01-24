<?php
// 100次循环测试
$result = "";
$i = 0;
while ($i < 100) {
    $result = $result . "x";
    $i = $i + 1;
}
echo "Length: ";
echo strlen($result);
echo "\n";
