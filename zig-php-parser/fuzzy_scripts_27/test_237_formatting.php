<?php
function formatBytes(int $bytes, int $precision = 2): string {
    $units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    $i = 0;
    while ($bytes >= 1024 && $i < count($units) - 1) {
        $bytes /= 1024;
        $i++;
    }
    return sprintf("%.{$precision}f %s", $bytes, $units[$i]);
}

function formatNumber(int|float $num, int $decimals = 0): string {
    return number_format($num, $decimals, '.', ',');
}

function formatCurrency(float $amount, string $symbol = '$'): string {
    return $symbol . number_format($amount, 2);
}

function formatDate(DateTime $date, string $format = 'Y-m-d'): string {
    return $date->format($format);
}

function formatRelativeTime(DateTime $date): string {
    $now = new DateTime();
    $diff = $now->diff($date);

    if ($diff->y > 0) return $diff->y . ' year(s) ago';
    if ($diff->m > 0) return $diff->m . ' month(s) ago';
    if ($diff->d > 0) return $diff->d . ' day(s) ago';
    if ($diff->h > 0) return $diff->h . ' hour(s) ago';
    if ($diff->i > 0) return $diff->i . ' minute(s) ago';
    return 'just now';
}

echo formatBytes(1024) . "\n";
echo formatBytes(1536) . "\n";
echo formatNumber(1234567.89, 2) . "\n";
echo formatCurrency(1234.56, '€') . "\n";
echo formatDate(new DateTime('2024-01-15'), 'd/m/Y') . "\n";
echo "OK\n";
