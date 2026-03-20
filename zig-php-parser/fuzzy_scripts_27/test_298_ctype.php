<?php
function isAscii(string $str): bool {
    return preg_match('/^[\x00-\x7F]*$/', $str) === 1;
}

function isAlpha(string $str): bool {
    return ctype_alpha($str);
}

function isAlnum(string $str): bool {
    return ctype_alnum($str);
}

function isDigit(string $str): bool {
    return ctype_digit($str);
}

function isSpace(string $str): bool {
    return ctype_space($str);
}

function isLower(string $str): bool {
    return ctype_lower($str);
}

function isUpper(string $str): bool {
    return ctype_upper($str);
}

echo isAscii('Hello') ? 'true' : 'false' . "\n";
echo isAlpha('Hello') ? 'true' : 'false' . "\n";
echo isAlnum('Hello123') ? 'true' : 'false' . "\n";
echo isDigit('12345') ? 'true' : 'false' . "\n";
echo isLower('hello') ? 'true' : 'false' . "\n";
echo isUpper('HELLO') ? 'true' : 'false' . "\n";
echo "OK\n";
