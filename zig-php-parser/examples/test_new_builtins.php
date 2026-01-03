<?php

echo "Testing Array Functions:\n";
$arr = [1, 2, 3];
echo "count: " . count($arr) . "\n";
echo "array_key_exists(1, \$arr): " . (array_key_exists(1, $arr) ? "true" : "false") . "\n";
echo "array_key_exists(5, \$arr): " . (array_key_exists(5, $arr) ? "true" : "false") . "\n";

$slice = array_slice($arr, 1, 1);
echo "array_slice: ";
print_r($slice);

$rev = array_reverse($arr);
echo "array_reverse: ";
print_r($rev);

echo "\nTesting String Functions:\n";
$str = "hello";
echo "strrev: " . strrev($str) . "\n";

$split = str_split($str, 2);
echo "str_split: ";
print_r($split);

$pos = stripos("Hello World", "world");
echo "stripos('Hello World', 'world'): " . ($pos !== false ? $pos : "false") . "\n";

echo "\nTesting Hash/Encoding Functions:\n";
$bin = "ABC";
$hex = bin2hex($bin);
echo "bin2hex('ABC'): " . $hex . "\n";
echo "hex2bin('$hex'): " . hex2bin($hex) . "\n";

$b64 = base64_encode("Hello");
echo "base64_encode('Hello'): " . $b64 . "\n";
echo "base64_decode('$b64'): " . base64_decode($b64) . "\n";

