<?php
function strContains2(string $haystack, string $needle): bool {
    return str_contains($haystack, $needle);
}

function strStartsWith2(string $haystack, string $needle): bool {
    return str_starts_with($haystack, $needle);
}

function strEndsWith2(string $haystack, string $needle): bool {
    return str_ends_with($haystack, $needle);
}

function strLimit(string $str, int $limit, string $suffix = '...'): string {
    if (mb_strlen($str) <= $limit) return $str;
    return mb_substr($str, 0, $limit - mb_strlen($suffix)) . $suffix;
}

function strWords(string $str): int {
    return count(preg_split('/\s+/', trim($str)));
}

function strReplaceArray(string $str, array $replacements): string {
    foreach ($replacements as $search => $replace) {
        $str = str_replace($search, $replace, $str);
    }
    return $str;
}

echo strContains2('Hello World', 'World') ? 'true' : 'false' . "\n";
echo strStartsWith2('Hello World', 'Hello') ? 'true' : 'false' . "\n";
echo strEndsWith2('Hello World', 'World') ? 'true' : 'false' . "\n";
echo strLimit('Hello World Example', 12) . "\n";
echo strWords('Hello World PHP') . "\n";
echo strReplaceArray('Hello World', ['World' => 'PHP', 'Hello' => 'Hi']) . "\n";
echo "OK\n";
