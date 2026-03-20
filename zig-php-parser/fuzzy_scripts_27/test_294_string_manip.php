<?php
function strReplace2(string $subject, string|array $search, string|array $replace): string {
    return str_replace($search, $replace, $subject);
}

function strIReplace2(string $subject, string|array $search, string|array $replace): string {
    return str_ireplace($search, $replace, $subject);
}

function strRepeat2(string $str, int $times): string {
    return str_repeat($str, $times);
}

function strPad2(string $str, int $length, string $pad_string = ' ', int $pad_type = STR_PAD_RIGHT): string {
    return str_pad($str, $length, $pad_string, $pad_type);
}

function strShuffle(string $str): string {
    return str_shuffle($str);
}

function strSplit2(string $str, int $length = 1): array {
    return str_split($str, $length);
}

echo strReplace2('Hello World', 'World', 'PHP') . "\n";
echo strIReplace2('HELLO world', 'hello', 'Hi') . "\n";
echo strRepeat2('Ha', 3) . "\n";
echo strPad2('X', 5, '-', STR_PAD_BOTH) . "\n";
echo strSplit2('hello', 2)[0] . "\n";
echo "OK\n";
