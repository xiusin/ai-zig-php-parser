<?php
// Test 079: DateInterval, DatePeriod
echo "=== DateInterval ===\n";
$interval = new DateInterval('P2Y3M4DT5H6M7S');
echo "2y {$interval->y}, 3m {$interval->m}, 4d {$interval->d}\n";
echo "5h {$interval->h}, 6m {$interval->i}, 7s {$interval->s}\n";

$interval2 = new DateInterval('P1D');
echo "1 day interval\n";

echo "\n=== DateTime add/sub ===\n";
$dt = new DateTime('2024-01-15 10:00:00');
echo "Original: " . $dt->format('Y-m-d H:i:s') . "\n";

$dt2 = clone $dt;
$dt2->add(new DateInterval('P1D'));
echo "After +1D: " . $dt2->format('Y-m-d') . "\n";

$dt3 = clone $dt;
$dt3->sub(new DateInterval('P2D'));
echo "After -2D: " . $dt3->format('Y-m-d') . "\n";

echo "\n=== DatePeriod ===\n";
$start = new DateTime('2024-01-01');
$interval = new DateInterval('P1D');
$end = new DateTime('2024-01-05');
$period = new DatePeriod($start, $interval, $end);

echo "Period days:\n";
foreach ($period as $date) {
    echo "  " . $date->format('m/d') . "\n";
}

echo "\n=== DateTime diff ===\n";
$dt1 = new DateTime('2024-01-01');
$dt2 = new DateTime('2024-01-15');
$diff = $dt1->diff($dt2);
echo "Diff: {$diff->days} days\n";
echo "Diff format: " . $diff->format('%d days, %m months') . "\n";