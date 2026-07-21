<?php
// 极度混搭: 时区处理 + 日历计算 + 时间序列 + 日期范围
echo "=== f096: Timezone + Calendar + TimeSeries + Range ===\n";

class DateHelper {
    public static function parse(string $date): array {
        $ts = strtotime($date);
        return [
            'timestamp' => $ts,
            'year' => (int)date('Y', $ts),
            'month' => (int)date('n', $ts),
            'day' => (int)date('j', $ts),
            'hour' => (int)date('G', $ts),
            'minute' => (int)date('i', $ts),
            'second' => (int)date('s', $ts),
            'weekday' => date('l', $ts),
            'week_num' => (int)date('W', $ts),
            'day_of_year' => (int)date('z', $ts),
        ];
    }

    public static function diff(string $d1, string $d2): array {
        $ts1 = strtotime($d1); $ts2 = strtotime($d2);
        $diff = abs($ts2 - $ts1);
        return [
            'seconds' => $diff,
            'minutes' => (int)($diff / 60),
            'hours' => (int)($diff / 3600),
            'days' => (int)($diff / 86400),
            'weeks' => (int)($diff / (86400 * 7)),
        ];
    }

    public static function addDays(string $date, int $days): string {
        return date('Y-m-d', strtotime("$date $days days"));
    }

    public static function addMonths(string $date, int $months): string {
        return date('Y-m-d', strtotime("$date $months months"));
    }

    public static function isWeekend(string $date): bool {
        $weekday = date('N', strtotime($date));
        return $weekday >= 6;
    }

    public static function isLeapYear(int $year): bool {
        return ($year % 4 === 0 && $year % 100 !== 0) || ($year % 400 === 0);
    }

    public static function daysInMonth(int $year, int $month): int {
        return (int)date('t', mktime(0, 0, 0, $month, 1, $year));
    }

    public static function range(string $start, string $end, string $interval = '1 day'): array {
        $dates = [];
        $current = strtotime($start);
        $endTs = strtotime($end);
        while ($current <= $endTs) {
            $dates[] = date('Y-m-d', $current);
            $current = strtotime("+1 $interval", $current);
        }
        return $dates;
    }

    public static function quarter(string $date): int {
        $month = (int)date('n', strtotime($date));
        return (int)ceil($month / 3);
    }

    public static function age(string $birthDate): int {
        $ts = strtotime($birthDate);
        $age = (int)date('Y') - (int)date('Y', $ts);
        if (date('md') < date('md', $ts)) $age--;
        return $age;
    }
}

class TimeSeries {
    private array $data = [];

    public function add(string $timestamp, float $value): void {
        $this->data[strtotime($timestamp)] = $value;
        ksort($this->data);
    }

    public function resample(string $interval): array {
        $result = [];
        $intervalSec = match($interval) {
            '1min' => 60, '5min' => 300, '1hour' => 3600,
            '1day' => 86400, '1week' => 604800,
            default => 3600,
        };
        $buckets = [];
        foreach ($this->data as $ts => $val) {
            $bucket = (int)($ts / $intervalSec) * $intervalSec;
            if (!isset($buckets[$bucket])) $buckets[$bucket] = [];
            $buckets[$bucket][] = $val;
        }
        foreach ($buckets as $bucket => $vals) {
            $result[date('Y-m-d H:i', $bucket)] = array_sum($vals) / count($vals);
        }
        return $result;
    }

    public function movingAverage(int $window): array {
        $values = array_values($this->data);
        $timestamps = array_keys($this->data);
        $result = [];
        for ($i = 0; $i < count($values); $i++) {
            $start = max(0, $i - $window + 1);
            $slice = array_slice($values, $start, $i - $start + 1);
            $result[date('Y-m-d H:i', $timestamps[$i])] = array_sum($slice) / count($slice);
        }
        return $result;
    }

    public function stats(): array {
        $values = array_values($this->data);
        if (empty($values)) return [];
        return [
            'count' => count($values),
            'min' => min($values),
            'max' => max($values),
            'avg' => array_sum($values) / count($values),
            'first' => date('Y-m-d H:i', min(array_keys($this->data))),
            'last' => date('Y-m-d H:i', max(array_keys($this->data))),
        ];
    }

