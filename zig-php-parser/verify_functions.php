<?php
// 验证脚本 - 测试已实现的函数

echo "=== 验证 mbstring 函数 ===\n";
echo "mb_strlen('Hello World'): " . mb_strlen('Hello World') . " (期望: 11)\n";
echo "mb_strlen('你好世界'): " . mb_strlen('你好世界') . " (期望: 4)\n";
echo "mb_substr('Hello World', 0, 5): " . mb_substr('Hello World', 0, 5) . " (期望: Hello)\n";
echo "mb_strtoupper('hello'): " . mb_strtoupper('hello') . " (期望: HELLO)\n";
echo "mb_strtolower('HELLO'): " . mb_strtolower('HELLO') . " (期望: hello)\n";

echo "\n=== 验证字符串函数 ===\n";
echo "substr_count('Hello World World World', 'World'): " . substr_count('Hello World World World', 'World') . " (期望: 3)\n";
echo "ucfirst('hello'): " . ucfirst('hello') . " (期望: Hello)\n";
echo "lcfirst('HELLO'): " . lcfirst('HELLO') . " (期望: hELLO)\n";
echo "ucwords('hello world'): " . ucwords('hello world') . " (期望: Hello World)\n";
echo "strrpos('Hello World World', 'World'): " . strrpos('Hello World World', 'World') . " (期望: 12)\n";
echo "str_word_count('Hello World PHP'): " . str_word_count('Hello World PHP') . " (期望: 3)\n";
echo "strpos('Hello World', 'World'): " . strpos('Hello World', 'World') . " (期望: 6)\n";
echo "substr('Hello World', 0, 5): " . substr('Hello World', 0, 5) . " (期望: Hello)\n";

echo "\n=== 验证数学函数 ===\n";
echo "floor(3.9): " . floor(3.9) . " (期望: 3)\n";
echo "ceil(3.1): " . ceil(3.1) . " (期望: 4)\n";
echo "sin(0): " . sin(0) . " (期望: 0)\n";
echo "cos(0): " . cos(0) . " (期望: 1)\n";
echo "pow(2, 10): " . pow(2, 10) . " (期望: 1024)\n";
echo "min(1, 3, 2): " . min(1, 3, 2) . " (期望: 1)\n";
echo "max(1, 3, 2): " . max(1, 3, 2) . " (期望: 3)\n";

echo "\n=== 验证字符操作函数 ===\n";
echo "ord('A'): " . ord('A') . " (期望: 65)\n";
echo "chr(65): " . chr(65) . " (期望: A)\n";
echo "md5('hello'): " . md5('hello') . " (期望: 5d41402abc4b2a76b9719d911017c592)\n";
echo "sha1('hello'): " . sha1('hello') . " (期望: aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d)\n";
echo "strrev('hello'): " . strrev('hello') . " (期望: olleh)\n";

echo "\n=== 验证 trim 函数 ===\n";
echo "trim('  hello  '): '" . trim('  hello  ') . "' (期望: 'hello')\n";
echo "ltrim('  hello  '): '" . ltrim('  hello  ') . "' (期望: 'hello  ')\n";
echo "rtrim('  hello  '): '" . rtrim('  hello  ') . "' (期望: '  hello')\n";

echo "\n=== 验证 addslashes/stripslashes ===\n";
echo "addslashes(\"Hello 'World'\"): " . addslashes("Hello 'World'") . " (期望: Hello \\'World\\')\n";
echo "stripslashes(addslashes(\"Hello 'World'\")): " . stripslashes(addslashes("Hello 'World'")) . " (期望: Hello 'World')\n";

echo "\n=== 验证 implode/explode ===\n";
$arr = explode(' ', 'a b c');
echo "explode(' ', 'a b c') count: " . count($arr) . " (期望: 3)\n";
echo "implode('-', ['a', 'b', 'c']): " . implode('-', ['a', 'b', 'c']) . " (期望: a-b-c)\n";

echo "\n=== 验证 call_user_func ===\n";
function test_add($a, $b) { return $a + $b; }
echo "call_user_func('test_add', 5, 3): " . call_user_func('test_add', 5, 3) . " (期望: 8)\n";
echo "is_callable('test_add'): " . (is_callable('test_add') ? 'true' : 'false') . " (期望: true)\n";

echo "\n=== 验证 get_debug_type ===\n";
echo "get_debug_type('string'): " . get_debug_type('string') . " (期望: string)\n";
echo "get_debug_type(123): " . get_debug_type(123) . " (期望: int)\n";
echo "get_debug_type([]): " . get_debug_type([]) . " (期望: array)\n";

echo "\n=== 验证 ctype 函数 ===\n";
echo "ctype_alnum('abc123'): " . (ctype_alnum('abc123') ? 'true' : 'false') . " (期望: true)\n";
echo "ctype_alpha('abc'): " . (ctype_alpha('abc') ? 'true' : 'false') . " (期望: true)\n";
echo "ctype_digit('123'): " . (ctype_digit('123') ? 'true' : 'false') . " (期望: true)\n";
echo "ctype_space(' '): " . (ctype_space(' ') ? 'true' : 'false') . " (期望: true)\n";
echo "ctype_upper('ABC'): " . (ctype_upper('ABC') ? 'true' : 'false') . " (期望: true)\n";
echo "ctype_lower('abc'): " . (ctype_lower('abc') ? 'true' : 'false') . " (期望: true)\n";

echo "\n=== 所有验证完成 ===\n";
?>
