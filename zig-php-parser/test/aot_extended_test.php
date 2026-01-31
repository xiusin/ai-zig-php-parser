<?php
/**
 * AOT运行时库扩展功能测试脚本
 * 
 * 测试新增的数组、字符串、文件、JSON等函数
 */

$passed = 0;
$failed = 0;
$tests = [];

function test($name, $condition, $expected = null, $actual = null) {
    global $passed, $failed, $tests;
    if ($condition) {
        $passed++;
        $tests[] = "✓ $name";
    } else {
        $failed++;
        $detail = "";
        if ($expected !== null) {
            $detail = " (期望: " . var_export($expected, true) . ", 实际: " . var_export($actual, true) . ")";
        }
        $tests[] = "✗ $name$detail";
    }
}

echo "=== AOT扩展功能测试 ===\n\n";

// ============================================================================
// 数组扩展函数测试
// ============================================================================
echo "--- 数组扩展函数 ---\n";

// array_sum
$arr = [1, 2, 3, 4, 5];
$sum = array_sum($arr);
test("array_sum 整数", $sum === 15, 15, $sum);

$arr_float = [1.5, 2.5, 3.0];
$sum_float = array_sum($arr_float);
test("array_sum 浮点数", $sum_float === 7.0, 7.0, $sum_float);

// array_product
$arr = [1, 2, 3, 4];
$product = array_product($arr);
test("array_product", $product === 24, 24, $product);

// array_reverse
$arr = [1, 2, 3];
$reversed = array_reverse($arr);
test("array_reverse", $reversed === [3, 2, 1], [3, 2, 1], $reversed);

// array_unique
$arr = [1, 2, 2, 3, 3, 3];
$unique = array_unique($arr);
test("array_unique", count($unique) === 3);

// array_flip
$arr = ['a' => 1, 'b' => 2];
$flipped = array_flip($arr);
test("array_flip", isset($flipped[1]) && $flipped[1] === 'a');

// array_key_exists
$arr = ['name' => 'Alice', 'age' => 30];
test("array_key_exists 存在", array_key_exists('name', $arr) === true);
test("array_key_exists 不存在", array_key_exists('email', $arr) === false);

// array_key_first / array_key_last (PHP 7.3+)
$arr = ['a' => 1, 'b' => 2, 'c' => 3];
test("array_key_first", array_key_first($arr) === 'a', 'a', array_key_first($arr));
test("array_key_last", array_key_last($arr) === 'c', 'c', array_key_last($arr));

// array_fill
$filled = array_fill(0, 3, 'x');
test("array_fill", count($filled) === 3 && $filled[0] === 'x');

// range
$range = range(1, 5);
test("range 递增", $range === [1, 2, 3, 4, 5], [1, 2, 3, 4, 5], $range);

$range_desc = range(5, 1);
test("range 递减", $range_desc === [5, 4, 3, 2, 1], [5, 4, 3, 2, 1], $range_desc);

// array_search
$arr = ['apple', 'banana', 'cherry'];
$idx = array_search('banana', $arr);
test("array_search 找到", $idx === 1, 1, $idx);

$idx_not_found = array_search('orange', $arr);
test("array_search 未找到", $idx_not_found === false);

// ============================================================================
// 字符串扩展函数测试
// ============================================================================
echo "\n--- 字符串扩展函数 ---\n";

// ord / chr
test("ord", ord('A') === 65, 65, ord('A'));
test("chr", chr(65) === 'A', 'A', chr(65));

// stripos (不区分大小写)
$pos = stripos("Hello World", "WORLD");
test("stripos", $pos === 6, 6, $pos);

// strrpos (最后出现位置)
$pos = strrpos("hello hello", "hello");
test("strrpos", $pos === 6, 6, $pos);

// number_format
$formatted = number_format(1234.5678, 2);
test("number_format", strpos($formatted, "234") !== false);

// nl2br
$result = nl2br("line1\nline2");
test("nl2br", strpos($result, "<br") !== false);

// strip_tags
$result = strip_tags("<p>Hello</p> <b>World</b>");
test("strip_tags", $result === "Hello World", "Hello World", $result);

// gettype
test("gettype null", gettype(null) === "NULL", "NULL", gettype(null));
test("gettype bool", gettype(true) === "boolean", "boolean", gettype(true));
test("gettype int", gettype(42) === "integer", "integer", gettype(42));
test("gettype float", gettype(3.14) === "double", "double", gettype(3.14));
test("gettype string", gettype("hello") === "string", "string", gettype("hello"));
test("gettype array", gettype([1,2,3]) === "array", "array", gettype([1,2,3]));

// strval
test("strval int", strval(123) === "123", "123", strval(123));
test("strval float", strval(3.14) === "3.14" || strval(3.14) === "3.1400000000000001");

// ============================================================================
// JSON函数测试
// ============================================================================
echo "\n--- JSON函数 ---\n";

// json_encode 基础类型
test("json_encode null", json_encode(null) === "null", "null", json_encode(null));
test("json_encode bool true", json_encode(true) === "true", "true", json_encode(true));
test("json_encode bool false", json_encode(false) === "false", "false", json_encode(false));
test("json_encode int", json_encode(42) === "42", "42", json_encode(42));
test("json_encode string", json_encode("hello") === '"hello"', '"hello"', json_encode("hello"));

// json_encode 数组
$arr = [1, 2, 3];
$json = json_encode($arr);
test("json_encode 索引数组", $json === "[1,2,3]", "[1,2,3]", $json);

$obj = ['name' => 'Alice', 'age' => 30];
$json = json_encode($obj);
test("json_encode 关联数组", strpos($json, '"name"') !== false && strpos($json, '"Alice"') !== false);

