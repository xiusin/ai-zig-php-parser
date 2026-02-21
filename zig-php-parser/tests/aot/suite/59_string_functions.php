<?php
// 测试: 字符串函数组合
$str = "Hello World";
$len = strlen($str);
$upper = strtoupper($str);
$lower = strtolower($str);
$sub = substr($str, 0, 5);

echo "StrFunc: $len,$upper,$lower,$sub (expect 11,HELLO WORLD,hello world,Hello)\n";
