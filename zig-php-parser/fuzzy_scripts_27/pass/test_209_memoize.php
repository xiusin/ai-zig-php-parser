<?php
function memoize(callable $fn): callable {
    $cache = [];
    return function(...$args) use ($fn, &$cache) {
        $key = serialize($args);
        if (isset($cache[$key])) {
            return $cache[$key];
        }
        return $cache[$key] = $fn(...$args);
    };
}

$fib = function($n) use (&$fib) {
    if ($n <= 1) return $n;
    return $fib($n - 1) + $fib($n - 2);
};

$memoFib = memoize($fib);

$start = microtime(true);
echo $memoFib(20) . "\n";
$time1 = microtime(true) - $start;

$start = microtime(true);
echo $fib(20) . "\n";
$time2 = microtime(true) - $start;

$start = microtime(true);
echo $memoFib(20) . "\n";
$time3 = microtime(true) - $start;

echo "Memoized: " . sprintf("%.6f", $time1) . "s, Recursive: " . sprintf("%.6f", $time2) . "s, Cached: " . sprintf("%.6f", $time3) . "s\n";
echo "OK\n";
