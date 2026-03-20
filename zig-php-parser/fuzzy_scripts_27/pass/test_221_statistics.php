<?php
function calculateStats(array $numbers): array {
    $count = count($numbers);
    if ($count === 0) return ['mean' => 0, 'median' => 0, 'mode' => 0, 'std' => 0];

    $mean = array_sum($numbers) / $count;

    sort($numbers);
    $mid = (int)($count / 2);
    $median = $count % 2 === 0 ? ($numbers[$mid - 1] + $numbers[$mid]) / 2 : $numbers[$mid];

    $freq = [];
    foreach ($numbers as $n) {
        $freq[$n] = ($freq[$n] ?? 0) + 1;
    }
    arsort($freq);
    $mode = array_key_first($freq);

    $variance = 0;
    foreach ($numbers as $n) {
        $variance += pow($n - $mean, 2);
    }
    $std = sqrt($variance / $count);

    return ['mean' => $mean, 'median' => $median, 'mode' => $mode, 'std' => $std];
}

$numbers = [10, 20, 20, 20, 30, 40, 50, 60, 70, 80, 90, 100];
$stats = calculateStats($numbers);
echo sprintf("Mean: %.2f\n", $stats['mean']);
echo sprintf("Median: %.2f\n", $stats['median']);
echo "Mode: {$stats['mode']}\n";
echo sprintf("Std Dev: %.2f\n", $stats['std']);
echo "OK\n";
