#!/bin/bash

# AOT 模糊测试脚本 v7 - 更多复杂测试

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=354

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

# 354-400 更多复杂测试

auto_test '$x = 1 + 2 * 3 - 4 / 2; echo $x;' "算术优先级" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; for ($i = 0; $i < count($arr); $i++) { $sum += $arr[$i]; } echo $sum;' "数组遍历求和" "数组"
auto_test '$str = "hello"; for ($i = 0; $i < strlen($str); $i++) { echo $str[$i]; }' "字符串遍历" "字符串"
auto_test '$arr = array(); for ($i = 0; $i < 10; $i++) { $arr[] = $i * $i; } echo implode(",", $arr);' "数组生成" "数组"
auto_test 'function factorial($n) { if ($n <= 1) return 1; return $n * factorial($n - 1); } echo factorial(5);' "阶乘递归" "递归"
auto_test '$x = 0; for ($i = 1; $i <= 10; $i++) { $x += $i; } echo $x;' "1到10求和" "循环"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); sort($arr); echo implode(",", $arr);' "数组排序" "数组"
auto_test '$str = "hello world"; echo strtoupper($str);' "strtoupper" "函数"
auto_test '$str = "HELLO WORLD"; echo strtolower($str);' "strtolower" "函数"
auto_test '$str = "hello"; echo strlen($str);' "strlen" "函数"
auto_test '$str = "hello world"; echo substr($str, 0, 5);' "substr" "函数"
auto_test '$str = "hello"; echo strpos($str, "l");' "strpos" "函数"
auto_test '$str = "hello world"; echo str_replace("world", "php", $str);' "str_replace" "函数"
auto_test '$arr = array("a", "b", "c"); echo implode("-", $arr);' "implode" "函数"
auto_test '$str = "a,b,c,d"; print_r(explode(",", $str));' "explode" "函数"
auto_test '$str = "  hello  "; echo strlen(trim($str));' "trim" "函数"
auto_test '$x = 123; echo gettype($x);' "gettype" "函数"
auto_test '$x = "123"; echo intval($x);' "intval" "函数"
auto_test '$x = 123; echo floatval($x);' "floatval" "函数"
auto_test '$x = 123; echo strval($x);' "strval" "函数"
auto_test '$arr = array(1, 2, 3); echo is_array($arr) ? "array" : "not";' "is_array" "函数"
auto_test '$x = 123; echo is_int($x) ? "int" : "not";' "is_int" "函数"
auto_test '$x = "hello"; echo is_string($x) ? "string" : "not";' "is_string" "函数"
auto_test '$x = 0; echo empty($x) ? "empty" : "not";' "empty" "函数"
auto_test '$arr = array("a" => 1); echo isset($arr["a"]) ? "set" : "not";' "isset" "函数"
auto_test 'echo defined("PHP_VERSION") ? "yes" : "no";' "defined" "常量"
auto_test 'echo PHP_VERSION;' "PHP_VERSION" "常量"
auto_test '$x = range(1, 5); echo implode(",", $x);' "range" "函数"
auto_test '$arr = array(1, 2, 3); echo array_sum($arr);' "array_sum" "函数"
auto_test '$arr = array(1, 2, 3); echo array_product($arr);' "array_product" "函数"
auto_test '$x = 5; $y = 10; echo ($x > $y) ? $x : $y;' "三元选大" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); $first = reset($arr); echo $first;' "reset" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $last = end($arr); echo $last;' "end" "函数"
auto_test '$arr = array(1, 2, 3); next($arr); echo current($arr);' "next_current" "函数"
auto_test '$arr = array(1, 2, 3); end($arr); prev($arr); echo current($arr);' "prev" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_search(3, $arr);' "array_search" "函数"
auto_test '$arr = array(1, 2, 3); echo in_array(2, $arr) ? "yes" : "no";' "in_array" "函数"
auto_test '$arr = array(1, 2, 3); echo array_key_exists(1, $arr) ? "yes" : "no";' "array_key_exists" "函数"
auto_test 'function sum() { $args = func_get_args(); return array_sum($args); } echo sum(1, 2, 3, 4, 5);' "可变参数" "函数"
auto_test '$x = 10; $y = 20; $z = 30; echo max($x, $y, $z);' "max多参数" "函数"
auto_test '$arr = array(5, 2, 8, 1, 9); echo max($arr);' "max数组" "函数"
auto_test '$arr = array(5, 2, 8, 1, 9); echo min($arr);' "min数组" "函数"
auto_test 'echo pow(2, 10);' "pow" "函数"
auto_test 'echo sqrt(16);' "sqrt" "函数"
auto_test 'echo rand(1, 100);' "rand" "函数"
auto_test 'echo mt_rand(1, 100);' "mt_rand" "函数"
auto_test 'echo time();' "time" "函数"

echo ""
echo "========================================="
echo "测试完成！报告: $REPORT_FILE"
echo "========================================="
tail -50 "$REPORT_FILE"
