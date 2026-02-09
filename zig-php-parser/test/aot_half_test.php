<?php
/**
 * AOT 复杂功能测试
 * 用于发现 AOT 运行时中未实现或有问题的功能
 */

$passed = 0;
$failed = 0;
$errors = [];

function test($name, $condition) {
    global $passed, $failed, $errors;
    if ($condition) {
        $passed++;
        echo "[PASS] $name\n";
    } else {
        $failed++;
        $errors[] = $name;
        echo "[FAIL] $name\n";
    }
}

// ============================================================================
// 1. 复杂算术运算测试
// ============================================================================
echo "\n=== 复杂算术运算 ===\n";

// 嵌套运算
$a = 10;
$b = 3;
$c = 2;
$result = ($a + $b) * $c - ($a / $b);
test("嵌套算术: (10+3)*2-(10/3)", abs($result - 22.666666666667) < 0.0001);

// 复合赋值运算
$x = 100;
$x += 50;
$x -= 30;
$x *= 2;
$x /= 4;
test("复合赋值: 100+50-30*2/4", $x == 60);

// 自增自减
$i = 5;
$pre = ++$i;
$post = $i++;
test("前置自增: ++5 == 6", $pre == 6);
test("后置自增: 6++ == 6", $post == 6);
test("自增后值: i == 7", $i == 7);

// 取模和幂运算
test("取模: 17 % 5 == 2", 17 % 5 == 2);
test("负数取模: -17 % 5", (-17 % 5) == -2 || (-17 % 5) == 3);
test("幂运算: 2 ** 10 == 1024", 2 ** 10 == 1024);
test("浮点幂: 2.5 ** 3", abs(2.5 ** 3 - 15.625) < 0.0001);

// ============================================================================
// 2. 复杂字符串操作测试
// ============================================================================
echo "\n=== 复杂字符串操作 ===\n";

// 字符串插值
$name = "Alice";
$age = 30;
$greeting = "Hello, $name! You are $age years old.";
test("字符串插值", $greeting == "Hello, Alice! You are 30 years old.");

// 复杂字符串函数链
$text = "  Hello World  ";
$result = strtoupper(trim($text));
test("函数链: strtoupper(trim())", $result == "HELLO WORLD");

// 字符串替换
$str = "foo bar foo baz foo";
$replaced = str_replace("foo", "XXX", $str);
test("str_replace 多次替换", $replaced == "XXX bar XXX baz XXX");

// explode 和 implode
$csv = "apple,banana,cherry";
$arr = explode(",", $csv);
test("explode 分割", count($arr) == 3 && $arr[0] == "apple");

$joined = implode("-", $arr);
test("implode 连接", $joined == "apple-banana-cherry");

// substr 负数索引
$str = "Hello World";
test("substr 负数起始: substr('Hello World', -5)", substr($str, -5) == "World");
test("substr 负数长度: substr('Hello World', 0, -6)", substr($str, 0, -6) == "Hello");
test("substr 负数起始和长度: substr('Hello World', -5, -2)", substr($str, -5, -2) == "Wor");

// str_pad
$padded = str_pad("42", 5, "0");
test("str_pad 右填充", strlen($padded) == 5);

// str_repeat
$repeated = str_repeat("ab", 3);
test("str_repeat", $repeated == "ababab");

// strrev
$reversed = strrev("hello");
test("strrev", $reversed == "olleh");

// ucfirst/lcfirst/ucwords
test("ucfirst", ucfirst("hello") == "Hello");
test("lcfirst", lcfirst("HELLO") == "hELLO");
test("ucwords", ucwords("hello world") == "Hello World");

// PHP 8.0+ 字符串函数
test("str_contains 存在", str_contains("Hello World", "World"));
test("str_contains 不存在", !str_contains("Hello World", "xyz"));
test("str_starts_with", str_starts_with("Hello World", "Hello"));
test("str_ends_with", str_ends_with("Hello World", "World"));

// ============================================================================
// 3. 复杂数组操作测试
// ============================================================================
echo "\n=== 复杂数组操作 ===\n";

// 多维数组
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];
test("多维数组访问", $matrix[1][1] == 5);

// 关联数组
$person = [
    "name" => "John",
    "age" => 25,
    "city" => "NYC"
];
test("关联数组 name", $person["name"] == "John");
test("关联数组 age", $person["age"] == 25);

// 数组函数
$numbers = [3, 1, 4, 1, 5, 9, 2, 6];
test("count", count($numbers) == 8);
test("array_sum", array_sum($numbers) == 31);
test("array_product", array_product([2, 3, 4]) == 24);

// in_array
test("in_array 存在", in_array(5, $numbers));
test("in_array 不存在", !in_array(100, $numbers));

// array_keys 和 array_values
$assoc = ["a" => 1, "b" => 2, "c" => 3];
$keys = array_keys($assoc);
$values = array_values($assoc);
test("array_keys", count($keys) == 3);
test("array_values", count($values) == 3);

// array_merge
$arr1 = [1, 2];
$arr2 = [3, 4];
$merged = array_merge($arr1, $arr2);
test("array_merge", count($merged) == 4 && $merged[3] == 4);

// array_slice
$slice = array_slice([1, 2, 3, 4, 5], 1, 3);
test("array_slice", count($slice) == 3 && $slice[0] == 2);

// array_reverse
$rev = array_reverse([1, 2, 3]);
test("array_reverse", $rev[0] == 3 && $rev[2] == 1);

// array_unique
$unique = array_unique([1, 2, 2, 3, 3, 3]);
test("array_unique", count($unique) == 3);

// array_flip
$flipped = array_flip(["a" => 1, "b" => 2]);
test("array_flip", $flipped[1] == "a");

// array_fill
$filled = array_fill(0, 5, "x");
test("array_fill", count($filled) == 5 && $filled[4] == "x");

// range
$range = range(1, 5);
test("range 升序", count($range) == 5 && $range[0] == 1 && $range[4] == 5);

$range_desc = range(5, 1);
test("range 降序", count($range_desc) == 5 && $range_desc[0] == 5);

// array_key_exists
test("array_key_exists 存在", array_key_exists("name", $person));
test("array_key_exists 不存在", !array_key_exists("unknown", $person));

// ============================================================================
// 4. 控制流测试
// ============================================================================
echo "\n=== 控制流 ===\n";

// 嵌套 if-else
$score = 85;
$grade = "";
if ($score >= 90) {
    $grade = "A";
