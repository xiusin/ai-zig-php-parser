<?php
function strPos2(string $haystack, string $needle, int $offset = 0): int|false {
    return strpos($haystack, $needle, $offset);
}

function strRPos2(string $haystack, string $needle): int|false {
    return strrpos($haystack, $needle);
}

function strContains3(string $haystack, string $needle): bool {
    return strpos($haystack, $needle) !== false;
}

function substrCount2(string $haystack, string $needle): int {
    return substr_count($haystack, $needle);
}

function strWordCount2(string $str): int {
    return str_word_count($str);
}

function strLen2(string $str): int {
    return strlen($str);
}

echo strPos2('Hello World World', 'World') . "\n";
echo strRPos2('Hello World World', 'World') . "\n";
echo strContains3('Hello World', 'PHP') ? 'true' : 'false' . "\n";
echo substrCount2('Hello World World World', 'World') . "\n";
echo strWordCount2('Hello World PHP') . "\n";
echo strLen2('Hello') . "\n";
echo "OK\n";