    public function trend(): string {
        $values = array_values($this->data);
        if (count($values) < 2) return 'stable';
        $firstHalf = array_slice($values, 0, (int)(count($values) / 2));
        $secondHalf = array_slice($values, (int)(count($values) / 2));
        $avg1 = array_sum($firstHalf) / count($firstHalf);
        $avg2 = array_sum($secondHalf) / count($secondHalf);
        if ($avg2 > $avg1 * 1.05) return 'upward';
        if ($avg2 < $avg1 * 0.95) return 'downward';
        return 'stable';
    }
}

class Calendar {
    public static function generateMonth(int $year, int $month): array {
        $firstDay = mktime(0, 0, 0, $month, 1, $year);
        $daysInMonth = DateHelper::daysInMonth($year, $month);
        $startWeekday = (int)date('N', $firstDay);
        $calendar = [];
        $day = 1;
        for ($week = 0; $week < 6; $week++) {
            $calendar[$week] = [];
            for ($dow = 1; $dow <= 7; $dow++) {
                if (($week === 0 && $dow < $startWeekday) || $day > $daysInMonth) {
                    $calendar[$week][$dow] = null;
                } else {
                    $calendar[$week][$dow] = $day++;
                }
            }
            if ($day > $daysInMonth) break;
        }
        return $calendar;
    }

    public static function printMonth(int $year, int $month): void {
        $cal = self::generateMonth($year, $month);
        echo "  " . date('F Y', mktime(0, 0, 0, $month, 1, $year)) . "\n";
        echo "  Mo Tu We Th Fr Sa Su\n";
        foreach ($cal as $week) {
            $row = "  ";
            for ($d = 1; $d <= 7; $d++) {
                $day = $week[$d] ?? null;
                $row .= ($day === null ? '  ' : str_pad((string)$day, 2, ' ', STR_PAD_LEFT)) . ' ';
            }
            echo rtrim($row) . "\n";
        }
    }
}

// 测试
echo "--- Date Parsing ---\n";
$info = DateHelper::parse('2024-03-15 14:30:00');
echo "Parsed: " . json_encode($info) . "\n";

echo "\n--- Date Difference ---\n";
$diff = DateHelper::diff('2024-01-01', '2024-03-15');
echo "Diff 2024-01-01 to 2024-03-15: " . json_encode($diff) . "\n";

echo "\n--- Date Arithmetic ---\n";
echo "2024-03-15 + 10 days = " . DateHelper::addDays('2024-03-15', 10) . "\n";
echo "2024-03-15 + 2 months = " . DateHelper::addMonths('2024-03-15', 2) . "\n";
echo "2024-03-15 + 45 days = " . DateHelper::addDays('2024-03-15', 45) . "\n";

echo "\n--- Calendar Info ---\n";
echo "2024-03-15 is weekend: " . var_export(DateHelper::isWeekend('2024-03-15'), true) . "\n";
echo "2024-03-16 is weekend: " . var_export(DateHelper::isWeekend('2024-03-16'), true) . "\n";
echo "2024 is leap year: " . var_export(DateHelper::isLeapYear(2024), true) . "\n";
echo "2024 is leap year: " . var_export(DateHelper::isLeapYear(2023), true) . "\n";
echo "Feb 2024 days: " . DateHelper::daysInMonth(2024, 2) . "\n";
echo "Feb 2023 days: " . DateHelper::daysInMonth(2023, 2) . "\n";
echo "Q1 of March: " . DateHelper::quarter('2024-03-15') . "\n";
echo "Q3 of August: " . DateHelper::quarter('2024-08-15') . "\n";

echo "\n--- Date Range ---\n";
$range = DateHelper::range('2024-03-01', '2024-03-07');
echo "Range: " . implode(', ', $range) . "\n";

echo "\n--- Calendar ---\n";
Calendar::printMonth(2024, 2);

echo "\n--- Time Series ---\n";
$ts = new TimeSeries();
$ts->add('2024-01-01 00:00', 10);
$ts->add('2024-01-01 01:00', 15);
$ts->add('2024-01-01 02:00', 12);
$ts->add('2024-01-01 03:00', 18);
$ts->add('2024-01-01 04:00', 20);
$ts->add('2024-01-01 05:00', 17);

echo "Stats: " . json_encode($ts->stats()) . "\n";
echo "Trend: " . $ts->trend() . "\n";

echo "\nMoving Average (window=3):\n";
foreach ($ts->movingAverage(3) as $time => $val) {
    echo "  $time: " . number_format($val, 2) . "\n";
}

echo "=== f096 Done ===\n";
