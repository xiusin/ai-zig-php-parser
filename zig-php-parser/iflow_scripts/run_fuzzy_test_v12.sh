#!/bin/bash

# AOT 模糊测试脚本 v12 - 更多边界和复杂场景

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=595

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

# 595-660 更多复杂场景

auto_test '$x = 1; $y = 2; $z = 3; $result = $x + $y * $z; echo $result;' "运算符优先级" "表达式"
auto_test '$arr = array(1,2,3); $arr2 = $arr; $arr2[] = 4; echo count($arr) . "," . count($arr2);' "数组复制" "数组"
auto_test '$x = 10; $y = 3; echo intdiv($x, $y);' "intdiv整除" "函数"
auto_test '$x = 10; $y = 3; echo $x % $y;' "取模运算" "表达式"
auto_test '$x = -5; echo abs($x); echo sqrt(abs($x));' "abs和sqrt" "函数"
auto_test 'echo pow(2, 8); echo pow(3, 4);' "pow函数" "函数"
auto_test 'echo log10(100); echo log2(8);' "log函数" "函数"
auto_test 'echo exp(1); echo pi();' "exp/pi" "函数"
auto_test '$x = 3.14159; echo round($x, 2);' "round精度" "函数"
auto_test '$arr = array(1,2,3,4,5); $s = 0; foreach ($arr as $i => $v) { $s += $v; } echo $s;' "foreach带键" "循环"
auto_test '$arr = array("a"=>1, "b"=>2, "c"=>3); foreach ($arr as $k => $v) { echo "$k=$v,"; }' "关联数组遍历" "数组"
auto_test 'for ($i = 0; $i < 5; $i++) { if ($i == 2) continue; echo "$i,"; }' "continue语句" "循环"
auto_test 'for ($i = 0; $i < 5; $i++) { if ($i == 3) break; echo "$i,"; }' "break语句" "循环"
auto_test '$i = 0; while ($i < 5) { echo "$i,"; $i++; }' "while循环" "循环"
auto_test '$i = 0; do { echo "$i,"; $i++; } while ($i < 3);' "do-while2" "循环"
auto_test '$arr = range(1, 10); echo implode(",", array_reverse($arr));' "array_reverse" "函数"
auto_test '$arr = array(1,2,3); echo array_sum($arr); echo array_product($arr);' "sum和product" "函数"
auto_test '$str = "abc"; echo str_repeat($str, 3);' "str_repeat" "函数"
auto_test '$str = "hello"; echo substr_count($str, "l");' "substr_count" "函数"
auto_test '$str = "hello"; echo strchr($str, "l");' "strchr查找" "函数"
auto_test '$arr = array(1, 2, 3); echo end($arr); prev($arr); echo current($arr);' "prev函数" "函数"
auto_test '$arr = array(1,2,3,4,5); $s = 0; for ($i = count($arr)-1; $i >= 0; $i--) { $s += $arr[$i]; } echo $s;' "逆序遍历" "循环"
auto_test 'function sum() { $s = 0; foreach (func_get_args() as $a) { $s += $a; } return $s; } echo sum(1,2,3,4,5);' "可变参数" "函数"
auto_test '$arr = array(1,2,3,4,5); echo array_sum(array_map(function($x) { return $x * $x; }, $arr));' "map平方和" "函数"
auto_test '$str = "  hello world  "; echo trim($str); echo ltrim($str); echo rtrim($str);' "trim系列" "函数"
auto_test '$str = "Hello"; echo lcfirst($str);' "lcfirst" "函数"
auto_test '$str = "hello"; echo strrev($str);' "strrev" "函数"
auto_test '$arr = array(5, 3, 8, 1, 9); sort($arr); print_r($arr);' "sort输出" "函数"
auto_test '$arr = array(5, 3, 8, 1, 9); rsort($arr); echo implode(",", $arr);' "rsort输出" "函数"
auto_test '$arr = array("b"=>2, "a"=>1, "c"=>3); ksort($arr); echo implode(",", array_keys($arr));' "ksort2" "函数"
auto_test '$arr = array("b"=>2, "a"=>1, "c"=>3); asort($arr); echo implode(",", $arr);' "asort2" "函数"
auto_test '$arr = array(1,2,3,4,5); echo in_array(6, $arr) ? "yes" : "no";' "in_array2" "函数"
auto_test '$arr = array("a"=>1, "b"=>2); echo array_key_exists("c", $arr) ? "yes" : "no";' "key_exists2" "函数"
auto_test '$x = 0; echo $x++ . "," . $x++ . "," . $x;' "后置递增" "表达式"
auto_test '$x = 0; echo ++$x . "," . ++$x . "," . $x;' "前置递增" "表达式"
auto_test '$x = 5; $y = ++$x; echo "$x,$y";' "递增赋值" "表达式"
auto_test '$x = 5; $y = $x++; echo "$x,$y";' "后置递增赋值" "表达式"
auto_test '$arr = array(1,2,3); $arr[] = 4; echo count($arr);' "数组追加" "数组"
auto_test '$arr = array(1,2,3); unset($arr[1]); echo implode(",", array_values($arr));' "unset元素" "数组"
auto_test '$arr = range(1,5); array_splice($arr, 1, 2); echo implode(",", $arr);' "array_splice" "函数"
auto_test '$arr = array(1,2,3,4,5); echo array_sum(array_slice($arr, 0, 3));' "slice求和" "函数"
auto_test '$arr1 = array(1,2,3); $arr2 = array(4,5,6); $merged = array_merge($arr1, $arr2); echo implode(",", $merged);' "merge2" "函数"
auto_test '$arr = array(1,2,3,4,5); echo max($arr) . "," . min($arr);' "max/min数组" "函数"
auto_test '$arr = array(1,5,3,2,4); sort($arr); echo implode(",", $arr);' "数组排序2" "函数"
auto_test '$arr = array("z"=>3, "a"=>1, "m"=>2); ksort($arr); echo implode(",", array_keys($arr));' "ksort3" "函数"
auto_test '$str = "hello"; echo str_pad($str, 10, "-");' "str_pad右填充" "函数"
auto_test '$str = "hello"; echo str_pad($str, 10, "-", STR_PAD_LEFT);' "str_pad左填充" "函数"
auto_test '$str = "abc"; echo str_repeat($str, 2);' "str_repeat2" "函数"
auto_test '$str = "hello world"; $arr = explode(" ", $str); echo implode("-", $arr);' "explode_implode" "函数"
auto_test '$arr = array(1,2,3,4,5); $filtered = array_filter($arr, function($x) { return $x > 2; }); echo implode(",", $filtered);' "filter大于2" "函数"
auto_test '$arr = array(1,2,3,4,5); $mapped = array_map(function($x) { return $x * 10; }, $arr); echo implode(",", $mapped);' "map乘10" "函数"
auto_test '$arr = array(1,2,3); echo array_reduce($arr, function($c, $i) { return $c + $i; }, 0);' "reduce带初始值" "函数"
auto_test '$arr = array(1,2,3,4,5); $sum = 0; foreach ($arr as $v) { if ($v % 2 == 0) $sum += $v; } echo $sum;' "偶数求和2" "循环"
auto_test '$x = 1; $y = 2; echo ($x < $y) ? ($y < 3 ? "yes" : "no") : "other";' "三元嵌套3" "表达式"

echo ""
echo "========================================="
echo "测试完成！报告: $REPORT_FILE"
echo "========================================="
tail -30 "$REPORT_FILE"
