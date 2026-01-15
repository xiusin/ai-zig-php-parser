<?php
/**
 * Quick Performance Benchmark
 * Reduced iterations for faster comparison
 */

echo "=== Quick Performance Benchmark ===\n\n";

function bench($name, $iters, $fn) {
    $start = microtime(true);
    for ($i = 0; $i < $iters; $i++) {
        $fn();
    }
    $end = microtime(true);
    $ms = ($end - $start) * 1000;
    $ops = $iters / ($end - $start);
    echo $name . ": " . round($ms, 1) . " ms (" . round($ops) . " ops/s)\n";
    return $ms;
}

$t = 0;

echo "--- Integer ---\n";
$t += bench("Int add", 100000, function() { $a = 42 + 17; return $a; });
$t += bench("Int mul", 100000, function() { $a = 123 * 456; return $a; });
$t += bench("Int cmp", 100000, function() { $a = 42 > 17; return $a; });

echo "\n--- Float ---\n";
$t += bench("Float add", 100000, function() { $a = 3.14 + 2.71; return $a; });
$t += bench("Float mul", 100000, function() { $a = 3.14 * 2.71; return $a; });

echo "\n--- String ---\n";
$s = "hello world test";
$t += bench("strlen", 100000, function() use ($s) { return strlen($s); });
$t += bench("strpos", 100000, function() use ($s) { return strpos($s, "test"); });

echo "\n--- Array ---\n";
$arr = [1, 2, 3, 4, 5];
$t += bench("Array get", 100000, function() use ($arr) { return $arr[2]; });
$t += bench("count", 100000, function() use ($arr) { return count($arr); });

echo "\n--- Object ---\n";
class Pt { public $x = 10; }
$p = new Pt();
$t += bench("Prop get", 100000, function() use ($p) { return $p->x; });

echo "\n--- Function ---\n";
function add($a, $b) { return $a + $b; }
$t += bench("Func call", 100000, function() { return add(1, 2); });

echo "\n--- Loop ---\n";
$t += bench("For loop", 10000, function() {
    $s = 0;
    for ($i = 0; $i < 100; $i++) { $s = $s + $i; }
    return $s;
});

echo "\n--- Fibonacci ---\n";
function fib($n) { if ($n <= 1) return $n; return fib($n-1) + fib($n-2); }
$t += bench("Fib(15)", 1000, function() { return fib(15); });

echo "\n=== Total: " . round($t, 1) . " ms ===\n";
?>
