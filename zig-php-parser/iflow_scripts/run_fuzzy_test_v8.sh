#!/bin/bash

# AOT 模糊测试脚本 v8 - 更多边界和复杂测试

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=401

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

# 401-450 更多复杂测试

auto_test '$arr = array(array(1, 2), array(3, 4)); echo $arr[1][0];' "二维数组访问" "数组"
auto_test '$arr = array(1, 2, 3); echo count($arr) + count(array());' "count混合" "数组"
auto_test '$str = ""; echo strlen($str) . strlen("a");' "空串长度" "字符串"
auto_test '$x = PHP_INT_MAX; echo $x + 1;' "整数溢出" "边界"
auto_test '$x = -PHP_INT_MAX; echo $x - 1;' "负整数溢出" "边界"
auto_test '$arr = array(1, 0, 2, 0, 3); $filtered = array_filter($arr); echo count($filtered);' "array_filter" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $mapped = array_map(function($x) { return $x * 2; }, $arr); echo implode(",", $mapped);' "array_map" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $reduced = array_reduce($arr, function($carry, $item) { return $carry + $item; }, 0); echo $reduced;' "array_reduce" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_reduce($arr, function($carry, $item) { return $carry * $item; }, 1);' "array_reduce乘积" "函数"
auto_test '$arr = range(1, 10); echo array_sum(array_map(function($x) { return $x * $x; }, $arr));' "链式数组操作" "函数"
auto_test '$x = "123abc"; echo intval($x);' "intval字符串" "函数"
auto_test '$x = "3.14abc"; echo floatval($x);' "floatval字符串" "函数"
auto_test '$x = ""; echo $x === "" ? "empty" : "not";' "空字符串比较" "比较"
auto_test '$x = null; echo $x === null ? "null" : "not";' "null全等比较" "比较"
auto_test '$arr1 = array(1, 2, 3); $arr2 = array(1, 2, 3); echo $arr1 == $arr2 ? "eq" : "neq";' "数组相等" "比较"
auto_test '$arr1 = array(1, 2, 3); $arr2 = array(1, 2, 3); echo $arr1 === $arr2 ? "same" : "diff";' "数组全等" "比较"
auto_test '$str = "hello"; $str[0] = "H"; $str[1] = "E"; echo $str;' "字符串索引修改" "字符串"
auto_test '$x = 1; echo $x++ + ++$x;' "递增组合" "表达式"
auto_test '$x = 5; echo $x-- + --$x;' "递减组合" "表达式"
auto_test '$a = 1; $b = 2; $c = 3; echo $a + $b * $c;' "混合运算" "表达式"
auto_test '$a = 1; $b = 2; $c = 3; echo ($a + $b) * $c;' "括号运算" "表达式"
auto_test '$x = 10 % 3 % 2; echo $x;' "连续取模" "表达式"
auto_test '$x = 2 ** 3 ** 2; echo $x;' "连续幂" "表达式"
auto_test '$x = 1; $x += 2; $x *= 3; $x -= 4; echo $x;' "连续赋值" "表达式"
auto_test '$arr = array(1, 2, 3); foreach ($arr as $k => $v) { echo "$k=$v "; }' "foreach键值" "循环"
auto_test '$arr = array("a" => 1, "b" => 2); foreach ($arr as $k => $v) { echo "$k=$v "; }' "关联数组遍历" "循环"
auto_test 'for ($i = 0; $i < 5; $i++) { if ($i == 2) continue; if ($i == 4) break; echo $i; }' "continue_break组合" "控制流"
auto_test '$x = 1; switch ($x) { case 1: echo "one"; break; case 2: echo "two"; break; default: echo "default"; }' "switch详细" "控制流"
auto_test '$arr = array(1, 2, 3); while (count($arr) > 0) { echo array_shift($arr) . " "; }' "while_array_shift" "循环"
auto_test '$x = 0; do { echo $x; $x++; } while ($x < 3);' "do_while详细" "循环"
auto_test 'function test($a, $b = 5, $c = 10) { return $a + $b + $c; } echo test(1); echo test(1, 2); echo test(1, 2, 3);' "默认参数组合" "函数"
auto_test 'function &getRef() { global $x; return $x; } $x = 100; $ref = &getRef(); $ref = 200; echo $x;' "引用返回" "函数"
auto_test '$arr = array(1, 2, 3); function getArr() { return $arr; } echo count(getArr());' "函数返回数组" "函数"
auto_test 'function outer() { $x = 10; function inner() { global $x; return $x + 1; } return inner(); } echo outer();' "嵌套函数" "函数"
auto_test '$x = 1; function outer() { $x = 2; function inner() { return 3; } return inner(); } echo outer();' "函数嵌套" "函数"
auto_test '$arr = array(); for ($i = 0; $i < 5; $i++) { $arr[] = $i; } echo array_sum($arr);' "循环建数组" "数组"
auto_test '$matrix = array(array(array(1))); echo $matrix[0][0][0];' "三维数组" "数组"
auto_test '$obj = new stdClass(); $obj->test = 123; echo $obj->test;' "stdClass" "OOP"
auto_test '$arr = array("key" => "value"); extract($arr); echo $key;' "extract" "函数"
auto_test '$a = 1; $b = 2; $arr = compact("a", "b"); echo array_sum($arr);' "compact" "函数"
auto_test '$arr = array_fill(0, 5, "x"); echo implode("", $arr);' "array_fill" "函数"
auto_test '$keys = array("a", "b", "c"); $vals = array(1, 2, 3); $combined = array_combine($keys, $vals); echo $combined["a"] + $combined["b"];' "array_combine" "函数"
auto_test '$arr = array_chunk(array(1, 2, 3, 4, 5, 6), 2); echo count($arr);' "array_chunk" "函数"
auto_test '$arr = array(1, 2, 2, 3, 3, 3); print_r(array_count_values($arr));' "array_count_values" "函数"

echo ""
echo "========================================="
echo "测试完成！报告: $REPORT_FILE"
echo "========================================="
tail -50 "$REPORT_FILE"
