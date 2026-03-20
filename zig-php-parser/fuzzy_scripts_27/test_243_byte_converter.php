<?php
function formatBytes2(int $bytes, int $precision = 2): string {
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];
    $unitIndex = 0;
    $value = $bytes;

    while ($value >= 1024 && $unitIndex < count($units) - 1) {
        $value /= 1024;
        $unitIndex++;
    }

    return sprintf("%.*f %s", $precision, $value, $units[$unitIndex]);
}

function parseBytes(string $str): int {
    $units = ['B' => 1, 'KB' => 1024, 'MB' => 1024 * 1024, 'GB' => 1024 * 1024 * 1024, 'TB' => 1024 * 1024 * 1024 * 1024];

    if (preg_match('/^([\d.]+)\s*([A-Z]+)$/i', trim($str), $matches)) {
        $value = (float)$matches[1];
        $unit = strtoupper($matches[2]);

        if (isset($units[$unit])) {
            return (int)($value * $units[$unit]);
        }
    }

    return 0;
}

echo formatBytes2(1024) . "\n";
echo formatBytes2(1536) . "\n";
echo formatBytes2(1048576) . "\n";
echo parseBytes('1KB') . "\n";
echo parseBytes('2.5MB') . "\n";
echo parseBytes('1G') . "\n";
echo "OK\n";
