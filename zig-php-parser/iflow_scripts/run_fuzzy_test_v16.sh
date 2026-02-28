#!/bin/bash

# AOT 模糊测试脚本 v16 - 更多复杂场景

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=848

REPORT_FILE="$SCRIPT_DIR/fuzzy_test_report.md"

auto_test() {
    local php_code="$1"
    local desc="$2"
    local category="$3"
    
    local script_path="$SCRIPT_DIR/test_${COUNTER}.php"
    local php_out="$SCRIPT_DIR/test_${COUNTER}_php.out"
    local interp_out="$SCRIPT_DIR/test_${COUNTER}_interp.out"
    local aot_out="$SCRIPT_DIR/test_${COUNTER}_aot.out"
    local aot_binary="$SCRIPT_DIR/test_${COUNTER}_aot"
    
    printf '%s\n%s%s\n' '<?php' "$php_code" '?>' > "$script_path"
    
    $TIMEOUT 30s $PHP "$script_path" > "$php_out" 2>&1
    PHP_EXIT=$?
    PHP_RESULT=$(cat "$php_out")
    
    $TIMEOUT 30s "$INTERPRETER" "$script_path" 2>&1 | head -1 > "$interp_out" 2>&1
    INTERP_EXIT=$?
    INTERP_RESULT=$(cat "$interp_out")
    
    rm -rf "$SCRIPT_DIR/.zigphp_aot_build"
    $TIMEOUT 30s "$INTERPRETER" --compile --output="$aot_binary" "$script_path" > "$SCRIPT_DIR/test_${COUNTER}_aot_compile.log" 2>&1
    AOT_COMPILE_EXIT=$?
    
    if [ $AOT_COMPILE_EXIT -eq 0 ] && [ -x "$aot_binary" ]; then
        $TIMEOUT 30s "$aot_binary" > "$aot_out" 2>&1
        AOT_EXIT=$?
        AOT_RESULT=$(cat "$aot_out")
    else
        AOT_EXIT=1
        AOT_RESULT="[编译失败]"
    fi
    
    if [ $PHP_EXIT -ne 0 ]; then
        STATUS="PHP_ERROR"
    elif [ $INTERP_EXIT -ne 0 ]; then
        STATUS="INTERP_ERROR"
    elif [ $AOT_COMPILE_EXIT -ne 0 ]; then
        STATUS="AOT_COMPILE_ERROR"
    elif [ $AOT_EXIT -ne 0 ]; then
        STATUS="AOT_RUNTIME_ERROR"
    elif [ "$INTERP_RESULT" != "$PHP_RESULT" ]; then
        STATUS="INTERP_MISMATCH"
    elif [ "$PHP_RESULT" != "$AOT_RESULT" ]; then
        STATUS="RESULT_MISMATCH"
    else
        STATUS="PASS"
    fi
    
    if [ $AOT_COMPILE_EXIT -ne 0 ]; then
        ERROR_INFO=$(cat "$SCRIPT_DIR/test_${COUNTER}_aot_compile.log" 2>/dev/null | grep -i "error" | head -1 | cut -c1-60)
    elif [ $AOT_EXIT -ne 0 ]; then
        ERROR_INFO="AOT运行时错误"
    elif [ "$PHP_RESULT" != "$AOT_RESULT" ]; then
        ERROR_INFO="结果不一致"
    else
        ERROR_INFO="-"
    fi
    
    echo "| $COUNTER | test_$COUNTER.php | $category | ${PHP_RESULT:0:30} | ${INTERP_RESULT:0:30} | ${AOT_RESULT:0:30} | $STATUS | ${ERROR_INFO:0:50} |" >> "$REPORT_FILE"
    
    echo "[$COUNTER] $STATUS: $desc"
    
    COUNTER=$((COUNTER + 1))
}

# 848-950 更多复杂场景测试

