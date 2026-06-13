<?php
/**
 * Comprehensive test suite for PHP runtime functions.
 * Tests: implode/join, string index read/write, array_keys, array_values,
 *        explode, in_array, array_search, strlen, strpos, substr.
 */

$passed = 0;
$failed = 0;
$test_num = 0;

function assert_eq($expected, $actual, $test_name) {
    global $passed, $failed, $test_num;
    $test_num++;
    if ($expected === $actual) {
        $passed++;
        echo "PASS: [$test_num] $test_name\n";
    } else {
        $failed++;
        echo "FAIL: [$test_num] $test_name\n";
        echo "  Expected: " . var_export($expected, true) . "\n";
        echo "  Actual:   " . var_export($actual, true) . "\n";
    }
}

function assert_true($condition, $test_name) {
    global $passed, $failed, $test_num;
    $test_num++;
    if ($condition) {
        $passed++;
        echo "PASS: [$test_num] $test_name\n";
    } else {
        $failed++;
        echo "FAIL: [$test_num] $test_name\n";
        echo "  Expected: true\n";
        echo "  Actual:   false\n";
    }
}

function assert_false($condition, $test_name) {
    global $passed, $failed, $test_num;
    $test_num++;
    if (!$condition) {
        $passed++;
        echo "PASS: [$test_num] $test_name\n";
    } else {
        $failed++;
        echo "FAIL: [$test_num] $test_name\n";
        echo "  Expected: false\n";
        echo "  Actual:   true\n";
    }
}

// ============================================================
// 1. strlen
// ============================================================
echo "=== Testing strlen ===\n";

assert_eq(0, strlen(""), "strlen of empty string");
assert_eq(5, strlen("hello"), "strlen of 'hello'");
assert_eq(11, strlen("hello world"), "strlen of 'hello world'");
assert_eq(1, strlen("a"), "strlen of single char 'a'");
assert_eq(3, strlen("你好"), "strlen of multi-byte UTF-8 '你好'");

// ============================================================
// 2. strpos
// ============================================================
echo "\n=== Testing strpos ===\n";

assert_eq(0, strpos("hello", "h"), "strpos find 'h' at start");
assert_eq(2, strpos("hello", "l"), "strpos find first 'l'");
assert_eq(4, strpos("hello", "o"), "strpos find 'o' at end");
assert_eq(false, strpos("hello", "x"), "strpos not found returns false");
assert_eq(false, strpos("", "a"), "strpos empty haystack returns false");
assert_eq(false, strpos("hello", ""), "strpos empty needle returns false");
assert_eq(6, strpos("hello world", "world"), "strpos find 'world'");
assert_eq(3, strpos("abcdef", "def", 0), "strpos with offset 0");

// ============================================================
// 3. substr
// ============================================================
echo "\n=== Testing substr ===\n";

assert_eq("hello", substr("hello world", 0, 5), "substr positive start + length");
assert_eq("world", substr("hello world", 6), "substr positive start, no length");
assert_eq("world", substr("hello world", 6, 5), "substr exact match");
assert_eq("hell", substr("hello", 0, 4), "substr partial");
assert_eq("ello", substr("hello", 1), "substr from index 1");
assert_eq("o", substr("hello", -1), "substr negative start (last char)");
assert_eq("world", substr("hello world", -5), "substr negative start (last 5)");
assert_eq("wo", substr("hello world", 6, 2), "substr with explicit length");
assert_eq("", substr("hello", 10), "substr start beyond length");
assert_eq("", substr("hello", 0, 0), "substr zero length");

// ============================================================
// 4. explode
// ============================================================
echo "\n=== Testing explode ===\n";

$result = explode(",", "a,b,c,d");
assert_eq(["a", "b", "c", "d"], $result, "explode by comma");

$result = explode(" ", "hello world foo bar");
assert_eq(["hello", "world", "foo", "bar"], $result, "explode by space");

$result = explode(":", "single");
assert_eq(["single"], $result, "explode no delimiter found");

$result = explode("-", "one--two--three");
assert_eq(["one", "", "two", "", "three"], $result, "explode with empty parts");

$result = explode("|", "a|b|c|d|e");
assert_eq(["a", "b", "c", "d", "e"], $result, "explode with pipe delimiter");

// ============================================================
// 5. implode / join
// ============================================================
echo "\n=== Testing implode ===\n";

assert_eq("a,b,c", implode(",", ["a", "b", "c"]), "implode with comma");
assert_eq("hello world", implode(" ", ["hello", "world"]), "implode with space");
assert_eq("", implode(",", []), "implode empty array");
assert_eq("abc", implode("", ["a", "b", "c"]), "implode with empty glue");
assert_eq("one", implode("|", ["one"]), "implode single element");
assert_eq("1-2-3", implode("-", [1, 2, 3]), "implode numeric array");

