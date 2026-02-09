<?php
// 最小 array_merge 测试

$a = [1, 2];
$b = [3, 4];
$c = array_merge($a, $b);

echo "Result: " . implode(", ", $c) . "\n";
echo "Expected: 1, 2, 3, 4\n";
