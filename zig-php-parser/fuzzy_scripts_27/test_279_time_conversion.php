<?php
function secondsToMinutes(int $seconds): int {
    return (int)($seconds / 60);
}

function minutesToHours(int $minutes): int {
    return (int)($minutes / 60);
}

function hoursToDays(int $hours): int {
    return (int)($hours / 24);
}

function daysToWeeks(int $days): int {
    return (int)($days / 7);
}

function weeksToMonths(int $weeks): int {
    return (int)($weeks / 4);
}

function monthsToYears(int $months): int {
    return (int)($months / 12);
}

function formatDuration(int $seconds): string {
    $minutes = secondsToMinutes($seconds);
    $seconds = $seconds % 60;
    $hours = minutesToHours($minutes);
    $minutes = $minutes % 60;
    $days = hoursToDays($hours);
    $hours = $hours % 24;

    return sprintf("%d days %d hours %d minutes %d seconds", $days, $hours, $minutes, $seconds);
}

echo secondsToMinutes(130) . "\n";
echo minutesToHours(90) . "\n";
echo formatDuration(3600 * 25 + 125) . "\n";
echo "OK\n";
