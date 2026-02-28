#!/bin/bash

# AOT 模糊测试脚本 v14 - 特殊场景和边界条件

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=704

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

# 704-780 更多边界和特殊场景

auto_test '$x = 0; echo $x ?: "default";' "null合并" "表达式"
auto_test '$x = 5; echo $x ?: "default";' "null合并2" "表达式"
auto_test '$arr = array(1, 2, 3); $x = $arr[0] ?? "default"; echo $x;' "空合并数组" "表达式"
auto_test '$arr = array(); $x = $arr[0] ?? "default"; echo $x;' "空合并空数组" "表达式"
auto_test '$x = null; $y = $x ?? 0; echo $y;' "null值合并" "表达式"
auto_test '$x = 10; $y = 20; echo $x <=> $y;' "飞船运算符" "表达式"
auto_test '$x = 20; $y = 20; echo $x <=> $y;' "飞船运算符2" "表达式"
auto_test '$x = 30; $y = 20; echo $x <=> $y;' "飞船运算符3" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); $s = array_sum(array_filter($arr, function($x) { return $x > 2; })); echo $s;' "filter求和3" "函数"
auto_test '$arr = range(1, 10); $mapped = array_map(function($x) { return $x * $x; }, $arr); echo array_sum(array_slice($mapped, 0, 5));' "map_slice_sum" "函数"
auto_test '$str = "abc123"; echo preg_match("/[0-9]+/", $str) ? "has digits" : "no digits";' "正则匹配" "函数"
auto_test '$str = "hello"; echo preg_replace("/[aeiou]/", "*", $str);' "正则替换" "函数"
auto_test '$str = "a,b,c,d,e"; $arr = explode(",", $str); echo count($arr);' "explode计数2" "函数"
auto_test '$arr = array(1, 2, 3); $str = implode(",", $arr); echo strlen($str);' "implode长度" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; for ($i = 0; $i < count($arr); $i++) { if ($arr[$i] % 2 == 0) $sum += $arr[$i]; } echo $sum;' "偶数求和3" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { if ($v > 2) $sum += $v; } echo $sum;' "条件求和" "循环"
auto_test '$x = 1; while ($x < 100) { $x *= 2; } echo $x;' "while翻倍" "循环"
auto_test '$x = 100; while ($x > 1) { $x /= 2; } echo $x;' "while减半" "循环"
auto_test '$arr = array(5, 3, 8, 1, 9, 2); sort($arr); echo $arr[0];' "排序后最小值" "函数"
auto_test '$arr = array(5, 3, 8, 1, 9, 2); rsort($arr); echo $arr[0];' "倒序后最大值" "函数"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); echo count(array_unique($arr));' "唯一值计数" "函数"
auto_test '$arr = range(1, 5); echo array_product($arr);' "数组乘积3" "函数"
auto_test '$str = "hello"; echo strtoupper(substr($str, 0, 3));' "链式字符串函数" "函数"
auto_test '$arr = array(1, 2, 3); echo max($arr) - min($arr);' "max_min差值" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $s = 0; foreach ($arr as $i => $v) { $s += $v * ($i + 1); } echo $s;' "加权求和" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_reduce($arr, function($c, $i) { return max($c, $i); }, 0);' "reduce取最大值" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_reduce($arr, function($c, $i) { return min($c, $i); }, 999);' "reduce取最小值" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum($arr) / count($arr);' "平均值2" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5, 6, 7, 8, 9, 10); $sum = 0; for ($i = 0; $i < count($arr); $i += 2) { $sum += $arr[$i]; } echo $sum;' "奇数索引求和" "循环"
auto_test '$str = "hello"; $chars = str_split($str); echo implode(",", $chars);' "str_split2" "函数"
auto_test '$str = "hello"; echo str_repeat($str, strlen($str));' "字符串重复" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_map(function($x) { return $x * $x * $x; }, $arr));' "立方和" "函数"
auto_test '$x = 1; $y = 2; echo ($x and $y) ? "true" : "false";' "逻辑and" "表达式"
auto_test '$x = 1; $y = 0; echo ($x or $y) ? "true" : "false";' "逻辑or" "表达式"
auto_test '$x = 1; echo (!$x) ? "false" : "true";' "逻辑not" "表达式"
auto_test '$x = 5; echo ($x & 3) . " " . ($x | 3);' "位运算" "表达式"
auto_test '$x = 10; echo ($x << 2) . " " . ($x >> 1);' "位移运算" "表达式"
auto_test '$x = 5; $x ^= 3; echo $x;' "异或赋值" "表达式"
auto_test '$arr = array(1, 2, 3); $arr2 = array_map(function($x) { return $x * 2; }, $arr); echo implode(",", $arr2);' "map乘2" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $arr2 = array_filter($arr, function($x) { return $x != 3; }); echo implode(",", $arr2);' "filter不等于" "函数"
auto_test '$str = "abc"; echo str_pad($str, 8, "0", STR_PAD_LEFT);' "左零填充" "函数"
auto_test '$str = "abc"; echo str_pad($str, 8, "0", STR_PAD_BOTH);' "两端零填充" "函数"
auto_test '$arr = array(1, 2, 3); $merged = array_merge($arr, $arr); echo implode(",", $merged);' "数组合并自身" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_slice($arr, 2, 2));' "slice中间求和" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $reversed = array_reverse($arr); echo $reversed[0];' "array_reverse首元素" "函数"
auto_test '$arr = array(1, 2, 3); echo current($arr); next($arr); next($arr); echo current($arr);' "指针移动" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { $sum += $v; if ($sum > 6) break; } echo $sum;' "条件break" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { if ($v == 3) continue; $sum += $v; } echo $sum;' "条件continue" "循环"
auto_test '$arr = array("a" => 1, "b" => 2); echo array_sum(array_values($arr));' "关联数组值求和" "函数"
auto_test '$arr = array("a" => 1, "b" => 2); echo array_sum(array_keys($arr));' "关联数组键求和" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_reduce($arr, function($c, $i) { return $c . $i; }, "");' "reduce字符串拼接" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $chunks = array_chunk($arr, 2); echo count($chunks[0]) . "," . count($chunks[1]);' "array_chunk2" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $first = array_slice($arr, 0, 2); $last = array_slice($arr, -2); echo implode(",", array_merge($first, $last));' "首尾合并" "函数"
auto_test '$arr = range(1, 10); echo array_sum(array_filter($arr, function($x) { return $x % 2 == 0 && $x > 4; }));' "多条件filter" "函数"
auto_test '$arr = array(1, 2, 3); echo end($arr); echo reset($arr); echo current($arr);' "reset函数" "函数"
auto_test '$str = "12345"; echo array_sum(str_split($str));' "数字字符串各位和" "函数"
auto_test '$arr = array(1, 2, 3); echo count($arr) > 0 ? array_sum($arr) / count($arr) : 0;' "安全平均值" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); echo in_array(3, $arr) ? "found" : "not found";' "in_array2" "函数"
auto_test '$arr = array(1, 2, 3); echo array_search(2, $arr);' "array_search2" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_reduce($arr, function($c, $i) { return $c + $i; }, 0) > 10 ? "big" : "small";' "reduce条件判断" "表达式"

echo ""
echo "========================================="
echo "测试完成！报告: $REPORT_FILE"
echo "========================================="
tail -30 "$REPORT_FILE"
