<?php
// 简单的嵌套引用测试
$arr = [[1, 2], [3, 4]];

echo "Before:\n";
foreach ($arr as $row) {
    foreach ($row as $val) {
        echo $val . " ";
    }
    echo "\n";
}

foreach ($arr as &$row) {
    foreach ($row as &$val) {
        $val *= 2;
    }
}

echo "After:\n";
foreach ($arr as $row) {
    foreach ($row as $val) {
        echo $val . " ";
    }
    echo "\n";
}
