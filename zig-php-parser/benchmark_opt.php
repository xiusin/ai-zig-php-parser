<?php
$start = microtime(true);

// 1. Math functions optimization
$abs_res = 0;
$floor_res = 0;
for ($i = 0; $i < 100000; $i++) {
    $abs_res += abs($i - 50000);
    $floor_res += floor($i / 100);
}

// 2. Array sum optimization
$arr = [];
for ($i = 0; $i < 10000; $i++) {
    $arr[] = $i * 1.5;
}
$sum = 0;
for ($j = 0; $j < 100; $j++) {
    $sum += array_sum($arr);
}

// 3. Variable access & Inc/Dec optimization
$counter = 0;
function test_stack($n) {
    global $counter;
    $local = 0;
    for ($k = 0; $k < $n; $k++) {
        $local++;
        $counter++;
    }
    return $local;
}
test_stack(100000);

// 4. String operations (concatenation & interning)
$str_res = "";
for ($m = 0; $m < 50000; $m++) {
    $str_res = "prefix_" . ($m % 100);
}

$end = microtime(true);
echo "Time: " . ($end - $start) . "\n";
echo "Abs: $abs_res\n";
echo "Floor: $floor_res\n";
echo "Sum: $sum\n";
echo "Counter: $counter\n";
echo "String Len: " . strlen($str_res) . "\n";
