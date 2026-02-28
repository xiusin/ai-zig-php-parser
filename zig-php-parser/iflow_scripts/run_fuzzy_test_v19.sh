#!/bin/bash

# AOT 模糊测试脚本 v19 - 边缘案例测试

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=1127

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

# 1127-1226 边缘案例测试

auto_test '$x = 0; echo !$x;' "0非运算" "表达式"
auto_test '$x = 1; echo !$x;' "1非运算" "表达式"
auto_test '$x = ""; echo !$x;' "空串非" "表达式"
auto_test '$arr = array(); echo count($arr);' "空数组计数" "函数"
auto_test '$arr = array(); echo empty($arr) ? "empty" : "not";' "空数组empty" "函数"
auto_test '$arr = array(1); echo isset($arr[0]) ? "set" : "not";' "索引存在" "函数"
auto_test '$arr = array(1); echo isset($arr[5]) ? "set" : "not";' "索引不存在" "函数"
auto_test '$x = null; echo is_null($x) ? "null" : "not";' "null检测" "函数"
auto_test '$x = null; echo isset($x) ? "set" : "not";' "null isset" "函数"
auto_test '$x = 0; echo empty($x) ? "empty" : "not";' "0 empty" "函数"
auto_test '$x = "0"; echo empty($x) ? "empty" : "not";' "字符串0 empty" "函数"
auto_test '$x = false; echo empty($x) ? "empty" : "not";' "false empty" "函数"
auto_test '$x = 0.0; echo empty($x) ? "empty" : "not";' "0.0 empty" "函数"
auto_test '$arr = array(null); echo $arr[0] === null ? "null" : "not";' "null元素" "表达式"
auto_test '$x = 5; $y = 0; echo $y == 0 ? "zero" : $y;' "零判断" "表达式"
auto_test '$x = 5; $y = $x ?: 10; echo $y;' "elvis2" "表达式"
auto_test '$x = 0; $y = $x ?: 10; echo $y;' "elvis零" "表达式"
auto_test '$x = null; $y = $x ?: 10; echo $y;' "elvis null" "表达式"
auto_test '$x = 5 <=> 3; echo $x;' "飞船大于" "表达式"
auto_test '$x = 3 <=> 5; echo $x;' "飞船小于" "表达式"
auto_test '$x = 5 <=> 5; echo $x;' "飞船等于" "表达式"
auto_test '$arr = array(1, 2, 3); echo current($arr);' "current首" "函数"
auto_test '$arr = array(1, 2, 3); next($arr); echo key($arr);' "key函数" "函数"
auto_test '$arr = array(1, 2, 3); echo key($arr);' "key首" "函数"
auto_test '$arr = array("a" => 1, "b" => 2); echo key($arr);' "关联key" "函数"
auto_test '$arr = array(1, 2, 3); next($arr); next($arr); echo current($arr);' "current末" "函数"
auto_test '$arr = array(); echo current($arr) === false ? "false" : "true";' "空数组current" "函数"
auto_test '$x = 1; echo -$x;' "负号2" "表达式"
auto_test '$x = -5; echo -$x;' "双重负" "表达式"
auto_test '$x = 5; echo +$x;' "正号" "表达式"
auto_test '$x = 1; $y = 2; echo $x <= $y ? "yes" : "no";' "小于等于" "表达式"
auto_test '$x = 1; $y = 2; echo $x >= $y ? "yes" : "no";' "大于等于" "表达式"
auto_test '$x = 1; $y = 1; echo $x == $y ? "yes" : "no";' "等于2" "表达式"
auto_test '$x = 1; $y = "1"; echo $x == $y ? "yes" : "no";' "等值比较" "表达式"
auto_test '$x = 1; $y = "1"; echo $x === $y ? "yes" : "no";' "全等比较" "表达式"
auto_test '$x = 1; $y = 2; echo $x != $y ? "yes" : "no";' "不等2" "表达式"
auto_test '$x = 1; $y = 2; echo $x <> $y ? "yes" : "no";' "不等同" "表达式"
auto_test '$x = 1; $y = "1"; echo $x !== $y ? "yes" : "no";' "不全等" "表达式"
auto_test '$x = 1; $y = 2; echo ($x > 0 && $y > 0) ? "positive" : "not";' "逻辑与2" "表达式"
auto_test '$x = 1; $y = -1; echo ($x > 0 || $y > 0) ? "has" : "none";' "逻辑或2" "表达式"
auto_test '$x = 0; echo ($x == 0 xor true) ? "xor" : "not";' "xor运算" "表达式"
auto_test '$x = 1; echo ($x & 1) === 1 ? "odd" : "even";' "奇数判断" "表达式"
auto_test '$x = 8; echo ($x & 7) === 0 ? "multiple" : "not";' "8倍数判断" "表达式"
auto_test '$x = 15; echo $x | 1;' "位或加1" "表达式"
auto_test '$x = 10; echo $x ^ 7;' "异或7" "表达式"
auto_test '$x = 1; echo ~$x;' "位反2" "表达式"
auto_test '$x = 10 << 2;' "左移2位" "表达式"
auto_test '$x = 40 >> 2;' "右移2位" "表达式"
auto_test '$x = 1; $x <<= 3; echo $x;' "左移赋值" "表达式"
auto_test '$x = 16; $x >>= 2; echo $x;' "右移赋值" "表达式"
auto_test '$x = 5; $x &= 3; echo $x;' "位与赋值" "表达式"
auto_test '$x = 5; $x |= 3; echo $x;' "位或赋值" "表达式"
auto_test '$x = 5; $x ^= 3; echo $x;' "异或赋值2" "表达式"
auto_test '$arr = array(); echo $arr ? "true" : "false";' "空数组bool" "表达式"
auto_test '$arr = array(1); echo $arr ? "true" : "false";' "非空数组bool" "表达式"
auto_test '$str = ""; echo $str ? "true" : "false";' "空串bool" "表达式"
auto_test '$str = "x"; echo $str ? "true" : "false";' "非空串bool" "表达式"
auto_test '$x = 0; echo $x ? "true" : "false";' "零bool" "表达式"
auto_test '$x = 1; echo $x ? "true" : "false";' "1 bool" "表达式"
auto_test '$x = -1; echo $x ? "true" : "false";' "-1 bool" "表达式"
auto_test '$x = 0.0; echo $x ? "true" : "false";' "0.0 bool" "表达式"
auto_test '$x = 0.1; echo $x ? "true" : "false";' "0.1 bool" "表达式"
auto_test '$x = false; echo $x ? "true" : "false";' "false bool" "表达式"
auto_test '$x = true; echo $x ? "true" : "false";' "true bool" "表达式"
auto_test '$x = null; echo $x ? "true" : "false";' "null bool" "表达式"
auto_test 'echo gettype(123);' "int类型" "函数"
auto_test 'echo gettype(1.5);' "float类型" "函数"
auto_test 'echo gettype("abc");' "string类型" "函数"
auto_test 'echo gettype(true);' "bool类型" "函数"
auto_test 'echo gettype(array());' "array类型" "函数"
auto_test 'echo gettype(null);' "null类型" "函数"
auto_test '$x = "123"; echo is_int($x);' "字符串int" "函数"
auto_test '$x = 123; echo is_string($x);' "int字符串" "函数"
auto_test '$x = array(); echo is_array($x);' "数组检测" "函数"
auto_test '$x = "true"; echo is_bool($x);' "字符串bool" "函数"
auto_test '$x = 1; echo is_numeric($x);' "数字int" "函数"
auto_test '$x = "1.5"; echo is_numeric($x);' "数字串" "函数"
auto_test '$x = "abc"; echo is_numeric($x);' "非数字串" "函数"
auto_test '$arr = array(1, 2, 3); echo end($arr);' "end2" "函数"
auto_test '$arr = array(1, 2, 3); echo prev($arr);' "prev2" "函数"
auto_test '$arr = array(1, 2, 3); next($arr); echo prev($arr);' "prev返回" "函数"
auto_test '$arr = array("a" => 1, "b" => 2); echo array_keys($arr);' "array_keys" "函数"
auto_test '$arr = array("a" => 1, "b" => 2); echo array_values($arr);' "array_values" "函数"
auto_test '$arr = array(1, 2, 3, 4); echo array_flip($arr);' "array_flip" "函数"
auto_test '$arr = array(3, 1, 4, 1, 5); echo array_reverse($arr);' "array_reverse2" "函数"
auto_test '$arr = array(1, 2, 3); echo array_push($arr, 4);' "array_push2" "函数"
auto_test '$arr = array(1, 2, 3); echo array_pop($arr);' "array_pop2" "函数"
auto_test '$arr = array(1, 2, 3); echo array_shift($arr);' "array_shift2" "函数"
auto_test '$arr = array(2, 3); echo array_unshift($arr, 1);' "array_unshift" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_slice($arr, 1);' "slice去掉首" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_slice($arr, 0, 3);' "slice前3" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); array_splice($arr, 1, 2); echo implode(",", $arr);' "splice删2" "函数"
auto_test '$arr = array(1, 2, 3); array_splice($arr, 1, 0, array(9)); echo implode(",", $arr);' "splice插入" "函数"
auto_test '$arr1 = array(1, 2); $arr2 = array(3, 4); echo array_merge($arr1, $arr2);' "merge2数组" "函数"
auto_test '$arr = array(1, 2, 2, 3, 3, 3); echo array_count_values($arr);' "count_values" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo range(1, 5);' "range1" "函数"
auto_test '$arr = range(5, 1); echo implode(",", $arr);' "range倒序" "函数"
auto_test '$arr = range(0, 10, 2); echo implode(",", $arr);' "range步长" "函数"
auto_test '$x = 5; echo pow($x, 2);' "平方2" "函数"
auto_test '$x = 2; echo pow($x, 8);' "2的8次" "函数"
auto_test '$x = 4; echo sqrt($x);' "sqrt4" "函数"
auto_test '$x = 2; echo log($x);' "log2" "函数"
auto_test '$x = 2; echo exp($x);' "exp2" "函数"
auto_test 'echo pi();' "pi函数" "函数"
auto_test '$x = -5; echo abs($x);' "abs负" "函数"
auto_test '$x = 3.7; echo floor($x);' "floor3.7" "函数"
auto_test '$x = 3.2; echo ceil($x);' "ceil3.2" "函数"
auto_test '$x = 3.5; echo round($x);' "round3.5" "函数"
auto_test '$x = 3.5; echo round($x, 0, PHP_ROUND_HALF_UP);' "round向上" "函数"
auto_test '$x = 3.5; echo round($x, 0, PHP_ROUND_HALF_DOWN);' "round向下" "函数"
auto_test '$x = 100; echo intdiv($x, 7);' "intdiv100" "函数"

echo ""
echo "========================================="
echo "测试完成！"
echo "========================================="
