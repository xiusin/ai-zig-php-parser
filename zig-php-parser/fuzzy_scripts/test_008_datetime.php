<?php
// Test 008: DateTime, DateInterval, DatePeriod and timezone handling
class DateLab {
    private DateTimeZone $tz;
    private DateTimeZone $tz2;

    public function __construct() {
        $this->tz = new DateTimeZone('America/New_York');
        $this->tz2 = new DateTimeZone('Asia/Shanghai');
    }

    public function process(): string {
        $out = "";

        // Current time
        $now = new DateTime('now', $this->tz);
        $out .= "Now (NY): " . $now->format('Y-m-d H:i:s T') . "\n";

        $nowShanghai = new DateTime('now', $this->tz2);
        $out .= "Now (Shanghai): " . $nowShanghai->format('Y-m-d H:i:s T') . "\n";

        // DateTime creation
        $dt1 = new DateTime('2024-01-15 10:30:00', $this->tz);
        $out .= "Created: " . $dt1->format('Y-m-d H:i:s') . "\n";

        // Add intervals
        $dt2 = clone $dt1;
        $dt2->add(new DateInterval('P1D'));
        $out .= "After +1D: " . $dt2->format('Y-m-d') . "\n";

        $dt3 = clone $dt1;
        $dt3->sub(new DateInterval('P2DT3H'));
        $out .= "After -2D3H: " . $dt3->format('Y-m-d H:i:s') . "\n";

        // Diff
        $diff = $dt1->diff($dt2);
        $out .= "Diff (dt1 to dt2): " . $diff->format('%d days') . "\n";

        // Modify
        $dt4 = clone $dt1;
        $dt4->modify('+1 week');
        $out .= "After +1 week: " . $dt4->format('Y-m-d') . "\n";

        // Timestamp
        $out .= "Timestamp: " . $dt1->getTimestamp() . "\n";
        $dt5 = (new DateTime())->setTimestamp(1704067200);
        $out .= "From timestamp: " . $dt5->format('Y-m-d H:i:s') . "\n";

        // DateInterval creation
        $di1 = new DateInterval('P2Y3M4DT5H6M7S');
        $out .= "Interval: {$di1->y}y {$di1->m}m {$di1->d}d {$di1->h}h {$di1->i}m {$di1->s}s\n";

        // DatePeriod
        $start = new DateTime('2024-01-01');
        $interval = new DateInterval('P1D');
        $end = new DateTime('2024-01-05');
        $period = new DatePeriod($start, $interval, $end);
        $out .= "Period days: ";
        foreach ($period as $day) {
            $out .= $day->format('m/d') . " ";
        }
        $out .= "\n";

        // Timezone conversion
        $utc = new DateTime('2024-06-15 12:00:00', new DateTimeZone('UTC'));
        $out .= "UTC: " . $utc->format('Y-m-d H:i:s T') . "\n";
        $utc->setTimezone($this->tz);
        $out .= "Converted to NY: " . $utc->format('Y-m-d H:i:s T') . "\n";

        // Format options
        $out .= "ATOM: " . $dt1->format(DateTimeInterface::ATOM) . "\n";
        $out .= "COOKIE: " . $dt1->format(DateTimeInterface::COOKIE) . "\n";
        $out .= "ISO8601: " . $dt1->format(DateTimeInterface::ISO8601) . "\n";

        // Create from format
        $parsed = DateTime::createFromFormat('Y-m-d H:i:s', '2024-03-20 15:30:00', $this->tz);
        $out .= "Parsed from format: " . ($parsed ? $parsed->format('Y-m-d H:i:s') : 'null') . "\n";

        return $out;
    }
}

$lab = new DateLab();
echo $lab->process();