<?php
// 极度混搭: 日期时间处理 + 日历计算 + 时区模拟 + 间隔 + 格式化
echo "=== f045: DateTime + Calendar + Interval + Format ===\n";

class DateTools {
    public static function dayOfYear(int $year, int $month, int $day): int {
        $days = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        if (self::isLeapYear($year)) $days[2] = 29;
        $total = 0;
        for ($m = 1; $m < $month; $m++) $total += $days[$m];
        return $total + $day;
    }

    public static function isLeapYear(int $year): bool {
        return ($year % 4 === 0 && $year % 100 !== 0) || ($year % 400 === 0);
    }

    public static function daysInMonth(int $year, int $month): int {
        $days = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        if ($month === 2 && self::isLeapYear($year)) return 29;
        return $days[$month];
    }

    public static function dayOfWeek(int $year, int $month, int $day): int {
        // Zeller's formula (0=Sunday)
        if ($month < 3) { $month += 12; $year--; }
        $k = $year % 100;
        $j = (int)($year / 100);
        $h = ($day + (int)(13 * ($month + 1) / 5) + $k + (int)($k / 4) + (int)($j / 4) + 5 * $j) % 7;
        return ($h + 6) % 7; // Convert to 0=Sunday
    }

    public static function dayName(int $year, int $month, int $day): string {
        $names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        return $names[self::dayOfWeek($year, $month, $day)];
    }

    public static function addDays(int $year, int $month, int $day, int $days): array {
        $timestamp = mktime(12, 0, 0, $month, $day + $days, $year);
        return ['year' => (int)date('Y', $timestamp), 'month' => (int)date('m', $timestamp), 'day' => (int)date('d', $timestamp)];
    }

    public static function daysBetween(int $y1, int $m1, int $d1, int $y2, int $m2, int $d2): int {
        $t1 = mktime(12, 0, 0, $m1, $d1, $y1);
        $t2 = mktime(12, 0, 0, $m2, $d2, $y2);
        return (int)(($t2 - $t1) / 86400);
    }

    public static function weekNumber(int $year, int $month, int $day): int {
        $doy = self::dayOfYear($year, $month, $day);
        return (int)(($doy - 1) / 7) + 1;
    }

    public static function quarter(int $month): int {
        return (int)(($month - 1) / 3) + 1;
    }

    public static function isWeekend(int $year, int $month, int $day): bool {
        $dow = self::dayOfWeek($year, $month, $day);
        return $dow === 0 || $dow === 6;
    }

    public static function formatDuration(int $seconds): string {
        $days = (int)($seconds / 86400);
        $seconds %= 86400;
        $hours = (int)($seconds / 3600);
        $seconds %= 3600;
        $mins = (int)($seconds / 60);
        $secs = $seconds % 60;
        $parts = [];
        if ($days > 0) $parts[] = "{$days}d";
        if ($hours > 0) $parts[] = "{$hours}h";
        if ($mins > 0) $parts[] = "{$mins}m";
        $parts[] = "{$secs}s";
        return implode(' ', $parts);
    }

    public static function parseDuration(string $str): int {
        $seconds = 0;
        if (preg_match('/(\d+)d/', $str, $m)) $seconds += $m[1] * 86400;
        if (preg_match('/(\d+)h/', $str, $m)) $seconds += $m[1] * 3600;
        if (preg_match('/(\d+)m/', $str, $m)) $seconds += $m[1] * 60;
        if (preg_match('/(\d+)s/', $str, $m)) $seconds += $m[1];
        return $seconds;
    }
}

// 测试
echo "isLeapYear(2000): " . var_export(DateTools::isLeapYear(2000), true) . "\n";
echo "isLeapYear(1900): " . var_export(DateTools::isLeapYear(1900), true) . "\n";
echo "isLeapYear(2024): " . var_export(DateTools::isLeapYear(2024), true) . "\n";
echo "daysInMonth(2024,2): " . DateTools::daysInMonth(2024, 2) . "\n";
echo "daysInMonth(2023,2): " . DateTools::daysInMonth(2023, 2) . "\n";
echo "dayOfYear(2025,7,20): " . DateTools::dayOfYear(2025, 7, 20) . "\n";
echo "dayOfWeek(2025,1,1): " . DateTools::dayName(2025, 1, 1) . "\n";
echo "dayOfWeek(2025,7,20): " . DateTools::dayName(2025, 7, 20) . "\n";
echo "isWeekend(2025,7,20): " . var_export(DateTools::isWeekend(2025, 7, 20), true) . "\n";
echo "quarter(7): " . DateTools::quarter(7) . "\n";
echo "weekNumber(2025,7,20): " . DateTools::weekNumber(2025, 7, 20) . "\n";

$added = DateTools::addDays(2025, 1, 1, 100);
echo "2025-01-01 + 100 days: {$added['year']}-{$added['month']}-{$added['day']}\n";

echo "daysBetween(2025-01-01, 2025-12-31): " . DateTools::daysBetween(2025, 1, 1, 2025, 12, 31) . "\n";

echo "formatDuration(90061): " . DateTools::formatDuration(90061) . "\n";
echo "parseDuration('1d 2h 30m 15s'): " . DateTools::parseDuration('1d 2h 30m 15s') . "s\n";

// 日历打印
echo "\n--- Calendar (2025-07) ---\n";
echo "  Sun Mon Tue Wed Thu Fri Sat\n";
$first = DateTools::dayOfWeek(2025, 7, 1);
$dim = DateTools::daysInMonth(2025, 7);
echo str_repeat('    ', $first);
for ($d = 1; $d <= $dim; $d++) {
    echo sprintf('%4d', $d);
    if (($first + $d) % 7 === 0) echo "\n";
}
echo "\n";

echo "=== f045 Done ===\n";
