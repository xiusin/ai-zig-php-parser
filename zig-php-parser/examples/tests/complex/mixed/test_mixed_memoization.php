<?php
function memoize($callback) {
    $cache = [];
    return function(...$args) use (&$cache, $callback) {
        $key = json_encode($args);
        if (isset($cache[$key])) {
            return $cache[$key];
        }
        $result = $callback(...$args);
        $cache[$key] = $result;
        return $result;
    };
}

$fibMemo = memoize(function($n) use (&$fibMemo) {
    if ($n <= 1) return $n;
    return $fibMemo($n - 1) + $fibMemo($n - 2);
});

echo "Fibonacci (memoized):\n";
for ($i = 0; $i <= 20; $i++) {
    echo "fib($i) = " . $fibMemo($i) . "\n";
}
