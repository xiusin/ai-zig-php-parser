<?php
/**
 * Benchmark: Bubble sort 5,000 elements.
 */
$size = (int)($argv[1] ?? 5000);

function bubble_sort(&$arr) {
    $n = count($arr);
    for ($i = 0; $i < $n - 1; $i++) {
        for ($j = 0; $j < $n - $i - 1; $j++) {
            if ($arr[$j] > $arr[$j + 1]) {
                $tmp = $arr[$j];
                $arr[$j] = $arr[$j + 1];
                $arr[$j + 1] = $tmp;
            }
        }
    }
}

// Warmup
$warmup = [];
for ($i = 0; $i < min($size, 100); $i++) { $warmup[] = rand(); }
bubble_sort($warmup);

// Setup
$arr = [];
for ($i = 0; $i < $size; $i++) { $arr[] = rand(); }

// Timed run
$start = microtime(true);
bubble_sort($arr);
$elapsed = microtime(true) - $start;

printf("bench_bubble_sort: iterations=%d, time=%.6f seconds\n", $size, $elapsed);