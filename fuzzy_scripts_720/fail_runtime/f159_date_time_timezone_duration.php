<?php
// 日期时间：时区、持续时间、日历计算、格式化、解析
echo "=== f159: DateTime + Timezone + Duration + Calendar ===\n";

class DateTimeHelper {
    // 计算两个日期之间的天数
    public static function daysBetween(string $date1, string $date2): int {
        $d1 = new DateTime($date1);
        $d2 = new DateTime($date2);
        $diff = $d1->diff($d2);
        return $diff->days;
    }

    // 添加/减去工作日
    public static function addBusinessDays(string $date, int $days): string {
        $d = new DateTime($date);
        $added = 0;
        while ($added < $days) {
            $d->modify('+1 day');
            $weekday = (int)$d->format('N');
            if ($weekday <= 5) $added++;
        }
        return $d->format('Y-m-d');
    }

    // 获取月份日历
    public static function getMonthCalendar(int $year, int $month): array {
        $firstDay = new DateTime("$year-$month-01");
        $daysInMonth = (int)$firstDay->format('t');
        $startWeekday = (int)$firstDay->format('N'); // 1=Monday, 7=Sunday

        $calendar = [];
        $day = 1;
        for ($week = 0; $day <= $daysInMonth; $week++) {
            $weekDays = [];
            for ($dow = 1; $dow <= 7; $dow++) {
                if ($week === 0 && $dow < $startWeekday) {
                    $weekDays[] = null;
                } elseif ($day > $daysInMonth) {
                    $weekDays[] = null;
                } else {
                    $weekDays[] = $day++;
                }
            }
            $calendar[] = $weekDays;
        }
        return $calendar;
    }

    // 时区转换
    public static function convertTimezone(string $time, string $fromTz, string $toTz): string {
        $dt = new DateTime($time, new DateTimeZone($fromTz));
        $dt->setTimezone(new DateTimeZone($toTz));
        return $dt->format('Y-m-d H:i:s');
    }

    // 年龄计算
    public static function calculateAge(string $birthDate): int {
        $birth = new DateTime($birthDate);
        $now = new DateTime();
        return $birth->diff($now)->y;
    }

    // 季度计算
    public static function getQuarter(string $date): array {
        $d = new DateTime($date);
        $month = (int)$d->format('n');
        $quarter = (int)ceil($month / 3);
        $qStartMonth = ($quarter - 1) * 3 + 1;
        $qEndMonth = $qStartMonth + 2;
        $year = (int)$d->format('Y');
        return [
            'quarter' => $quarter,
            'start' => sprintf('%d-%02d-01', $year, $qStartMonth),
            'end' => sprintf('%d-%02d-%02d', $year, $qEndMonth, (int)$d->format('t')),
            'label' => "Q$quarter $year",
        ];
    }

    // 格式化持续时间
    public static function formatDuration(int $seconds): string {
        $days = intdiv($seconds, 86400);
        $seconds %= 86400;
        $hours = intdiv($seconds, 3600);
        $seconds %= 3600;
        $mins = intdiv($seconds, 60);
        $secs = $seconds % 60;

        $parts = [];
        if ($days > 0) $parts[] = "{$days}d";
        if ($hours > 0) $parts[] = "{$hours}h";
        if ($mins > 0) $parts[] = "{$mins}m";
        if ($secs > 0 || empty($parts)) $parts[] = "{$secs}s";
        return implode(' ', $parts);
    }

    // 下一个 N 天后的日期
    public static function nextOccurrence(string $date, string $weekday): string {
        $targetDay = ['Monday' => 1, 'Tuesday' => 2, 'Wednesday' => 3, 'Thursday' => 4,
                       'Friday' => 5, 'Saturday' => 6, 'Sunday' => 7][$weekday];
        $d = new DateTime($date);
        $currentDay = (int)$d->format('N');
        $diff = ($targetDay - $currentDay + 7) % 7;
        if ($diff === 0) $diff = 7;
        $d->modify("+$diff days");
        return $d->format('Y-m-d');
    }

    // 是否闰年
    public static function isLeapYear(int $year): bool {
        return ($year % 4 === 0 && $year % 100 !== 0) || ($year % 400 === 0);
    }
}

// 测试
echo "--- Days Between ---\n";
echo "  2026-01-01 to 2026-12-31: " . DateTimeHelper::daysBetween('2026-01-01', '2026-12-31') . " days\n";
echo "  2025-06-15 to 2026-06-15: " . DateTimeHelper::daysBetween('2025-06-15', '2026-06-15') . " days\n";
echo "  2026-01-01 to 2026-01-01: " . DateTimeHelper::daysBetween('2026-01-01', '2026-01-01') . " days\n";

echo "\n--- Business Days ---\n";
echo "  2026-07-20 + 5 business days: " . DateTimeHelper::addBusinessDays('2026-07-20', 5) . "\n";
echo "  2026-07-20 + 10 business days: " . DateTimeHelper::addBusinessDays('2026-07-20', 10) . "\n";

echo "\n--- Month Calendar (2026-07) ---\n";
$cal = DateTimeHelper::getMonthCalendar(2026, 7);
echo "  Mon Tue Wed Thu Fri Sat Sun\n";
foreach ($cal as $week) {
    $line = '  ';
    foreach ($week as $day) {
        $line .= ($day === null ? '   ' : sprintf('%3d', $day));
    }
    echo $line . "\n";
}

echo "\n--- Timezone Conversion ---\n";
echo "  Beijing to UTC: " . DateTimeHelper::convertTimezone('2026-07-20 12:00:00', 'Asia/Shanghai', 'UTC') . "\n";
echo "  UTC to New York: " . DateTimeHelper::convertTimezone('2026-07-20 12:00:00', 'UTC', 'America/New_York') . "\n";
echo "  Tokyo to London: " . DateTimeHelper::convertTimezone('2026-07-20 12:00:00', 'Asia/Tokyo', 'Europe/London') . "\n";

echo "\n--- Age Calculation ---\n";
echo "  Born 1990-05-15: " . DateTimeHelper::calculateAge('1990-05-15') . " years\n";
echo "  Born 2000-01-01: " . DateTimeHelper::calculateAge('2000-01-01') . " years\n";

echo "\n--- Quarter ---\n";
$dates = ['2026-01-15', '2026-03-31', '2026-04-01', '2026-07-20', '2026-10-15', '2026-12-31'];
foreach ($dates as $date) {
    $q = DateTimeHelper::getQuarter($date);
    echo "  $date → {$q['label']} ({$q['start']} to {$q['end']})\n";
}

echo "\n--- Duration Formatting ---\n";
$durations = [0, 45, 90, 3661, 90061, 86400, 900061, 954061];
foreach ($durations as $d) {
    echo "  {$d}s → " . DateTimeHelper::formatDuration($d) . "\n";
}

echo "\n--- Next Occurrence ---\n";
echo "  Next Monday from 2026-07-20 (Mon): " . DateTimeHelper::nextOccurrence('2026-07-20', 'Monday') . "\n";
echo "  Next Friday from 2026-07-20: " . DateTimeHelper::nextOccurrence('2026-07-20', 'Friday') . "\n";
echo "  Next Sunday from 2026-07-20: " . DateTimeHelper::nextOccurrence('2026-07-20', 'Sunday') . "\n";

echo "\n--- Leap Year ---\n";
$years = [1900, 2000, 2020, 2024, 2026, 2100, 2400];
foreach ($years as $y) {
    echo "  $y: " . (DateTimeHelper::isLeapYear($y) ? 'leap' : 'not leap') . "\n";
}

echo "=== f159 Done ===\n";
