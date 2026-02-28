#!/bin/bash

# AOT 模糊测试脚本 v10 - 更多复杂场景

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=494

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

# 494-550 更多复杂测试

auto_test 'function fib($n) { if ($n <= 1) return $n; return fib($n-1) + fib($n-2); } echo fib(10);' "斐波那契" "递归"
auto_test 'function sum($arr) { $s = 0; foreach ($arr as $v) { $s += $v; } return $s; } echo sum(array(1,2,3,4,5));' "数组求和函数" "函数"
auto_test 'function maxArr($arr) { $m = $arr[0]; foreach ($arr as $v) { if ($v > $m) $m = $v; } return $m; } echo maxArr(array(3,1,4,1,5));' "数组最大值" "函数"
auto_test 'function isPrime($n) { if ($n < 2) return false; for ($i = 2; $i <= sqrt($n); $i++) { if ($n % $i == 0) return false; } return true; } echo isPrime(17) ? "prime" : "not";' "素数判断" "函数"
auto_test 'function revStr($s) { $r = ""; for ($i = strlen($s)-1; $i >= 0; $i--) { $r .= $s[$i]; } return $r; } echo revStr("hello");' "字符串反转" "函数"
auto_test 'function countChars($s) { $c = array(); for ($i = 0; $i < strlen($s); $i++) { $ch = $s[$i]; $c[$ch] = isset($c[$ch]) ? $c[$ch]+1 : 1; } return $c; } print_r(countChars("hello"));' "字符计数" "函数"
auto_test '$arr = range(1, 100); $sum = 0; foreach ($arr as $v) { $sum += $v; } echo $sum;' "1到100求和" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 10; $i++) { $arr[] = $i * $i; } echo array_sum($arr);' "平方和" "循环"
auto_test '$fact = 1; for ($i = 1; $i <= 10; $i++) { $fact *= $i; } echo $fact;' "10的阶乘" "循环"
auto_test '$a = 1; $b = 2; $c = 3; $d = 4; echo ($a+$b)*($c+$d);' "复杂表达式" "表达式"
auto_test '$arr = array(1,2,3); $sum = 0; $i = 0; while ($i < count($arr)) { $sum += $arr[$i]; $i++; } echo $sum;' "while遍历数组" "循环"
auto_test 'for ($i = 1; $i <= 5; $i++) { for ($j = 1; $j <= $i; $j++) { echo "*"; } echo "\n"; }' "三角形" "循环"
auto_test '$arr = array(5,3,8,1,9,2); $min = $arr[0]; foreach ($arr as $v) { if ($v < $min) $min = $v; } echo $min;' "最小值" "数组"
auto_test '$arr = array(5,3,8,1,9,2); $max = $arr[0]; foreach ($arr as $v) { if ($v > $max) $max = $v; } echo $max;' "最大值" "数组"
auto_test '$str = "the quick brown fox"; $words = explode(" ", $str); echo count($words);' "单词计数" "字符串"
auto_test '$str = "hello"; echo strrev($str) == strrev($str) ? "palindrome" : "not";' "回文检测" "字符串"
auto_test '$arr = array(1, 2, 3); echo implode("", array_map(function($x) { return $x * 2; }, $arr));' "map转换" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = array_reduce($arr, function($c, $i) { return $c + $i; }); echo $sum;' "reduce求和" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $filtered = array_filter($arr, function($x) { return $x % 2 == 0; }); echo implode(",", $filtered);' "filter偶数" "函数"
auto_test '$arr1 = array(1, 2, 3); $arr2 = array(4, 5, 6); echo implode(",", array_merge($arr1, $arr2));' "数组合并" "函数"
auto_test '$matrix = array(array(1,2), array(3,4)); $sum = 0; for ($i = 0; $i < 2; $i++) { for ($j = 0; $j < 2; $j++) { $sum += $matrix[$i][$j]; } } echo $sum;' "矩阵求和" "数组"
auto_test '$arr = array(1, 2, 3); echo end($arr);' "end函数" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum($arr) / count($arr);' "平均值" "数组"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { $sum += $v * $v; } echo sqrt($sum);' "均方根" "函数"
auto_test 'function gcd($a, $b) { while ($b != 0) { $t = $b; $b = $a % $b; $a = $t; } return $a; } echo gcd(48, 18);' "最大公约数" "函数"
auto_test 'function lcm($a, $b) { return $a * $b / gcd($a, $b); } function gcd($a, $b) { while ($b != 0) { $t = $b; $b = $a % $b; $a = $t; } return $a; } echo lcm(4, 6);' "最小公倍数" "函数"
auto_test '$arr = range(1, 20); $even = array_filter($arr, function($x) { return $x % 2 == 0; }); echo array_sum($even);' "偶数求和" "函数"
auto_test '$str = "abc"; $arr = str_split($str); sort($arr); echo implode("", $arr);' "字符串排序" "字符串"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); $unique = array_unique($arr); echo count($unique);' "唯一元素数" "数组"
auto_test '$arr = array(1, 2, 3); echo in_array(2, $arr) && in_array(4, $arr) ? "both" : "not";' "多值检测" "函数"
auto_test '$arr = array("a" => 1, "b" => 2, "c" => 3); $keys = array_keys($arr); echo $keys[0];' "array_keys" "函数"
auto_test '$arr = array("a" => 1, "b" => 2, "c" => 3); $vals = array_values($arr); echo $vals[0];' "array_values" "函数"
auto_test '$str = "hello world"; $arr = explode(" ", $str); echo count($arr);' "explode计数" "函数"
auto_test '$arr = array(1, 2, 3); echo current($arr); next($arr); echo current($arr);' "指针操作" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_product($arr);' "数组乘积" "函数"
auto_test '$x = 5; $y = 10; echo $x < $y ? ($x > 3 ? "yes" : "no") : "other";' "嵌套三元" "表达式"
auto_test '$arr = array(1, 2, 3); echo !empty($arr) ? "not empty" : "empty";' "empty检测" "函数"
auto_test '$x = null; echo !isset($x) ? "not set" : "set";' "isset检测" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_filter($arr, function($x) { return $x > 2; }));' "filter后求和" "函数"
auto_test 'echo str_repeat("*", 10);' "重复字符" "函数"
auto_test '$str = "hello"; echo substr($str, -3);' "负索引substr" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_slice($arr, 1, 3));' "slice后求和" "函数"
auto_test '$arr1 = array(1, 2, 3); $arr2 = array(3, 4, 5); echo count(array_intersect($arr1, $arr2));' "数组交集" "函数"
auto_test '$arr1 = array(1, 2, 3); $arr2 = array(3, 4, 5); echo count(array_diff($arr1, $arr2));' "数组差集" "函数"

echo ""
echo "========================================="
echo "测试完成！报告: $REPORT_FILE"
echo "========================================="
tail -50 "$REPORT_FILE"