// join is alias of implode
assert_eq("a,b,c", join(",", ["a", "b", "c"]), "join is alias of implode");

// ============================================================
// 6. array_keys
// ============================================================
echo "\n=== Testing array_keys ===\n";

$keys = array_keys(["a" => 1, "b" => 2, "c" => 3]);
sort($keys);
assert_eq(["a", "b", "c"], $keys, "array_keys string keys");

$keys = array_keys([10, 20, 30, 40]);
assert_eq([0, 1, 2, 3], $keys, "array_keys integer keys");

$keys = array_keys(["x" => "foo", 5 => "bar", "y" => "baz"]);
assert_eq(["x", 5, "y"], $keys, "array_keys mixed keys");

$keys = array_keys([]);
assert_eq([], $keys, "array_keys empty array");

// ============================================================
// 7. array_values
// ============================================================
echo "\n=== Testing array_values ===\n";

$values = array_values(["a" => 1, "b" => 2, "c" => 3]);
assert_eq([1, 2, 3], $values, "array_values with string keys");

$values = array_values([10, 20, 30]);
assert_eq([10, 20, 30], $values, "array_values with integer keys");

$values = array_values(["x" => "foo", "y" => "bar"]);
assert_eq(["foo", "bar"], $values, "array_values string values");

$values = array_values([]);
assert_eq([], $values, "array_values empty array");

// ============================================================
// 8. in_array
// ============================================================
echo "\n=== Testing in_array ===\n";

assert_true(in_array("a", ["a", "b", "c"]), "in_array string found");
assert_false(in_array("x", ["a", "b", "c"]), "in_array string not found");
assert_true(in_array(42, [10, 20, 30, 42]), "in_array int found");
assert_false(in_array(99, [10, 20, 30]), "in_array int not found");
assert_true(in_array("42", [42]), "in_array loose comparison string to int");
assert_false(in_array("hello", []), "in_array empty array");
assert_false(in_array("test", "not_an_array"), "in_array non-array haystack");

// ============================================================
// 9. array_search
// ============================================================
echo "\n=== Testing array_search ===\n";

assert_eq(1, array_search("b", ["a", "b", "c"]), "array_search find string");
assert_eq(2, array_search(30, [10, 20, 30]), "array_search find integer");
assert_eq("a", array_search(1, ["a" => 1, "b" => 2]), "array_search returns string key");
assert_eq(false, array_search("x", ["a", "b", "c"]), "array_search not found returns false");
assert_eq(false, array_search("test", []), "array_search empty array returns false");

// ============================================================
// 10. String index read ($str[offset])
// ============================================================
echo "\n=== Testing string index read ===\n";

$str = "hello";
assert_eq("h", $str[0], "string index read first char");
assert_eq("e", $str[1], "string index read second char");
assert_eq("o", $str[4], "string index read last char");
assert_eq("l", $str[2], "string index read middle char");

// Negative offsets (if supported - PHP 7.1+)
$str2 = "abcdef";
assert_eq("f", $str2[-1], "string index read negative offset -1");
assert_eq("e", $str2[-2], "string index read negative offset -2");

// Out of bounds
$str3 = "hi";
assert_eq("", @$str3[10], "string index read out of bounds returns empty string");

// Empty string
$str4 = "";
assert_eq("", @$str4[0], "string index read on empty string returns empty string");

// ============================================================
// 11. String index write ($str[offset] = 'x')
// ============================================================
echo "\n=== Testing string index write ===\n";

$str5 = "hello";
$str5[0] = "H";
assert_eq("Hello", $str5, "string index write modify first char");

$str6 = "hello";
$str6[4] = "O";
assert_eq("hellO", $str6, "string index write modify last char");

$str7 = "hello";
$str7[1] = "A";
assert_eq("hAllo", $str7, "string index write modify middle char");

// Write single character from multi-char string (takes first byte)
$str8 = "hello";
$str8[0] = "XY";
assert_eq("Xello", $str8, "string index write takes first char from multi-char");

// Empty char write does nothing
$str9 = "test";
$str9[2] = "";
assert_eq("test", $str9, "string index write empty string does nothing");

// Write at negative offset
$str10 = "abcdef";
$str10[-1] = "X";
assert_eq("abcdeX", $str10, "string index write at negative offset");

// ============================================================
// Summary
// ============================================================
echo "\n=======================================\n";
echo "Tests completed: $test_num\n";
echo "Passed: $passed\n";
echo "Failed: $failed\n";
echo "=======================================\n";

if ($failed > 0) {
    exit(1);
}