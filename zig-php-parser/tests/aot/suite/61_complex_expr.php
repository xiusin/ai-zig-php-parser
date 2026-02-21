<?php
// 测试: 复杂表达式求值
$a = 2;
$b = 3;
$c = 4;

$result = ($a + $b) * $c - ($a * $b) + ($c / $a);
echo "Expr: $result (expect 16)\n";
