<?php
function ord2(string $char): int {
    return ord($char);
}

function chr2(int $ascii): string {
    return chr($ascii);
}

function md52(string $str): string {
    return md5($str);
}

function sha12(string $str): string {
    return sha1($str);
}

function crc322(string $str): string {
    return sprintf('%u', crc32($str));
}

function strlen2(string $str): int {
    return strlen($str);
}

function strrev2(string $str): string {
    return strrev($str);
}

echo ord2('A') . "\n";
echo chr2(65) . "\n";
echo md52('hello') . "\n";
echo sha12('hello') . "\n";
echo crc322('hello') . "\n";
echo strrev2('hello') . "\n";
echo "OK\n";
