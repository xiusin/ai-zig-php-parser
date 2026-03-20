<?php
function substr2(string $str, int $start, ?int $length = null): string {
    return substr($str, $start, $length);
}

function substrReplace(string $str, string $replace, int $start, ?int $length = null): string {
    return substr_replace($str, $replace, $start, $length);
}

function substrCount2(string $haystack, string $needle): int {
    return substr_count($haystack, $needle);
}

function implode2(string $glue, array $pieces): string {
    return implode($glue, $pieces);
}

function explode2(string $delimiter, string $str, int $limit = PHP_INT_MAX): array {
    return explode($delimiter, $str, $limit);
}

function join2(array $pieces, string $glue = ''): string {
    return implode($glue, $pieces);
}

echo substr2('Hello World', 6) . "\n";
echo substr2('Hello World', 6, 5) . "\n";
echo substrReplace('Hello World', 'PHP', 6) . "\n";
echo implode2('-', ['a', 'b', 'c']) . "\n";
echo implode2(',', explode2('/', 'a/b/c')) . "\n";
echo "OK\n";
