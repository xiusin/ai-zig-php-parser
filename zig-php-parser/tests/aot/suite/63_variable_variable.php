<?php
// 测试: 变量变量
$name = "value";
$value = 42;
$result = $$name;
echo "VarVar: $result (expect 42)\n";
