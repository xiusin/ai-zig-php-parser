<?php
function isLeapYear(int $year): bool {
    return ($year % 4 === 0 && $year % 100 !== 0) || ($year % 400 === 0);
}

function daysInMonth(int $month, int $year): int {
    return match($month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => isLeapYear($year) ? 29 : 28,
        default => 0
    };
}

function dayOfYear(int $day, int $month, int $year): int {
    $days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (isLeapYear($year)) $days[1] = 29;
    $doy = 0;
    for ($m = 1; $m < $month; $m++) {
        $doy += $days[$m - 1];
    }
    return $doy + $day;
}

function addDays(DateTime $date, int $days): DateTime {
    $date->modify("+$days days");
    return $date;
}

echo isLeapYear(2024) ? 'true' : 'false' . "\n";
echo isLeapYear(2023) ? 'true' : 'false' . "\n";
echo isLeapYear(2000) ? 'true' : 'false' . "\n";
echo daysInMonth(2, 2024) . "\n";
echo dayOfYear(15, 6, 2024) . "\n";

$date = new DateTime('2024-01-01');
echo addDays(clone $date, 100)->format('Y-m-d') . "\n";
echo "OK\n";
