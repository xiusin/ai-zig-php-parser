<?php

echo "测试foreach键值对\n";

$arr = [10, 20, 30];
echo "数组: ";
print_r($arr);

echo "\n只有值:\n";
foreach ($arr as $v) {
    echo "值: $v\n";
}

echo "\n键值对:\n";
foreach ($arr as $k => $v) {
    echo "键: $k, 值: $v\n";
}

echo "\n完成\n";

?>
