<?php
// 最小嵌套闭包测试 - 返回闭包

function outer(int $x): callable {
    return function(int $y) use ($x): callable {
        return function(int $z) use ($x, $y): int {
            return $x + $y + $z;
        };
    };
}

$fn1 = outer(1);
$fn2 = $fn1(2);
$result = $fn2(3);
echo "Result: " . $result . "\n";
echo "Expected: 6\n";
