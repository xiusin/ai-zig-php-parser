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
} elseif ($score >= 80) {
    $grade = "B";
} elseif ($score >= 70) {
    $grade = "C";
} else {
    $grade = "F";
}
test("嵌套 if-elseif-else", $grade == "B");

// 三元运算符
$status = $score >= 60 ? "Pass" : "Fail";
test("三元运算符", $status == "Pass");

// 空合并运算符
$val = null;
$default = $val ?? "default";
test("空合并 ?? null", $default == "default");

$val2 = "value";
$default2 = $val2 ?? "default";
test("空合并 ?? 有值", $default2 == "value");

// for 循环
$sum = 0;
for ($i = 1; $i <= 10; $i++) {
    $sum += $i;
}
test("for 循环求和 1-10", $sum == 55);

// while 循环
$factorial = 1;
$n = 5;
while ($n > 1) {
    $factorial *= $n;
    $n--;
}
test("while 循环阶乘 5!", $factorial == 120);

// foreach
$colors = ["red", "green", "blue"];
$concat = "";
foreach ($colors as $color) {
    $concat .= $color;
}
test("foreach 连接", $concat == "redgreenblue");

// foreach 带键
$kv = "";
foreach ($person as $k => $v) {
    $kv .= "$k:$v;";
}
test("foreach 带键", strpos($kv, "name:John") !== false);

// break 和 continue
$result = 0;
for ($i = 0; $i < 10; $i++) {
    if ($i == 3) continue;
    if ($i == 7) break;
    $result += $i;
}
test("break/continue", $result == 0 + 1 + 2 + 4 + 5 + 6); // 18

// switch
$day = 3;
$dayName = "";
switch ($day) {
    case 1: $dayName = "Mon"; break;
    case 2: $dayName = "Tue"; break;
    case 3: $dayName = "Wed"; break;
    default: $dayName = "Unknown";
}
test("switch", $dayName == "Wed");

// ============================================================================
// 5. 函数测试
// ============================================================================
echo "\n=== 函数 ===\n";

// 基本函数
function add($a, $b) {
    return $a + $b;
}
test("基本函数", add(3, 4) == 7);

// 默认参数
function greet($name, $greeting = "Hello") {
    return "$greeting, $name!";
}
test("默认参数", greet("World") == "Hello, World!");
test("覆盖默认参数", greet("World", "Hi") == "Hi, World!");

// 递归函数
function fib($n) {
    if ($n <= 1) return $n;
    return fib($n - 1) + fib($n - 2);
}
test("递归: fib(10)", fib(10) == 55);

// 闭包/匿名函数
$multiply = function($x, $y) {
    return $x * $y;
};
test("匿名函数", $multiply(3, 4) == 12);

// ============================================================================
// 6. 数学函数测试
// ============================================================================
echo "\n=== 数学函数 ===\n";

test("abs 负数", abs(-42) == 42);
test("abs 浮点", abs(-3.14) == 3.14);
test("ceil", ceil(4.3) == 5);
test("floor", floor(4.7) == 4);
test("round", round(4.5) == 5);
test("sqrt", abs(sqrt(16) - 4) < 0.0001);
test("pow", pow(2, 8) == 256);
test("min", min(3, 1, 4, 1, 5) == 1);
test("max", max(3, 1, 4, 1, 5) == 5);

// 三角函数
test("sin(0)", abs(sin(0)) < 0.0001);
test("cos(0)", abs(cos(0) - 1) < 0.0001);
test("tan(0)", abs(tan(0)) < 0.0001);

// 对数和指数
test("log(e)", abs(log(M_E) - 1) < 0.0001);
test("exp(1)", abs(exp(1) - M_E) < 0.0001);
test("log10(100)", abs(log10(100) - 2) < 0.0001);

// 角度转换
test("deg2rad(180)", abs(deg2rad(180) - M_PI) < 0.0001);
test("rad2deg(PI)", abs(rad2deg(M_PI) - 180) < 0.0001);

