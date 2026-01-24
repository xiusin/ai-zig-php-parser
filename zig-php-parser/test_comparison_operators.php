<?php
// 测试比较运算符
$a = 10;
$b = 20;

if ($a < $b) {
    echo "10 < 20: true\n";
}

if ($a <= 10) {
    echo "10 <= 10: true\n";
}

if ($b > $a) {
    echo "20 > 10: true\n";
}

if ($b >= 20) {
    echo "20 >= 20: true\n";
}

if ($a == 10) {
    echo "10 == 10: true\n";
}

if ($a != $b) {
    echo "10 != 20: true\n";
}
