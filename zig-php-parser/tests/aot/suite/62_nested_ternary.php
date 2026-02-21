<?php
// 测试: 三元运算符嵌套
$x = 5;
$result = $x > 10 ? "big" : ($x > 5 ? "medium" : ($x == 5 ? "five" : "small"));
echo "Ternary: $result (expect five)\n";
