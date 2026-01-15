<?php
// Comprehensive PHP Performance Benchmark
// Tests: Mathematical functions, Array operations, String operations

function benchmark_math_functions($iterations = 100000) {
    $start_time = microtime(true);
    $start_memory = memory_get_usage();

    $result = 0;
    for ($i = 0; $i < $iterations; $i++) {
        $result += abs(-$i * 2);
        $result += floor($i / 3.14);
        $result += ceil($i * 1.5);
        $result += (int)sqrt($i + 1);
    }

    $end_time = microtime(true);
    $end_memory = memory_get_usage();

    return [
        'name' => 'Math Functions',
        'iterations' => $iterations,
        'time' => $end_time - $start_time,
        'memory_peak' => memory_get_peak_usage() - $start_memory,
        'result' => $result
    ];
}

function benchmark_array_operations($size = 50000) {
    $start_time = microtime(true);
    $start_memory = memory_get_usage();

    // Create large array
    $array = [];
    for ($i = 0; $i < $size; $i++) {
        $array[] = $i;
    }

    // Array sum operation
    $sum = array_sum($array);

    // Array search
    $search_result = array_search(25000, $array);

    // Array slice and merge
    $slice = array_slice($array, 5000, 500);
    $merged = array_merge($slice, [999999]);

    $end_time = microtime(true);
    $end_memory = memory_get_usage();

    return [
        'name' => 'Array Operations',
        'size' => $size,
        'time' => $end_time - $start_time,
        'memory_peak' => memory_get_peak_usage() - $start_memory,
        'sum' => $sum,
        'search_result' => $search_result,
        'slice_size' => count($slice),
        'merged_size' => count($merged)
    ];
}

function benchmark_string_operations($iterations = 25000) {
    $start_time = microtime(true);
    $start_memory = memory_get_usage();

    $result = "";

    // String concatenation
    for ($i = 0; $i < $iterations; $i++) {
        $result .= "item" . ($i % 50) . "_";
    }

    // String replacement
    $result = str_replace("item25", "replaced", $result);

    // String splitting
    $parts = explode("_", $result);
    $count = count($parts);

    // String search
    $strpos_result = strpos($result, "replaced");

    $end_time = microtime(true);
    $end_memory = memory_get_usage();

    return [
        'name' => 'String Operations',
        'iterations' => $iterations,
        'time' => $end_time - $start_time,
        'memory_peak' => memory_get_peak_usage() - $start_memory,
        'result_length' => strlen($result),
        'parts_count' => $count,
        'strpos_result' => $strpos_result
    ];
}

function benchmark_function_calls($iterations = 10000) {
    $start_time = microtime(true);
    $start_memory = memory_get_usage();

    $result = 0;

    function simple_add($a, $b) {
        return $a + $b;
    }

    for ($i = 0; $i < $iterations; $i++) {
        $result += simple_add($i, 1);
    }

    $end_time = microtime(true);
    $end_memory = memory_get_usage();

    return [
        'name' => 'Function Calls',
        'iterations' => $iterations,
        'time' => $end_time - $start_time,
        'memory_peak' => memory_get_peak_usage() - $start_memory,
        'result' => $result
    ];
}

// Run all benchmarks
$results = [];

echo "Running PHP Performance Benchmarks...\n\n";

$results[] = benchmark_math_functions();
$results[] = benchmark_array_operations();
$results[] = benchmark_string_operations();
$results[] = benchmark_function_calls();

// Output results in plain text format
foreach ($results as $result) {
    echo $result['name'] . ": " . number_format($result['time'], 4) . "s, " . $result['memory_peak'] . " bytes\n";
}
?>
