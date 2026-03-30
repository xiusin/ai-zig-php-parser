<?php
// Test 111: DateTime with timezones
$ny = new DateTimeZone('America/New_York');
$tokyo = new DateTimeZone('Asia/Tokyo');
$utc = new DateTimeZone('UTC');

echo "=== Timezones ===\n";
$dt = new DateTime('2024-01-15 12:00:00', $ny);
echo "NY: " . $dt->format('Y-m-d H:i:s T') . "\n";

$dt->setTimezone($tokyo);
echo "Tokyo: " . $dt->format('Y-m-d H:i:s T') . "\n";

echo "\n=== Create from timestamp ===\n";
$ts = new DateTime('@1704067200');
$ts->setTimezone($utc);
echo "From timestamp: " . $ts->format('Y-m-d H:i:s T') . "\n";

echo "\n=== DateInterval create from string ===\n";
$interval = DateInterval::createFromDateString('2 days 3 hours');
echo "Created interval: {$interval->d} days, {$interval->h} hours\n";

echo "\n=== Modify ===\n";
$dt2 = new DateTime('2024-03-15');
$dt2->modify('+1 week');
echo "After +1 week: " . $dt2->format('Y-m-d') . "\n";
$dt2->modify('last day of last month');
echo "Last day of last month: " . $dt2->format('Y-m-d') . "\n";