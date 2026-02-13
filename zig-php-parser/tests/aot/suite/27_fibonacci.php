<?php
// 测试: 递归斐波那契
function fib($n) {
    if ($n <= 1) {
        return $n;
    }
    return fib($n - 1) + fib($n - 2);
}

echo fib(10) . "\n";
