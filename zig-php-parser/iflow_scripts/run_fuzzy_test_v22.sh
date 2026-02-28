#!/bin/bash

# AOT 模糊测试脚本 v22 - 更多边界测试

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=1446

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
    
    # 只记录失败的测试
    if [ "$STATUS" = "PASS" ]; then
        echo "[$COUNTER] PASS: $desc"
        COUNTER=$((COUNTER + 1))
        return
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

# 1446-1545 更多边界测试

auto_test '$x = PHP_INT_MAX; echo $x;' "INT_MAX" "常量"
auto_test '$x = PHP_INT_MIN; echo $x;' "INT_MIN" "常量"
auto_test 'echo PHP_VERSION;' "PHP_VERSION" "常量"
auto_test 'echo PHP_OS;' "PHP_OS" "常量"
auto_test '$x = M_PI; echo $x;' "M_PI" "常量"
auto_test '$x = M_E; echo $x;' "M_E" "常量"
auto_test '$arr = array_fill(0, 5, 1); echo implode(",", $arr);' "array_fill" "函数"
auto_test '$arr = array_fill(0, 3, "a"); echo implode(",", $arr);' "array_fill串" "函数"
auto_test '$arr = range(1, 5); echo array_sum($arr);' "range求和" "函数"
auto_test '$arr = range(5, 1); echo implode(",", $arr);' "range倒序" "函数"
auto_test '$arr = range(0, 10, 2); echo implode(",", $arr);' "range步长2" "函数"
auto_test '$arr = range(0, 10, 3); echo implode(",", $arr);' "range步长3" "函数"
auto_test '$str = "hello"; echo $str[0];' "字符串索引" "表达式"
auto_test '$str = "hello"; echo $str[4];' "字符串末索引" "表达式"
auto_test '$str = "hello"; $str[0] = "H"; echo $str;' "字符串修改" "表达式"
auto_test '$arr = array(1, 2, 3); echo $arr[0];' "数组索引" "表达式"
auto_test '$arr = array("a", "b", "c"); echo $arr[2];' "数组末索引" "表达式"
auto_test '$arr = array("a" => 1, "b" => 2); echo $arr["a"];' "关联索引" "表达式"
auto_test '$x = 5; $y = 10; echo "x=" . $x . ",y=" . $y;' "字符串连接" "表达式"
auto_test '$x = 5; $y = 10; echo $x + $y;' "加法" "表达式"
auto_test '$x = 5; $y = 10; echo $x * $y;' "乘法" "表达式"
auto_test '$x = 10; $y = 3; echo $x / $y;' "除法" "表达式"
auto_test '$x = 10; $y = 3; echo $x % $y;' "取模" "表达式"
auto_test '$x = 2; echo $x ** 10;' "幂运算10" "表达式"
auto_test '$x = 2; echo $x ** 20;' "幂运算20" "表达式"
auto_test '$x = -5; echo abs($x);' "负数绝对值" "表达式"
auto_test '$x = -3.5; echo abs($x);' "负浮点绝对值" "表达式"
auto_test '$x = 3.7; echo floor($x);' "floor小数" "表达式"
auto_test '$x = 3.2; echo ceil($x);' "ceil小数" "表达式"
auto_test '$x = 3.5; echo round($x);' "round小数" "表达式"
auto_test '$x = 3.14159; echo round($x, 4);' "round四位" "表达式"
auto_test '$x = 16; echo sqrt($x);' "sqrt16" "表达式"
auto_test '$x = 2; echo log($x);' "log2" "表达式"
auto_test '$x = 2; echo exp($x);' "exp2" "表达式"
auto_test '$x = 10; echo log10($x);' "log10" "表达式"
auto_test '$x = 8; echo pow($x, 2);' "pow8平方" "表达式"
auto_test '$x = 2; echo sin($x);' "sin" "表达式"
auto_test '$x = 2; echo cos($x);' "cos" "表达式"
auto_test '$x = 2; echo tan($x);' "tan" "表达式"
auto_test '$arr = array(1, 2, 3); echo count($arr);' "count" "函数"
auto_test '$str = "abc"; echo strlen($str);' "strlen" "函数"
auto_test '$arr = array(1, 2, 3); echo array_sum($arr);' "array_sum" "函数"
auto_test '$arr = array(1, 2, 3); echo array_product($arr);' "array_product" "函数"
auto_test '$arr = array(1, 2, 3); echo implode("-", $arr);' "implode" "函数"
auto_test '$str = "a-b-c"; $arr = explode("-", $str); echo count($arr);' "explode" "函数"
auto_test '$str = "hello"; echo strtoupper($str);' "strtoupper" "函数"
auto_test '$str = "HELLO"; echo strtolower($str);' "strtolower" "函数"
auto_test '$str = "hello world"; echo ucwords($str);' "ucwords" "函数"
auto_test '$str = "hello"; echo ucfirst($str);' "ucfirst" "函数"
auto_test '$str = "HELLO"; echo lcfirst($str);' "lcfirst" "函数"
auto_test '$str = "hello"; echo strrev($str);' "strrev" "函数"
auto_test '$str = "a,b,c,d,e"; $arr = explode(",", $str); echo implode("", $arr);' "去逗号" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_slice($arr, 2);' "slice后3" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_slice($arr, 1, 2);' "slice中2" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); array_splice($arr, 1, 2); echo implode(",", $arr);' "splice" "函数"
auto_test '$arr1 = array(1, 2); $arr2 = array(3, 4); echo implode(",", array_merge($arr1, $arr2));' "array_merge" "函数"
auto_test '$arr = array(3, 1, 2); sort($arr); echo implode(",", $arr);' "sort" "函数"
auto_test '$arr = array(3, 1, 2); rsort($arr); echo implode(",", $arr);' "rsort" "函数"
auto_test '$arr = array("c" => 1, "a" => 2, "b" => 3); ksort($arr); echo implode(",", array_keys($arr));' "ksort" "函数"
auto_test '$arr = array("c" => 1, "a" => 2, "b" => 3); asort($arr); echo implode(",", $arr);' "asort" "函数"
auto_test '$arr = array(3, 1, 2); echo in_array(2, $arr) ? "yes" : "no";' "in_array" "函数"
auto_test '$arr = array("a" => 1, "b" => 2); echo array_key_exists("a", $arr) ? "yes" : "no";' "array_key_exists" "函数"
auto_test '$arr = array(1, 2, 3); echo array_search(2, $arr);' "array_search" "函数"
auto_test '$arr = array(1, 2, 3, 2, 1); echo implode(",", array_unique($arr));' "array_unique" "函数"
auto_test '$arr = array(1, 2, 2, 3); echo array_count_values($arr);' "array_count_values" "函数"
auto_test '$str = "hello"; echo str_pad($str, 10, "-");' "str_pad右" "函数"
auto_test '$str = "hello"; echo str_pad($str, 10, "-", STR_PAD_LEFT);' "str_pad左" "函数"
auto_test '$str = "hello"; echo str_pad($str, 11, "-", STR_PAD_BOTH);' "str_pad双" "函数"
auto_test '$str = "aaa"; echo str_repeat($str, 3);' "str_repeat" "函数"
auto_test '$str = "hello world"; echo substr($str, 0, 5);' "substr前5" "函数"
auto_test '$str = "hello world"; echo substr($str, 6);' "substr后5" "函数"
auto_test '$str = "hello world"; echo substr($str, -5);' "substr末5" "函数"
auto_test '$str = "abcabcabc"; echo substr_count($str, "a");' "substr_count" "函数"
auto_test '$str = "hello"; echo str_replace("l", "L", $str);' "str_replace" "函数"
auto_test '$str = "hello"; echo trim($str);' "trim" "函数"
auto_test '$str = "---hello---"; echo trim($str, "-");' "trim指定" "函数"
auto_test '$str = "hello"; echo ltrim($str);' "ltrim" "函数"
auto_test '$str = "hello   "; echo rtrim($str);' "rtrim" "函数"
auto_test '$str = "hello"; echo md5($str);' "md5" "函数"
auto_test '$str = "hello"; echo sha1($str);' "sha1" "函数"
auto_test '$str = "A"; echo ord($str);' "ord" "函数"
auto_test '$x = 65; echo chr($x);' "chr" "函数"
auto_test '$x = 255; echo dechex($x);' "dechex" "函数"
auto_test '$x = "ff"; echo hexdec($x);' "hexdec" "函数"
auto_test '$x = 63; echo decoct($x);' "decoct" "函数"
auto_test '$x = "77"; echo octdec($x);' "octdec" "函数"
auto_test '$x = "1010"; echo bindec($x);' "bindec" "函数"
auto_test '$num = 1234567; echo number_format($num);' "number_format" "函数"
auto_test '$num = 1234567.89; echo number_format($num, 2);' "number_format2" "函数"
auto_test '$x = 123; echo strval($x);' "strval" "函数"
auto_test '$x = "123"; echo intval($x);' "intval" "函数"
auto_test '$x = "123.45"; echo floatval($x);' "floatval" "函数"
auto_test '$x = 1; echo (bool)$x;' "bool_cast" "表达式"
auto_test '$x = 0; echo (int)$x;' "int_cast" "表达式"
auto_test '$x = 1.5; echo (int)$x;' "int_cast2" "表达式"
auto_test '$arr = array(); echo empty($arr) ? "empty" : "not";' "empty_arr" "函数"
auto_test '$str = ""; echo empty($str) ? "empty" : "not";' "empty_str" "函数"
auto_test '$x = 0; echo empty($x) ? "empty" : "not";' "empty_int" "函数"
auto_test '$x = null; echo is_null($x) ? "null" : "not";' "is_null" "函数"
auto_test '$x = "123"; echo is_numeric($x) ? "yes" : "no";' "is_numeric" "函数"
auto_test '$x = "abc"; echo is_numeric($x) ? "yes" : "no";' "is_numeric2" "函数"
auto_test '$x = array(); echo is_array($x) ? "yes" : "no";' "is_array" "函数"
auto_test '$x = 123; echo gettype($x);' "gettype" "函数"
auto_test '$x = 1.5; echo gettype($x);' "gettype2" "函数"
auto_test '$x = true; echo gettype($x);' "gettype3" "函数"
auto_test '$x = null; echo gettype($x);' "gettype4" "函数"
auto_test '$arr = array(1, 2, 3); echo current($arr);' "current" "函数"
auto_test '$arr = array(1, 2, 3); next($arr); echo current($arr);' "next" "函数"
auto_test '$arr = array(1, 2, 3); next($arr); next($arr); echo current($arr);' "next2" "函数"
auto_test '$arr = array(1, 2, 3); end($arr); echo current($arr);' "end" "函数"
auto_test '$arr = array(1, 2, 3); echo key($arr);' "key" "函数"
auto_test '$arr = array("a" => 1, "b" => 2); next($arr); echo key($arr);' "key2" "函数"
auto_test '$arr = array(1, 2, 3); echo reset($arr);' "reset" "函数"
auto_test '$arr = array(1, 2, 3); end($arr); echo reset($arr);' "reset2" "函数"
auto_test '$arr = array(1, 2, 3, 4); echo array_chunk($arr, 2)[0][0];' "array_chunk" "函数"
auto_test '$x = 5 <=> 3;' "spaceship1" "表达式"
auto_test '$x = 3 <=> 5;' "spaceship2" "表达式"
auto_test '$x = 5 <=> 5;' "spaceship3" "表达式"
auto_test '$x = 0 ?: 5;' "elvis1" "表达式"
auto_test '$x = null ?: 5;' "elvis2" "表达式"
auto_test '$x = "" ?: "default";' "elvis3" "表达式"

echo ""
echo "========================================="
echo "测试完成！"
echo "========================================="
