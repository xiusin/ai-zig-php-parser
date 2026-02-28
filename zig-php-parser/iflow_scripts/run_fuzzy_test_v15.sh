#!/bin/bash

# AOT 模糊测试脚本 v15 - 更多PHP8特性

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=764

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

# 764-850 更多PHP8特性和复杂场景

auto_test '$x = match(2) { 1 => "one", 2 => "two", 3 => "three", default => "other", }; echo $x;' "match表达式" "控制流"
auto_test '$x = match("b") { "a" => "A", "b" => "B", default => "C", }; echo $x;' "match字符串" "控制流"
auto_test '$x = match(true) { $x > 10 => "big", default => "small", }; $x = 15; echo $x > 10 ? "big" : "small";' "match条件" "控制流"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; for ($i = 0; $i < count($arr); $i++) { $sum = $sum + $arr[$i]; } echo $sum;' "for累加" "循环"
auto_test '$arr = array(1, 2, 3); $x = array_reduce($arr, function($c, $i) { return $c + $i; }, 0); echo $x;' "reduce求和3" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $x = array_filter($arr, function($i) { return $i % 2 == 1; }); echo implode(",", array_values($x));' "filter奇数" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $x = array_map(function($i) { return $i * $i; }, $arr); echo implode(",", $x);' "map平方" "函数"
auto_test '$arr = array(1, 2, 3); echo array_sum($arr);' "数组求和3" "函数"
auto_test '$arr = array(1, 2, 3); echo array_product($arr);' "数组乘积4" "函数"
auto_test '$str = "hello"; echo strlen($str);' "strlen2" "函数"
auto_test '$str = "hello"; echo strtoupper($str);' "strtoupper2" "函数"
auto_test '$str = "HELLO"; echo strtolower($str);' "strtolower2" "函数"
auto_test '$str = "hello world"; echo ucwords($str);' "ucwords2" "函数"
auto_test '$str = "hello"; echo ucfirst($str);' "ucfirst2" "函数"
auto_test '$str = "HELLO"; echo lcfirst($str);' "lcfirst2" "函数"
auto_test '$str = "hello"; echo strrev($str);' "strrev2" "函数"
auto_test '$str = "a,b,c"; $arr = explode(",", $str); echo count($arr);' "explode3" "函数"
auto_test '$arr = array("a", "b", "c"); echo implode("-", $arr);' "implode3" "函数"
auto_test '$arr = array(1, 2, 3); echo in_array(2, $arr) ? "yes" : "no";' "in_array3" "函数"
auto_test '$arr = array("a" => 1, "b" => 2); echo array_key_exists("a", $arr) ? "yes" : "no";' "key_exists3" "函数"
auto_test '$arr = array(5, 3, 8, 1); sort($arr); echo implode(",", $arr);' "sort2" "函数"
auto_test '$arr = array(5, 3, 8, 1); rsort($arr); echo implode(",", $arr);' "rsort2" "函数"
auto_test '$arr = array("c" => 3, "a" => 1, "b" => 2); ksort($arr); echo implode(",", array_keys($arr));' "ksort4" "函数"
auto_test '$arr = array("c" => 3, "a" => 1, "b" => 2); asort($arr); echo implode(",", $arr);' "asort3" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_slice($arr, 1, 3);' "slice3" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); array_splice($arr, 1, 2); echo implode(",", $arr);' "splice3" "函数"
auto_test '$arr1 = array(1, 2); $arr2 = array(3, 4); echo implode(",", array_merge($arr1, $arr2));' "merge3" "函数"
auto_test '$arr = array(1, 2, 3); echo array_reverse($arr);' "reverse2" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_filter($arr, function($x) { return $x > 3; }));' "filter求和4" "函数"
auto_test '$arr = array(1, 2, 3); echo end($arr);' "end2" "函数"
auto_test '$arr = array(1, 2, 3); echo current($arr); next($arr); echo current($arr);' "current_next" "函数"
auto_test '$x = 10; $y = 3; echo intdiv($x, $y);' "intdiv2" "函数"
auto_test '$x = 10; $y = 3; echo $x % $y;' "mod2" "表达式"
auto_test '$x = -5; echo abs($x);' "abs2" "函数"
auto_test '$x = 3.7; echo floor($x) . ceil($x);' "floor_ceil" "函数"
auto_test '$x = 3.5; echo round($x);' "round2" "函数"
auto_test '$x = 2; echo pow($x, 8);' "pow2" "函数"
auto_test '$x = 8; echo sqrt($x);' "sqrt2" "函数"
auto_test '$arr = array(1, 5, 3); echo max($arr) . min($arr);' "max_min2" "函数"
auto_test '$x = 1; $x++; echo $x;' "后增1" "表达式"
auto_test '$x = 1; ++$x; echo $x;' "前增1" "表达式"
auto_test '$x = 5; $x += 3; echo $x;' "加等于" "表达式"
auto_test '$x = 5; $x -= 3; echo $x;' "减等于" "表达式"
auto_test '$x = 5; $x *= 3; echo $x;' "乘等于" "表达式"
auto_test '$x = 12; $x /= 3; echo $x;' "除等于" "表达式"
auto_test '$x = 10; $x %= 3; echo $x;' "模等于" "表达式"
auto_test '$x = 1 and 1; echo ($x and 1) ? "true" : "false";' "and运算符" "表达式"
auto_test '$x = 0 or 1; echo ($x or 0) ? "true" : "false";' "or运算符" "表达式"
auto_test '$x = 1; echo !$x ? "false" : "true";' "not运算符" "表达式"
auto_test '$x = 5; echo $x & 3;' "and位运算" "表达式"
auto_test '$x = 5; echo $x | 3;' "or位运算" "表达式"
auto_test '$x = 5; echo $x ^ 3;' "xor位运算" "表达式"
auto_test '$x = 8; echo $x << 2;' "左移" "表达式"
auto_test '$x = 8; echo $x >> 1;' "右移" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum($arr) / count($arr);' "平均3" "函数"
auto_test '$arr = range(1, 10); echo array_sum($arr);' "1到10和" "函数"
auto_test '$arr = range(1, 20); $sum = 0; foreach ($arr as $v) { if ($v % 2 == 0) $sum += $v; } echo $sum;' "偶数和" "循环"
auto_test '$arr = range(1, 15); $sum = 0; foreach ($arr as $v) { if ($v % 3 == 0) $sum += $v; } echo $sum;' "3的倍数和" "循环"
auto_test '$arr = range(1, 12); $sum = 0; foreach ($arr as $v) { if ($v % 5 == 0) $sum += $v; } echo $sum;' "5的倍数和" "循环"
auto_test '$x = 1; while ($x < 50) { $x *= 2; } echo $x;' "while翻倍2" "循环"
auto_test '$x = 100; while ($x > 1) { $x = (int)($x / 2); } echo $x;' "while减半2" "循环"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); $min = $arr[0]; foreach ($arr as $v) { if ($v < $min) $min = $v; } echo $min;' "找最小值" "循环"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); $max = $arr[0]; foreach ($arr as $v) { if ($v > $max) $max = $v; } echo $max;' "找最大值" "循环"
auto_test '$x = 1; $y = 2; $z = 3; echo ($x + $y) * $z;' "括号2" "表达式"
auto_test '$x = 10; $y = 20; $z = 30; echo $x + $y * $z - $x;' "混合运算" "表达式"
auto_test '$arr = array(1, 2, 3); echo count($arr) + strlen("abc");' "多函数2" "表达式"
auto_test '$str = "a-b-c"; $arr = explode("-", $str); echo implode(",", $arr);' "explode_implode2" "函数"
auto_test '$arr = array(1, 2, 3); $arr2 = array_reverse($arr); echo implode(",", $arr2);' "reverse_implode" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_slice($arr, 0, 3));' "slice_sum" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_slice($arr, -3));' "slice负索引" "函数"
auto_test '$str = "hello"; echo ord($str[0]);' "ord2" "函数"
auto_test '$x = 65; echo chr($x);' "chr2" "函数"
auto_test '$arr = array(1, 2, 3); $sum = 0; foreach ($arr as $v) { $sum = $sum + $v; } echo $sum;' "foreach求和" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; $i = 0; while ($i < count($arr)) { $sum += $arr[$i]; $i++; } echo $sum;' "while遍历数组" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 10; $i++) { $arr[] = $i; } echo array_sum($arr);' "创建数组求和" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 10; $i++) { if ($i % 2 == 0) $arr[] = $i; } echo implode(",", $arr);' "筛选偶数" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $found = false; foreach ($arr as $v) { if ($v == 3) { $found = true; break; } } echo $found ? "found" : "not";' "查找元素" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $count = 0; foreach ($arr as $v) { if ($v > 2) $count++; } echo $count;' "计数条件" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { $sum += $v * 2; } echo $sum;' "翻倍求和" "循环"
auto_test '$arr = array(1, 2, 3); echo implode(",", array_unique($arr));' "unique2" "函数"
auto_test '$arr = array(1, 2, 3); echo array_count_values($arr);' "count_values" "函数"
auto_test '$arr = array(1, 2, 3, 2, 1); echo max(array_count_values($arr));' "出现最多次数" "函数"
auto_test '$arr = array("a", "b", "c"); echo join(",", $arr);' "join函数" "函数"
auto_test '$str = "hello"; echo join("", str_split($str));' "split_join" "函数"

echo ""
echo "========================================="
echo "测试完成！报告: $REPORT_FILE"
echo "========================================="
tail -30 "$REPORT_FILE"
