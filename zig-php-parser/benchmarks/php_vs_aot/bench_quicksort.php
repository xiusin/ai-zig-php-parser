<?php
/**
 * Benchmark: Quicksort 10,000 random integers.
 */
$size = (int)($argv[1] ?? 10000);

function quicksort(&$arr, $low, $high) {
    if ($low < $high) {
        $pivot = $arr[(int)(($low + $high) / 2)];
        $i = $low;
        $j = $high;
        while ($i <= $j) {
            while ($arr[$i] < $pivot) $i++;
            while ($arr[$j] > $pivot) $j--;
            if ($i <= $j) {
                $tmp = $arr[$i]; $arr[$i] = $arr[$j]; $arr[$j] = $tmp;
                $i++; $j--;
            }
        }
        quicksort($arr, $low, $j);
        quicksort($arr, $i, $high);
    }
}

// Warmup
$warmup = [];
for ($i = 0; $i < min($size, 100); $i++) { $warmup[] = rand(); }
quicksort($warmup, 0, count($warmup) - 1);

// Setup
$arr = [];
for ($i = 0; $i < $size; $i++) { $arr[] = rand(); }

// Timed run
$start = microtime(true);
quicksort($arr, 0, $size - 1);
$elapsed = microtime(true) - $start;

printf("bench_quicksort: iterations=%d, time=%.6f seconds\n", $size, $elapsed);