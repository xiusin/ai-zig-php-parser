<?php
function chunkString(string $str, int $length): array {
    return str_split($str, $length);
}

function padLeft(string $str, int $length, string $char = ' '): string {
    return str_pad($str, $length, $char, STR_PAD_LEFT);
}

function padRight(string $str, int $length, string $char = ' '): string {
    return str_pad($str, $length, $char, STR_PAD_RIGHT);
}

function padBoth(string $str, int $length, string $char = ' '): string {
    return str_pad($str, $length, $char, STR_PAD_BOTH);
}

function startsWith(string $str, string $prefix): bool {
    return str_starts_with($str, $prefix);
}

function endsWith(string $str, string $suffix): bool {
    return str_ends_with($str, $suffix);
}

function contains(string $str, string $needle): bool {
    return str_contains($str, $needle);
}

echo implode(',', chunkString('hello world', 3)) . "\n";
echo padLeft('42', 5, '0') . "\n";
echo padRight('Hi', 8, '_') . "\n";
echo padBoth('X', 7, '-') . "\n";
echo startsWith('Hello World', 'Hello') ? 'true' : 'false' . "\n";
echo endsWith('Hello World', 'World') ? 'true' : 'false' . "\n";
echo contains('Hello World', 'lo') ? 'true' : 'false' . "\n";
echo "OK\n";
