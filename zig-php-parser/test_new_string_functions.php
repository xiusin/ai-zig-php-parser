<?php
// 测试新增的字符串函数

echo "=== 字符串函数测试 ===\n";

// 1. ltrim 和 rtrim
$str1 = "  hello world  ";
echo "原字符串: '";
echo $str1;
echo "'\n";

// 2. str_replace
$text = "Hello World";
$replaced = str_replace("World", "PHP", $text);
echo "str_replace: ";
echo $replaced;
echo "\n";

// 3. str_repeat
$repeated = str_repeat("ab", 3);
echo "str_repeat('ab', 3): ";
echo $repeated;
echo "\n";

// 4. strrev
$reversed = strrev("hello");
echo "strrev('hello'): ";
echo $reversed;
echo "\n";

// 5. str_contains (PHP 8.0+)
$contains = str_contains("hello world", "world");
echo "str_contains('hello world', 'world'): ";
if ($contains) {
    echo "true";
} else {
    echo "false";
}
echo "\n";

// 6. str_starts_with (PHP 8.0+)
$starts = str_starts_with("hello world", "hello");
echo "str_starts_with('hello world', 'hello'): ";
if ($starts) {
    echo "true";
} else {
    echo "false";
}
echo "\n";

// 7. str_ends_with (PHP 8.0+)
$ends = str_ends_with("hello world", "world");
echo "str_ends_with('hello world', 'world'): ";
if ($ends) {
    echo "true";
} else {
    echo "false";
}
echo "\n";

// 8. ucfirst
$ucfirst = ucfirst("hello");
echo "ucfirst('hello'): ";
echo $ucfirst;
echo "\n";

// 9. ucwords
$ucwords = ucwords("hello world");
echo "ucwords('hello world'): ";
echo $ucwords;
echo "\n";

// 10. explode
$parts = explode(" ", "one two three");
echo "explode(' ', 'one two three'): ";
echo $parts[0];
echo ", ";
echo $parts[1];
echo ", ";
echo $parts[2];
echo "\n";

// 11. strcmp
$cmp = strcmp("abc", "abc");
echo "strcmp('abc', 'abc'): ";
echo $cmp;
echo "\n";

echo "\n=== 数学函数测试 ===\n";

// 12. sin, cos, tan
$angle = 0;
echo "sin(0): ";
echo sin($angle);
echo "\n";

echo "cos(0): ";
echo cos($angle);
echo "\n";

// 13. log, exp
echo "log(2.718282): ";
echo log(2.718282);
echo "\n";

echo "exp(1): ";
echo exp(1);
echo "\n";

// 14. pow
$power = pow(2, 3);
echo "pow(2, 3): ";
echo $power;
echo "\n";

// 15. deg2rad, rad2deg
$rad = deg2rad(180);
echo "deg2rad(180): ";
echo $rad;
echo "\n";

// 16. pi
$pi_val = pi();
echo "pi(): ";
echo $pi_val;
echo "\n";

// 17. hypot
$hyp = hypot(3, 4);
echo "hypot(3, 4): ";
echo $hyp;
echo "\n";

echo "\n测试完成！\n";
