#!/bin/bash

# AOT 模糊测试脚本 v9 - 更多边缘情况

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=445

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

# 445-500 更多边缘测试

auto_test 'echo "hello" . " " . "world" . "!";' "多重字符串连接" "字符串"
auto_test '$arr = array(1, 2, 3); echo implode(",", array_reverse($arr));' "array_reverse" "函数"
auto_test '$arr = array(1, 2, 3); $flipped = array_flip($arr); echo $flipped[1];' "array_flip" "函数"
auto_test '$arr = array(1, 2, 3, 4); echo array_pop($arr); echo count($arr);' "array_pop" "函数"
auto_test '$arr = array(1, 2, 3); echo array_shift($arr); echo count($arr);' "array_shift" "函数"
auto_test '$arr = array(1, 2); array_unshift($arr, 0); echo implode(",", $arr);' "array_unshift" "函数"
auto_test '$arr = array(1, 2); array_push($arr, 3); echo implode(",", $arr);' "array_push" "函数"
auto_test '$x = 0; echo $x ?: "default";' "elvis运算符" "运算符"
auto_test '$arr = array(1, 2, 3); echo each($arr);' "each" "函数"
auto_test '$str = "hello"; echo ucwords($str);' "ucwords" "函数"
auto_test '$str = "HELLO"; echo ucfirst($str);' "ucfirst" "函数"
auto_test '$str = "hello"; echo lcfirst($str);' "lcfirst" "函数"
auto_test '$str = "hello"; echo str_repeat($str, 3);' "str_repeat" "函数"
auto_test '$str = "hello"; echo str_pad($str, 10, "*", STR_PAD_LEFT);' "str_pad左" "函数"
auto_test '$str = "hello"; echo str_pad($str, 10, "*", STR_PAD_RIGHT);' "str_pad右" "函数"
auto_test '$str = "hello"; echo str_pad($str, 10, "*", STR_PAD_BOTH);' "str_pad双" "函数"
auto_test '$str = "hello"; print_r(str_split($str));' "str_split" "函数"
auto_test 'echo str_shuffle("abc");' "str_shuffle" "函数"
auto_test '$str = "hello"; echo strrev($str);' "strrev" "函数"
auto_test '$str = "HELLO"; echo strtolower($str); echo strtoupper($str);' "大小写转换" "函数"
auto_test '$str = "a,b,c,d,e"; $arr = str_split($str, 2); echo implode(";", $arr);' "str_split带长度" "函数"
auto_test '$str = "hello world"; echo substr_count($str, "l");' "substr_count" "函数"
auto_test '$str = "hello"; echo strtr($str, "l", "L");' "strtr" "函数"
auto_test '$x = array("a" => 1); $y = array("b" => 2); $z = array_merge($x, $y); echo count($z);' "数组合并" "函数"
auto_test '$x = array("a" => 1, "b" => 2); $y = array("a" => 10); $z = array_replace($x, $y); echo $z["a"];' "array_replace" "函数"
auto_test '$arr = array(1, 2, 3); echo array_rand($arr);' "array_rand" "函数"
auto_test '$arr = array("a", "b", "c"); shuffle($arr); echo implode("", $arr);' "shuffle数组" "函数"
auto_test '$arr = array(3, 1, 2); rsort($arr); echo implode(",", $arr);' "rsort" "函数"
auto_test '$arr = array("b" => 2, "a" => 1); ksort($arr); echo implode(",", array_keys($arr));' "ksort" "函数"
auto_test '$arr = array("b" => 2, "a" => 1); asort($arr); echo implode(",", $arr);' "asort" "函数"
auto_test '$arr = array("b" => 2, "a" => 1); arsort($arr); echo implode(",", $arr);' "arsort" "函数"
auto_test '$arr = array("b" => 2, "a" => 1); krsort($arr); echo implode(",", array_keys($arr));' "krsort" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_slice($arr, 1, 3);' "array_slice" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $copy = array_slice($arr, 0); echo count($copy);' "array_slice复制" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); array_splice($arr, 1, 2); echo implode(",", $arr);' "array_splice" "函数"
auto_test '$arr = array(1, 2, 3); echo array_sum($arr) + array_product($arr);' "数组函数组合" "函数"
auto_test '$arr = array(array(1, 2), array(3, 4)); echo count($arr, COUNT_RECURSIVE);' "count递归" "函数"
auto_test '$arr = range(1, 10); echo array_sum(array_filter($arr, function($x) { return $x % 2 == 0; }));' "filter后求和" "函数"
auto_test 'echo sprintf("Number: %d, String: %s", 123, "hello");' "sprintf" "函数"
auto_test 'printf("Num: %d, Str: %s\n", 42, "test");' "printf" "函数"
auto_test 'echo hexdec("ff");' "hexdec" "函数"
auto_test 'echo dechex(255);' "dechex" "函数"
auto_test 'echo bindec("1010");' "bindec" "函数"
auto_test 'echo octdec("77");' "octdec" "函数"
auto_test 'echo base_convert("ff", 16, 10);' "base_convert" "函数"
auto_test 'echo chr(65) . chr(66) . chr(67);' "chr多个" "函数"
auto_test 'echo ord("A") + ord("B");' "ord组合" "函数"
auto_test 'echo number_format(1234567.891, 2);' "number_format" "函数"
auto_test '$str = "This is a test"; echo wordwrap($str, 5, "<br>", true);' "wordwrap" "函数"

echo ""
echo "========================================="
echo "测试完成！报告: $REPORT_FILE"
echo "========================================="
tail -50 "$REPORT_FILE"
