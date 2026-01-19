<?php
// 字符串操作测试
// 用于 AOT 性能测试

function string_concat_test() {
    $result = "";
    for ($i = 0; $i < 1000; $i++) {
        $result .= "test";
    }
    return strlen($result);
}

function string_search_test() {
    $haystack = str_repeat("abcdefghijklmnopqrstuvwxyz", 100);
    $count = 0;
    for ($i = 0; $i < 100; $i++) {
        if (strpos($haystack, "xyz") !== false) {
            $count++;
        }
    }
    return $count;
}

function string_replace_test() {
    $text = str_repeat("hello world ", 100);
    for ($i = 0; $i < 100; $i++) {
        $text = str_replace("world", "PHP", $text);
    }
    return strlen($text);
}

// 执行测试
$concat_len = string_concat_test();
$search_count = string_search_test();
$replace_len = string_replace_test();

echo "Concat length: $concat_len\n";
echo "Search count: $search_count\n";
echo "Replace length: $replace_len\n";