auto_test '$arr = array(1, 2, 3); $x = $arr; $x[] = 4; echo count($arr) . "," . count($x);' "数组复制2" "数组"
auto_test '$arr = array(1, 2, 3); echo json_encode($arr);' "json_encode" "函数"
auto_test '$arr = array("a" => 1, "b" => 2); echo json_encode($arr);' "json_encode关联" "函数"
auto_test '$str = "[1,2,3]"; $arr = json_decode($str); echo implode(",", $arr);' "json_decode" "函数"
auto_test '$str = "1,2,3"; $arr = str_getcsv($str); echo count($arr);' "str_getcsv" "函数"
auto_test '$str = "hello"; echo similar_text($str, "world");' "similar_text" "函数"
auto_test '$str = "hello"; echo levenshtein($str, "world");' "levenshtein" "函数"
auto_test '$x = 123.456; echo round($x, 1);' "round一位小数" "函数"
auto_test '$x = 100; echo dechex($x);' "十进制转十六进制" "函数"
auto_test '$x = 255; echo hexdec("ff");' "十六进制转十进制" "函数"
auto_test '$x = 10; echo decoct($x);' "十进制转八进制" "函数"
auto_test '$x = 8; echo octdec($x);' "八进制转十进制" "函数"
auto_test '$x = 5; echo bindec("101");' "二进制转十进制" "函数"
auto_test '$str = "HELLO"; echo strcasecmp($str, "hello");' "strcasecmp" "函数"
auto_test '$str = "abc"; echo strcmp($str, "abd");' "strcmp" "函数"
auto_test '$str = "hello"; echo strncmp($str, "hellx", 4);' "strncmp" "函数"
auto_test '$str = "hello"; echo strncasecmp($str, "HELLO", 4);' "strncasecmp" "函数"
auto_test '$str = "hello world"; echo strpos($str, "world");' "strpos2" "函数"
auto_test '$str = "hello"; echo stripos($str, "L");' "stripos" "函数"
auto_test '$str = "hello"; echo strrpos($str, "l");' "strrpos" "函数"
auto_test '$str = "hello"; echo strripos($str, "L");' "strripos" "函数"
auto_test '$str = "hello"; echo strstr($str, "l");' "strstr" "函数"
auto_test '$str = "hello"; echo stristr($str, "L");' "stristr" "函数"
auto_test '$str = "hello"; echo substr($str, 1);' "substr从索引" "函数"
auto_test '$str = "hello"; echo substr($str, 1, 3);' "substr范围" "函数"
auto_test '$str = "hello"; echo substr_replace($str, "xx", 1, 2);' "substr_replace" "函数"
auto_test '$str = "hello"; echo strtr($str, "lo", "xy");' "strtr2" "函数"
auto_test '$str = "hello"; echo strtr($str, array("l" => "x", "o" => "y"));' "strtr数组" "函数"
auto_test '$arr = array(1, 2, 3); echo array_sum($arr);' "array_sum" "函数"
auto_test '$arr = array(1, 2, 3); echo array_product($arr);' "array_product2" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_reduce($arr, function($c, $i) { return $c + $i; }, 0);' "reduce带初始" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $filtered = array_filter($arr, function($x) { return $x > 2; }); echo implode(",", $filtered);' "filter2" "函数"
auto_test '$arr = array(1, 2, 3); $mapped = array_map(function($x) { return $x * 2; }, $arr); echo implode(",", $mapped);' "map2" "函数"
auto_test '$arr = array(1, 2, 3); echo in_array(2, $arr) ? "yes" : "no";' "in_array4" "函数"
auto_test '$arr = array(1, 2, 3); echo array_search(2, $arr);' "array_search3" "函数"
auto_test '$arr = array(1, 2, 3); echo isset($arr[0]) ? "yes" : "no";' "isset2" "函数"
auto_test '$arr = array(1, 2, 3); echo empty($arr) ? "yes" : "no";' "empty2" "函数"
auto_test '$arr = array("a", "b", "c"); echo implode("", $arr);' "implode空" "函数"
auto_test '$arr = array(); echo count($arr);' "count空数组" "函数"
auto_test '$arr = array(1); echo is_array($arr) ? "array" : "not";' "is_array" "函数"
auto_test '$x = "hello"; echo is_string($x) ? "string" : "not";' "is_string" "函数"
auto_test '$x = 123; echo is_int($x) ? "int" : "not";' "is_int" "函数"
auto_test '$x = 1.5; echo is_float($x) ? "float" : "not";' "is_float" "函数"
auto_test '$x = true; echo is_bool($x) ? "bool" : "not";' "is_bool" "函数"
auto_test '$x = null; echo is_null($x) ? "null" : "not";' "is_null" "函数"
auto_test '$x = 123; echo gettype($x);' "gettype" "函数"
auto_test '$x = "123"; echo intval($x);' "intval2" "函数"
auto_test '$x = 123.45; echo floatval($x);' "floatval" "函数"
auto_test '$x = 123; echo strval($x);' "strval2" "函数"
auto_test '$x = 1; echo (bool)$x;' "bool转换" "函数"
auto_test '$x = 1.5; echo (int)$x;' "int转换2" "函数"
auto_test '$x = 5; echo (float)$x;' "float转换" "函数"
auto_test '$arr = array(1, 2, 3); print_r($arr);' "print_r" "函数"
auto_test '$arr = array("a" => 1, "b" => 2); print_r($arr);' "print_r关联" "函数"
auto_test '$arr = array(1, 2, 3); var_dump($arr);' "var_dump" "函数"
auto_test '$x = array(1, 2, 3); echo is_array($x) ? "yes" : "no";' "is_array2" "函数"
auto_test '$arr = range(1, 10); echo implode(",", array_slice($arr, 0, 5));' "range_slice" "函数"
auto_test '$arr = range(1, 10); echo implode(",", array_slice($arr, 5));' "range_slice2" "函数"
auto_test '$arr = range(1, 10); echo implode(",", array_reverse($arr));' "range_reverse" "函数"
auto_test '$arr1 = array(1, 2); $arr2 = array(3, 4); echo implode(",", array_merge($arr1, $arr2));' "merge_two" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_slice($arr, 0, 3));' "slice_sum2" "函数"
auto_test '$arr = array(1, 2, 3); echo array_sum(array_map(function($x) { return $x; }, $arr));' "map_identity" "函数"
auto_test '$arr = array(1, 2, 3); echo array_sum(array_filter($arr, function($x) { return true; }));' "filter_all" "函数"
auto_test '$arr = array(); for ($i = 1; $i <= 5; $i++) { $arr[] = $i * $i; } echo implode(",", $arr);' "平方数组" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 10; $i++) { if ($i % 2 == 0) $arr[] = $i; } echo implode(",", $arr);' "偶数数组" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 10; $i++) { $arr[$i] = $i * 2; } echo implode(",", array_values($arr));' "关联数组循环" "循环"
auto_test '$sum = 0; for ($i = 1; $i <= 20; $i++) { if ($i % 3 == 0) $sum += $i; } echo $sum;' "3的倍数20内" "循环"
auto_test '$sum = 0; for ($i = 1; $i <= 50; $i++) { if ($i % 5 == 0) $sum += $i; } echo $sum;' "5的倍数50内" "循环"
auto_test '$fact = 1; for ($i = 1; $i <= 12; $i++) { $fact *= $i; } echo $fact;' "12的阶乘" "循环"
auto_test '$fib = array(1, 1); for ($i = 2; $i < 10; $i++) { $fib[] = $fib[$i-1] + $fib[$i-2]; } echo implode(",", $fib);' "斐波那契数列" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { $sum += $v; } echo $sum;' "foreach_sum" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $i => $v) { $sum += $v * ($i + 1); } echo $sum;' "foreach加权" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $found = false; foreach ($arr as $v) { if ($v == 3) { $found = true; break; } } echo $found ? "found" : "not";' "foreach查找" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $count = 0; foreach ($arr as $v) { if ($v % 2 == 0) $count++; } echo $count;' "foreach计数偶数" "循环"
auto_test '$i = 0; $sum = 0; while ($i <= 10) { $sum += $i; $i++; } echo $sum;' "while_sum" "循环"
auto_test '$i = 1; $fact = 1; while ($i <= 10) { $fact *= $i; $i++; } echo $fact;' "while阶乘2" "循环"
auto_test '$i = 0; $sum = 0; do { $sum += $i; $i++; } while ($i <= 10); echo $sum;' "do_while_sum" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; for ($i = 0; $i < count($arr); $i++) { $sum += $arr[$i]; } echo $sum;' "for_index_sum" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; for ($i = count($arr) - 1; $i >= 0; $i--) { $sum += $arr[$i]; } echo $sum;' "for_reverse_sum" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum($arr); echo array_product($arr);' "sum_product" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo max($arr) . min($arr);' "max_min3" "函数"

echo ""
echo "========================================="
echo "测试完成！报告: $REPORT_FILE"
echo "========================================="
tail -30 "$REPORT_FILE"
