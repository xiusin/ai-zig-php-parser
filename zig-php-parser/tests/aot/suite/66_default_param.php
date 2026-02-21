<?php
// 测试: 默认参数
function greet($name = "World") {
    return "Hello " . $name;
}

$r1 = greet();
$r2 = greet("PHP");
echo "Default: $r1,$r2 (expect Hello World,Hello PHP)\n";
