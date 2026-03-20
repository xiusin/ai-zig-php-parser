<?php
function leftPad(string $str, int $length, string $char = ' '): string {
    $padLength = $length - mb_strlen($str);
    if ($padLength <= 0) return $str;
    return str_repeat($char, $padLength) . $str;
}

function rightPad(string $str, int $length, string $char = ' '): string {
    $padLength = $length - mb_strlen($str);
    if ($padLength <= 0) return $str;
    return $str . str_repeat($char, $padLength);
}

function truncateMiddle(string $str, int $maxLength, string $separator = '...'): string {
    if (mb_strlen($str) <= $maxLength) return $str;

    $sepLength = mb_strlen($separator);
    $available = $maxLength - $sepLength;

    $left = (int)floor($available / 2);
    $right = (int)ceil($available / 2);

    return mb_substr($str, 0, $left) . $separator . mb_substr($str, -$right);
}

echo leftPad('Hello', 10, '-') . "\n";
echo rightPad('Hello', 10, '-') . "\n";
echo truncateMiddle('Hello World PHP Programming', 20) . "\n";
echo truncateMiddle('Short', 20) . "\n";
echo "OK\n";