// json_decode
$decoded = json_decode('{"name":"Bob","age":25}', true);
test("json_decode 对象", $decoded['name'] === 'Bob' && $decoded['age'] === 25);

$decoded_arr = json_decode('[1,2,3]', true);
test("json_decode 数组", $decoded_arr === [1, 2, 3], [1, 2, 3], $decoded_arr);

$decoded_null = json_decode('null');
test("json_decode null", $decoded_null === null);

$decoded_bool = json_decode('true');
test("json_decode true", $decoded_bool === true);

// ============================================================================
// 文件函数测试
// ============================================================================
echo "\n--- 文件函数 ---\n";

$test_file = '/tmp/aot_test_file.txt';
$test_content = "Hello, AOT!\nLine 2";

// file_put_contents
$bytes = file_put_contents($test_file, $test_content);
test("file_put_contents", $bytes > 0, "> 0", $bytes);

// file_exists
test("file_exists 存在", file_exists($test_file) === true);
test("file_exists 不存在", file_exists('/tmp/nonexistent_file_xyz.txt') === false);

// is_file
test("is_file 是文件", is_file($test_file) === true);

// is_dir
test("is_dir /tmp", is_dir('/tmp') === true);
test("is_dir 不是目录", is_dir($test_file) === false);

// file_get_contents
$content = file_get_contents($test_file);
test("file_get_contents", $content === $test_content, $test_content, $content);

// basename
test("basename", basename('/path/to/file.txt') === 'file.txt', 'file.txt', basename('/path/to/file.txt'));

// dirname
test("dirname", dirname('/path/to/file.txt') === '/path/to', '/path/to', dirname('/path/to/file.txt'));

// unlink (删除测试文件)
$deleted = unlink($test_file);
test("unlink", $deleted === true);
test("unlink 验证删除", file_exists($test_file) === false);

// mkdir / rmdir
$test_dir = '/tmp/aot_test_dir_' . time();
test("mkdir", mkdir($test_dir) === true);
test("mkdir 验证", is_dir($test_dir) === true);
test("rmdir", rmdir($test_dir) === true);
test("rmdir 验证", is_dir($test_dir) === false);

// ============================================================================
// 杂项函数测试
// ============================================================================
echo "\n--- 杂项函数 ---\n";

// empty
test("empty null", empty(null) === true);
test("empty false", empty(false) === true);
test("empty 0", empty(0) === true);
test("empty ''", empty('') === true);
test("empty '0'", empty('0') === true);
test("empty []", empty([]) === true);
test("empty 非空字符串", empty('hello') === false);
test("empty 非零数", empty(1) === false);

// isset
$var = "test";
$null_var = null;
test("isset 已设置", isset($var) === true);
test("isset null", isset($null_var) === false);

// ============================================================================
// 已有函数验证（确保未破坏）
// ============================================================================
echo "\n--- 已有函数回归测试 ---\n";

// 字符串函数
test("strlen", strlen("hello") === 5);
test("strtoupper", strtoupper("hello") === "HELLO");
test("strtolower", strtolower("HELLO") === "hello");
test("trim", trim("  hello  ") === "hello");
test("str_replace", str_replace("world", "PHP", "hello world") === "hello PHP");
test("strpos", strpos("hello", "ll") === 2);
test("substr", substr("hello", 1, 3) === "ell");
test("ucfirst", ucfirst("hello") === "Hello");
test("str_repeat", str_repeat("ab", 3) === "ababab");
test("strrev", strrev("hello") === "olleh");
test("str_contains", str_contains("hello world", "world") === true);
test("str_starts_with", str_starts_with("hello", "hel") === true);
test("str_ends_with", str_ends_with("hello", "llo") === true);

// 数组函数
$arr = [1, 2, 3];
test("count", count($arr) === 3);
test("array_push", (array_push($arr, 4) && count($arr) === 4));
test("in_array", in_array(2, $arr) === true);
test("array_keys", array_keys(['a' => 1, 'b' => 2]) == ['a', 'b']);
test("array_values", array_values(['a' => 1, 'b' => 2]) == [1, 2]);
test("array_merge", array_merge([1, 2], [3, 4]) == [1, 2, 3, 4]);

// 数学函数
test("abs", abs(-5) === 5);
test("sqrt", sqrt(16) === 4.0);
test("round", round(3.7) === 4.0);
test("floor", floor(3.7) === 3.0);
test("ceil", ceil(3.2) === 4.0);
test("min", min(1, 2, 3) === 1);
test("max", max(1, 2, 3) === 3);
test("pow", pow(2, 3) == 8);
test("pi", abs(pi() - 3.14159) < 0.001);

// 类型检查
test("is_null", is_null(null) === true);
test("is_bool", is_bool(true) === true);
test("is_int", is_int(42) === true);
test("is_float", is_float(3.14) === true);
test("is_string", is_string("hello") === true);
test("is_array", is_array([1,2,3]) === true);
test("is_numeric int", is_numeric(42) === true);
test("is_numeric string", is_numeric("42") === true);

// 类型转换
test("intval", intval("123") === 123);
test("floatval", floatval("3.14") === 3.14);
test("boolval", boolval(1) === true);

// ============================================================================
// 测试结果汇总
// ============================================================================
echo "\n=== 测试结果汇总 ===\n";
echo "通过: $passed\n";
echo "失败: $failed\n";
echo "总计: " . ($passed + $failed) . "\n";

if ($failed > 0) {
    echo "\n失败的测试:\n";
    foreach ($tests as $test) {
        if (strpos($test, "✗") === 0) {
            echo "  $test\n";
        }
    }
}

echo "\n完成率: " . round($passed / ($passed + $failed) * 100, 1) . "%\n";

// 返回适当的退出码
exit($failed > 0 ? 1 : 0);