// ============================================================================
// 7. 类型检查和转换测试
// ============================================================================
echo "\n=== 类型检查和转换 ===\n";

test("is_null", is_null(null));
test("is_bool", is_bool(true));
test("is_int", is_int(42));
test("is_float", is_float(3.14));
test("is_string", is_string("hello"));
test("is_array", is_array([1, 2, 3]));
test("is_numeric int", is_numeric(42));
test("is_numeric float", is_numeric(3.14));
test("is_numeric string", is_numeric("123"));
test("is_numeric 非数字", !is_numeric("abc"));

// 类型转换
test("intval string", intval("42") == 42);
test("intval float", intval(3.9) == 3);
test("floatval string", abs(floatval("3.14") - 3.14) < 0.0001);
test("boolval 0", boolval(0) == false);
test("boolval 1", boolval(1) == true);
test("boolval empty string", boolval("") == false);
test("boolval non-empty string", boolval("hello") == true);

// gettype
test("gettype null", gettype(null) == "NULL");
test("gettype bool", gettype(true) == "boolean");
test("gettype int", gettype(42) == "integer");
test("gettype float", gettype(3.14) == "double");
test("gettype string", gettype("hi") == "string");
test("gettype array", gettype([]) == "array");

// ============================================================================
// 8. JSON 测试
// ============================================================================
echo "\n=== JSON ===\n";

$data = [
    "name" => "John",
    "age" => 30,
    "active" => true,
    "scores" => [85, 90, 78]
];
$json = json_encode($data);
test("json_encode 包含 name", strpos($json, '"name"') !== false);
test("json_encode 包含 30", strpos($json, '30') !== false);

$decoded = json_decode($json);
test("json_decode 是数组", is_array($decoded));

// 简单 JSON
$simple = json_encode(["a" => 1, "b" => 2]);
test("json_encode 简单对象", $simple == '{"a":1,"b":2}' || strpos($simple, '"a":1') !== false);

$list = json_encode([1, 2, 3]);
test("json_encode 数组", $list == '[1,2,3]');

// ============================================================================
// 9. 哈希函数测试
// ============================================================================
echo "\n=== 哈希函数 ===\n";

$md5_result = md5("hello");
test("md5 长度", strlen($md5_result) == 32);
test("md5 hello", $md5_result == "5d41402abc4b2a76b9719d911017c592");

$sha1_result = sha1("hello");
test("sha1 长度", strlen($sha1_result) == 40);
test("sha1 hello", $sha1_result == "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d");

// base64
$encoded = base64_encode("Hello World");
test("base64_encode", $encoded == "SGVsbG8gV29ybGQ=");

$decoded_b64 = base64_decode($encoded);
test("base64_decode", $decoded_b64 == "Hello World");

// ============================================================================
// 10. 时间函数测试
// ============================================================================
echo "\n=== 时间函数 ===\n";

$now = time();
test("time 返回正数", $now > 0);

$micro = microtime(true);
test("microtime(true) 返回浮点数", is_float($micro));
test("microtime(true) > time()", $micro >= $now);

// ============================================================================
// 11. 随机数测试
// ============================================================================
echo "\n=== 随机数 ===\n";

$rand1 = rand(1, 100);
test("rand 范围", $rand1 >= 1 && $rand1 <= 100);

$rand2 = mt_rand(1, 100);
test("mt_rand 范围", $rand2 >= 1 && $rand2 <= 100);

// ============================================================================
// 总结
// ============================================================================
echo "\n========================================\n";
echo "测试结果: $passed 通过, $failed 失败\n";
echo "========================================\n";

if ($failed > 0) {
    echo "\n失败的测试:\n";
    foreach ($errors as $err) {
        echo "  - $err\n";
    }
}

// 退出码
if ($failed > 0) {
    exit(1);
}
