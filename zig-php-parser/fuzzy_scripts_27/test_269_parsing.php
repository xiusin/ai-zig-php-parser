<?php
function parseNumber(string $str): int|float|null {
    if (is_numeric($str)) {
        return str_contains($str, '.') ? (float)$str : (int)$str;
    }
    return null;
}

function parseBool(string $str): bool|null {
    return match(strtolower($str)) {
        'true', '1', 'yes', 'on' => true,
        'false', '0', 'no', 'off' => false,
        default => null
    };
}

function parseInt2(string $str, int $base = 10): int|null {
    $result = filter_var($str, FILTER_VALIDATE_INT, ['options' => ['default' => null, 'base' => $base]]);
    return $result !== false ? $result : null;
}

function parseFloat2(string $str): float|null {
    $result = filter_var($str, FILTER_VALIDATE_FLOAT);
    return $result !== false ? $result : null;
}

echo parseNumber('42') . "\n";
echo parseNumber('3.14') . "\n";
echo parseBool('true') ? 'true' : 'false' . "\n";
echo parseBool('0') ? 'true' : 'false' . "\n";
echo parseInt2('255', 16) . "\n";
echo parseFloat2('3.14159') . "\n";
echo "OK\n";
